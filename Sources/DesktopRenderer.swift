import MetalKit
import MetalPerformanceShaders
import CoreVideo

struct FoldParameters {
    var progress: Float = 0
    var opacity: Float = 1
}

final class DesktopRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let scale: MPSImageBilinearScale
    private var blurKernels = [MPSImageGaussianBlur]()
    private var blurTextures = [MTLTexture]()
    private var smallTexture: MTLTexture?
    private var textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    private let inFlight = DispatchSemaphore(value: 2)
    private var frame: CVPixelBuffer?
    private var generation: UInt64 = 0
    private var blurredGeneration: UInt64?
    private let motion: LidMotion
    private var wasPresented = false
    var presentationTime: CFTimeInterval?
    var onPresentation: ((Error?) -> Void)?
    var onRest: (() -> Void)?
    private(set) var renderedFrames = 0

    init(resources: Bundle, motion: LidMotion) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw DesktopError.message("Metal is unavailable on this Mac.")
        }
        self.device = device
        self.queue = queue
        self.motion = motion
        self.scale = MPSImageBilinearScale(device: device)
        guard let sourceURL = resources.url(forResource: "Fold", withExtension: "metal") else {
            throw DesktopError.message("The desktop renderer is missing. Rebuild the app.")
        }
        let library = try device.makeLibrary(source: String(contentsOf: sourceURL, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    var hasFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frame != nil
    }

    func receive(_ frame: CVPixelBuffer) {
        lock.lock()
        self.frame = frame
        generation &+= 1
        lock.unlock()
    }

    func warmUp(width: Int, height: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                guard self.prepareBlur(width: width, height: height), let smallTexture = self.smallTexture,
                      let command = self.queue.makeCommandBuffer() else {
                    throw DesktopError.message("Could not prepare the desktop renderer.")
                }
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .renderTarget]
                guard let source = self.device.makeTexture(descriptor: descriptor) else {
                    throw DesktopError.message("Could not allocate the desktop texture.")
                }
                descriptor.width = 32
                descriptor.height = 32
                guard let destination = self.device.makeTexture(descriptor: descriptor) else {
                    throw DesktopError.message("Could not allocate the renderer warmup texture.")
                }
                let sourcePass = MTLRenderPassDescriptor()
                sourcePass.colorAttachments[0].texture = source
                sourcePass.colorAttachments[0].loadAction = .clear
                sourcePass.colorAttachments[0].storeAction = .store
                sourcePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                guard let clear = command.makeRenderCommandEncoder(descriptor: sourcePass) else {
                    throw DesktopError.message("Could not initialize the desktop texture.")
                }
                clear.endEncoding()
                self.scale.encode(commandBuffer: command, sourceTexture: source, destinationTexture: smallTexture)
                for (kernel, texture) in zip(self.blurKernels, self.blurTextures) {
                    kernel.encode(commandBuffer: command, sourceTexture: smallTexture, destinationTexture: texture)
                }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = destination
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                guard self.encodeFold(command: command, pass: pass, texture: source, progress: 0.5, opacity: 1) else {
                    throw DesktopError.message("Could not prepare the fold pipeline.")
                }
                command.addCompletedHandler { command in
                    if let error = command.error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
                command.commit()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func prepareBlur(width: Int, height: Int) -> Bool {
        let smallWidth = max(width / 4, 1)
        let smallHeight = max(height / 4, 1)
        if smallTexture?.width == smallWidth, smallTexture?.height == smallHeight { return true }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: smallWidth, height: smallHeight, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let small = device.makeTexture(descriptor: descriptor) else { return false }
        var textures = [MTLTexture]()
        for _ in 0..<3 {
            guard let texture = device.makeTexture(descriptor: descriptor) else { return false }
            textures.append(texture)
        }
        smallTexture = small
        blurTextures = textures
        blurKernels = [6.0, 16.0, 36.0].map {
            let kernel = MPSImageGaussianBlur(device: device, sigma: Float($0 * Double(smallWidth) / 786))
            kernel.edgeMode = .clamp
            return kernel
        }
        blurredGeneration = nil
        return true
    }

    func draw(in view: MTKView) {
        let time = presentationTime ?? CACurrentMediaTime()
        presentationTime = nil
        let progress = motion.sample(at: time)
        guard progress > 0 else {
            clear(view)
            return
        }
        lock.lock()
        let buffer = frame
        let generation = generation
        lock.unlock()
        guard let buffer, let textureCache else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var wrappedTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &wrappedTexture)
        guard let wrappedTexture, let texture = CVMetalTextureGetTexture(wrappedTexture),
              prepareBlur(width: texture.width, height: texture.height), let smallTexture,
              let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        if blurredGeneration != generation {
            scale.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: smallTexture)
            for (kernel, destination) in zip(blurKernels, blurTextures) {
                kernel.encode(commandBuffer: command, sourceTexture: smallTexture, destinationTexture: destination)
            }
            blurredGeneration = generation
        }
        let blend = min(progress / 0.025, 1)
        let opacity = blend * blend * (3 - 2 * blend)
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, Double(opacity))
        guard encodeFold(command: command, pass: pass, texture: texture, progress: progress, opacity: opacity) else {
            blurredGeneration = nil
            inFlight.signal()
            return
        }
        command.present(drawable)
        let inFlight = inFlight
        let notify = !wasPresented
        let onPresentation = onPresentation
        wasPresented = true
        command.addCompletedHandler { command in
            _ = wrappedTexture
            _ = buffer
            inFlight.signal()
            if notify || command.error != nil {
                let failure = command.error
                DispatchQueue.main.async { onPresentation?(failure) }
            }
        }
        command.commit()
        renderedFrames += 1
    }

    private func encodeFold(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, texture: MTLTexture, progress: Float, opacity: Float) -> Bool {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        var parameters = FoldParameters(progress: progress, opacity: opacity)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        for (index, texture) in blurTextures.enumerated() { encoder.setFragmentTexture(texture, index: index + 1) }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func clear(_ view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        encoder.endEncoding()
        command.present(drawable)
        wasPresented = false
        let inFlight = inFlight
        let onRest = onRest
        let onPresentation = onPresentation
        command.addCompletedHandler { command in
            inFlight.signal()
            let error = command.error
            DispatchQueue.main.async {
                if let error { onPresentation?(error) }
                else { onRest?() }
            }
        }
        command.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

enum DesktopError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
