import AppKit
import SwiftUI
import UmamiBarCore

@main
struct UmamiBarApp: App {
    @State private var store = AppStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("UmamiBar", systemImage: "chart.bar.xaxis") {
            PopoverView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("UmamiBar Preview", id: "preview") {
            PopoverView()
                .environment(store)
                .onAppear {
                    if store.previewMode { NSApp.setActivationPolicy(.regular) }
                }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(store.previewMode ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("--settings") ? .presented : .suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
