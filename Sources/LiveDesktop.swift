import SwiftUI
import ScreenCaptureKit
import MetalKit

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

@MainActor
final class LiveDesktop: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var sensorAvailable = false
    @Published private(set) var openAngle: Double?
    @Published private(set) var error: String?
    @Published private(set) var needsPermission = false
    private let sensor = LidSensor()
    private let motion = LidMotion()
    private var stream: SCStream?
    private var frames: ScreenFrames?
    private var renderer: DesktopRenderer?
    private var overlay: NSWindow?
    private var metalView: MTKView?
    private var session = UUID()
    private var observers = [NSObjectProtocol]()
    private var resumeAfterWake = false
    private var wakeTask: Task<Void, Never>?
    private var frameTimeout: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var capturedDisplayID: CGDirectDisplayID?
    private var includedWindowIDs = Set<CGWindowID>()

    init() {
        let motion = motion
        sensor.onAngle = { [weak self] angle in
            let update = motion.receive(angle)
            guard update.availabilityChanged || update.beganClosing else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if update.availabilityChanged {
                    self.sensorAvailable = update.available
                    if update.available, self.openAngle == nil { self.setOpenPosition() }
                    if !update.available, self.isActive {
                        self.stop()
                        self.error = "The lid sensor stopped responding. Turn Hinge on again to reconnect."
                    }
                }
                if update.beganClosing { self.beginRendering() }
            }
        }
        sensor.start()
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
            Task { @MainActor in self?.refreshDisplay() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshIncludedWindows() }
        })
    }

    func setOpenPosition() {
        guard let angle = motion.calibrate() else {
            error = "Open the lid to your comfortable viewing position first."
            return
        }
        openAngle = angle
        error = nil
        restOverlay()
    }

    func start(calibrate: Bool = true) async {
        guard !isStarting, !isActive else { return }
        error = nil
        needsPermission = false
        guard sensorAvailable else {
            sensor.reconnect()
            error = "The lid sensor is unavailable. Reconnecting, try turning Hinge on again in a moment."
            return
        }
        if calibrate {
            guard let angle = motion.calibrate() else {
                error = "Open the lid to your comfortable viewing position first."
                return
            }
            openAngle = angle
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            needsPermission = true
            error = "Allow Hinge in Screen Recording settings, then quit and reopen it."
            return
        }
        isStarting = true
        let session = UUID()
        self.session = session
        do {
            let renderer = try DesktopRenderer(resources: .main, motion: motion)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard self.session == session else { return }
            guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
                  let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) else {
                throw DesktopError.message("No built-in MacBook display was found.")
            }
            let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let ownWindows = includedWindows(in: content)
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: ownWindows)
            capturedDisplayID = display.displayID
            includedWindowIDs = Set(ownWindows.map(\.windowID))
            let area = screen.visibleFrame
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: area.minX - screen.frame.minX, y: screen.frame.maxY - area.maxY, width: area.width, height: area.height)
            let scale = min(screen.backingScaleFactor, 2400 / area.width)
            configuration.width = Int(area.width * scale) / 2 * 2
            configuration.height = Int(area.height * scale) / 2 * 2
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
            try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "hinge.capture", qos: .userInteractive))
            self.renderer = renderer
            self.frames = frames
            self.stream = stream
            renderer.onPresentation = { [weak self] failure in
                guard let self, self.session == session else { return }
                if let failure {
                    self.stop()
                    self.error = "The desktop renderer stopped: \(failure.localizedDescription)"
                } else if self.overlay?.isVisible == true {
                    self.overlay?.alphaValue = 1
                }
            }
            renderer.onRest = { [weak self] in self?.restOverlay() }
            makeOverlay(screen: screen, renderer: renderer)
            try await stream.startCapture()
            guard self.session == session else {
                try? await stream.stopCapture()
                return
            }
            motion.setEnabled(true)
            isActive = true
            isStarting = false
            if motion.isClosing { beginRendering() }
            frameTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.session == session, !renderer.hasFrame else { return }
                self.stop()
                self.error = "No desktop frames arrived. Check Screen Recording permission and reopen Hinge."
                self.needsPermission = true
            }
        } catch {
            guard self.session == session else { return }
            stop()
            self.error = error.localizedDescription
        }
    }

    private func includedWindows(in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier &&
            $0.windowID != CGWindowID(overlay?.windowNumber ?? 0) &&
            $0.title != "Hinge Desktop Overlay"
        }
    }

    private func refreshIncludedWindows() async {
        guard isActive, let stream, let capturedDisplayID else { return }
        let currentSession = session
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard session == currentSession,
                  let display = content.displays.first(where: { $0.displayID == capturedDisplayID }) else { return }
            let windows = includedWindows(in: content)
            let windowIDs = Set(windows.map(\.windowID))
            guard windowIDs != includedWindowIDs else { return }
            let applications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            try await stream.updateContentFilter(SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: windows))
            if session == currentSession { includedWindowIDs = windowIDs }
        } catch {
            guard session == currentSession else { return }
            stop()
            self.error = "Could not update the captured windows: \(error.localizedDescription)"
        }
    }

    private func makeOverlay(screen: NSScreen, renderer: DesktopRenderer) {
        let area = screen.visibleFrame
        let window = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "Hinge Desktop Overlay"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.alphaValue = 0.001
        let view = MTKView(frame: NSRect(origin: .zero, size: area.size), device: renderer.device)
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = min(max(screen.maximumFramesPerSecond, 60), 120)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        window.contentView = view
        window.setFrame(area, display: false)
        overlay = window
        metalView = view
    }

    private func beginRendering() {
        guard isActive, motion.isClosing, let overlay, let metalView else { return }
        if !overlay.isVisible {
            renderer?.preparePresentation()
            overlay.alphaValue = 0.001
            overlay.orderFrontRegardless()
        }
        metalView.isPaused = false
    }

    private func restOverlay() {
        guard !motion.isClosing else { return }
        metalView?.isPaused = true
        overlay?.orderOut(nil)
    }

    private func refreshDisplay() {
        guard isActive, !resumeAfterWake else { return }
        displayTask?.cancel()
        displayTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.isActive, !self.resumeAfterWake else { return }
            self.displayTask = nil
            self.stop()
            await self.start(calibrate: false)
        }
    }

    private func suspendForSleep() {
        resumeAfterWake = resumeAfterWake || isActive || isStarting
        stop(preserveResume: true)
        sensor.stop()
    }

    private func resumeFromSleep() {
        sensor.reconnect()
        guard resumeAfterWake, wakeTask == nil else { return }
        wakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.resumeAfterWake, !Task.isCancelled else { return }
            self.wakeTask = nil
            self.resumeAfterWake = false
            await self.start(calibrate: false)
        }
    }

    func stop(preserveResume: Bool = false) {
        if !preserveResume {
            resumeAfterWake = false
            wakeTask?.cancel()
            wakeTask = nil
        }
        session = UUID()
        motion.setEnabled(false)
        metalView?.isPaused = true
        metalView?.delegate = nil
        overlay?.orderOut(nil)
        overlay?.close()
        overlay = nil
        metalView = nil
        frameTimeout?.cancel()
        frameTimeout = nil
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
