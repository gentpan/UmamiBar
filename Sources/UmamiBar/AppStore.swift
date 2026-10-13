import Foundation
import UmamiBarCore

struct SiteDetail {
    var series: [SeriesPoint]
    var visitorSeries: [SeriesPoint] = []
    var topPages: [MetricRow]
    var topReferrers: [MetricRow]
}

struct SiteSnapshot: Identifiable {
    let website: Website
    var stats: WebsiteStats?
    var active: Int?
    var detail: SiteDetail?
    var errorMessage: String?
    var detailError: String?
    var isLoadingDetail = false
    var updatedAt: Date?
    var id: String { website.id }
}

private struct SiteResult: Sendable {
    let id: String
    let stats: WebsiteStats?
    let active: Int?
    let errors: [String]
}

private final class DemoCredentials: CredentialStorage {
    private var values: [String: String] = [:]
    func get(_ key: String) -> String? { values[key] }
    func set(_ value: String, for key: String) throws { values[key] = value }
}

@Observable
@MainActor
final class AppStore {
    let settings: SettingsStore
    private(set) var client: any AnalyticsClient
    private let clientFactory: (Connection) -> any AnalyticsClient
    private let autoRefresh: Bool
    let previewMode: Bool
    private(set) var demoMode: Bool

    var websites: [Website] = []
    var sites: [SiteSnapshot] = []
    var range: DateRange
    var expandedSiteId: String?
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var refreshID: UUID?
    private var detailIDs: [String: UUID] = [:]

    var visibleSites: [SiteSnapshot] {
        guard let ids = settings.visibleWebsiteIDs else { return sites }
        let selected = Set(ids)
        return sites.filter { selected.contains($0.id) }
    }

    func panelOpened() async {
        // A single monitored website always opens with its details visible.
        if visibleSites.count == 1, let site = visibleSites.first {
            expandedSiteId = site.id
            if site.detail == nil { await loadDetail(for: site.id) }
        }
    }

    func updateWebsiteVisibility(_ ids: [String]?) {
        settings.visibleWebsiteIDs = ids
        invalidateRequests()
        if let expandedSiteId, !visibleSites.contains(where: { $0.id == expandedSiteId }) {
            self.expandedSiteId = nil
        }
        Task { await refresh(); await panelOpened() }
    }

    var isReady: Bool { demoMode || settings.isConfigured }

    init(settings suppliedSettings: SettingsStore? = nil,
         clientFactory: @escaping (Connection) -> any AnalyticsClient = { UmamiClient(connection: $0) },
         autoRefresh: Bool = true,
         demoMode: Bool = ProcessInfo.processInfo.environment["UMAMIBAR_DEMO"] == "1" || ProcessInfo.processInfo.arguments.contains("--demo")) {
        let settings = suppliedSettings ?? (demoMode
            ? SettingsStore(defaults: UserDefaults(suiteName: "com.umamibar.app.preview")!, credentials: DemoCredentials())
            : SettingsStore())
        self.settings = settings
        self.clientFactory = clientFactory
        self.autoRefresh = autoRefresh
        self.previewMode = demoMode
        self.demoMode = demoMode
        self.client = clientFactory(demoMode ? Connection(kind: .cloud) : settings.connection)
        self.range = settings.dateRange
        if demoMode { installDemoData() }
        else if settings.isConfigured, autoRefresh { startAutoRefresh() }
    }

    func refresh() async {
        guard !demoMode, settings.isConfigured, !isLoading else { return }
        let id = UUID()
        let version = generation
        let client = self.client
        let range = self.range
        refreshID = id
        isLoading = true
        defer {
            if refreshID == id { isLoading = false; refreshID = nil }
        }
        let targets: [Website]
        do {
            let available = try await client.websites()
            guard version == generation, !Task.isCancelled else { return }
            websites = available
            sites = available.map { website in
                let old = sites.first { $0.id == website.id }
                return SiteSnapshot(website: website, stats: old?.stats, active: old?.active,
                                    detail: old?.detail, errorMessage: old?.errorMessage,
                                    detailError: old?.detailError, isLoadingDetail: old?.isLoadingDetail ?? false,
                                    updatedAt: old?.updatedAt)
            }
            targets = visibleSites.map(\.website)
            if let expandedSiteId, !targets.contains(where: { $0.id == expandedSiteId }) {
                self.expandedSiteId = nil
            }
        } catch {
            guard version == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            return
        }
        if targets.isEmpty {
            errorMessage = nil
            lastUpdated = Date()
            return
        }

        let results = await withTaskGroup(of: SiteResult.self, returning: [SiteResult].self) { group in
            var pending = targets.makeIterator()
            func enqueue(_ site: Website) {
                group.addTask {
                    var stats: WebsiteStats?
                    var active: Int?
                    var errors: [String] = []
                    do { stats = try await client.stats(websiteId: site.id, range: range) }
                    catch { errors.append(error.localizedDescription) }
                    do { active = try await client.active(websiteId: site.id) }
                    catch { errors.append(error.localizedDescription) }
                    return SiteResult(id: site.id, stats: stats, active: active, errors: errors)
                }
            }
            for _ in 0..<4 { if let site = pending.next() { enqueue(site) } }
            var collected: [SiteResult] = []
            while let result = await group.next() {
                collected.append(result)
                if !Task.isCancelled, let site = pending.next() { enqueue(site) }
            }
            return collected
        }
        guard version == generation, !Task.isCancelled else { return }
        let now = Date()
        var failures = 0
        for result in results {
            guard let index = sites.firstIndex(where: { $0.id == result.id }) else { continue }
            if let stats = result.stats { sites[index].stats = stats }
            // Do not display a stale live visitor count after a failed request.
            sites[index].active = result.active
            sites[index].errorMessage = result.errors.first
            if result.errors.isEmpty { sites[index].updatedAt = now }
            else { failures += 1 }
        }
        errorMessage = failures > 0
            ? String.localizedStringWithFormat(String(localized: "refreshFailures"), failures, targets.count)
            : nil
        if failures == 0 { lastUpdated = now }
        if let expandedSiteId { await loadDetail(for: expandedSiteId) }
    }

    func toggle(site: SiteSnapshot) {
        if expandedSiteId == site.id { expandedSiteId = nil }
        else {
            expandedSiteId = site.id
            Task { await loadDetail(for: site.id) }
        }
    }

    func loadDetail(for id: String) async {
        guard !demoMode, settings.isConfigured,
              let index = sites.firstIndex(where: { $0.id == id }), !sites[index].isLoadingDetail else { return }
        let requestID = UUID()
        let version = generation
        let client = self.client
        let range = self.range
        detailIDs[id] = requestID
        sites[index].isLoadingDetail = true
        sites[index].detailError = nil
        defer {
            if detailIDs[id] == requestID, let index = sites.firstIndex(where: { $0.id == id }) {
                sites[index].isLoadingDetail = false
                detailIDs[id] = nil
            }
        }
        do {
            async let pages = client.metrics(websiteId: id, range: range, type: "url", limit: 5)
            async let referrers = client.metrics(websiteId: id, range: range, type: "referrer", limit: 5)
            async let series = client.pageviews(websiteId: id, range: range)
            let detail = try await SiteDetail(series: series.pageviews, visitorSeries: series.sessions,
                                             topPages: Array(pages.prefix(5)), topReferrers: Array(referrers.prefix(5)))
            guard version == generation, !Task.isCancelled,
                  let index = sites.firstIndex(where: { $0.id == id }) else { return }
            sites[index].detail = detail
        } catch {
            guard version == generation, !Task.isCancelled,
                  let index = sites.firstIndex(where: { $0.id == id }) else { return }
            sites[index].detailError = error.localizedDescription
        }
    }

    func select(range: DateRange) {
        guard self.range != range else { return }
        invalidateRequests()
        self.range = range
        settings.dateRange = range
        if !demoMode {
            lastUpdated = nil
            for index in sites.indices {
                sites[index].stats = nil
                sites[index].detail = nil
                sites[index].errorMessage = nil
            }
            Task { await refresh() }
        }
    }

    private func invalidateRequests() {
        generation += 1
        refreshID = nil
        detailIDs = [:]
        isLoading = false
        errorMessage = nil
        for index in sites.indices {
            sites[index].isLoadingDetail = false
            sites[index].detailError = nil
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        guard autoRefresh, !demoMode else { return }
        let interval = settings.refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func reconfigure() {
        stopAutoRefresh()
        invalidateRequests()
        client = clientFactory(settings.connection)
        websites = []
        sites = []
        expandedSiteId = nil
        lastUpdated = nil
        if previewMode { demoMode = false }
        if settings.isConfigured {
            Task { await refresh() }
            startAutoRefresh()
        }
    }

    // Fabricated data for screenshots/previews: UMAMIBAR_DEMO=1
    private func installDemoData() {
        func stats(_ visitors: Double, _ views: Double, _ visits: Double,
                   _ pv: Double, _ vv: Double, _ iv: Double) -> WebsiteStats {
            WebsiteStats(pageviews: views, visitors: visitors, visits: visits,
                         bounces: visitors * 0.4, totaltime: visitors * 180,
                         comparison: .init(pageviews: pv, visitors: vv,
                                           visits: iv, bounces: 0, totaltime: 0))
        }

        let shop = Website(id: "demo-shop", name: "acme-shop.com", domain: "acme-shop.com")
        let blog = Website(id: "demo-blog", name: "blog.janedoe.dev", domain: "blog.janedoe.dev")
        let docs = Website(id: "demo-docs", name: "docs.example.io", domain: "docs.example.io")

        websites = [shop, blog, docs]
        sites = [
            SiteSnapshot(website: shop,
                         stats: stats(12438, 28412, 15937, 24300, 10765, 13770),
                         active: 43),
            SiteSnapshot(website: blog,
                         stats: stats(3214, 5870, 3990, 5375, 2980, 3720),
                         active: 8,
                         detail: SiteDetail(
                            series: demoSeries(count: 24, base: 150),
                            visitorSeries: demoSeries(count: 24, base: 85),
                            topPages: [
                                MetricRow(x: "/", y: 2104),
                                MetricRow(x: "/posts/swiftui-menubar-apps", y: 1462),
                                MetricRow(x: "/posts/self-hosting-umami", y: 987),
                                MetricRow(x: "/about", y: 342),
                                MetricRow(x: "/posts/homelab-2025", y: 211),
                            ],
                            topReferrers: [
                                MetricRow(x: "news.ycombinator.com", y: 1203),
                                MetricRow(x: "google.com", y: 891),
                                MetricRow(x: "t.co", y: 244),
                                MetricRow(x: "reddit.com", y: 187),
                                MetricRow(x: "lobste.rs", y: 96),
                            ])),
            SiteSnapshot(website: docs,
                         stats: stats(987, 1452, 1120, 1710, 1155, 1300),
                         active: 2),
        ]
        for index in sites.indices where sites[index].detail == nil {
            sites[index].detail = SiteDetail(series: demoSeries(count: 24, base: 100),
                                            visitorSeries: demoSeries(count: 24, base: 55),
                                            topPages: [MetricRow(x: "/", y: 100)],
                                            topReferrers: [MetricRow(x: "", y: 50)])
        }
        expandedSiteId = blog.id
        lastUpdated = Date()
    }

    /// Deterministic wave-shaped series for screenshots/previews.
    private func demoSeries(count: Int, base: Double) -> [SeriesPoint] {
        (0..<count).map { index in
            let wave = sin(Double(index) / 3.1) * 0.5 + 0.5
            let jitter = sin(Double(index) * 1.7) * 0.12
            return SeriesPoint(x: "\(index)", y: max(1, base * (0.45 + wave * 0.55 + jitter)))
        }
    }
}
