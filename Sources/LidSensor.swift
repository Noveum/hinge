import Foundation
import IOKit.hid

final class LidSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var failures = 0
    var onAngle: ((Double?) -> Void)?

    func start() {
        guard timer == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x0020,
            kIOHIDDeviceUsageKey: 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            onAngle?(nil)
            return
        }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
            if read(candidate) != nil {
                device = candidate
                break
            }
            IOHIDDeviceClose(candidate, 0)
        }
        guard device != nil else { onAngle?(nil); return }
        poll()
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.poll() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func read(_ device: IOHIDDevice) -> Double? {
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(bytes.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return (0...180).contains(angle) ? Double(angle) : nil
    }

    private func poll() {
        guard let device else { return }
        guard let angle = read(device) else {
            failures += 1
            if failures == 15 { onAngle?(nil) }
            return
        }
        failures = 0
        onAngle?(angle)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        if let manager { IOHIDManagerClose(manager, 0) }
        manager = nil
    }

    deinit { stop() }
}
