import Foundation
import QuartzCore
import IOKit.hid

final class LidSensor {
    private let queue = DispatchQueue(label: "hinge.sensor", qos: .userInteractive)
    private var connection: LidConnection?
    var onAngle: ((Double?) -> Void)?

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    func reconnect() {
        queue.async { [weak self] in
            self?.disconnect()
            self?.connect()
        }
    }

    private func connect() {
        guard connection == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x0020,
            kIOHIDDeviceUsageKey: 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, 0)
            onAngle?(nil)
            return
        }
        for device in devices {
            guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { continue }
            guard let angle = LidConnection.read(device) else {
                IOHIDDeviceClose(device, 0)
                continue
            }
            let connection = LidConnection(device: device, manager: manager, queue: queue) { [weak self] value in
                self?.onAngle?(value)
            }
            self.connection = connection
            connection.begin()
            onAngle?(angle)
            return
        }
        IOHIDManagerClose(manager, 0)
        onAngle?(nil)
    }

    func stop() {
        queue.async { [weak self] in self?.disconnect() }
    }

    private func disconnect() {
        connection?.cancel()
        connection = nil
    }

    deinit {
        let connection = connection
        queue.async { connection?.cancel() }
    }
}

private final class LidConnection {
    private let device: IOHIDDevice
    private let manager: IOHIDManager
    private let queue: DispatchQueue
    private let onAngle: (Double?) -> Void
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private var watchdog: DispatchSourceTimer?
    private var lastReport = CACurrentMediaTime()
    private var failures = 0
    private var cancelled = false

    init(device: IOHIDDevice, manager: IOHIDManager, queue: DispatchQueue, onAngle: @escaping (Double?) -> Void) {
        self.device = device
        self.manager = manager
        self.queue = queue
        self.onAngle = onAngle
        let maximum = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64
        bufferSize = min(max(maximum, 16), 4096)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    func begin() {
        let context = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, result, _, _, reportID, bytes, count in
            guard let context, result == kIOReturnSuccess, reportID == 1, count >= 3 else { return }
            let connection = Unmanaged<LidConnection>.fromOpaque(context).takeUnretainedValue()
            let value = Int(bytes[1]) | (Int(bytes[2]) << 8)
            guard (0...180).contains(value), !connection.cancelled else { return }
            connection.lastReport = CACurrentMediaTime()
            connection.failures = 0
            connection.onAngle(Double(value))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let connection = Unmanaged<LidConnection>.fromOpaque(context).takeUnretainedValue()
            guard !connection.cancelled else { return }
            connection.onAngle(nil)
            connection.cancel()
        }, context)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceSetCancelHandler(device) {
            Unmanaged<LidConnection>.fromOpaque(context).release()
        }
        IOHIDDeviceActivate(device)
        let watchdog = DispatchSource.makeTimerSource(queue: queue)
        watchdog.schedule(deadline: .now() + 2, repeating: .seconds(1), leeway: .milliseconds(100))
        watchdog.setEventHandler { [weak self] in self?.checkConnection() }
        self.watchdog = watchdog
        watchdog.resume()
    }

    private func checkConnection() {
        guard !cancelled, CACurrentMediaTime() - lastReport > 1.5 else { return }
        if let angle = Self.read(device) {
            lastReport = CACurrentMediaTime()
            failures = 0
            onAngle(angle)
        } else {
            failures += 1
            if failures == 2 { onAngle(nil) }
        }
    }

    static func read(_ device: IOHIDDevice) -> Double? {
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(bytes.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length) == kIOReturnSuccess,
              length >= 3 else { return nil }
        let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return (0...180).contains(angle) ? Double(angle) : nil
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        watchdog?.cancel()
        watchdog = nil
        IOHIDDeviceCancel(device)
    }

    deinit {
        IOHIDDeviceClose(device, 0)
        IOHIDManagerClose(manager, 0)
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }
}
