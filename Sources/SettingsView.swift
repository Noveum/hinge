import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var desktop: LiveDesktop
  @State private var loginItemStatus = SMAppService.mainApp.status
  @State private var loginItemError: String?

  var body: some View {
    SettingsPage {
      look
      controls
      status
      about
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      loginItemStatus = SMAppService.mainApp.status
    }
  }

  private var look: some View {
    SettingsGroup(title: "Look") {
      SettingsRow(
        "slider.horizontal.3", tint: .orange, title: "Effect strength",
        subtitle: "\(Int(desktop.effectStrength * 100))%"
      ) {
        HStack(spacing: 8) {
          Slider(
            value: Binding(
              get: { desktop.effectStrength },
              set: { desktop.setEffectStrength($0) }),
            in: 0.25...1, step: 0.05
          )
          .frame(width: 110)
          .accessibilityLabel("Effect strength")
          .accessibilityValue("\(Int(desktop.effectStrength * 100)) percent")
          Button("Default") { desktop.setEffectStrength(1) }
            .controlSize(.small)
            .fixedSize()
            .disabled(desktop.effectStrength == 1)
            .help("Reset effect strength to 100%")
            .accessibilityLabel("Reset effect strength to default")
        }
      }
      SettingsDivider()
      SettingsRow(
        "square.lefthalf.filled", tint: .indigo, title: "Sides",
        subtitle: "Beside the folded desktop"
      ) {
        Picker(
          "Sides",
          selection: Binding(get: { desktop.sideFill }, set: { desktop.setSideFill($0) })
        ) {
          Text("Blur").tag(SideFill.blur)
          Text("Black").tag(SideFill.black)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
      }
    }
  }

  private var controls: some View {
    SettingsGroup(title: "Controls") {
      SettingsRow(
        "power", tint: .blue, title: "Launch at login", subtitle: loginItemError ?? loginItemNote
      ) {
        if loginItemStatus == .requiresApproval {
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            .controlSize(.small)
        }
        Toggle("Launch at login", isOn: launchAtLogin)
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
      }
      SettingsDivider()
      SettingsRow("keyboard", tint: .gray, title: "Turn Hinge on or off") {
        Text("⌃⌥H")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
      }
    }
  }

  private var status: some View {
    SettingsGroup(
      title: "Status",
      footnote:
        "Hinge reads your display only to draw the fold. Frames stay in memory on your Mac."
    ) {
      let allowed = CGPreflightScreenCaptureAccess()
      SettingsRow(
        "rectangle.dashed.badge.record", tint: .red, title: "Screen Recording",
        subtitle: allowed ? "Allowed" : "Needed to show your live desktop"
      ) {
        if allowed {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
          Button("Open Settings", action: openScreenRecordingSettings)
            .controlSize(.small)
        }
      }
      SettingsDivider()
      SettingsRow(
        "laptopcomputer", tint: .teal, title: "Lid angle sensor",
        subtitle: desktop.sensorAvailable ? "Connected" : "Not connected"
      ) {
        Circle()
          .fill(desktop.sensorAvailable ? Color.green : Color.orange)
          .frame(width: 8, height: 8)
      }
    }
  }

  private var about: some View {
    SettingsGroup(title: "About") {
      SettingsRow(
        title: "Hinge \(version)", subtitle: "Your desktop follows your lid.",
        leading: { Image(nsImage: NSApp.applicationIconImage).resizable() },
        trailing: {
          if let project = URL(string: "https://github.com/Noveum/hinge") {
            Link("GitHub", destination: project).font(.system(size: 12))
          }
        })
    }
  }

  private var loginItemNote: String? {
    loginItemStatus == .requiresApproval ? "Allow Hinge in Login Items to finish." : nil
  }

  private var launchAtLogin: Binding<Bool> {
    Binding(
      get: {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
      },
      set: setLaunchAtLogin)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginItemError = nil
    } catch {
      loginItemError = "Could not update Launch at Login: \(error.localizedDescription)"
    }
    loginItemStatus = SMAppService.mainApp.status
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }
}
