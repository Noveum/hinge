import SwiftUI

struct FoldProjection: GeometryEffect {
    var progress: Double
    var perspective: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, perspective) }
        set { progress = newValue.first; perspective = newValue.second }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(BendMath.projection(size: size, progress: progress, perspective: perspective))
    }
}

struct FoldSurface: View, Animatable {
    var progress: Double
    var perspective: Double = 1
    var blur: Double = 0.65
    var shadow: Double = 0.55
    var style: BendStyle = .silk
    var desktop = false
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 786
            let amount = max(0, min(progress, 1))
            let blurStrength = blur / 0.65 * style.blurMultiplier
            ZStack {
                MountainWallpaper(desktop: desktop)
                ForEach(0..<3) { index in
                    MountainWallpaper(desktop: desktop)
                        .blur(radius: [6.0, 16.0, 36.0][index] * unit * blurStrength)
                        .mask(LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: [0.30, 0.15, 0.06][index]),
                            .init(color: .clear, location: [0.75, 0.52, 0.34][index])
                        ], startPoint: .top, endPoint: .bottom))
                        .opacity(amount * min(blurStrength, 1))
                }
                LinearGradient(colors: [.black.opacity(0.5), .clear, .clear], startPoint: .top, endPoint: .bottom)
                    .opacity(amount * shadow * style.shadowMultiplier)
                HStack(spacing: 0) {
                    RadialGradient(colors: [.black.opacity(0.8), .clear], center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 0.48)
                    RadialGradient(colors: [.black.opacity(0.8), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.48)
                }
                .opacity(amount * shadow * style.shadowMultiplier)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: geometry.size.width * 0.032, topTrailingRadius: geometry.size.width * 0.032))
            .mask(LinearGradient(stops: [
                .init(color: .black.opacity(1 - amount), location: 0),
                .init(color: .black.opacity(1 - amount * 0.75), location: max(0.001, amount * 0.055)),
                .init(color: .black.opacity(1 - amount * 0.35), location: max(0.002, amount * 0.121)),
                .init(color: .black, location: max(0.003, amount * 0.22))
            ], startPoint: .top, endPoint: .bottom))
            .compositingGroup()
            .modifier(FoldProjection(progress: amount, perspective: perspective))
        }
        .accessibilityLabel("Desktop fold preview")
        .accessibilityValue("\(Int(progress * 100)) percent folded")
    }
}

struct MacBookPreview: View {
    @ObservedObject var model: BendModel
    var interactive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart = 135.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let displayWidth = width * 0.89
            let displayHeight = displayWidth / 1.55
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: width * 0.052)
                    .fill(.black.opacity(0.2))
                    .frame(width: width * 0.92, height: 10)
                    .blur(radius: 12)
                    .offset(y: displayHeight + width * 0.028)
                UnevenRoundedRectangle(topLeadingRadius: width * 0.05, topTrailingRadius: width * 0.05)
                    .fill(Color(hex: 0x111212))
                    .frame(width: displayWidth, height: displayHeight)
                    .overlay(alignment: .top) {
                        FoldSurface(progress: reduceMotion ? 0 : model.progress, perspective: model.perspective, blur: model.blur, shadow: model.shadow, style: model.style, desktop: model.showDesktop)
                            .padding(.horizontal, width * 0.023)
                            .padding(.top, width * 0.024)
                            .padding(.bottom, width * 0.027)
                    }
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(bottomLeadingRadius: width * 0.01, bottomTrailingRadius: width * 0.01)
                            .fill(Color(hex: 0x111212))
                            .frame(width: width * 0.2, height: width * 0.047)
                            .padding(.top, width * 0.021)
                    }
                UnevenRoundedRectangle(bottomLeadingRadius: width * 0.012, bottomTrailingRadius: width * 0.012)
                    .fill(LinearGradient(colors: [Color(hex: 0xa1a1a1), Color(hex: 0x858585)], startPoint: .top, endPoint: .bottom))
                    .frame(height: width * 0.032)
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(bottomLeadingRadius: width * 0.01, bottomTrailingRadius: width * 0.01)
                            .fill(Color(hex: 0x565656))
                            .frame(width: width * 0.24, height: width * 0.012)
                    }
                    .offset(y: displayHeight)
                if interactive {
                    Button { model.play() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: width * 0.04, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: width * 0.13, height: width * 0.13)
                            .background(.black.opacity(model.isPlaying ? 0.2 : 0.38), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(y: displayHeight * 0.45 - width * 0.065)
                    .help(model.isPlaying ? "Pause preview" : "Play lid animation")
                    .accessibilityLabel(model.isPlaying ? "Pause preview" : "Play preview")
                    .keyboardShortcut(.space, modifiers: [])
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if value.translation == .zero { dragStart = model.angle }
                    model.setAngle(dragStart - value.translation.height / displayHeight * 135)
                }
                .onEnded { _ in dragStart = model.angle })
        }
        .aspectRatio(1 / (0.89 / 1.55 + 0.048), contentMode: .fit)
    }
}
