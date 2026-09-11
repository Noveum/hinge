import AppKit
import SwiftUI

struct MainView: View {
  @ObservedObject var desktop: LiveDesktop
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.6)
      ScrollView {
        VStack(spacing: 20) {
          hero
          if let error = desktop.error { errorCard(error) }
          positionCard
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20))
      }
      .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
    .frame(width: 420, height: 470)
  }

  private var header: some View {
    ZStack {
      Text("Hinge")
        .font(.system(size: 13, weight: .semibold))
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        HeaderButton(symbol: "gearshape.fill", help: "Settings") {
          openWindow(id: "settings")
          NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
      }
      .padding(.trailing, 12)
    }
    .frame(height: 40)
    .background(HeaderMaterial().ignoresSafeArea())
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
      Button(desktop.isActive ? "Turn off" : "Turn on") {
        if desktop.isActive {
          desktop.stop()
        } else {
          Task { await desktop.start() }
        }
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
    if desktop.isStarting { return "Starting…" }
    return desktop.isActive ? "On" : "Off"
  }

  private var subtitle: String {
    if desktop.isStarting { return "Getting the desktop and the sensor ready." }
    if desktop.isActive { return "Your desktop bends as the lid closes." }
    if !desktop.sensorAvailable { return "Waiting for the lid angle sensor." }
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
