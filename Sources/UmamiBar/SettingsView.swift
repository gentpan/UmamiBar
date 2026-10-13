import AppKit
import ServiceManagement
import SwiftUI
import UmamiBarCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showAllWebsites = true
    @State private var selectedWebsiteIDs: Set<String> = []
    @State private var kind: ServerKind = .cloud
    @State private var apiKey = ""
    @State private var selfHostedAPIKey = false
    @State private var saveError: String?
    @State private var region: CloudRegion = .auto
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var refreshInterval: TimeInterval = 60
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    private static let labelWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if store.previewMode {
                Label("Preview connection is temporary and is not saved to Keychain.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            card("Connection", systemImage: "globe") {
                Picker("Type", selection: $kind) {
                    ForEach(ServerKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if kind == .cloud {
                    row("API key") {
                        SecureField("", text: $apiKey, prompt: Text("umami_api_…"))
                    }
                    row("Region") {
                        Picker("", selection: $region) {
                            ForEach(CloudRegion.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("") {
                        Link(destination: URL(string: "https://cloud.umami.is/settings/api-keys")!) {
                            Text("Create a key at cloud.umami.is → Settings → API keys")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    row("Server URL") {
                        TextField("", text: $baseURL, prompt: Text("https://analytics.example.com"))
                    }
                    Toggle("Use an API key", isOn: $selfHostedAPIKey)
                    if selfHostedAPIKey {
                        row("API key") { SecureField("", text: $apiKey) }
                    } else {
                    row("Username") {
                        TextField("", text: $username)
                    }
                    row("Password") {
                        SecureField("", text: $password)
                    }
                    }
                }

                HStack(spacing: 8) {
                    Button(isTesting ? "Testing…" : "Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.glass)
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else if let testResult {
                        Label {
                            Text(testResult).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? .green : .red)
                    }
                }
            }

            card("Displayed websites", systemImage: "list.bullet") {
                Picker("Display", selection: $showAllWebsites) {
                    Text("All websites").tag(true)
                    Text("Selected websites").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !showAllWebsites {
                    if store.websites.isEmpty {
                        Text("Connect to load the website list.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Refresh") { Task { await store.refresh() } }
                            .disabled(store.isLoading)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(store.websites.sorted { $0.name < $1.name }) { website in
                                    Toggle(isOn: Binding(
                                        get: { selectedWebsiteIDs.contains(website.id) },
                                        set: { selected in
                                            if selected { selectedWebsiteIDs.insert(website.id) }
                                            else { selectedWebsiteIDs.remove(website.id) }
                                        })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(website.name)
                                            Text(website.domain).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.padding(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .scrollIndicators(.hidden)
                        Text("Select at least one website. A single website opens expanded.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            card("General", systemImage: "gearshape") {
                row("Refresh every") {
                    Picker("", selection: $refreshInterval) {
                        Text("30 seconds").tag(TimeInterval(30))
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                row("Startup") {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .disabled(store.previewMode)
                        if let launchError {
                            Text(launchError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(store.previewMode ? LocalizedStringKey("Connect for preview") : LocalizedStringKey("Save")) {
                    save()
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(isTesting || (!showAllWebsites && !store.websites.contains { selectedWebsiteIDs.contains($0.id) }))
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .textFieldStyle(.roundedBorder)
        .background { ScrollChromeHider(layoutHeight: showAllWebsites ? 1 : 2) }
        .onAppear {
            loadFromStore()
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(store.previewMode ? .regular : .accessory)
        }
        .task { if store.websites.isEmpty { await store.refresh() } }
        .onChange(of: formConnection) { _, _ in testResult = nil; saveError = nil }
    }

    /// Liquid-glass card with a floating capsule label overlapping its top edge.
    private func card<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .overlay(alignment: .topLeading) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .padding(.leading, 14)
                .offset(y: -14)
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadFromStore() {
        let s = store.settings
        showAllWebsites = s.visibleWebsiteIDs == nil
        selectedWebsiteIDs = Set(s.visibleWebsiteIDs ?? [])
        kind = s.kind
        apiKey = s.apiKey
        selfHostedAPIKey = s.kind == .selfHosted && !apiKey.isEmpty
        region = s.region
        baseURL = s.baseURL
        username = s.username
        password = s.password
        refreshInterval = s.refreshInterval
        launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
        if SMAppService.mainApp.status == .requiresApproval {
            launchError = String(localized: "Allow UmamiBar in System Settings → General → Login Items.")
        }
    }

    private var formConnection: Connection {
        Connection(kind: kind, baseURL: baseURL, region: region,
                   apiKey: kind == .cloud || selfHostedAPIKey ? apiKey : "",
                   username: username, password: password).normalized
    }

    private func applyToStore() throws {
        let s = store.settings
        if s.connection != formConnection { try s.apply(formConnection) }
        s.refreshInterval = refreshInterval
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let testedConnection = formConnection
        let client = UmamiClient(connection: testedConnection)
        Task {
            do {
                let count = try await client.testConnection()
                await MainActor.run {
                    guard formConnection == testedConnection else { isTesting = false; return }
                    testResult = String.localizedStringWithFormat(String(localized: "connectedWebsites"), count)
                    testSucceeded = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    guard formConnection == testedConnection else { isTesting = false; return }
                    testResult = error.localizedDescription
                    testSucceeded = false
                    isTesting = false
                }
            }
        }
    }

    private func save() {
        do {
            let connectionChanged = store.settings.connection != formConnection
            try applyToStore()
            let ids = showAllWebsites ? nil : Array(selectedWebsiteIDs)
            if connectionChanged {
                store.settings.visibleWebsiteIDs = ids
                store.reconfigure()
            } else {
                store.startAutoRefresh()
                store.updateWebsiteVisibility(ids)
            }
            if store.previewMode { dismissWindow(id: "settings"); return }
            let status = SMAppService.mainApp.status
            do {
                if launchAtLogin && status != .enabled && status != .requiresApproval {
                    try SMAppService.mainApp.register()
                } else if !launchAtLogin && (status == .enabled || status == .requiresApproval) {
                    try SMAppService.mainApp.unregister()
                }
                launchError = nil
            } catch {
                launchError = error.localizedDescription
                return
            }
            if SMAppService.mainApp.status == .requiresApproval {
                launchError = String(localized: "Allow UmamiBar in System Settings → General → Login Items.")
                return
            }
            dismissWindow(id: "settings")
        } catch {
            saveError = error.localizedDescription
        }
    }
}
