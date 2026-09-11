import Foundation
import simd

public struct Uniforms {
    public var imageSize: SIMD2<Float>
    public var cover: SIMD2<Float>
    public var aspect: Float
    public var turn: Float                    // 0.0 = fully open (90°+), 1.0 = fully closed (0°)
    public var blurStrength: Float
    public var perspectiveStrength: Float
    public var darkVoidIntensity: Float
    public var reflectionIntensity: Float
    public var hasNotch: Float                // 1.0 = notch visible, 0.0 = disabled
    public var showHingeFrame: Float           // 0.0 = iPhone Duo full-screen mode (default), 1.0 = hardware bezel and notch frame
    public var notchSize: SIMD2<Float>        // (normalized width, normalized height)
    
    public init(
        imageSize: SIMD2<Float> = .init(1920, 1080),
        cover: SIMD2<Float> = .init(1, 1),
        aspect: Float = 1.0,
        turn: Float = 0.0,
        blurStrength: Float = 1.0,
        perspectiveStrength: Float = 1.0,
        darkVoidIntensity: Float = 1.0,
        reflectionIntensity: Float = 0.3,
        hasNotch: Float = 0.0,
        showHingeFrame: Float = 0.0,
        notchSize: SIMD2<Float> = .init(0.138, 0.038)
    ) {
        self.imageSize = imageSize
        self.cover = cover
        self.aspect = aspect
        self.turn = turn
        self.blurStrength = blurStrength
        self.perspectiveStrength = perspectiveStrength
        self.darkVoidIntensity = darkVoidIntensity
        self.reflectionIntensity = reflectionIntensity
        self.hasNotch = hasNotch
        self.showHingeFrame = showHingeFrame
        self.notchSize = notchSize
    }
}
