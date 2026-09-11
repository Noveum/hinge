import CoreVideo
import MetalKit
import MetalPerformanceShaders

struct FoldParameters {
  var progress: Float = 0
  var opacity: Float = 1
  var blurInset: Float = 0
  var blurSpan: Float = 1
  var taper = DesktopRenderer.taper
}

enum SideFill: String {
  case blur
  case black
}

final class DesktopRenderer: NSObject, MTKViewDelegate {
  static let taper: Float = 0.30
  let device: MTLDevice
  let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let scale: MPSImageBilinearScale
  private let extend: MPSImageBilinearScale
  private var blurKernels = [MPSImageGaussianBlur]()
  private var flatKernel: MPSImageGaussianBlur?
  private var blurTextures = [MTLTexture]()
  private var smallTexture: MTLTexture?
  private var tinyTexture: MTLTexture?
  private var flatTexture: MTLTexture?
  private var sideTexture: MTLTexture?
  private var blurPadding = 0
  private var textureCache: CVMetalTextureCache?
  private let lock = NSLock()
  private let inFlight = DispatchSemaphore(value: 2)
  private var frame: CVPixelBuffer?
  private var generation: UInt64 = 0
  private var blurredGeneration: UInt64?
  private let motion: LidMotion
  private var wasPresented = false
  var effectStrength: Float = 1
  var sideFill = SideFill.blur {
    didSet { if sideFill != oldValue { blurredGeneration = nil } }
  }
  var presentationTime: CFTimeInterval?
  var onPresentation: ((Error?) -> Void)?
  var onRest: (() -> Void)?
  private(set) var renderedFrames = 0

  init(resources: Bundle, motion: LidMotion) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw DesktopError.message(String(localized: "Metal is unavailable on this Mac."))
    }
    self.device = device
    self.queue = queue
    self.motion = motion
    self.scale = MPSImageBilinearScale(device: device)
    self.extend = MPSImageBilinearScale(device: device)
    self.extend.edgeMode = .clamp
    guard let sourceURL = resources.url(forResource: "Fold", withExtension: "metal") else {
      throw DesktopError.message(
        String(localized: "The desktop renderer is missing. Rebuild the app."))
    }
    let library = try device.makeLibrary(
      source: String(contentsOf: sourceURL, encoding: .utf8), options: nil)
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
        guard self.prepareBlur(width: width, height: height),
          let command = self.queue.makeCommandBuffer()
        else {
          throw DesktopError.message(String(localized: "Could not prepare the desktop renderer."))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let source = self.device.makeTexture(descriptor: descriptor) else {
          throw DesktopError.message(String(localized: "Could not allocate the desktop texture."))
        }
        descriptor.width = 32
        descriptor.height = 32
        guard let destination = self.device.makeTexture(descriptor: descriptor) else {
          throw DesktopError.message(
            String(localized: "Could not allocate the renderer warmup texture."))
        }
        let sourcePass = MTLRenderPassDescriptor()
        sourcePass.colorAttachments[0].texture = source
        sourcePass.colorAttachments[0].loadAction = .clear
        sourcePass.colorAttachments[0].storeAction = .store
        sourcePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let clear = command.makeRenderCommandEncoder(descriptor: sourcePass) else {
          throw DesktopError.message(String(localized: "Could not initialize the desktop texture."))
        }
        clear.endEncoding()
        guard self.encodeBlur(command: command, texture: source) else {
          throw DesktopError.message(String(localized: "Could not prepare the desktop renderer."))
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard
          self.encodeFold(command: command, pass: pass, texture: source, progress: 0.5, opacity: 1)
        else {
          throw DesktopError.message(String(localized: "Could not prepare the fold pipeline."))
        }
        command.addCompletedHandler { command in
          if let error = command.error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
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
    let padding = Int((Double(smallWidth) * Double(Self.taper) / 2).rounded(.up)) + 1
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: smallWidth, height: smallHeight, mipmapped: false)
    descriptor.storageMode = .private
    descriptor.usage = [.shaderRead, .shaderWrite]
    guard let small = device.makeTexture(descriptor: descriptor) else { return false }
    descriptor.width = max(smallWidth / 4, 1)
    descriptor.height = max(smallHeight / 4, 1)
    guard let tiny = device.makeTexture(descriptor: descriptor),
      let flat = device.makeTexture(descriptor: descriptor)
    else { return false }
    descriptor.width = smallWidth + 2 * padding
    descriptor.height = smallHeight
    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    var textures = [MTLTexture]()
    for _ in 0..<4 {
      guard let texture = device.makeTexture(descriptor: descriptor) else { return false }
      textures.append(texture)
    }
    smallTexture = small
    tinyTexture = tiny
    flatTexture = flat
    sideTexture = textures.removeLast()
    blurPadding = padding
    blurTextures = textures
    blurKernels = [6.0, 16.0, 36.0, 9.0].map {
      let kernel = MPSImageGaussianBlur(device: device, sigma: Float($0 * Double(smallWidth) / 786))
      kernel.edgeMode = .clamp
      return kernel
    }
    flatKernel = blurKernels.removeLast()
    blurredGeneration = nil
    return true
  }

  private func encodeBlur(command: MTLCommandBuffer, texture: MTLTexture) -> Bool {
    guard let smallTexture, let sideTexture else { return false }
    scale.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: smallTexture)
    switch sideFill {
    case .black:
      guard encodeClear(command: command, texture: sideTexture) else { return false }
    case .blur:
      guard let tinyTexture, let flatTexture, let flatKernel else { return false }
      scale.encode(
        commandBuffer: command, sourceTexture: smallTexture, destinationTexture: tinyTexture)
      flatKernel.encode(
        commandBuffer: command, sourceTexture: tinyTexture, destinationTexture: flatTexture)
      let transform = MPSScaleTransform(
        scaleX: Double(smallTexture.width) / Double(flatTexture.width),
        scaleY: Double(smallTexture.height) / Double(flatTexture.height),
        translateX: Double(blurPadding), translateY: 0)
      withUnsafePointer(to: transform) { transform in
        extend.scaleTransform = transform
        extend.encode(
          commandBuffer: command, sourceTexture: flatTexture, destinationTexture: sideTexture)
      }
      extend.scaleTransform = nil
    }
    guard let blit = command.makeBlitCommandEncoder() else { return false }
    blit.copy(
      from: smallTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
      sourceSize: MTLSize(width: smallTexture.width, height: smallTexture.height, depth: 1),
      to: sideTexture, destinationSlice: 0, destinationLevel: 0,
      destinationOrigin: MTLOrigin(x: blurPadding, y: 0, z: 0))
    blit.endEncoding()
    for (kernel, destination) in zip(blurKernels, blurTextures) {
      kernel.encode(
        commandBuffer: command, sourceTexture: sideTexture, destinationTexture: destination)
    }
    return true
  }

  private func encodeClear(command: MTLCommandBuffer, texture: MTLTexture) -> Bool {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
    encoder.endEncoding()
    return true
  }

  func draw(in view: MTKView) {
    let time = presentationTime ?? CACurrentMediaTime()
    presentationTime = nil
    let progress = motion.sample(at: time) * effectStrength
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
    CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(buffer),
      CVPixelBufferGetHeight(buffer), 0, &wrappedTexture)
    guard let wrappedTexture, let texture = CVMetalTextureGetTexture(wrappedTexture),
      prepareBlur(width: texture.width, height: texture.height),
      let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
      let command = queue.makeCommandBuffer()
    else {
      inFlight.signal()
      return
    }
    if blurredGeneration != generation, encodeBlur(command: command, texture: texture) {
      blurredGeneration = generation
    }
    let blend = min(progress / 0.025, 1)
    let opacity = blend * blend * (3 - 2 * blend)
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, Double(opacity))
    guard
      encodeFold(
        command: command, pass: pass, texture: texture, progress: progress, opacity: opacity)
    else {
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

  private func encodeFold(
    command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, texture: MTLTexture, progress: Float,
    opacity: Float
  ) -> Bool {
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
    let paddedWidth = Float(sideTexture?.width ?? 1)
    var parameters = FoldParameters(
      progress: progress, opacity: opacity, blurInset: Float(blurPadding) / paddedWidth,
      blurSpan: (paddedWidth - Float(2 * blurPadding)) / paddedWidth)
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
    encoder.setFragmentBytes(&parameters, length: MemoryLayout<FoldParameters>.stride, index: 0)
    encoder.setFragmentTexture(texture, index: 0)
    for (index, texture) in blurTextures.enumerated() {
      encoder.setFragmentTexture(texture, index: index + 1)
    }
    encoder.setFragmentTexture(sideTexture, index: 4)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    return true
  }

  private func clear(_ view: MTKView) {
    guard inFlight.wait(timeout: .now()) == .success else { return }
    guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
      let command = queue.makeCommandBuffer()
    else {
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
        if let error { onPresentation?(error) } else { onRest?() }
      }
    }
    command.commit()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

enum DesktopError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): text
    }
  }
}
