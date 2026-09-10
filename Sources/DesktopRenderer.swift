import MetalKit
import CoreVideo

struct FoldParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.65
    var shadow: Float = 0.55
    var width: Float = 1512
    var height: Float = 982
    var frost: Float = 0
    var padding: Float = 0
}

final class DesktopRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var parameters = FoldParameters()
    private var textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    private let inFlight = DispatchSemaphore(value: 3)
    private var frame: CVPixelBuffer?
    private(set) var renderedFrames = 0
    var onPresentation: ((Error?) -> Void)?

    init(resources: Bundle) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw DesktopError.message("Metal is unavailable on this Mac.")
        }
        self.device = device
        self.queue = queue
        guard let sourceURL = resources.url(forResource: "Fold", withExtension: "metal") else {
            throw DesktopError.message("The fold renderer is missing. Rebuild the app.")
        }
        let library = try device.makeLibrary(source: String(contentsOf: sourceURL), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
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
        lock.unlock()
    }

    func draw(in view: MTKView) {
        lock.lock()
        let buffer = frame
        lock.unlock()
        guard let buffer, let textureCache else { return }
        var wrappedTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &wrappedTexture)
        guard let wrappedTexture, let texture = CVMetalTextureGetTexture(wrappedTexture),
              let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        var parameters = parameters
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        let inFlight = inFlight
        let onPresentation = onPresentation
        command.addCompletedHandler { command in
            _ = wrappedTexture
            _ = buffer
            inFlight.signal()
            let failure = command.error
            DispatchQueue.main.async { onPresentation?(failure) }
        }
        command.commit()
        renderedFrames += 1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

enum DesktopError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
