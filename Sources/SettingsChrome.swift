import AppKit
import SwiftUI

enum SettingsMetrics {
  static let groupSpacing: CGFloat = 22
  static let cardCorner: CGFloat = 12
  static let rowPaddingH: CGFloat = 14
  static let rowPaddingV: CGFloat = 11
  static let iconSize: CGFloat = 26
  static let iconCorner: CGFloat = 6.5
  static let dividerInset: CGFloat = rowPaddingH + iconSize + 11
}

struct SettingsGroup<Content: View>: View {
  let title: String
  var footnote: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 2)
      VStack(spacing: 0) { content }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
      if let footnote {
        Text(footnote)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.leading, 2)
          .padding(.top, 1)
      }
    }
  }
}

struct SettingsIcon: View {
  let symbol: String
  var tint = Color.accentColor

  var body: some View {
    RoundedRectangle(cornerRadius: SettingsMetrics.iconCorner, style: .continuous)
      .fill(tint.gradient)
      .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
      .overlay(
        Image(systemName: symbol)
          .font(.system(size: SettingsMetrics.iconSize * 0.55, weight: .semibold))
          .foregroundStyle(.white)
      )
  }
}

struct SettingsRow<Leading: View, Trailing: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 11) {
      leading
        .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13))
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 10)
      trailing
    }
    .padding(.horizontal, SettingsMetrics.rowPaddingH)
    .padding(.vertical, SettingsMetrics.rowPaddingV)
  }
}

extension SettingsRow where Leading == SettingsIcon {
  init(
    _ symbol: String, tint: Color = .accentColor, title: String, subtitle: String? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.init(
      title: title, subtitle: subtitle, leading: { SettingsIcon(symbol: symbol, tint: tint) },
      trailing: trailing)
  }
}

struct SettingsDivider: View {
  var inset = SettingsMetrics.dividerInset

  var body: some View {
    Divider()
      .opacity(0.5)
      .padding(.leading, inset)
  }
}

struct SettingsPage<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
        content
      }
      .padding(EdgeInsets(top: 4, leading: 20, bottom: 24, trailing: 20))
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentMargins(.top, 8, for: .scrollContent)
    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
  }
}

struct SidebarMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
