import SwiftUI
import AppKit

// NOTE: this file must NOT be named `main.swift` — SwiftPM treats main.swift as implicit
// top-level code and it collides with `@main`.

@main
struct WeChatAntiRecallGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 540, idealWidth: 580, maxWidth: 720, minHeight: 620, idealHeight: 680)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no "New Window"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensures the app activates as a normal windowed app even when the SwiftPM binary is
        // launched directly during development (before it is wrapped in a .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
