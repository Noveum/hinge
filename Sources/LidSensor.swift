import Foundation
import IOKit.hid

final class LidSensor {
  private let queue = DispatchQueue(label: "hinge.sensor", qos: .userInteractive)
  private var connection: LidConnection?
  private var tracking = false
  var onAngle: ((Double?) -> Void)?

  func start() {
    queue.async { [weak self] in self?.connect() }
  }

  func setTracking(_ active: Bool) {
    queue.async { [weak self] in
      guard let self else { return }
      self.tracking = active
      self.connection?.setTracking(active)
    }
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
      kIOHIDDeviceUsageKey: 0x008A,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
      let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
    else {
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
      let connection = LidConnection(device: device, manager: manager, queue: queue) {
        [weak self] value in
        self?.onAngle?(value)
      }
      self.connection = connection
      onAngle?(angle)
      connection.setTracking(tracking)
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
  private var timer: DispatchSourceTimer?
  private var failures = 0
  private var failureLimit = 3

  init(
    device: IOHIDDevice, manager: IOHIDManager, queue: DispatchQueue,
    onAngle: @escaping (Double?) -> Void
  ) {
    self.device = device
    self.manager = manager
    self.queue = queue
    self.onAngle = onAngle
  }

  func setTracking(_ active: Bool) {
    timer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(
      deadline: .now(), repeating: .nanoseconds(active ? 8_333_333 : 100_000_000),
      leeway: .microseconds(active ? 500 : 10_000))
    timer.setEventHandler { [weak self] in self?.sample() }
    failureLimit = active ? 12 : 3
    failures = 0
    self.timer = timer
    timer.resume()
  }

  func sample() {
    if let angle = Self.read(device) {
      failures = 0
      onAngle(angle)
    } else {
      failures += 1
      if failures == failureLimit { onAngle(nil) }
    }
  }

  static func read(_ device: IOHIDDevice) -> Double? {
    var bytes = [UInt8](repeating: 0, count: 8)
    var length = CFIndex(bytes.count)
    guard
      IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length) == kIOReturnSuccess,
      length >= 3
    else { return nil }
    let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
    return (0...180).contains(angle) ? Double(angle) : nil
  }

  func cancel() {
    timer?.cancel()
    timer = nil
  }

  deinit {
    timer?.cancel()
    IOHIDDeviceClose(device, 0)
    IOHIDManagerClose(manager, 0)
  }
}
