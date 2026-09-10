import Foundation
import QuartzCore

final class LidMotion {
    private let lock = NSLock()
    private var angle: Double?
    private var baseline = 0.0
    private var enabled = false
    private var target = 0.0
    private var displayed = 0.0
    private var lastFrame = 0.0
    private var lastSample = 0.0

    struct Update {
        let availabilityChanged: Bool
        let available: Bool
        let beganClosing: Bool
    }

    func receive(_ value: Double?) -> Update {
        lock.lock()
        defer { lock.unlock() }
        let changed = (angle == nil) != (value == nil)
        let previous = target
        angle = value
        lastSample = CACurrentMediaTime()
        updateTarget()
        return Update(availabilityChanged: changed, available: value != nil, beganClosing: previous == 0 && target > 0)
    }

    var currentAngle: Double? {
        lock.lock()
        defer { lock.unlock() }
        return angle
    }

    @discardableResult
    func calibrate() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let angle, angle >= 25 else { return nil }
        baseline = angle
        target = 0
        displayed = 0
        lastFrame = 0
        return baseline
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        enabled = value
        displayed = 0
        lastFrame = 0
        updateTarget()
    }

    private func updateTarget() {
        guard enabled, baseline > 8, let angle else { target = 0; return }
        target = min(max((baseline - 0.75 - angle) / (baseline - 8.75), 0), 1)
    }

    func sample(at time: Double = CACurrentMediaTime()) -> Float {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, time - lastSample < 0.5 else {
            displayed = 0
            return 0
        }
        let delta = lastFrame > 0 ? min(max(time - lastFrame, 0), 0.05) : 1.0 / 120
        lastFrame = time
        displayed += (target - displayed) * (1 - exp(-delta / 0.012))
        if abs(displayed - target) < 0.0001 { displayed = target }
        return Float(displayed)
    }

    var isClosing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return target > 0
    }
}
