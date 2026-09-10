import SwiftUI
import AppKit

@main
struct BendyPrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = BendModel()
    @StateObject private var desktop = LiveDesktop()

    var body: some Scene {
        Window("Bendy Prototype", id: "settings") {
            SettingsView(model: model, desktop: desktop)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.onTerminate = { desktop.stop(); model.shutDown() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Text("Bendy Prototype 0.2")
            }
        }
        MenuBarExtra("Bendy", systemImage: desktop.isActive ? "laptopcomputer.and.arrow.down" : "laptopcomputer") {
            BendyMenu(model: model, desktop: desktop)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}

struct BendyMenu: View {
    @ObservedObject var model: BendModel
    @ObservedObject var desktop: LiveDesktop
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.sensorAngle.map { "Lid angle: \(Int($0))°" } ?? "Lid sensor unavailable")
        Text(desktop.status)
        Divider()
        if desktop.isActive {
            Button("Stop desktop effect") { desktop.stop() }
                .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button("Follow my MacBook lid") { Task { await desktop.start(model: model) } }
                .disabled(desktop.isStarting || model.sensorAngle == nil)
            Button("Play on my desktop") { Task { await desktop.start(model: model, demo: true) } }
                .disabled(desktop.isStarting)
        }
        Menu("Style") {
            Picker("Style", selection: $model.style) {
                ForEach(BendStyle.allCases) { style in Text(style.rawValue).tag(style) }
            }
        }
        Toggle("Opening sound", isOn: $model.soundEnabled)
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Button("Quit Bendy") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
