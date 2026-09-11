import SwiftUI

struct SettingsView: View {
  @ObservedObject var desktop: LiveDesktop

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 14) {
        Image(systemName: "laptopcomputer")
          .font(.system(size: 29, weight: .light))
          .foregroundStyle(.blue)
          .frame(width: 54, height: 54)
          .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 4) {
          Text("Hinge").font(.system(size: 26, weight: .semibold))
          Text("Your desktop follows your lid.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      VStack(spacing: 18) {
        Toggle(
          isOn: Binding(
            get: { desktop.isActive || desktop.isStarting },
            set: { enabled in
              if enabled { Task { await desktop.start() } } else { desktop.stop() }
            })
        ) {
          HStack(spacing: 7) {
            Circle().fill(desktop.isActive ? Color.green : Color.secondary.opacity(0.45))
              .frame(width: 6, height: 6)
            Text(desktop.isStarting ? "Starting…" : desktop.isActive ? "On" : "Off")
              .fontWeight(.medium)
          }
        }
        .toggleStyle(.switch)
        .disabled(desktop.isStarting)
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Effect strength").fontWeight(.medium)
            Text("\(Int(desktop.effectStrength * 100))%")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Spacer()
          Slider(
            value: Binding(
              get: { desktop.effectStrength },
              set: { desktop.setEffectStrength($0) }),
            in: 0.25...1, step: 0.05
          )
          .frame(width: 100)
          .accessibilityLabel("Effect strength")
          .accessibilityValue("\(Int(desktop.effectStrength * 100)) percent")
          Button("Default") { desktop.setEffectStrength(1) }
            .disabled(desktop.effectStrength == 1)
            .help("Reset effect strength to 100%")
            .accessibilityLabel("Reset effect strength to default")
        }
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Open position").fontWeight(.medium)
            Text("\(Int(desktop.openAngle))°")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Spacer()
          Button("Set open position") { desktop.setOpenPosition() }
            .disabled(!desktop.sensorAvailable || desktop.isStarting)
        }
      }
      .font(.system(size: 12))
      if let error = desktop.error {
        VStack(alignment: .leading, spacing: 8) {
          Text(error).foregroundStyle(.orange)
          if desktop.needsPermission {
            Button("Open Screen Recording settings") {
              NSWorkspace.shared.open(
                URL(
                  string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
              )
            }
            .buttonStyle(.link)
          }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Starts at 100°. Set your comfortable open position once, and Hinge remembers it.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(28)
    .padding(.top, 12)
    .frame(width: 376)
  }
}
