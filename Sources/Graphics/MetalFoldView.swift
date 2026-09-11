import Foundation
import Metal
import MetalKit
import AppKit
import QuartzCore

public final class MetalFoldView: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    
    private var currentTexture: MTLTexture?
    private var imageSize: SIMD2<Float> = .init(1920, 1080)
    
    public var currentTurn: Float = 0.0 {
        didSet {
            // Unpause rendering when folding is active
            if currentTurn > 0.0001 && isPaused {
                isPaused = false
            } else if currentTurn <= 0.0001 && !isPaused {
                isPaused = true
            }
        }
    }
    
    // Performance telemetry
    public private(set) var renderedFPS: Double = 0.0
    public private(set) var lastFrameTimeMs: Double = 0.0
    private var frameCounter: Int = 0
    private var lastFPSCheckTime: CFTimeInterval = CACurrentMediaTime()
    
    public init(frame: CGRect) {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this Mac.")
        }
        super.init(frame: frame, device: defaultDevice)
        commonInit()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        if self.device == nil {
            self.device = MTLCreateSystemDefaultDevice()
        }
        commonInit()
    }
    
    private func commonInit() {
        guard let dev = self.device else { return }
        
        self.commandQueue = dev.makeCommandQueue()
        self.delegate = self
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        self.framebufferOnly = false
        self.enableSetNeedsDisplay = false
        self.isPaused = true // Start paused for zero idle overhead
        
        // Trilinear clamp sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = dev.makeSamplerState(descriptor: samplerDesc)
        
        buildPipeline()
    }
    
    public func buildPipeline() {
        guard let dev = self.device else { return }
        
        var library: MTLLibrary?
        
        // 1. Try bundled metallib
        if let libUrl = Bundle.main.url(forResource: "default", withExtension: "metallib") {
            library = try? dev.makeLibrary(URL: libUrl)
        }
        
        // 2. Try default library
        if library == nil {
            library = dev.makeDefaultLibrary()
        }
        
        // 3. Compile from Shaders.metal source file at runtime
        if library == nil {
            let possibleLocations: [URL?] = [
                Bundle.main.url(forResource: "Shaders", withExtension: "metal"),
                Bundle.main.resourceURL?.appendingPathComponent("Shaders.metal"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Shaders.metal"),
                URL(fileURLWithPath: "Sources/Graphics/Shaders.metal"),
                URL(fileURLWithPath: "/Users/jenilrevaliya/Desktop/Projects/Progressive Blur/Sources/Graphics/Shaders.metal")
            ]
            
            for loc in possibleLocations {
                guard let url = loc else { continue }
                do {
                    let source = try String(contentsOf: url, encoding: .utf8)
                    do {
                        library = try dev.makeLibrary(source: source, options: nil)
                        print("[MetalFoldView] Compiled Shaders.metal from: \(url.path)")
                        break
                    } catch {
                        print("[MetalFoldView] Metal compilation error from \(url.path): \(error)")
                    }
                } catch {
                    // file not at this path, continue
                }
            }
        }
        
        guard let lib = library else {
            print("[MetalFoldView] Warning: Could not locate Shaders.metal library.")
            return
        }
        
        guard let vertexFunc = lib.makeFunction(name: "foldVertex"),
              let fragmentFunc = lib.makeFunction(name: "foldFragment") else {
            print("[MetalFoldView] Error: Missing shader entry points.")
            return
        }
        
        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFunc
        pipeDesc.fragmentFunction = fragmentFunc
        pipeDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            self.pipelineState = try dev.makeRenderPipelineState(descriptor: pipeDesc)
            print("[MetalFoldView] Successfully compiled Metal pipeline: foldVertex + foldFragment")
        } catch {
            print("[MetalFoldView] Failed to make render pipeline state: \(error)")
        }
    }
    
    public func updateImage(_ cgImage: CGImage) {
        guard let dev = self.device, let cq = self.commandQueue else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let width = cgImage.width
            let height = cgImage.height
            let imgSize = SIMD2<Float>(Float(width), Float(height))
            
            let levels = max(1, Int(floor(log2(Double(max(width, height))))))
            
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: true
            )
            desc.mipmapLevelCount = levels
            desc.usage = [.shaderRead, .renderTarget]
            
            guard let texture = dev.makeTexture(descriptor: desc) else { return }
            
            // Render CGImage into level 0
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerRow = width * 4
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let data = context.data {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: bytesPerRow
                )
            }
            
            // Generate mipmaps using blit encoder
            if let cb = cq.makeCommandBuffer(),
               let blit = cb.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: texture)
                blit.endEncoding()
                cb.commit()
                cb.waitUntilCompleted()
            }
            
            DispatchQueue.main.async {
                self?.imageSize = imgSize
                self?.currentTexture = texture
            }
        }
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        let frameStart = CACurrentMediaTime()
        
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let pipeline = self.pipelineState,
              let texture = self.currentTexture,
              let cq = self.commandQueue,
              let cb = cq.makeCommandBuffer(),
              let encoder = cb.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        let settings = AppSettings.shared
        let viewSize = view.drawableSize
        let aspect = Float(viewSize.width / max(1.0, viewSize.height))
        let imgAspect = imageSize.x / max(1.0, imageSize.y)
        
        let cover = SIMD2<Float>(
            min(1.0, aspect / imgAspect),
            min(1.0, imgAspect / aspect)
        )
        
        var uniforms = Uniforms(
            imageSize: imageSize,
            cover: cover,
            aspect: aspect,
            turn: currentTurn,
            blurStrength: Float(settings.blurStrength),
            perspectiveStrength: Float(settings.perspectiveStrength),
            darkVoidIntensity: Float(settings.darkVoidIntensity),
            reflectionIntensity: Float(settings.reflectionIntensity),
            hasNotch: settings.shouldPortrayNotch ? 1.0 : 0.0,
            notchSize: settings.notchNormalizedSize
        )
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        cb.present(drawable)
        cb.commit()
        
        // Frame stats
        let frameEnd = CACurrentMediaTime()
        lastFrameTimeMs = (frameEnd - frameStart) * 1000.0
        frameCounter += 1
        if frameEnd - lastFPSCheckTime >= 1.0 {
            renderedFPS = Double(frameCounter) / (frameEnd - lastFPSCheckTime)
            frameCounter = 0
            lastFPSCheckTime = frameEnd
        }
    }
}
