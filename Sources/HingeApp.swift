import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct HingeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var desktop = LiveDesktop()

  var body: some Scene {
    Window("Hinge", id: "main") {
      MainView(desktop: desktop)
        .onAppear {
          delegate.onTerminate = { desktop.shutDown() }
          delegate.installToggleHotKey {
            if desktop.isActive {
              desktop.stop()
            } else if !desktop.isStarting {
              Task { await desktop.start() }
            }
          }
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultPosition(.center)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Text(
          "Hinge \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        )
      }
    }
    settingsWindow
    MenuBarExtra(
      "Hinge", systemImage: desktop.isActive ? "laptopcomputer.and.arrow.down" : "laptopcomputer"
    ) {
      HingeMenu(desktop: desktop)
    }
  }

  private var settingsWindow: some Scene {
    Window("Settings", id: "settings") {
      SettingsView(desktop: desktop)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var onTerminate: (() -> Void)?
  private var toggleHotKey: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationWillTerminate(_ notification: Notification) {
    if let toggleHotKey { UnregisterEventHotKey(toggleHotKey) }
    if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    onTerminate?()
  }

  func installToggleHotKey(_ action: @escaping () -> Void) {
    onToggle = action
    guard toggleHotKey == nil else { return }
    var event = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    var handler: EventHandlerRef?
    let context = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in delegate.onToggle?() }
        return noErr
      }, 1, &event, context, &handler)
    guard handlerStatus == noErr else {
      showHotKeyError(handlerStatus)
      return
    }
    var hotKey: EventHotKeyRef?
    let hotKeyStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
      EventHotKeyID(signature: OSType(0x484E_4745), id: 1), GetApplicationEventTarget(), 0,
      &hotKey)
    guard hotKeyStatus == noErr else {
      if let handler { RemoveEventHandler(handler) }
      showHotKeyError(hotKeyStatus)
      return
    }
    hotKeyHandler = handler
    toggleHotKey = hotKey
  }

  private var onToggle: (() -> Void)?

  private func showHotKeyError(_ status: OSStatus) {
    let alert = NSAlert()
    alert.messageText = "Keyboard shortcut unavailable"
    alert.informativeText = "Hinge could not register ⌃⌥H (error \(status))."
    alert.alertStyle = .warning
    alert.runModal()
  }
}

struct HingeMenu: View {
  @ObservedObject var desktop: LiveDesktop
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button {
      if desktop.isActive { desktop.stop() } else { Task { await desktop.start() } }
    } label: {
      HStack {
        Text(desktop.isActive ? "Turn off" : "Turn on")
        Spacer()
        Text("⌃⌥H").foregroundStyle(.secondary)
      }
    }
    .disabled(desktop.isStarting)
    Button("Set open position") { desktop.setOpenPosition() }
      .disabled(!desktop.sensorAvailable || desktop.isStarting)
    Divider()
    Button("Open Hinge") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("Settings…") {
      openWindow(id: "settings")
      NSApp.activate(ignoringOtherApps: true)
    }.keyboardShortcut(",")
    Button("Quit Hinge") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
}
