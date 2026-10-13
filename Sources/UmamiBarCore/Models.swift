import Foundation

public struct Website: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let domain: String

    public init(id: String, name: String, domain: String) {
        self.id = id
        self.name = name
        self.domain = domain
    }
}

public struct WebsitesResponse: Codable, Sendable {
    public let data: [Website]
    public let count: Int?

    public init(data: [Website], count: Int? = nil) {
        self.data = data
        self.count = count
    }
}

public enum WebsitesResult: Sendable {
    public static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [Website] {
        if let wrapped = try? decoder.decode(WebsitesResponse.self, from: data) {
            return wrapped.data
        }
        return try decoder.decode([Website].self, from: data)
    }
}

private struct StatObject: Decodable {
    let value: Double
    let prev: Double?
}

private enum StatValue: Decodable {
    case number(Double)
    case object(StatObject)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else {
            self = .object(try container.decode(StatObject.self))
        }
    }

    var value: Double {
        switch self {
        case .number(let n): return n
        case .object(let o): return o.value
        }
    }

    var prev: Double? {
        switch self {
        case .number: return nil
        case .object(let o): return o.prev
        }
    }
}

public struct WebsiteStats: Sendable {
    public var pageviews: Double
    public var visitors: Double
    public var visits: Double
    public var bounces: Double
    public var totaltime: Double
    public var comparison: Comparison?

    public struct Comparison: Sendable {
        public var pageviews: Double
        public var visitors: Double
        public var visits: Double
        public var bounces: Double
        public var totaltime: Double

        public init(pageviews: Double, visitors: Double, visits: Double, bounces: Double, totaltime: Double) {
            self.pageviews = pageviews
            self.visitors = visitors
            self.visits = visits
            self.bounces = bounces
            self.totaltime = totaltime
        }
    }

    public init(pageviews: Double, visitors: Double, visits: Double, bounces: Double, totaltime: Double, comparison: Comparison? = nil) {
        self.pageviews = pageviews
        self.visitors = visitors
        self.visits = visits
        self.bounces = bounces
        self.totaltime = totaltime
        self.comparison = comparison
    }
}

extension WebsiteStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case pageviews, visitors, visits, bounces, totaltime, comparison
    }
    private enum ComparisonKeys: String, CodingKey {
        case pageviews, visitors, visits, bounces, totaltime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pv = try c.decode(StatValue.self, forKey: .pageviews)
        let vs = try c.decode(StatValue.self, forKey: .visitors)
        let vi = try c.decode(StatValue.self, forKey: .visits)
        let bo = try c.decode(StatValue.self, forKey: .bounces)
        let tt = try c.decode(StatValue.self, forKey: .totaltime)
        pageviews = pv.value
        visitors = vs.value
        visits = vi.value
        bounces = bo.value
        totaltime = tt.value

        if let nested = try c.decodeIfPresent(ComparisonNested.self, forKey: .comparison) {
            comparison = Comparison(pageviews: nested.pageviews, visitors: nested.visitors,
                                    visits: nested.visits, bounces: nested.bounces, totaltime: nested.totaltime)
        } else if let pvp = pv.prev, let vsp = vs.prev, let vip = vi.prev, let bop = bo.prev, let ttp = tt.prev {
            comparison = Comparison(pageviews: pvp, visitors: vsp, visits: vip, bounces: bop, totaltime: ttp)
        } else {
            comparison = nil
        }
    }

    private struct ComparisonNested: Decodable {
        let pageviews: Double
        let visitors: Double
        let visits: Double
        let bounces: Double
        let totaltime: Double

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: ComparisonKeys.self)
            pageviews = try c.decodeFlexDouble(forKey: .pageviews)
            visitors = try c.decodeFlexDouble(forKey: .visitors)
            visits = try c.decodeFlexDouble(forKey: .visits)
            bounces = try c.decodeFlexDouble(forKey: .bounces)
            totaltime = try c.decodeFlexDouble(forKey: .totaltime)
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexDouble(forKey key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        let obj = try decode(StatValue.self, forKey: key)
        return obj.value
    }
}

public struct ActiveVisitors: Sendable {
    public let visitors: Int

    public init(visitors: Int) {
        self.visitors = visitors
    }
}

extension ActiveVisitors: Decodable {
    private enum CodingKeys: String, CodingKey { case visitors }
    private struct XEntry: Decodable { let x: Int }

    public init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([XEntry].self) {
            visitors = arr.first?.x ?? 0
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visitors = try c.decode(Int.self, forKey: .visitors)
    }
}

public struct SeriesPoint: Codable, Sendable {
    public let x: String
    public let y: Double

    public init(x: String, y: Double) {
        self.x = x
        self.y = y
    }

    public var date: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: x) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: x) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: x)
    }
}

public struct PageviewsResponse: Codable, Sendable {
    public let pageviews: [SeriesPoint]
    public let sessions: [SeriesPoint]

    public init(pageviews: [SeriesPoint], sessions: [SeriesPoint]) {
        self.pageviews = pageviews
        self.sessions = sessions
    }
}

public struct MetricRow: Codable, Identifiable, Sendable {
    public let x: String
    public let y: Double
    public var id: String { x }

    public init(x: String, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum DateRange: String, CaseIterable, Identifiable, Sendable {
    case today, last24h, last7d, last30d, thisMonth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return String(localized: "Today", bundle: .main)
        case .last24h: return String(localized: "Last 24 hours", bundle: .main)
        case .last7d: return String(localized: "Last 7 days", bundle: .main)
        case .last30d: return String(localized: "Last 30 days", bundle: .main)
        case .thisMonth: return String(localized: "This month", bundle: .main)
        }
    }

    public var endAt: Date { Date() }

    public var startAt: Date {
        startAt(relativeTo: Date())
    }

    public func startAt(relativeTo now: Date, calendar cal: Calendar = .current) -> Date {
        switch self {
        case .today:
            return cal.startOfDay(for: now)
        case .last24h:
            return cal.date(byAdding: .hour, value: -24, to: now) ?? now
        case .last7d:
            return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30d:
            return cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            return cal.date(from: comps) ?? now
        }
    }

    public var unit: String {
        switch self {
        case .today, .last24h: return "hour"
        case .last7d, .last30d, .thisMonth: return "day"
        }
    }
}

public enum ServerKind: String, CaseIterable, Identifiable, Sendable {
    case cloud, selfHosted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cloud: return String(localized: "Umami Cloud", bundle: .main)
        case .selfHosted: return String(localized: "Self-hosted", bundle: .main)
        }
    }
}

public enum CloudRegion: String, CaseIterable, Identifiable, Sendable {
    case auto, us, eu

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return String(localized: "Auto", bundle: .main)
        case .us: return String(localized: "US", bundle: .main)
        case .eu: return String(localized: "EU", bundle: .main)
        }
    }
}

public struct Connection: Sendable, Equatable {
    public var kind: ServerKind
    public var baseURL: String
    public var region: CloudRegion
    public var apiKey: String
    public var username: String
    public var password: String

    public init(kind: ServerKind, baseURL: String = "", region: CloudRegion = .auto,
                apiKey: String = "", username: String = "", password: String = "") {
        self.kind = kind
        self.baseURL = baseURL
        self.region = region
        self.apiKey = apiKey
        self.username = username
        self.password = password
    }

    public var isConfigured: Bool {
        switch kind {
        case .cloud:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .selfHosted:
            return !baseURL.isEmpty && (!apiKey.isEmpty || (!username.isEmpty && !password.isEmpty))
        }
    }

    public var apiBase: String {
        switch kind {
        case .cloud:
            var base = "https://api.umami.is/v1"
            switch region {
            case .auto: break
            case .us: base += "/us"
            case .eu: base += "/eu"
            }
            return base
        case .selfHosted:
            var trimmed = baseURL
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            return trimmed.hasSuffix("/api") ? trimmed : trimmed + "/api"
        }
    }

    public var dashboardURL: String {
        switch kind {
        case .cloud: return "https://cloud.umami.is"
        case .selfHosted:
            var trimmed = baseURL
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            return trimmed.hasSuffix("/api") ? String(trimmed.dropLast(4)) : trimmed
        }
    }

    public var normalized: Connection {
        var result = self
        result.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        result.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    public func validate() throws {
        guard normalized.isConfigured else { throw UmamiError.notConfigured }
        if kind == .selfHosted {
            guard let url = URLComponents(string: normalized.baseURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { throw UmamiError.invalidURL }
        }
    }
}
