import Foundation
import QuartzCore

final class LidMotion {
    private let lock = NSLock()
    private var angle: Double?
    private var trackedAngle: Double?
    private var angularVelocity = 0.0
    private var direction = 0
    private var baseline = 0.0
    private var enabled = false
    private var target = 0.0
    private var displayed = 0.0
    private var displayVelocity = 0.0
    private var lastFrame = 0.0
    private var lastSample = 0.0

    struct Update {
        let availabilityChanged: Bool
        let available: Bool
        let beganClosing: Bool
    }

    func receive(_ value: Double?, at time: Double = CACurrentMediaTime()) -> Update {
        lock.lock()
        defer { lock.unlock() }
        let changed = (angle == nil) != (value == nil)
        let previous = target
        angle = value
        if let value, let trackedAngle, lastSample > 0, time - lastSample < 0.5 {
            let delta = min(max(time - lastSample, 0.001), 0.1)
            let nextAngle = min(max(trackedAngle, value - 0.6), value + 0.6)
            if nextAngle < trackedAngle { direction = 1 }
            else if nextAngle > trackedAngle { direction = -1 }
            let measuredVelocity = (nextAngle - trackedAngle) / delta
            angularVelocity += (measuredVelocity - angularVelocity) * (1 - exp(-delta / 0.06))
            self.trackedAngle = nextAngle
        } else {
            trackedAngle = value
            angularVelocity = 0
            direction = 0
        }
        lastSample = time
        updateTarget()
        return Update(availabilityChanged: changed, available: value != nil, beganClosing: previous == 0 && target > 0)
    }

    @discardableResult
    func calibrate() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let angle, angle >= 25 else { return nil }
        baseline = angle
        reset()
        return baseline
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        enabled = value
        reset()
        updateTarget()
    }

    private func reset() {
        trackedAngle = angle
        angularVelocity = 0
        direction = 0
        target = 0
        displayed = 0
        displayVelocity = 0
        lastFrame = 0
    }

    private func updateTarget() {
        guard enabled, baseline > 8, let angle, let trackedAngle, angle < baseline else {
            target = 0
            if enabled { direction = -1 }
            return
        }
        let prediction = min(max(angularVelocity * 0.035, -0.75), 0.75)
        target = min(max((baseline - 0.6 - trackedAngle - prediction) / (baseline - 8.6), 0), 1)
    }

    func sample(at time: Double = CACurrentMediaTime()) -> Float {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, time - lastSample < 0.5 else {
            displayed = 0
            displayVelocity = 0
            return 0
        }
        let delta = lastFrame > 0 ? min(max(time - lastFrame, 0), 0.05) : 1.0 / 120
        lastFrame = time
        let frequency = 45.0
        let offset = displayed - target
        let travel = (displayVelocity + frequency * offset) * delta
        let decay = exp(-frequency * delta)
        let previous = displayed
        displayed = target + (offset + travel) * decay
        displayVelocity = (displayVelocity - frequency * travel) * decay
        if (direction > 0 && displayed < previous) || (direction < 0 && displayed > previous) {
            displayed = previous
            displayVelocity = 0
        }
        if abs(displayed - target) < 0.00001, abs(displayVelocity) < 0.0001 {
            displayed = target
            displayVelocity = 0
        }
        if displayed < 0 || displayed > 1 {
            displayed = min(max(displayed, 0), 1)
            displayVelocity = 0
        }
        return Float(displayed)
    }

    var isClosing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return target > 0
    }
}
