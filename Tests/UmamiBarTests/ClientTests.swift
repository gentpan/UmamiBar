import XCTest
@testable import UmamiBarCore

private struct HTTPReply {
    var status: Int = 200
    var body: String
    var headers: [String: String] = [:]
}

private final class HTTPState: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    var handler: (URLRequest, Int) throws -> HTTPReply = { _, _ in HTTPReply(body: "[]") }
    func reset(_ handler: @escaping (URLRequest, Int) throws -> HTTPReply) {
        lock.lock(); defer { lock.unlock() }
        requests = []; self.handler = handler
    }
    func respond(_ request: URLRequest) throws -> HTTPReply {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return try handler(request, requests.count)
    }
    func captured() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return requests
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = HTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let reply = try Self.state.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    private let site = #"{"id":"a","name":"A","domain":"a.example"}"#
    private func client(_ connection: Connection) -> UmamiClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return UmamiClient(connection: connection, session: URLSession(configuration: configuration))
    }

    func testCloudRegionAndBearerHeader() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: "[]") }
        let client = client(Connection(kind: .cloud, region: .eu, apiKey: " key \n"))
        let sites = try await client.websites()
        XCTAssertTrue(sites.isEmpty)
        let request = try XCTUnwrap(StubURLProtocol.state.captured().first)
        XCTAssertEqual(request.url?.path, "/v1/eu/websites")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
    }

    func testSelfHostedLoginAndExpiredTokenRetry() async throws {
        StubURLProtocol.state.reset { request, call in
            if request.url?.path == "/api/auth/login" {
                return HTTPReply(body: call == 1 ? #"{"token":"old"}"# : #"{"token":"new"}"#)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
                return HTTPReply(status: 401, body: "{}")
            }
            return HTTPReply(body: "[]")
        }
        let client = client(Connection(kind: .selfHosted, baseURL: "https://test.example/api/", username: "u", password: "p"))
        _ = try await client.websites()
        let requests = StubURLProtocol.state.captured()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
    }

    func testAPIKeyDoesNotAttemptPasswordLogin() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: "[]") }
        _ = try await client(Connection(kind: .selfHosted, baseURL: "http://localhost:3000", apiKey: "local-key")).websites()
        let requests = StubURLProtocol.state.captured()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer local-key")
    }

    func testConcurrentRequestsShareOneLogin() async throws {
        StubURLProtocol.state.reset { request, _ in
            if request.url?.path == "/api/auth/login" { return HTTPReply(body: #"{"token":"session"}"#) }
            return HTTPReply(body: #"{"visitors":3}"#)
        }
        let client = client(Connection(kind: .selfHosted, baseURL: "https://test.example", username: "u", password: "p"))
        async let one = client.active(websiteId: "a")
        async let two = client.active(websiteId: "b")
        let values = try await [one, two]
        XCTAssertEqual(values, [3, 3])
        XCTAssertEqual(StubURLProtocol.state.captured().filter { $0.url?.path == "/api/auth/login" }.count, 1)
    }

    func testNewConnectionNeverReusesAnotherClientsToken() async throws {
        StubURLProtocol.state.reset { request, _ in
            request.url?.path == "/api/auth/login" ? HTTPReply(body: #"{"token":"session"}"#) : HTTPReply(body: "[]")
        }
        _ = try await client(Connection(kind: .selfHosted, baseURL: "https://one.example", username: "u", password: "p")).websites()
        _ = try await client(Connection(kind: .selfHosted, baseURL: "https://two.example", username: "u", password: "p")).websites()
        XCTAssertEqual(StubURLProtocol.state.captured().filter { $0.url?.path == "/api/auth/login" }.count, 2)
    }

    func testPaginatedWebsitesAreAllLoaded() async throws {
        let site = self.site
        StubURLProtocol.state.reset { _, call in
            HTTPReply(body: call == 1 ? "{\"data\":[\(site)],\"count\":2}" : #"{"data":[{"id":"b","name":"B","domain":"b.example"}],"count":2}"#)
        }
        let sites = try await client(Connection(kind: .selfHosted, baseURL: "https://test.example", apiKey: "k")).websites()
        XCTAssertEqual(sites.map(\.id), ["a", "b"])
        let last = try XCTUnwrap(StubURLProtocol.state.captured().last?.url)
        XCTAssertTrue(last.query?.contains("page=2") == true)
    }

    func testBrokenPaginationTerminatesWithError() async throws {
        let site = self.site
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: "{\"data\":[\(site)],\"count\":2}") }
        do {
            _ = try await client(Connection(kind: .selfHosted, baseURL: "https://test.example", apiKey: "k")).websites()
            XCTFail("Expected invalid pagination to fail")
        } catch { XCTAssertEqual(StubURLProtocol.state.captured().count, 2) }
    }

    func testUnauthorizedAPIKeyIsNotRetriedAsPasswordLogin() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(status: 403, body: "{}") }
        do {
            _ = try await client(Connection(kind: .cloud, apiKey: "bad")).websites()
            XCTFail("Expected unauthorized")
        } catch {
            guard case UmamiError.unauthorized = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(StubURLProtocol.state.captured().count, 1)
    }

    func testTwoFactorLoginHasActionableError() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: #"{"requiresTwoFactor":true,"partialToken":"partial"}"#) }
        do {
            _ = try await client(Connection(kind: .selfHosted, baseURL: "https://test.example", username: "u", password: "p")).websites()
            XCTFail("Expected two-factor error")
        } catch {
            guard case UmamiError.twoFactorRequired = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testRateLimitRetryRespectsHeader() async throws {
        StubURLProtocol.state.reset { _, call in
            call == 1 ? HTTPReply(status: 429, body: "{}", headers: ["Retry-After":"1"]) : HTTPReply(body: "[]")
        }
        _ = try await client(Connection(kind: .selfHosted, baseURL: "https://test.example", apiKey: "k")).websites()
        XCTAssertEqual(StubURLProtocol.state.captured().count, 2)
    }

    func testMalformedResponseHasDecodeError() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: "<html>broken</html>") }
        do {
            _ = try await client(Connection(kind: .cloud, apiKey: "k")).websites()
            XCTFail("Expected decoding failure")
        } catch {
            guard case UmamiError.decoding = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInvalidURLFailsBeforeAnyNetworkRequest() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: "[]") }
        for url in ["example.com", "file:///tmp/data", "https://test.example?key=secret", "https://user:password@test.example"] {
            do {
                _ = try await client(Connection(kind: .selfHosted, baseURL: url, apiKey: "k")).websites()
                XCTFail("Expected invalid URL: \(url)")
            } catch {
                guard case UmamiError.invalidURL = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        XCTAssertTrue(StubURLProtocol.state.captured().isEmpty)
    }

    func testModernPageMetricsUsePath() async throws {
        StubURLProtocol.state.reset { request, _ in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let type = query.first { $0.name == "type" }?.value
            return type == "path" ? HTTPReply(body: #"[{"x":"/","y":3}]"#) : HTTPReply(status: 400, body: "{}")
        }
        let client = client(Connection(kind: .selfHosted, baseURL: "https://test.example", apiKey: "k"))
        let rows = try await client.metrics(websiteId: "a", range: .today, type: "url")
        XCTAssertEqual(rows.first?.x, "/")
        XCTAssertEqual(StubURLProtocol.state.captured().count, 1)
    }

    func testLegacyPageMetricFallbackIsCached() async throws {
        StubURLProtocol.state.reset { request, _ in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let type = query.first { $0.name == "type" }?.value
            return type == "url" ? HTTPReply(body: #"[{"x":"/","y":3}]"#) : HTTPReply(status: 400, body: "{}")
        }
        let client = client(Connection(kind: .selfHosted, baseURL: "https://test.example", apiKey: "k"))
        _ = try await client.metrics(websiteId: "a", range: .today, type: "url")
        _ = try await client.metrics(websiteId: "b", range: .today, type: "url")
        XCTAssertEqual(StubURLProtocol.state.captured().count, 3)
    }

    func testRangeAndChartQueryParameters() async throws {
        StubURLProtocol.state.reset { _, _ in HTTPReply(body: #"{"pageviews":[],"sessions":[]}"#) }
        _ = try await client(Connection(kind: .cloud, apiKey: "k")).pageviews(websiteId: "a", range: .last24h)
        let url = try XCTUnwrap(StubURLProtocol.state.captured().first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["unit"], "hour")
        XCTAssertEqual(query["timezone"], TimeZone.current.identifier)
        let interval = Double(query["endAt"]!)! - Double(query["startAt"]!)!
        XCTAssertEqual(interval, 86_400_000, accuracy: 1)
    }
}
