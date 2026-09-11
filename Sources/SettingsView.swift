import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var desktop: LiveDesktop
  @State private var loginItemStatus = SMAppService.mainApp.status
  @State private var loginItemError: String?
  @State private var language = AppLanguage.current

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
    SettingsGroup(title: String(localized: "Look")) {
      SettingsRow(
        "slider.horizontal.3", tint: .orange, title: String(localized: "Effect strength"),
        subtitle: strength
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
          .accessibilityValue(strength)
          Button {
            desktop.setEffectStrength(1)
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }
          .controlSize(.small)
          .disabled(desktop.effectStrength == 1)
          .help(String(localized: "Reset effect strength to 100%"))
          .accessibilityLabel("Reset effect strength to default")
        }
      }
      SettingsDivider()
      SettingsRow(
        "square.lefthalf.filled", tint: .indigo, title: String(localized: "Sides"),
        subtitle: String(localized: "Beside the folded desktop")
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
    SettingsGroup(title: String(localized: "Controls")) {
      SettingsRow(
        "power", tint: .blue, title: String(localized: "Launch at login"),
        subtitle: loginItemError ?? loginItemNote
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
      SettingsRow("keyboard", tint: .gray, title: String(localized: "Turn Hinge on or off")) {
        Text("⌃⌥H")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
      }
      SettingsDivider()
      SettingsRow(
        "globe", tint: .indigo, title: String(localized: "Language"),
        subtitle: language == AppLanguage.atLaunch
          ? nil : String(localized: "Relaunch Hinge to switch languages.")
      ) {
        if language != AppLanguage.atLaunch {
          Button("Relaunch", action: AppLanguage.relaunch)
            .controlSize(.small)
        }
        Picker(
          "Language",
          selection: Binding(
            get: { language },
            set: {
              language = $0
              AppLanguage.choose($0)
            })
        ) {
          Text("System Language").tag("")
          ForEach(AppLanguage.available, id: \.self) { code in
            Text(verbatim: AppLanguage.name(of: code)).tag(code)
          }
        }
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
      }
    }
  }

  private var status: some View {
    SettingsGroup(
      title: String(localized: "Status"),
      footnote: String(
        localized:
          "Hinge reads your display only to draw the fold. Frames stay in memory on your Mac.")
    ) {
      let allowed = CGPreflightScreenCaptureAccess()
      SettingsRow(
        "rectangle.dashed.badge.record", tint: .red, title: String(localized: "Screen Recording"),
        subtitle: allowed
          ? String(localized: "Allowed") : String(localized: "Needed to show your live desktop")
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
        "laptopcomputer", tint: .teal, title: String(localized: "Lid angle sensor"),
        subtitle: desktop.sensorAvailable
          ? String(localized: "Connected") : String(localized: "Not connected")
      ) {
        Circle()
          .fill(desktop.sensorAvailable ? Color.green : Color.orange)
          .frame(width: 8, height: 8)
      }
    }
  }

  private var about: some View {
    SettingsGroup(title: String(localized: "About")) {
      SettingsRow(
        title: "Hinge \(version)", subtitle: String(localized: "Your desktop follows your lid."),
        leading: { Image(nsImage: NSApp.applicationIconImage).resizable() },
        trailing: {
          if let project = URL(string: "https://github.com/Noveum/hinge") {
            Link("GitHub", destination: project).font(.system(size: 12))
          }
        })
    }
  }

  private var loginItemNote: String? {
    loginItemStatus == .requiresApproval
      ? String(localized: "Allow Hinge in Login Items to finish.") : nil
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
      loginItemError = String(
        localized: "Could not update Launch at Login: \(error.localizedDescription)")
    }
    loginItemStatus = SMAppService.mainApp.status
  }

  private var strength: String {
    desktop.effectStrength.formatted(.percent.precision(.fractionLength(0)))
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }
}

private enum AppLanguage {
  static let atLaunch = current

  static var current: String {
    let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    return (domain?["AppleLanguages"] as? [String])?.first ?? ""
  }

  static let available = Set(Bundle.main.localizations).subtracting(["Base"]).sorted {
    name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending
  }

  static func name(of code: String) -> String {
    let locale = Locale(identifier: code)
    return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
  }

  static func choose(_ code: String) {
    if code.isEmpty {
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    } else {
      UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
  }

  static func relaunch() {
    let reopen = Process()
    reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
    reopen.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
    try? reopen.run()
    NSApp.terminate(nil)
  }
}
