import SwiftUI
import AppKit

enum BendStyle: String, CaseIterable, Identifiable {
    case silk = "Silk"
    case shade = "Shade"
    case frost = "Frost"
    var id: String { rawValue }
    var blurMultiplier: Double { self == .frost ? 1.65 : self == .shade ? 0.72 : 1 }
    var shadowMultiplier: Double { self == .shade ? 1.8 : self == .frost ? 0.55 : 1 }
    var detail: String {
        switch self {
        case .silk: "A soft, fluid fold."
        case .shade: "Deeper shadows. More dimension."
        case .frost: "A softer, frosted finish."
        }
    }
}

enum BendMath {
    static func progress(angle: Double, clearAngle: Double) -> Double {
        let t = min(max((clearAngle - angle) / max(clearAngle - 8, 1), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func projection(size: CGSize, progress: Double, perspective: Double) -> CATransform3D {
        let theta = progress * perspective * 72 * .pi / 180
        let distance = size.width * 1400 / 786
        let k = sin(theta) / max(distance, 1)
        let h = size.height
        let w = size.width
        var matrix = CATransform3DIdentity
        matrix.m21 = -w * k / 2
        matrix.m41 = w * h * k / 2
        matrix.m22 = cos(theta) - h * k
        matrix.m42 = h * (1 + h * k - cos(theta))
        matrix.m24 = -k
        matrix.m44 = 1 + h * k
        return matrix
    }
}

@MainActor
final class BendModel: ObservableObject {
    @Published var angle = 135.0
    @Published var clearAngle = 110.0
    @Published var perspective = 1.0
    @Published var blur = 0.65
    @Published var shadow = 0.55
    @Published var style = BendStyle.silk
    @Published var isPlaying = false
    @Published var isEnabled = true
    @Published var soundEnabled = true
    @Published var followLid = false
    @Published var sensorAngle: Double?
    @Published var showDesktop = false
    @Published var completedBends = 0
    var playback: Task<Void, Never>?
    var sound: NSSound?

    var progress: Double { isEnabled ? BendMath.progress(angle: angle, clearAngle: clearAngle) : 0 }

    func setAngle(_ value: Double) {
        stop()
        followLid = false
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.94)) {
            angle = min(max(value, 0), 135)
        }
    }

    func play() {
        if isPlaying { stop(); return }
        followLid = false
        isPlaying = true
        playback = Task { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.45)) { self.angle = 135 }
            guard await self.pause(0.65) else { return }
            withAnimation(.timingCurve(0.42, 0, 0.25, 1, duration: 2.4)) { self.angle = 12 }
            guard await self.pause(2.95) else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.65)) { self.angle = 135 }
            guard await self.pause(1.5) else { return }
            self.playClick()
            self.completedBends += 1
            guard await self.pause(0.65) else { return }
            self.isPlaying = false
        }
    }

    func pause(_ seconds: Double) async -> Bool {
        do { try await Task.sleep(for: .seconds(seconds)); return !Task.isCancelled }
        catch { return false }
    }

    func stop() {
        playback?.cancel()
        playback = nil
        isPlaying = false
    }

    func playClick() {
        guard soundEnabled else { return }
        if sound == nil, let url = Bundle.main.url(forResource: "fold", withExtension: "mp3") {
            sound = NSSound(contentsOf: url, byReference: true)
            sound?.volume = 0.4
        }
        sound?.stop()
        sound?.play()
    }

    func reset() {
        stop()
        withAnimation(.easeInOut(duration: 0.3)) {
            angle = 135
            clearAngle = 110
            perspective = 1
            blur = 0.65
            shadow = 0.55
            style = .silk
        }
    }
}
