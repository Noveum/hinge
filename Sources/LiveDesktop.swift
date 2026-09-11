import MetalKit
import ScreenCaptureKit
import SwiftUI

final class ScreenFrames: NSObject, SCStreamOutput, SCStreamDelegate {
  var renderer: DesktopRenderer?
  var onFailure: ((Error) -> Void)?

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let rawStatus = attachments.first?[.status] as? Int,
      SCFrameStatus(rawValue: rawStatus) == .complete,
      let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    renderer?.receive(buffer)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?(error) }
}

final class DesktopPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class LiveDesktop: NSObject, ObservableObject {
  @Published private(set) var isActive = false
  @Published private(set) var isStarting = false
  @Published private(set) var sensorAvailable = false
  @Published private(set) var openAngle: Double
  @Published private(set) var effectStrength: Double
  @Published private(set) var followOpenAngle: Bool
  @Published private(set) var sideFill: SideFill
  @Published private(set) var error: String?
  @Published private(set) var needsPermission = false
  @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "effectEnabled")
  private static let missingSensorMessage =
    "This Mac doesn't appear to have a lid angle sensor, so Hinge can't follow the lid."
  private static let sensorDroppedMessage =
    "The lid sensor stopped responding. Hinge turns back on as soon as it reconnects."
  private let sensor = LidSensor()
  private var sensorMissing = false
  private let motion: LidMotion
  private var stream: SCStream?
  private var frames: ScreenFrames?
  private var renderer: DesktopRenderer?
  private var overlay: NSWindow?
  private var metalView: MTKView?
  private var displayLink: CADisplayLink?
  private var session = UUID()
  private var observers = [NSObjectProtocol]()
  private var resumeAfterWake = false
  private var restoringAtLaunch = UserDefaults.standard.bool(forKey: "effectEnabled")
  private var wakeTask: Task<Void, Never>?
  private var displayTask: Task<Void, Never>?
  private var capturedDisplayID: CGDirectDisplayID?
  private var includedWindowIDs = Set<CGWindowID>()

  override init() {
    let savedAngle = UserDefaults.standard.object(forKey: "openAngle") as? Double ?? 100
    let openAngle = savedAngle.isFinite && (25...180).contains(savedAngle) ? savedAngle : 100
    let savedStrength = UserDefaults.standard.object(forKey: "effectStrength") as? Double ?? 1
    let effectStrength =
      savedStrength.isFinite && (0.25...1).contains(savedStrength) ? savedStrength : 1
    let followOpenAngle = UserDefaults.standard.object(forKey: "followOpenAngle") as? Bool ?? true
    self.openAngle = openAngle
    self.effectStrength = effectStrength
    self.followOpenAngle = followOpenAngle
    sideFill = UserDefaults.standard.string(forKey: "sideFill").flatMap(SideFill.init) ?? .blur
    motion = LidMotion(openAngle: openAngle, followOpenAngle: followOpenAngle)
    super.init()
    let motion = motion
    sensor.onAngle = { [weak self] angle in
      let update = motion.receive(angle)
      guard update.availabilityChanged || update.beganClosing || update.adoptedAngle != nil
      else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        if update.availabilityChanged {
          self.sensorAvailable = update.available
          if update.available, self.sensorMissing {
            self.sensorMissing = false
            if self.error == Self.missingSensorMessage { self.error = nil }
          }
          if !update.available, self.isActive || self.isStarting {
            self.stop()
            self.error = Self.sensorDroppedMessage
          }
        }
        if let adopted = update.adoptedAngle { self.storeOpenAngle(adopted) }
        if update.beganClosing { self.beginRendering() }
        if update.available, self.isEnabled, !self.isActive, !self.isStarting,
          !self.resumeAfterWake
        {
          let restoring = self.restoringAtLaunch
          self.restoringAtLaunch = false
          await self.start(promptForPermission: !restoring)
        }
      }
    }
    sensor.onMissing = { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, !self.sensorAvailable else { return }
        self.sensorMissing = true
        if self.error == nil { self.error = Self.missingSensorMessage }
      }
    }
    sensor.start()
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in self?.suspendForSleep() }
        })
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in self?.resumeFromSleep() }
        })
    }
    observers.append(
      center.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refreshSpace() }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refreshDisplay() }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in await self?.refreshIncludedWindows() }
      })
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    restoringAtLaunch = false
    UserDefaults.standard.set(enabled, forKey: "effectEnabled")
    if enabled { Task { await start() } } else { stop() }
  }

  func setOpenPosition() {
    guard let angle = motion.calibrate() else {
      error = "Open the lid to your comfortable viewing position first."
      return
    }
    storeOpenAngle(angle)
    error = nil
    displayLink?.isPaused = true
    metalView?.draw()
  }

  private func storeOpenAngle(_ angle: Double) {
    openAngle = angle
    UserDefaults.standard.set(angle, forKey: "openAngle")
  }

  func setFollowOpenAngle(_ value: Bool) {
    guard value != followOpenAngle else { return }
    followOpenAngle = value
    UserDefaults.standard.set(value, forKey: "followOpenAngle")
    motion.setFollowOpenAngle(value)
  }

  func setEffectStrength(_ value: Double) {
    let strength = value.isFinite ? min(max(value, 0.25), 1) : 1
    guard strength != effectStrength else { return }
    effectStrength = strength
    UserDefaults.standard.set(strength, forKey: "effectStrength")
    renderer?.effectStrength = Float(strength)
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
  }

  func setSideFill(_ fill: SideFill) {
    sideFill = fill
    UserDefaults.standard.set(fill.rawValue, forKey: "sideFill")
    renderer?.sideFill = fill
  }

  func start(promptForPermission: Bool = true) async {
    guard !isStarting, !isActive else { return }
    error = nil
    needsPermission = false
    guard sensorAvailable else {
      sensor.reconnect()
      if sensorMissing { error = Self.missingSensorMessage }
      return
    }
    let hasScreenAccess =
      CGPreflightScreenCaptureAccess() || (promptForPermission && CGRequestScreenCaptureAccess())
    guard hasScreenAccess else {
      needsPermission = true
      error = "Allow Hinge in Screen Recording settings, then quit and reopen it."
      return
    }
    isStarting = true
    sensor.setTracking(true)
    let session = UUID()
    self.session = session
    do {
      let renderer = try DesktopRenderer(resources: .main, motion: motion)
      renderer.effectStrength = Float(effectStrength)
      renderer.sideFill = sideFill
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      guard self.session == session else { return }
      guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
        let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            == display.displayID
        })
      else {
        throw DesktopError.message("No built-in MacBook display was found.")
      }
      let ownApplications = content.applications.filter {
        $0.processID == ProcessInfo.processInfo.processIdentifier
      }
      let ownWindows = includedWindows(in: content)
      let filter = SCContentFilter(
        display: display, excludingApplications: ownApplications, exceptingWindows: ownWindows)
      capturedDisplayID = display.displayID
      includedWindowIDs = Set(ownWindows.map(\.windowID))
      let area = screen.frame
      let configuration = SCStreamConfiguration()
      configuration.sourceRect = CGRect(
        x: area.minX - screen.frame.minX, y: screen.frame.maxY - area.maxY, width: area.width,
        height: area.height)
      let scale = min(screen.backingScaleFactor, 2400 / area.width)
      configuration.width = Int(area.width * scale) / 2 * 2
      configuration.height = Int(area.height * scale) / 2 * 2
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
      configuration.queueDepth = 3
      configuration.pixelFormat = kCVPixelFormatType_32BGRA
      configuration.showsCursor = false
      configuration.capturesAudio = false
      configuration.colorSpaceName = CGColorSpace.sRGB
      try await renderer.warmUp(width: configuration.width, height: configuration.height)
      guard self.session == session else { return }
      let frames = ScreenFrames()
      frames.renderer = renderer
      frames.onFailure = { [weak self] failure in
        Task { @MainActor in
          guard let self, self.session == session else { return }
          self.stop()
          self.error = failure.localizedDescription
        }
      }
      let stream = SCStream(filter: filter, configuration: configuration, delegate: frames)
      try stream.addStreamOutput(
        frames, type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "hinge.capture", qos: .userInteractive))
      self.renderer = renderer
      self.frames = frames
      self.stream = stream
      renderer.onPresentation = { [weak self] failure in
        guard let self, self.session == session else { return }
        if let failure {
          self.stop()
          self.error = "The desktop renderer stopped: \(failure.localizedDescription)"
        }
      }
      renderer.onRest = { [weak self] in self?.restOverlay() }
      makeOverlay(screen: screen, area: area, renderer: renderer)
      try await stream.startCapture()
      guard self.session == session else {
        try? await stream.stopCapture()
        return
      }
      let deadline = CACurrentMediaTime() + 5
      while !renderer.hasFrame {
        guard self.session == session else { return }
        guard CACurrentMediaTime() < deadline else {
          needsPermission = true
          throw DesktopError.message(
            "No desktop frames arrived. Check Screen Recording permission and reopen Hinge.")
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      guard self.session == session else { return }
      guard sensorAvailable else { throw DesktopError.message(Self.sensorDroppedMessage) }
      motion.setEnabled(true)
      isActive = true
      isStarting = false
      if motion.isClosing { beginRendering() }
    } catch {
      guard self.session == session else { return }
      stop()
      self.error = error.localizedDescription
    }
  }

  private func includedWindows(in content: SCShareableContent) -> [SCWindow] {
    content.windows.filter {
      $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        && $0.windowID != CGWindowID(overlay?.windowNumber ?? 0)
        && $0.title != "Hinge Desktop Overlay"
    }
  }

  private func refreshIncludedWindows() async {
    guard isActive, let stream, let capturedDisplayID else { return }
    let currentSession = session
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      guard session == currentSession,
        let display = content.displays.first(where: { $0.displayID == capturedDisplayID })
      else { return }
      let windows = includedWindows(in: content)
      let windowIDs = Set(windows.map(\.windowID))
      guard windowIDs != includedWindowIDs else { return }
      let applications = content.applications.filter {
        $0.processID == ProcessInfo.processInfo.processIdentifier
      }
      try await stream.updateContentFilter(
        SCContentFilter(
          display: display, excludingApplications: applications, exceptingWindows: windows))
      if session == currentSession { includedWindowIDs = windowIDs }
    } catch {
      guard session == currentSession else { return }
      stop()
      self.error = "Could not update the captured windows: \(error.localizedDescription)"
    }
  }

  private func refreshSpace() {
    guard isActive, !resumeAfterWake else { return }
    displayTask?.cancel()
    let refreshSession = session
    displayTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
      guard let self, !Task.isCancelled, self.session == refreshSession,
        self.isActive, !self.resumeAfterWake
      else { return }
      self.displayTask = nil
      guard let displayID = self.capturedDisplayID,
        let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value == displayID
        })
      else { return }
      if self.overlay?.frame != screen.frame {
        self.stop()
        await self.start()
      } else {
        self.overlay?.orderFrontRegardless()
      }
    }
  }

  private func makeOverlay(screen: NSScreen, area: CGRect, renderer: DesktopRenderer) {
    let window = DesktopPanel(
      contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    window.isFloatingPanel = true
    window.becomesKeyOnlyIfNeeded = true
    window.title = "Hinge Desktop Overlay"
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    window.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.sharingType = .readOnly
    let view = MTKView(frame: NSRect(origin: .zero, size: area.size), device: renderer.device)
    view.delegate = renderer
    view.colorPixelFormat = .bgra8Unorm
    view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    view.clearColor = MTLClearColorMake(0, 0, 0, 0)
    view.framebufferOnly = true
    view.isPaused = true
    view.enableSetNeedsDisplay = false
    view.autoResizeDrawable = true
    view.layer?.isOpaque = false
    window.contentView = view
    window.setFrame(area, display: false)
    overlay = window
    metalView = view
    window.orderFrontRegardless()
    view.draw()
    let link = view.displayLink(target: self, selector: #selector(drawFrame(_:)))
    let refresh = Float(min(max(screen.maximumFramesPerSecond, 1), 60))
    view.preferredFramesPerSecond = Int(refresh)
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: refresh, maximum: refresh, preferred: refresh)
    link.isPaused = true
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func beginRendering() {
    guard isActive, motion.isClosing else { return }
    displayLink?.isPaused = false
  }

  @objc private func drawFrame(_ link: CADisplayLink) {
    guard isActive else { return }
    renderer?.presentationTime = link.targetTimestamp
    metalView?.draw()
  }

  private func restOverlay() {
    guard !motion.isClosing else { return }
    displayLink?.isPaused = true
  }

  private func refreshDisplay() {
    guard isActive, !resumeAfterWake else { return }
    displayTask?.cancel()
    displayTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      guard let self, self.isActive, !self.resumeAfterWake else { return }
      self.displayTask = nil
      self.stop()
      await self.start()
    }
  }

  private func suspendForSleep() {
    resumeAfterWake = resumeAfterWake || isActive || isStarting
    stop(preserveResume: true)
    sensor.stop()
  }

  private func resumeFromSleep() {
    guard !isActive, !isStarting, wakeTask == nil else { return }
    sensor.reconnect()
    guard resumeAfterWake else { return }
    wakeTask = Task { [weak self] in
      guard let self else { return }
      for _ in 0..<5 {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard self.resumeAfterWake, !Task.isCancelled else { return }
        if self.sensorAvailable { break }
        self.sensor.reconnect()
      }
      guard self.resumeAfterWake, !Task.isCancelled else { return }
      self.wakeTask = nil
      self.resumeAfterWake = false
      await self.start()
    }
  }

  func stop(preserveResume: Bool = false) {
    if !preserveResume {
      resumeAfterWake = false
      wakeTask?.cancel()
      wakeTask = nil
    }
    session = UUID()
    sensor.setTracking(false)
    motion.setEnabled(false)
    displayLink?.invalidate()
    displayLink = nil
    metalView?.isPaused = true
    metalView?.delegate = nil
    overlay?.orderOut(nil)
    overlay?.close()
    overlay = nil
    metalView = nil
    displayTask?.cancel()
    displayTask = nil
    let oldStream = stream
    let oldFrames = frames
    stream = nil
    if let oldStream {
      Task {
        try? await oldStream.stopCapture()
        if let oldFrames { try? oldStream.removeStreamOutput(oldFrames, type: .screen) }
      }
    }
    frames = nil
    renderer = nil
    capturedDisplayID = nil
    includedWindowIDs = []
    isActive = false
    isStarting = false
  }

  func shutDown() {
    stop()
    sensor.stop()
  }
}
