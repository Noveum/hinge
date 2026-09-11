import Foundation
import IOKit.hid

final class LidSensor {
  private let queue = DispatchQueue(label: "hinge.sensor", qos: .userInteractive)
  private var connection: LidConnection?
  private var tracking = false
  private var hasConnected = false
  var onAngle: ((Double?) -> Void)?
  var onMissing: (() -> Void)?

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
    guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else {
      IOHIDManagerClose(manager, 0)
      onAngle?(nil)
      return
    }
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty
    else {
      IOHIDManagerClose(manager, 0)
      if !hasConnected { onMissing?() }
      onAngle?(nil)
      return
    }
    for device in devices {
      guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { continue }
      let precise = LidConnection.read(device, precise: true) != nil
      guard let angle = LidConnection.read(device, precise: precise) else {
        IOHIDDeviceClose(device, 0)
        continue
      }
      let connection = LidConnection(
        device: device, manager: manager, queue: queue, precise: precise, angle: angle
      ) {
        [weak self] value in
        self?.onAngle?(value)
      }
      self.connection = connection
      hasConnected = true
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
    onAngle?(nil)
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
  private let precise: Bool
  private let onAngle: (Double?) -> Void
  private var timer: DispatchSourceTimer?
  private var tracking = false
  private var failures = 0
  private var angle: Double?
  private var quietAt: UInt64 = 0
  private var lockedAt: UInt64 = 0
  private var windowStart: UInt64 = 0
  private var windowEnd: UInt64 = 0
  private var missed: UInt64 = 0
  private var period: UInt64 = 98_000_000

  init(
    device: IOHIDDevice, manager: IOHIDManager, queue: DispatchQueue, precise: Bool,
    angle: Double, onAngle: @escaping (Double?) -> Void
  ) {
    self.device = device
    self.manager = manager
    self.queue = queue
    self.precise = precise
    self.angle = angle
    self.onAngle = onAngle
  }

  func setTracking(_ active: Bool) {
    tracking = active
    failures = 0
    if timer == nil {
      let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
      timer.setEventHandler { [weak self] in self?.sample() }
      timer.resume()
      self.timer = timer
    }
    schedule(after: 0)
  }

  private func schedule(after delay: UInt64) {
    timer?.schedule(
      deadline: .now() + .nanoseconds(Int(delay)),
      leeway: .microseconds(tracking ? 500 : 10_000))
  }

  private func sample() {
    guard let value = Self.read(device, precise: precise) else {
      failures += 1
      if failures == (tracking ? 12 : 3) {
        angle = nil
        onAngle(nil)
      }
      schedule(after: tracking ? 8_333_333 : 100_000_000)
      return
    }
    failures = 0
    let now = DispatchTime.now().uptimeNanoseconds
    if value != angle {
      locate(changeAt: now)
      angle = value
      onAngle(value)
    } else {
      quietAt = now
      if windowStart > 0, now > windowEnd {
        let skipped = (now - windowEnd) / period + 1
        missed += skipped
        windowStart = missed > 5 ? 0 : windowStart + skipped * period
        windowEnd += skipped * period
      }
    }
    schedule(after: tracking ? nextPoll(at: now) : 100_000_000)
  }

  private func locate(changeAt now: UInt64) {
    missed = 0
    if quietAt > 0, now - quietAt <= 6_000_000 {
      if lockedAt > 0 {
        let cycles = (now - lockedAt + period / 2) / period
        let length = (now - lockedAt) / max(cycles, 1)
        if (1...20).contains(cycles), length > period * 9 / 10, length < period * 11 / 10 {
          period = (period * 3 + length) / 4
        }
      }
      lockedAt = now
      windowStart = now + period - 6_000_000
      windowEnd = now + period + 6_000_000
    } else if quietAt > 0, now - quietAt < period {
      windowStart = quietAt + period - 3_000_000
      windowEnd = now + period + 3_000_000
    } else {
      windowStart = now + period - 30_000_000
      windowEnd = now + period + 3_000_000
    }
  }

  private func nextPoll(at now: UInt64) -> UInt64 {
    guard windowStart > 0 else { return 25_000_000 }
    return windowStart > now + 1_000_000 ? windowStart - now : 3_000_000
  }

  static func read(_ device: IOHIDDevice, precise: Bool) -> Double? {
    var bytes = [UInt8](repeating: 0, count: 8)
    var length = CFIndex(bytes.count)
    guard
      IOHIDDeviceGetReport(
        device, kIOHIDReportTypeFeature, precise ? 7 : 1, &bytes, &length) == kIOReturnSuccess,
      length >= (precise ? 5 : 3)
    else { return nil }
    let raw = Int(bytes[1]) | Int(bytes[2]) << 8
    let angle =
      precise ? Double(raw | Int(bytes[3]) << 16 | Int(bytes[4]) << 24) / 100 : Double(raw)
    return (0...180).contains(angle) ? angle : nil
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
