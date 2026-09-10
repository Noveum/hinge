import SwiftUI
import AppKit

@main
struct HingeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var desktop = LiveDesktop()

    var body: some Scene {
        Window("Hinge", id: "settings") {
            SettingsView(desktop: desktop)
                .onAppear { delegate.onTerminate = { desktop.shutDown() } }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) { Text("Hinge \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") }
        }
        MenuBarExtra("Hinge", systemImage: desktop.isActive ? "laptopcomputer.and.arrow.down" : "laptopcomputer") {
            HingeMenu(desktop: desktop)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}

struct HingeMenu: View {
    @ObservedObject var desktop: LiveDesktop
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(desktop.isActive ? "Turn off" : "Turn on") {
            if desktop.isActive { desktop.stop() }
            else { Task { await desktop.start() } }
        }
        .disabled(desktop.isStarting)
        Button("Set open position") { desktop.setOpenPosition() }
            .disabled(!desktop.sensorAvailable || desktop.isStarting)
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Button("Quit Hinge") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
