import Foundation

public enum UmamiError: LocalizedError, Sendable {
    case invalidURL, unauthorized, notConfigured, twoFactorRequired, rateLimited
    case http(status: Int, body: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Enter a valid HTTP or HTTPS server URL without a query or fragment.")
        case .unauthorized: return String(localized: "Unauthorized — check your credentials.")
        case .notConfigured: return String(localized: "Complete the connection details in Settings.")
        case .twoFactorRequired: return String(localized: "This account requires two-factor authentication. Use a self-hosted API key instead.")
        case .rateLimited: return String(localized: "Too many requests. Wait a moment and retry.")
        case .http(let status, _):
            return String.localizedStringWithFormat(String(localized: "Server returned HTTP %d. Please retry."), status)
        case .decoding: return String(localized: "The server response is not compatible with this version of UmamiBar.")
        }
    }
}

public protocol AnalyticsClient: Sendable {
    func websites() async throws -> [Website]
    func stats(websiteId: String, range: DateRange) async throws -> WebsiteStats
    func active(websiteId: String) async throws -> Int
    func pageviews(websiteId: String, range: DateRange) async throws -> PageviewsResponse
    func metrics(websiteId: String, range: DateRange, type: String, limit: Int) async throws -> [MetricRow]
}

public actor UmamiClient: AnalyticsClient {
    private let connection: Connection
    private let session: URLSession
    private let decoder = JSONDecoder()
    // Session tokens stay in memory and can never be reused by another connection.
    private var token: String?
    private var loginTask: Task<String, Error>?
    private var nextCloudRequest = Date.distantPast
    private var pageMetricType: String?

    public init(connection: Connection, session: URLSession = .shared) {
        self.connection = connection.normalized
        self.session = session
    }

    private func authHeader() async throws -> String {
        if !connection.apiKey.isEmpty { return "Bearer \(connection.apiKey)" }
        if let token { return "Bearer \(token)" }
        if let loginTask { return try await loginTask.value }
        let task = Task { try await self.login() }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func login() async throws -> String {
        var req = URLRequest(url: try makeURL(path: "/auth/login", query: [:]), timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": connection.username, "password": connection.password])
        let (data, response) = try await session.data(for: req)
        try check(response, data: data)
        struct LoginResponse: Decodable { let token: String?; let requiresTwoFactor: Bool? }
        let decoded: LoginResponse = try decode(data)
        if decoded.requiresTwoFactor == true { throw UmamiError.twoFactorRequired }
        guard let value = decoded.token, !value.isEmpty else { throw UmamiError.unauthorized }
        token = value
        return "Bearer \(value)"
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        try connection.validate()
        guard var comps = URLComponents(string: connection.apiBase + path) else { throw UmamiError.invalidURL }
        if !query.isEmpty { comps.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url, url.host != nil else { throw UmamiError.invalidURL }
        return url
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }
        if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
        if http.statusCode == 429 { throw UmamiError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func data(path: String, query: [String: String] = [:], retryAuth: Bool = true, retryRate: Bool = true) async throws -> Data {
        try Task.checkCancellation()
        var req = URLRequest(url: try makeURL(path: path, query: query), timeoutInterval: 30)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let authorization = try await authHeader()
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        if connection.kind == .cloud {
            // Cloud allows 50 calls per 15 seconds. Reserve slots before suspension.
            let slot = max(Date(), nextCloudRequest)
            nextCloudRequest = slot.addingTimeInterval(0.32)
            let delay = slot.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            if (http.statusCode == 401 || http.statusCode == 403), retryAuth,
               connection.kind == .selfHosted, connection.apiKey.isEmpty {
                // Another request may already have renewed the same expired token.
                if authorization == token.map({ "Bearer \($0)" }) { token = nil }
                return try await self.data(path: path, query: query, retryAuth: false, retryRate: retryRate)
            }
            if http.statusCode == 429, retryRate {
                let wait = min(max(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 15, 1), 60)
                try await Task.sleep(for: .seconds(wait))
                return try await self.data(path: path, query: query, retryAuth: retryAuth, retryRate: false)
            }
        }
        try check(response, data: data)
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw UmamiError.decoding(error.localizedDescription) }
    }

    private func request<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(await data(path: path, query: query))
    }

    private func rangeQuery(_ range: DateRange) -> [String: String] {
        let now = Date()
        return ["startAt": String(Int(range.startAt(relativeTo: now).timeIntervalSince1970 * 1000)),
                "endAt": String(Int(now.timeIntervalSince1970 * 1000))]
    }

    public func websites() async throws -> [Website] {
        var sites: [Website] = []
        var seen = Set<String>()
        var page = 1
        while true {
            let data = try await self.data(path: "/websites", query: ["includeTeams": "true", "pageSize": "200", "page": String(page)])
            // Older servers can return a bare array with no pagination.
            guard let wrapped = try? decoder.decode(WebsitesResponse.self, from: data) else {
                return try decode(data)
            }
            let additions = wrapped.data.filter { seen.insert($0.id).inserted }
            sites.append(contentsOf: additions)
            if wrapped.data.isEmpty || (wrapped.count.map { sites.count >= $0 } ?? (wrapped.data.count < 200)) { return sites }
            guard !additions.isEmpty else { throw UmamiError.decoding("Pagination did not advance") }
            page += 1
        }
    }

    public func stats(websiteId: String, range: DateRange) async throws -> WebsiteStats {
        try await request("/websites/\(websiteId)/stats", query: rangeQuery(range))
    }

    public func active(websiteId: String) async throws -> Int {
        let active: ActiveVisitors = try await request("/websites/\(websiteId)/active")
        return active.visitors
    }

    public func pageviews(websiteId: String, range: DateRange) async throws -> PageviewsResponse {
        var query = rangeQuery(range)
        query["unit"] = range.unit
        query["timezone"] = TimeZone.current.identifier
        return try await request("/websites/\(websiteId)/pageviews", query: query)
    }

    public func metrics(websiteId: String, range: DateRange, type: String, limit: Int = 5) async throws -> [MetricRow] {
        var query = rangeQuery(range)
        let isPageMetric = type == "url" || type == "path"
        // Umami 3 uses "path"; older Umami 2 servers use "url".
        query["type"] = isPageMetric ? (pageMetricType ?? "path") : type
        query["limit"] = String(limit)
        let endpoint = "/websites/\(websiteId)/metrics"
        do {
            let rows: [MetricRow] = try await request(endpoint, query: query)
            if isPageMetric { pageMetricType = query["type"] }
            return rows
        } catch UmamiError.http(let status, _) where status == 400 && isPageMetric {
            query["type"] = query["type"] == "path" ? "url" : "path"
            let rows: [MetricRow] = try await request(endpoint, query: query)
            pageMetricType = query["type"]
            return rows
        }
    }

    public func testConnection() async throws -> Int { try await websites().count }
}
