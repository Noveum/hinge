import SwiftUI
import ScreenCaptureKit
import MetalKit
import Carbon

final class ScreenFrames: NSObject, SCStreamOutput, SCStreamDelegate {
    var renderer: DesktopRenderer?
    var onFailure: ((Error) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderer?.receive(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?(error) }
}

final class EscapeShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onEscape: (() -> Void)?

    func register() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let shortcut = Unmanaged<EscapeShortcut>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.onEscape?() }
            return noErr
        }, 1, &event, pointer, &handler)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x424E4459, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    deinit { unregister() }
}

@MainActor
final class LiveDesktop: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var isDemo = false
    @Published var error: String?
    @Published var needsPermission = false
    @Published private(set) var status = "Ready to bend your desktop"
    private var stream: SCStream?
    private var frames: ScreenFrames?
    private var renderer: DesktopRenderer?
    private var overlay: NSWindow?
    private var metalView: MTKView?
    private var timer: Timer?
    private var progress = 0.0
    private var lastTime = CACurrentMediaTime()
    private var demoStart: CFTimeInterval?
    private var captureStart: CFTimeInterval = 0
    private var wasFolded = false
    private var escape = EscapeShortcut()
    private weak var model: BendModel?
    private var session = UUID()
    private var observers = [NSObjectProtocol]()
    private var resumeAfterWake = false
    private var wakeTask: Task<Void, Never>?

    init() {
        escape.onEscape = { [weak self] in self?.stop() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspendForSleep() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeFromSleep() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.resumeAfterWake else { return }
                self.stop()
            }
        })
    }

    func start(model: BendModel, demo: Bool = false) async {
        guard !isStarting else { return }
        if isActive { stop() }
        self.model = model
        error = nil
        needsPermission = false
        if !demo && model.sensorAngle == nil {
            error = "The lid sensor is unavailable. You can still run a live desktop demo."
            return
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            needsPermission = true
            error = "Allow Bendy Prototype in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app."
            return
        }
        isStarting = true
        status = "Preparing live desktop…"
        let session = UUID()
        self.session = session
        do {
            let renderer = try DesktopRenderer()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard self.session == session else { return }
            guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
                  let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) else {
                throw DesktopError.message("No built-in MacBook display was found.")
            }
            let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = min(screen.backingScaleFactor, 2400 / screen.frame.width)
            configuration.width = Int(screen.frame.width * scale) / 2 * 2
            configuration.height = Int(screen.frame.height * scale) / 2 * 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 3
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.colorSpaceName = CGColorSpace.sRGB
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
            try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "bendy.capture", qos: .userInteractive))
            self.renderer = renderer
            self.frames = frames
            self.stream = stream
            try await stream.startCapture()
            guard self.session == session else { try? await stream.stopCapture(); return }
            makeOverlay(screen: screen, renderer: renderer)
            model.stop()
            model.isEnabled = true
            model.followLid = !demo
            if let angle = model.sensorAngle, !demo { model.angle = angle }
            isActive = true
            isStarting = false
            isDemo = demo
            captureStart = CACurrentMediaTime()
            demoStart = nil
            lastTime = captureStart
            status = demo ? "Playing on your desktop" : "Following your MacBook lid"
            escape.register()
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            if demo {
                NSApp.windows.filter { $0 !== overlay && $0.canBecomeKey }.forEach { $0.orderOut(nil) }
            }
        } catch {
            guard self.session == session else { return }
            stop()
            self.error = error.localizedDescription
        }
    }

    private func makeOverlay(screen: NSScreen, renderer: DesktopRenderer) {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "Bendy Desktop Overlay"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        overlay = window
        metalView = view
        renderer.parameters.width = Float(screen.frame.width)
        renderer.parameters.height = Float(screen.frame.height)
    }

    private func tick() {
        guard let model, let renderer, let metalView, let overlay else { return }
        let now = CACurrentMediaTime()
        guard renderer.hasFrame else {
            if now - captureStart > 8 {
                stop()
                error = "No desktop frames arrived. Check Screen Recording permission and try again."
            }
            return
        }
        if isDemo {
            if demoStart == nil { demoStart = now }
            let t = now - (demoStart ?? now)
            let angle: Double
            if t < 1 { angle = 135 }
            else if t < 3.4 { angle = 135 - 123 * ease((t - 1) / 2.4) }
            else if t < 4 { angle = 12 }
            else if t < 5.8 { angle = 12 + 123 * ease((t - 4) / 1.8) }
            else if t < 6.8 { angle = 135 }
            else { stop(); showSettings(); return }
            model.angle = angle
        } else if model.followLid {
            guard let sensorAngle = model.sensorAngle else {
                stop()
                error = "The lid sensor stopped responding. The desktop effect has been paused."
                return
            }
            model.angle = sensorAngle
        }
        let delta = min(max(now - lastTime, 0.001), 0.1)
        lastTime = now
        let target = model.progress
        progress += (target - progress) * (1 - exp(-delta / 0.085))
        if abs(target - progress) < 0.0002 { progress = target }
        if progress > 0.5 { wasFolded = true }
        if wasFolded && progress < 0.004 {
            wasFolded = false
            model.playClick()
            model.completedBends += 1
        }
        guard progress > 0.0001, model.isEnabled else {
            overlay.orderOut(nil)
            return
        }
        renderer.parameters.progress = Float(progress)
        renderer.parameters.perspective = Float(model.perspective)
        renderer.parameters.blur = Float(model.blur * model.style.blurMultiplier)
        renderer.parameters.shadow = Float(model.shadow * model.style.shadowMultiplier)
        renderer.parameters.frost = model.style == .frost ? 1 : 0
        if !overlay.isVisible { overlay.orderFrontRegardless() }
        renderer.draw(in: metalView)
    }

    private func ease(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func suspendForSleep() {
        resumeAfterWake = resumeAfterWake || (isActive && !isDemo)
        stop(preserveResume: true)
    }

    private func resumeFromSleep() {
        guard resumeAfterWake, let model, wakeTask == nil else { return }
        wakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.resumeAfterWake, !Task.isCancelled else { return }
            self.wakeTask = nil
            self.resumeAfterWake = false
            model.reconnectSensor()
            await self.start(model: model)
        }
    }

    func stop(preserveResume: Bool = false) {
        if !preserveResume {
            resumeAfterWake = false
            wakeTask?.cancel()
            wakeTask = nil
        }
        session = UUID()
        overlay?.orderOut(nil)
        overlay?.close()
        overlay = nil
        metalView = nil
        timer?.invalidate()
        timer = nil
        escape.unregister()
        let oldStream = stream
        stream = nil
        if let oldStream { Task { try? await oldStream.stopCapture() } }
        frames = nil
        renderer = nil
        progress = 0
        wasFolded = false
        demoStart = nil
        isActive = false
        isStarting = false
        isDemo = false
        status = "Ready to bend your desktop"
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Bendy Prototype" })?.makeKeyAndOrderFront(nil)
    }
}
