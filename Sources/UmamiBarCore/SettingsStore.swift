import Foundation

@Observable
public final class SettingsStore {
    private let defaults: UserDefaults
    private let credentials: any CredentialStorage
    private var revision = 0

    public init(defaults: UserDefaults = .standard, credentials: any CredentialStorage = SystemCredentialStorage()) {
        self.defaults = defaults
        self.credentials = credentials
    }

    public var kind: ServerKind {
        get { _ = revision; return ServerKind(rawValue: defaults.string(forKey: "kind") ?? "") ?? .cloud }
        set { defaults.set(newValue.rawValue, forKey: "kind"); revision += 1 }
    }

    public var baseURL: String {
        get { _ = revision; return defaults.string(forKey: "baseURL") ?? "" }
        set { defaults.set(newValue, forKey: "baseURL"); revision += 1 }
    }

    public var region: CloudRegion {
        get { _ = revision; return CloudRegion(rawValue: defaults.string(forKey: "region") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "region"); revision += 1 }
    }

    public var username: String {
        get { _ = revision; return defaults.string(forKey: "username") ?? "" }
        set { defaults.set(newValue, forKey: "username"); revision += 1 }
    }

    public var selectedWebsiteId: String? {
        get { _ = revision; return defaults.string(forKey: "selectedWebsiteId") }
        set { defaults.set(newValue, forKey: "selectedWebsiteId"); revision += 1 }
    }

    /// nil means all websites, including websites added to the server later.
    public var visibleWebsiteIDs: [String]? {
        get { _ = revision; return defaults.stringArray(forKey: "visibleWebsiteIDs") }
        set { defaults.set(newValue.map { Array(Set($0)).sorted() }, forKey: "visibleWebsiteIDs"); revision += 1 }
    }

    public var dateRange: DateRange {
        get { _ = revision; return DateRange(rawValue: defaults.string(forKey: "dateRange") ?? "") ?? .today }
        set { defaults.set(newValue.rawValue, forKey: "dateRange"); revision += 1 }
    }

    public var refreshInterval: TimeInterval {
        get {
            _ = revision
            let v = defaults.double(forKey: "refreshInterval")
            return [30.0, 60.0, 300.0].contains(v) ? v : 60
        }
        set { defaults.set(newValue, forKey: "refreshInterval"); revision += 1 }
    }

    public var apiKey: String {
        _ = revision; return credentials.get("apiKey") ?? ""
    }

    public var password: String {
        _ = revision; return credentials.get("password") ?? ""
    }

    public var isConfigured: Bool {
        connection.isConfigured
    }

    public var connection: Connection {
        _ = revision
        return Connection(kind: kind, baseURL: baseURL, region: region,
                          apiKey: apiKey, username: username, password: password)
    }

    public func apply(_ connection: Connection) throws {
        let c = connection.normalized
        try c.validate()
        let oldAPIKey = apiKey
        let oldPassword = password
        do {
            try credentials.set(c.apiKey, for: "apiKey")
            try credentials.set(c.password, for: "password")
        } catch {
            try? credentials.set(oldAPIKey, for: "apiKey")
            try? credentials.set(oldPassword, for: "password")
            throw error
        }
        defaults.set(c.kind.rawValue, forKey: "kind")
        defaults.set(c.baseURL, forKey: "baseURL")
        defaults.set(c.region.rawValue, forKey: "region")
        defaults.set(c.username, forKey: "username")
        revision += 1
    }
}
