import XCTest
@testable import UmamiBar
@testable import UmamiBarCore

final class MemoryCredentials: CredentialStorage {
    var values: [String: String] = [:]
    var failOnPassword = false
    func get(_ key: String) -> String? { values[key] }
    func set(_ value: String, for key: String) throws {
        if failOnPassword, key == "password" { throw UmamiError.unauthorized }
        values[key] = value
    }
}

actor MockAnalytics: AnalyticsClient {
    var list = [Website(id: "a", name: "A", domain: "a.example"), Website(id: "b", name: "B", domain: "b.example")]
    var failStats = Set<String>()
    var failActive = Set<String>()
    var failDetails = false
    var failList = false
    var websiteCalls = 0
    var statsCalls = 0
    var metricTypes: [String] = []
    var heldRange: DateRange?
    var heldDetailRange: DateRange?
    var continuations: [CheckedContinuation<Void, Never>] = []
    var listContinuation: CheckedContinuation<Void, Never>?
    var holdList = false

    func configure(failStats: Set<String> = [], failActive: Set<String> = [], failDetails: Bool = false, failList: Bool = false) {
        self.failStats = failStats; self.failActive = failActive
        self.failDetails = failDetails; self.failList = failList
    }
    func hold(_ range: DateRange) { heldRange = range }
    func holdDetails(_ range: DateRange) { heldDetailRange = range }
    func holdWebsites() { holdList = true }
    func release() {
        heldRange = nil
        heldDetailRange = nil
        let queued = continuations; continuations = []
        queued.forEach { $0.resume() }
        holdList = false
        listContinuation?.resume(); listContinuation = nil
    }
    func pendingCount() -> Int { continuations.count }
    func pendingList() -> Bool { listContinuation != nil }
    func calls() -> (Int, Int) { (websiteCalls, statsCalls) }
    func types() -> [String] { metricTypes }
    func replaceList(_ value: [Website]) { list = value }

    func websites() async throws -> [Website] {
        websiteCalls += 1
        if holdList { await withCheckedContinuation { listContinuation = $0 } }
        if failList { throw UmamiError.unauthorized }
        return list
    }
    func stats(websiteId: String, range: DateRange) async throws -> WebsiteStats {
        statsCalls += 1
        if heldRange == range { await withCheckedContinuation { continuations.append($0) } }
        if failStats.contains(websiteId) { throw UmamiError.http(status: 500, body: "") }
        let value: Double = range == .today ? 10 : 70
        return WebsiteStats(pageviews: value, visitors: value, visits: value, bounces: 0, totaltime: 0)
    }
    func active(websiteId: String) async throws -> Int {
        if failActive.contains(websiteId) { throw UmamiError.unauthorized }
        return 3
    }
    func pageviews(websiteId: String, range: DateRange) async throws -> PageviewsResponse {
        if heldDetailRange == range { await withCheckedContinuation { continuations.append($0) } }
        if failDetails { throw UmamiError.unauthorized }
        return PageviewsResponse(pageviews: [SeriesPoint(x: "2026-10-13 01:00:00", y: 3)], sessions: [SeriesPoint(x: "2026-10-13 01:00:00", y: 2)])
    }
    func metrics(websiteId: String, range: DateRange, type: String, limit: Int) async throws -> [MetricRow] {
        metricTypes.append(type)
        if failDetails { throw UmamiError.unauthorized }
        return [MetricRow(x: "/", y: 3)]
    }
}

@MainActor
final class AppStoreTests: XCTestCase {
    private func settings() throws -> SettingsStore {
        let defaults = UserDefaults(suiteName: "UmamiBarTests.\(UUID().uuidString)")!
        let value = SettingsStore(defaults: defaults, credentials: MemoryCredentials())
        try value.apply(Connection(kind: .cloud, apiKey: "test"))
        return value
    }
    private func store(_ mock: MockAnalytics) throws -> AppStore {
        AppStore(settings: try settings(), clientFactory: { _ in mock }, autoRefresh: false, demoMode: false)
    }
    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for state")
    }

    func testWebsiteSelectionPersistsAcrossSettingsInstances() throws {
        let defaults = UserDefaults(suiteName: "UmamiBarTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults, credentials: MemoryCredentials())
        XCTAssertNil(settings.visibleWebsiteIDs)
        settings.visibleWebsiteIDs = ["b", "a", "a"]
        let reopened = SettingsStore(defaults: defaults, credentials: MemoryCredentials())
        XCTAssertEqual(reopened.visibleWebsiteIDs, ["a", "b"])
        reopened.visibleWebsiteIDs = nil
        XCTAssertNil(settings.visibleWebsiteIDs)
    }

    func testSelectedWebsiteRefreshAndDefaultExpansion() async throws {
        let mock = MockAnalytics()
        let settings = try settings()
        settings.visibleWebsiteIDs = ["b"]
        let store = AppStore(settings: settings, clientFactory: { _ in mock }, autoRefresh: false, demoMode: false)
        await store.refresh()
        XCTAssertEqual(store.websites.count, 2)
        XCTAssertEqual(store.visibleSites.map(\.id), ["b"])
        XCTAssertNil(store.sites.first { $0.id == "a" }?.stats)
        let calls = await mock.calls()
        XCTAssertEqual(calls.1, 1)
        await store.panelOpened()
        XCTAssertEqual(store.expandedSiteId, "b")
        XCTAssertNotNil(store.visibleSites.first?.detail)
        store.toggle(site: store.visibleSites[0])
        XCTAssertNil(store.expandedSiteId)
        await store.refresh()
        XCTAssertNil(store.expandedSiteId, "Automatic refresh must respect manual collapse")
        await store.panelOpened()
        XCTAssertEqual(store.expandedSiteId, "b")
    }

    func testAllWebsitesIncludesNewSitesAndMultipleSelectionDoesNotAutoExpand() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh()
        await store.panelOpened()
        XCTAssertNil(store.expandedSiteId)
        await mock.replaceList([Website(id: "a", name: "A", domain: "a.example"),
                                Website(id: "c", name: "C", domain: "c.example")])
        await store.refresh()
        XCTAssertEqual(store.visibleSites.map(\.id), ["a", "c"])
        store.expandedSiteId = "c"
        store.updateWebsiteVisibility(["a"])
        try await eventually { !store.isLoading && store.expandedSiteId == "a" }
        XCTAssertEqual(store.visibleSites.map(\.id), ["a"])
    }

    func testTrafficSeriesAlignByTimestampWithoutInventingMissingVisitors() {
        let buckets = TrafficBucket.align(
            pageviews: [SeriesPoint(x: "2026-10-13 02:00:00", y: 12), SeriesPoint(x: "2026-10-13 01:00:00", y: 8)],
            visitors: [SeriesPoint(x: "2026-10-13 01:00:00", y: 3), SeriesPoint(x: "2026-10-13 03:00:00", y: 4)])
        XCTAssertEqual(buckets.map(\.time), ["2026-10-13 01:00:00", "2026-10-13 02:00:00", "2026-10-13 03:00:00"])
        XCTAssertEqual(buckets[0].pageviews, 8)
        XCTAssertEqual(buckets[0].visitors, 3)
        XCTAssertNil(buckets[1].visitors)
        XCTAssertNil(buckets[2].pageviews)
        XCTAssertEqual(buckets[2].visitors, 4)
    }

    func testTodayKeeps24HoursAndLeavesMissingHoursEmpty() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let now = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!
        let points = [SeriesPoint(x: "2026-10-13 00:00:00", y: 10),
                      SeriesPoint(x: "2026-10-13 04:00:00", y: 7),
                      SeriesPoint(x: "2026-10-12 23:00:00", y: 90)]
        let buckets = TrafficBucket.make(pageviews: points, visitors: [], range: .today, now: now, calendar: calendar)
        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets[0].pageviews, 10)
        XCTAssertEqual(buckets[4].pageviews, 7)
        XCTAssertNil(buckets[1].pageviews)
        XCTAssertNil(buckets[23].pageviews)
        XCTAssertTrue(buckets.allSatisfy { $0.visitors == nil })
        XCTAssertEqual(buckets[23].time, "2026-10-13 23:00:00")
    }

    func testTodayUsesLocalHourForISOTimestampsAndEmptyDayStillHas24Slots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let now = ISO8601DateFormatter().date(from: "2026-10-13T00:30:00Z")!
        let buckets = TrafficBucket.make(pageviews: [], visitors: [SeriesPoint(x: "2026-10-13T00:00:00Z", y: 3)],
                                         range: .today, now: now, calendar: calendar)
        XCTAssertEqual(buckets[5].visitors, 3)
        XCTAssertNil(buckets[0].visitors)
        let empty = TrafficBucket.make(pageviews: [], visitors: [], range: .today, now: now, calendar: calendar)
        XCTAssertEqual(empty.count, 24)
        XCTAssertTrue(empty.allSatisfy { $0.visitors == nil && $0.pageviews == nil })
        XCTAssertEqual(TrafficBucket.make(pageviews: [], visitors: [], range: .last24h).count, 0)
    }

    func testFullRefreshAndDetails() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh()
        XCTAssertEqual(store.sites.count, 2)
        XCTAssertEqual(store.sites[0].stats?.pageviews, 10)
        XCTAssertEqual(store.sites[0].active, 3)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertFalse(store.isLoading)
        await store.loadDetail(for: "a")
        XCTAssertNotNil(store.sites[0].detail)
        XCTAssertEqual(store.sites[0].detail?.visitorSeries.first?.y, 2)
        let types = await mock.types()
        XCTAssertTrue(types.contains("url")); XCTAssertFalse(types.contains("path"))
    }

    func testPartialFailurePreservesSuccessfulStatsAndMarksStaleSite() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh(); let timestamp = store.lastUpdated
        await mock.configure(failStats: ["b"])
        await store.refresh()
        XCTAssertEqual(store.lastUpdated, timestamp)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.sites[0].errorMessage)
        XCTAssertNotNil(store.sites[1].errorMessage)
        XCTAssertEqual(store.sites[1].stats?.pageviews, 10)
    }

    func testLiveFailureDoesNotDiscardSuccessfulStats() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.configure(failActive: ["a"])
        await store.refresh()
        XCTAssertEqual(store.sites[0].stats?.pageviews, 10)
        XCTAssertNil(store.sites[0].active)
        XCTAssertNotNil(store.sites[0].errorMessage)
        XCTAssertNil(store.lastUpdated)
    }

    func testTotalFailureDoesNotClaimFreshData() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.configure(failStats: ["a", "b"], failActive: ["a", "b"])
        await store.refresh()
        XCTAssertNil(store.lastUpdated)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testDetailsFailureStopsLoadingAndRetryRecovers() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh()
        await mock.configure(failDetails: true)
        await store.loadDetail(for: "a")
        XCTAssertFalse(store.sites[0].isLoadingDetail)
        XCTAssertNotNil(store.sites[0].detailError)
        await mock.configure()
        await store.loadDetail(for: "a")
        XCTAssertNotNil(store.sites[0].detail)
        XCTAssertNil(store.sites[0].detailError)
    }

    func testOldRangeCannotOverwriteNewRange() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.hold(.today)
        let old = Task { await store.refresh() }
        try await eventually { await mock.pendingCount() == 2 }
        store.select(range: .last7d)
        try await eventually { !store.isLoading && store.sites.first?.stats?.pageviews == 70 }
        await mock.release(); await old.value
        XCTAssertEqual(store.range, .last7d)
        XCTAssertEqual(store.sites[0].stats?.pageviews, 70)
    }

    func testConnectionChangeDiscardsOldWebsiteResponse() async throws {
        let oldClient = MockAnalytics(); let newClient = MockAnalytics()
        await newClient.replaceList([Website(id: "new", name: "New", domain: "new.example")])
        let settings = try settings()
        let store = AppStore(settings: settings,
                             clientFactory: { $0.apiKey == "new-key" ? newClient : oldClient },
                             autoRefresh: false, demoMode: false)
        await oldClient.holdWebsites()
        let old = Task { await store.refresh() }
        try await eventually { await oldClient.pendingList() }
        try settings.apply(Connection(kind: .cloud, apiKey: "new-key"))
        store.reconfigure()
        try await eventually { store.sites.first?.id == "new" && !store.isLoading }
        await oldClient.release(); await old.value
        XCTAssertEqual(store.sites.map(\.id), ["new"])
    }

    func testDuplicateRefreshIsCoalesced() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.hold(.today)
        let task = Task { await store.refresh() }
        try await eventually { await mock.pendingCount() == 2 }
        await store.refresh()
        let calls = await mock.calls()
        XCTAssertEqual(calls.0, 1)
        await mock.release(); await task.value
    }

    func testRefreshDiscoversNewSitesAndRenames() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh()
        await mock.replaceList([Website(id: "a", name: "Renamed", domain: "renamed.example")])
        await store.refresh()
        XCTAssertEqual(store.sites.count, 1)
        XCTAssertEqual(store.sites[0].website.name, "Renamed")
    }

    func testWebsiteListErrorRecovers() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.configure(failList: true); await store.refresh()
        XCTAssertNotNil(store.errorMessage); XCTAssertFalse(store.isLoading)
        await mock.configure(); await store.refresh()
        XCTAssertNil(store.errorMessage); XCTAssertEqual(store.sites.count, 2)
    }

    func testEmptyAccountCompletesWithoutSpinner() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await mock.replaceList([]); await store.refresh()
        XCTAssertFalse(store.isLoading); XCTAssertNotNil(store.lastUpdated)
        XCTAssertTrue(store.sites.isEmpty); XCTAssertNil(store.errorMessage)
    }

    func testDemoNeverContactsService() async throws {
        let mock = MockAnalytics()
        let store = AppStore(settings: try settings(), clientFactory: { _ in mock }, autoRefresh: false, demoMode: true)
        await store.refresh()
        for site in store.sites { await store.loadDetail(for: site.id) }
        XCTAssertEqual(store.sites.count, 3)
        XCTAssertTrue(store.sites.allSatisfy { $0.detail != nil })
        let calls = await mock.calls(); XCTAssertEqual(calls.0, 0); XCTAssertEqual(calls.1, 0)
    }



    func testPreviewCanConnectToLiveDataWithTemporaryCredentials() async throws {
        let mock = MockAnalytics()
        let settings = try settings()
        let store = AppStore(settings: settings, clientFactory: { _ in mock }, autoRefresh: false, demoMode: true)
        XCTAssertTrue(store.previewMode)
        XCTAssertTrue(store.demoMode)
        store.reconfigure()
        try await eventually { !store.isLoading && store.sites.count == 2 }
        XCTAssertFalse(store.demoMode)
        XCTAssertTrue(store.previewMode)
        XCTAssertEqual(store.sites[0].stats?.pageviews, 10)
        let calls = await mock.calls()
        XCTAssertEqual(calls.0, 1)
    }

    func testOldDetailsCannotReappearAfterRangeChange() async throws {
        let mock = MockAnalytics(); let store = try store(mock)
        await store.refresh()
        await mock.holdDetails(.today)
        let old = Task { await store.loadDetail(for: "a") }
        try await eventually { await mock.pendingCount() == 1 }
        store.select(range: .last7d)
        try await eventually { !store.isLoading && store.sites.first?.stats?.pageviews == 70 }
        await mock.release(); await old.value
        XCTAssertNil(store.sites[0].detail)
        XCTAssertFalse(store.sites[0].isLoadingDetail)
        await store.loadDetail(for: "a")
        XCTAssertNotNil(store.sites[0].detail)
    }

    func testConnectionNormalizationKeepsPasswordIntact() throws {
        let settings = try settings()
        try settings.apply(Connection(kind: .selfHosted, baseURL: " https://test.example/api/ ",
                                      username: " user ", password: " password "))
        XCTAssertEqual(settings.baseURL, "https://test.example/api/")
        XCTAssertEqual(settings.username, "user")
        XCTAssertEqual(settings.password, " password ")
        XCTAssertEqual(settings.connection.apiBase, "https://test.example/api")
        XCTAssertEqual(settings.connection.dashboardURL, "https://test.example")
    }

    func testInvalidRefreshIntervalsFallBackToOneMinute() throws {
        let settings = try settings()
        for value in [0.0, -1.0, Double.infinity, Double.nan, 1e30] {
            settings.refreshInterval = value
            XCTAssertEqual(settings.refreshInterval, 60)
        }
    }

    func testCalendarRangesUseSpecifiedTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        let now = ISO8601DateFormatter().date(from: "2026-10-12T22:30:00Z")!
        XCTAssertEqual(DateRange.today.startAt(relativeTo: now, calendar: calendar),
                       ISO8601DateFormatter().date(from: "2026-10-12T19:00:00Z"))
        XCTAssertEqual(DateRange.thisMonth.startAt(relativeTo: now, calendar: calendar),
                       ISO8601DateFormatter().date(from: "2026-09-30T19:00:00Z"))
    }

    func testCredentialSaveFailureDoesNotChangeConnection() throws {
        let secrets = MemoryCredentials()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "UmamiBarTests.\(UUID().uuidString)")!, credentials: secrets)
        try settings.apply(Connection(kind: .cloud, apiKey: "old"))
        secrets.failOnPassword = true
        XCTAssertThrowsError(try settings.apply(Connection(kind: .selfHosted, baseURL: "https://other.example", username: "u", password: "p")))
        XCTAssertEqual(settings.kind, .cloud); XCTAssertEqual(settings.apiKey, "old")
    }
}
