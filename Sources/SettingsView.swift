import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var desktop: LiveDesktop
  @State private var page = Page.effect

  enum Page: String, CaseIterable, Identifiable {
    case effect
    case general

    var id: String { rawValue }

    var title: String {
      switch self {
      case .effect: "Effect"
      case .general: "General"
      }
    }

    var symbol: String {
      switch self {
      case .effect: "laptopcomputer"
      case .general: "gearshape.fill"
      }
    }

    var tint: Color {
      switch self {
      case .effect: .blue
      case .general: .gray
      }
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: 180)
        .background(SidebarMaterial().ignoresSafeArea())
      Divider().ignoresSafeArea()
      switch page {
      case .effect: EffectPage(desktop: desktop)
      case .general: GeneralPage(desktop: desktop)
      }
    }
    .frame(width: 620, height: 460)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      Color.clear.frame(height: 10)
      ForEach(Page.allCases) { item in
        Button {
          page = item
        } label: {
          HStack(spacing: 10) {
            SettingsIcon(symbol: item.symbol, tint: item.tint)
            Text(item.title)
              .font(.system(size: 13))
              .foregroundStyle(page == item ? Color.white : Color.primary)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(page == item ? Color.accentColor : .clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 9)
  }
}

private struct EffectPage: View {
  @ObservedObject var desktop: LiveDesktop

  var body: some View {
    SettingsPage {
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
            .frame(width: 120)
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
      }
    }
  }

  private var status: String {
    if desktop.isStarting { return "Starting…" }
    return desktop.isActive ? "On. Your desktop bends as the lid closes." : "Off"
  }
}

private struct GeneralPage: View {
  @ObservedObject var desktop: LiveDesktop
  @State private var loginItemStatus = SMAppService.mainApp.status
  @State private var loginItemError: String?

  var body: some View {
    SettingsPage {
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
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      loginItemStatus = SMAppService.mainApp.status
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
