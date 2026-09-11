import AppKit
import SwiftUI

@MainActor
final class Navigator: ObservableObject {
  enum Screen {
    case main
    case settings
  }

  @Published var screen = Screen.main
}

struct MainView: View {
  @ObservedObject var desktop: LiveDesktop
  @ObservedObject var navigator: Navigator

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.6)
      content
    }
    .frame(width: 460, height: 580)
  }

  private var header: some View {
    ZStack {
      Text(navigator.screen == .main ? "Hinge" : "Settings")
        .font(.system(size: 13, weight: .semibold))
      HStack(spacing: 0) {
        if navigator.screen == .settings {
          HeaderButton(symbol: "chevron.left", help: "Back") { navigator.screen = .main }
            .keyboardShortcut(.escape, modifiers: [])
        }
        Spacer(minLength: 0)
        if navigator.screen == .main {
          HeaderButton(symbol: "gearshape.fill", help: "Settings") {
            navigator.screen = .settings
          }
          .keyboardShortcut(",", modifiers: .command)
        }
      }
      .padding(.leading, 76)
      .padding(.trailing, 12)
    }
    .frame(height: 40)
    .background(HeaderMaterial().ignoresSafeArea())
  }

  private var content: some View {
    ZStack {
      switch navigator.screen {
      case .main:
        home
          .transition(.move(edge: .leading).combined(with: .opacity))
      case .settings:
        SettingsView(desktop: desktop)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.22), value: navigator.screen)
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
  }

  private var home: some View {
    VStack(spacing: 20) {
      Spacer(minLength: 8)
      hero
      if let error = desktop.error { errorCard(error) }
      Spacer(minLength: 8)
      positionCard
    }
    .padding(EdgeInsets(top: 20, leading: 20, bottom: 22, trailing: 20))
  }

  private var hero: some View {
    VStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill((desktop.isActive ? Color.accentColor : Color.gray).gradient)
        .frame(width: 84, height: 84)
        .overlay(
          Image(
            systemName: desktop.isActive ? "laptopcomputer.and.arrow.down" : "laptopcomputer"
          )
          .font(.system(size: 36, weight: .medium))
          .foregroundStyle(.white)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.2), value: desktop.isActive)
      VStack(spacing: 4) {
        Text(title)
          .font(.system(size: 20, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(desktop.isEnabled ? "Turn off" : "Turn on") {
        desktop.setEnabled(!desktop.isEnabled)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(desktop.isStarting)
      Text("⌃⌥H anywhere")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity)
  }

  private var positionCard: some View {
    SettingsGroup(
      title: "Open position",
      footnote: "Starts at 100°. Set your comfortable open position once, and Hinge remembers it."
    ) {
      SettingsRow(
        "angle", tint: .indigo, title: "Open position", subtitle: "\(Int(desktop.openAngle))°"
      ) {
        Button("Set") { desktop.setOpenPosition() }
          .controlSize(.small)
          .disabled(!desktop.sensorAvailable || desktop.isStarting)
          .help("Save the lid angle you are viewing at right now")
      }
    }
  }

  private func errorCard(_ message: String) -> some View {
    SettingsGroup(title: "Attention") {
      SettingsRow("exclamationmark.triangle.fill", tint: .orange, title: message) {
        if desktop.needsPermission {
          Button("Open Settings", action: openScreenRecordingSettings)
            .controlSize(.small)
        }
      }
    }
  }

  private var title: String {
    if desktop.isActive { return "On" }
    if desktop.isStarting { return "Starting…" }
    return desktop.isEnabled ? "Waiting…" : "Off"
  }

  private var subtitle: String {
    if desktop.isActive { return "Your desktop bends as the lid closes." }
    if desktop.isStarting { return "Getting the desktop and the sensor ready." }
    if desktop.isWaitingForDisplay { return "Waiting for the built-in display to turn on." }
    if !desktop.sensorAvailable { return "Waiting for the lid angle sensor." }
    if desktop.isEnabled { return "Hinge is on but not running yet." }
    return "Turn Hinge on to follow the lid."
  }
}

private struct HeaderButton: View {
  let symbol: String
  let help: String
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 26, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.09 : 0))
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct HeaderMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .titlebar
    view.blendingMode = .withinWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
