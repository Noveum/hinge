import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case about = "About"
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: BendModel
    @ObservedObject var desktop: LiveDesktop
    @State private var page = SettingsPage.appearance

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    icon(page.symbol, color: page == .appearance ? .blue : .gray)
                    Text(page.rawValue).font(.system(size: 21, weight: .bold))
                    Spacer()
                    if desktop.isActive {
                        Label("Live", systemImage: "circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.bottom, 22)
                if page == .appearance { appearance }
                else if page == .general { general }
                else { about }
                Spacer(minLength: 12)
                if let error = desktop.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.system(size: 12)).foregroundStyle(Color(hex: 0xffd19a))
                            .fixedSize(horizontal: false, vertical: true)
                        if desktop.needsPermission {
                            Button("Open Screen Recording settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                            }.buttonStyle(.link)
                        }
                    }.padding(.bottom, 12)
                }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 29)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(hex: 0x5d5e61), Color(hex: 0x515358), Color(hex: 0x414851)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .frame(width: 870, height: desktop.error == nil ? 810 : 888)
        .foregroundStyle(Color(hex: 0xededee))
        .tint(Color(hex: 0x0a94ff))
        .background(Color(hex: 0x626364))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            navigation(.general)
            Text("Settings").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58)).padding(.top, 20).padding(.leading, 12).padding(.bottom, 3)
            navigation(.appearance)
            Text("Bendy").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58)).padding(.top, 20).padding(.leading, 12).padding(.bottom, 3)
            navigation(.about)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer").font(.system(size: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bendy").font(.system(size: 13, weight: .semibold))
                    Text("Local prototype · 0.1").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }.padding(12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 69)
        .padding(.bottom, 12)
        .frame(width: 207)
        .background(.white.opacity(0.035))
    }

    private func navigation(_ target: SettingsPage) -> some View {
        Button { page = target } label: {
            HStack(spacing: 11) {
                icon(target.symbol, color: target == .appearance ? .blue : Color(hex: 0x929395))
                Text(target.rawValue).font(.system(size: 16, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(.white.opacity(page == target ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8))
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacBookPreview(model: model)
                .frame(width: 445)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Text("\(Int(model.angle))°")
                    .font(.system(size: 17, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 45, alignment: .leading)
                Slider(value: Binding(get: { model.angle }, set: { model.setAngle($0) }), in: 0...135)
                    .accessibilityLabel("Lid angle")
                Toggle("Follow lid", isOn: Binding(get: { model.followLid }, set: {
                    model.stop()
                    model.followLid = $0
                    if $0, let angle = model.sensorAngle { model.angle = angle }
                }))
                .toggleStyle(.switch)
                .font(.system(size: 14, weight: .medium))
                .fixedSize()
                .disabled(model.sensorAngle == nil || desktop.isDemo)
            }
            .padding(.top, 16)
            .padding(.bottom, 23)
            Text("Style").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65)).padding(.bottom, 11)
            HStack(alignment: .top, spacing: 16) {
                ForEach(BendStyle.allCases) { style in
                    styleButton(style)
                }
            }.padding(.bottom, 22)
            VStack(spacing: 0) {
                control("Perspective", value: $model.perspective)
                Divider().opacity(0.3)
                control("Variable blur", value: $model.blur)
                Divider().opacity(0.3)
                control("Shadow", value: $model.shadow)
            }
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
            HStack {
                Text(model.style.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                Spacer()
                Button("Reset") { model.reset() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }.padding(.top, 12)
        }
    }

    private func styleButton(_ style: BendStyle) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { model.style = style }
        } label: {
            VStack(spacing: 9) {
                FoldSurface(progress: 0.36, perspective: style == .silk ? 0 : 0.35, blur: 0.85, shadow: 0.8, style: style)
                    .aspectRatio(1.58, contentMode: .fit)
                    .background(Color(hex: 0x171a1e))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(model.style == style ? Color(hex: 0x0a9bff) : .white.opacity(0.05), lineWidth: model.style == style ? 3 : 1))
                HStack(spacing: 6) {
                    Text(style.rawValue).font(.system(size: 14, weight: .medium))
                    if model.style == style {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0x0a9bff))
                    }
                }
            }
        }.buttonStyle(.plain)
            .accessibilityLabel("\(style.rawValue) style")
            .accessibilityAddTraits(model.style == style ? .isSelected : [])
    }

    private func control(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 15, weight: .medium)).frame(width: 126, alignment: .leading)
            Slider(value: value, in: 0...1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.66)).frame(width: 43, alignment: .trailing)
        }.padding(.horizontal, 18).frame(height: 55)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your desktop. A little more fluid.")
                    .font(.system(size: 24, weight: .semibold)).tracking(-0.7)
                Text("Windows and wallpaper fold together as your MacBook lid comes down.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.62))
            }.padding(.vertical, 12)
            VStack(spacing: 0) {
                settingsRow("Lid sensor", subtitle: model.sensorAngle.map { "Connected · \(Int($0))°" } ?? "Not detected on this Mac") {
                    Button("Reconnect") { model.reconnectSensor() }.controlSize(.small)
                }
                Divider().opacity(0.3)
                settingsRow("Screen Recording", subtitle: "Needed to bend your live desktop.") {
                    Image(systemName: CGPreflightScreenCaptureAccess() ? "checkmark.circle.fill" : "lock.circle")
                        .foregroundStyle(CGPreflightScreenCaptureAccess() ? .green : .secondary)
                }
                Divider().opacity(0.3)
                settingsRow("Opening sound", subtitle: "A soft click when your desktop clears.") {
                    Toggle("Opening sound", isOn: $model.soundEnabled).labelsHidden().toggleStyle(.switch)
                }
                Divider().opacity(0.3)
                settingsRow("Desktop in preview", subtitle: "Show a menu bar and Dock in the small preview.") {
                    Toggle("Desktop in preview", isOn: $model.showDesktop).labelsHidden().toggleStyle(.switch)
                }
            }.background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Clear at").font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("\(Int(model.clearAngle))°").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.clearAngle, in: 70...135, step: 1).accessibilityLabel("Clear angle")
                Text("Above this lid angle, the effect disappears and your desktop works normally.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }.padding(18).background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            Label("Press Esc at any time to stop the desktop effect.", systemImage: "escape")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            Text("The effect runs on your built-in display. Screen frames stay in memory on this Mac. Nothing is recorded or uploaded.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsRow<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            content()
        }.padding(18)
    }

    private var about: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer().frame(height: 45)
            Image(systemName: "laptopcomputer")
                .font(.system(size: 64, weight: .light)).foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 30))
            Text("Bendy Prototype").font(.system(size: 30, weight: .semibold)).tracking(-1)
            Text("Your desktop bends as you close the lid.")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
            Text("Native SwiftUI controls. Live desktop rendering.\nSilk, Shade, and Frost.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).lineSpacing(5).padding(.top, 4)
            Link("Reference: trybendy.app", destination: URL(string: "https://trybendy.app/")!)
                .font(.system(size: 12)).padding(.top, 12)
            Text("Version 0.1 · Local build")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        }.frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Divider().opacity(0.35)
            HStack(spacing: 9) {
                Circle().fill(desktop.isActive ? Color.green : .white.opacity(0.35)).frame(width: 6, height: 6)
                Text(desktop.isActive ? "Live on your Mac" : "Ready when you are")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button {
                    Task { await desktop.start(model: model, demo: true) }
                } label: {
                    Label("Try on desktop", systemImage: "play.fill").font(.system(size: 12, weight: .medium))
                }.buttonStyle(.bordered).controlSize(.large)
                    .disabled(desktop.isStarting || desktop.isDemo)
                    .help("Play one close-and-open animation on your actual desktop")
                Button {
                    if desktop.isActive { desktop.stop() }
                    else { Task { await desktop.start(model: model) } }
                } label: {
                    Text(desktop.isStarting ? "Starting…" : desktop.isActive ? "Stop" : "Enable on my Mac")
                        .font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(desktop.isStarting)
            }
        }
    }
}
