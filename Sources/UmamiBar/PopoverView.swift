import AppKit
import SwiftUI
import UmamiBarCore

struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var listHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        // An opaque surface prevents wallpaper and other windows tinting the panel.
        VStack(alignment: .leading, spacing: 12) {
            if store.isReady {
                header
                siteList
                if let message = store.errorMessage {
                    errorBanner(message)
                }
            } else {
                emptyContent
            }

            footer
        }
        .padding(14)
        .tint(Theme.brand)
        .frame(width: Theme.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .containerBackground(Color.white, for: .window)
        .preferredColorScheme(.light)
        .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { contentHeight = $0 }
        .background {
            // Standard preview windows already resize through SwiftUI.
            if !store.previewMode { WindowHeightResizer(height: contentHeight) }
            ScrollChromeHider(layoutHeight: contentHeight)
        }
        .task {
            await store.panelOpened()
            await store.refresh()
            await store.panelOpened()
        }

    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            UmamiMark()
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text("UmamiBar")
                .font(.headline)

            Spacer()

            rangeMenu
        }
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(DateRange.allCases) { range in
                Button(range.title) { store.select(range: range) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(store.range.title)
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.04), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Empty state

    /// Sits inside the unified card; the footer gear button opens settings.
    private var emptyContent: some View {
        VStack(spacing: 10) {
            UmamiMark().foregroundStyle(.black).frame(width: 32, height: 32)

            Text("Connect to Umami")
                .font(.headline)

            Text("Add your Umami Cloud API key or self-hosted server details.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
    }

    // MARK: - Metrics

    private func deltaText(_ current: Double, _ previous: Double?) -> Text {
        guard let previous, previous > 0 else { return Text("") }
        let delta = (current - previous) / previous
        return Text(String(format: "%@%.0f%%", delta >= 0 ? "↑" : "↓", abs(delta) * 100))
            .foregroundStyle(delta >= 0 ? .green : .red)
    }

    private static let metricWidth: CGFloat = 58
    private static let metricSpacing: CGFloat = 8

    private func metricCell(_ value: Double?, _ previous: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.map(compactNumber) ?? "–")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            deltaText(value ?? 0, previous)
                .font(.caption2)
        }
        .frame(width: Self.metricWidth, alignment: .trailing)
    }

    private func columnHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.metricWidth, alignment: .trailing)
    }

    // MARK: - Site list

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Self.metricSpacing) {
                Spacer(minLength: 0)
                columnHeader("Visitors")
                columnHeader("Views")
                columnHeader("Visits")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            let sorted = store.visibleSites.sorted(by: { $0.website.name < $1.website.name })
            if sorted.isEmpty {
                Group {
                    if store.isLoading || (store.lastUpdated == nil && store.errorMessage == nil) {
                        ProgressView()
                    } else {
                        Text("No websites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(sorted) { site in
                            VStack(spacing: 10) {
                                HoverableButton({
                                    store.toggle(site: site)
                                }, isActive: store.expandedSiteId == site.id) {
                                    rowLabel(site)
                                }
                                if store.expandedSiteId == site.id {
                                    detailView(site)
                                        .padding(.bottom, 10)
                                }
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { listHeight = $0 }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight == 0 ? nil : min(listHeight, 460))
            }
        }
    }

    private func rowLabel(_ site: SiteSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(store.expandedSiteId == site.id ? 90 : 0))
                .animation(.easeOut(duration: 0.12), value: store.expandedSiteId)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(site.website.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if site.errorMessage != nil {
                    Label("Refresh failed", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                        .help(site.errorMessage ?? "")
                }
                if let active = site.active, active > 0 {
                    HStack(spacing: 5) {
                        LiveDot()
                        Text(String.localizedStringWithFormat(String(localized: "activeCount"), active))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(site.website.domain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Self.metricSpacing) {
                metricCell(site.stats?.visitors, site.stats?.comparison?.visitors)
                metricCell(site.stats?.pageviews, site.stats?.comparison?.pageviews)
                metricCell(site.stats?.visits, site.stats?.comparison?.visits)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded detail

    private func detailView(_ site: SiteSnapshot) -> some View {
        Group {
            if let detail = site.detail {
                VStack(alignment: .leading, spacing: 12) {
                    if store.range == .today || !detail.series.isEmpty || !detail.visitorSeries.isEmpty {
                        chartPanel(detail)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 10),
                                        GridItem(.flexible(minimum: 0), spacing: 10)],
                              alignment: .leading, spacing: 10) {
                        detailPanel("Top pages", systemImage: "doc.text.magnifyingglass", rows: detail.topPages)
                        detailPanel("Top referrers", systemImage: "arrowshape.turn.up.left.circle", rows: detail.topReferrers)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if site.isLoadingDetail {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            if let message = site.detailError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.loadDetail(for: site.id) } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chartPanel(_ detail: SiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Traffic", systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                chartLegend("Visitors", color: Theme.visitorsBlue)
                chartLegend("Views", color: Theme.pageviewsBlue)
            }
            TrafficBarChart(points: detail.series, visitors: detail.visitorSeries, range: store.range)
                .frame(height: 82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .insetCard(cornerRadius: 10)
    }

    private func chartLegend(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func detailPanel(_ title: LocalizedStringKey, systemImage: String, rows: [MetricRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            let max = rows.map(\.y).max() ?? 1
            VStack(spacing: 3) {
                if rows.isEmpty { Text("No data").font(.caption).foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    barRow(row, max: max)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .insetCard(cornerRadius: 10)
    }

    private func barRow(_ row: MetricRow, max: Double) -> some View {
        let fraction = max > 0 ? CGFloat(row.y / max) : 0
        return HStack(spacing: 6) {
            Text(row.x.isEmpty ? String(localized: "(direct)") : row.x)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(compactNumber(row.y))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.softBlue)
                        .frame(width: Swift.max(4, geo.size.width * fraction))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Error & footer

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            if store.previewMode && !store.demoMode {
                Text("Live preview").font(.caption).foregroundStyle(.secondary)
            }
            if store.demoMode {
                Text("Demo data").font(.caption).foregroundStyle(.secondary)
            } else if store.isReady, let last = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text(String.localizedStringWithFormat(String(localized: "updatedAgo"), relativeTime(last)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 14) {
                if store.isReady {
                    FooterButton {
                        Task { await store.refresh() }
                    } label: {
                        if store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isLoading)
                }

                FooterButton {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings…")
                Menu {
                    Button("Open Umami dashboard") {
                        if let url = URL(string: store.settings.connection.dashboardURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Quit UmamiBar") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

/// Hide native scrollers as well as SwiftUI indicators without changing system preferences.
struct ScrollChromeHider: NSViewRepresentable {
    var layoutHeight: CGFloat

    final class AnchorView: NSView {
        var apply: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply?()
        }
        override func layout() {
            super.layout()
            apply?()
        }
    }

    @MainActor private static func hide(in view: NSView) {
        if let scroll = view as? NSScrollView {
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
            if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
        }
        if view is NSScroller, !view.isHidden { view.isHidden = true }
        for child in view.subviews { hide(in: child) }
    }

    @MainActor private static func schedule(_ view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let root = view?.window?.contentView else { return }
            hide(in: root)
        }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.apply = { [weak view] in
            if let view { Self.schedule(view) }
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        Self.schedule(nsView)
    }
}

/// Minimal footer icon button: bare symbol, no ring, with a faint circular
/// hover highlight.
private struct FooterButton<Label: View>: View {
    @State private var hovering = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 16, height: 16)
                .font(.system(size: 13, weight: .medium))
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                }
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MenuBarExtra(.window) grows its panel to fit expanding content but never
// shrinks it back, leaving dead translucent space around a centered view.
// Measure the ideal content height and resize the panel to match.
private struct WindowHeightResizer: NSViewRepresentable {
    var height: CGFloat

    final class SyncView: NSView {
        var onMoveToWindow: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onMoveToWindow?() }
        }
    }

    @MainActor final class Coordinator {
        var height: CGFloat = 0

        private var isScheduled = false

        func schedule(_ view: NSView) {
            guard !isScheduled else { return }
            isScheduled = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.isScheduled = false
                if let view { self.sync(view) }
            }
        }

        private func sync(_ view: NSView) {
            guard height > 0,
                  let window = view.window,
                  !window.styleMask.contains(.titled),
                  let contentView = window.contentView else { return }
            guard abs(contentView.bounds.height - height) > 0.5 else { return }
            // Keep the popover anchored below the menu bar while its contents shrink.
            let change = height - contentView.bounds.height
            var frame = window.frame
            frame.origin.y -= change
            frame.size.height += change
            window.setFrame(frame, display: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SyncView {
        let view = SyncView(frame: .zero)
        view.onMoveToWindow = { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            coordinator?.schedule(view)
        }
        return view
    }

    func updateNSView(_ nsView: SyncView, context: Context) {
        context.coordinator.height = height
        context.coordinator.schedule(nsView)
    }
}

struct HoverableButton<Label: View>: View {
    @State private var isHovering = false
    let action: () -> Void
    var isActive = false
    @ViewBuilder let label: () -> Label

    init(_ action: @escaping () -> Void, isActive: Bool = false,
         @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.isActive = isActive
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(HoverButtonStyle(isHovering: isHovering, isActive: isActive))
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous))
        .onHover { isHovering = $0 }
    }
}

struct HoverButtonStyle: ButtonStyle {
    let isHovering: Bool
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(
                        isActive
                            ? Theme.softBlue
                            : Color.primary.opacity(configuration.isPressed ? 0.10 : (isHovering ? 0.055 : 0))
                    )
            )
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
