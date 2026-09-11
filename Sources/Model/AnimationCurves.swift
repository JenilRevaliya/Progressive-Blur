import Foundation

public struct AnimationCurves {
    /// MAX_TILT angle in radians (approx 48.2 degrees tilt)
    public static let maxTiltRadians: Float = 0.84106867
    
    /// Perspective focal eye distance
    public static func eyeDistance(aspect: Float) -> Float {
        let invAspect = 1.0 / max(0.1, aspect)
        return 3.2 * max(invAspect, 1.0)
    }
    
    /// Computes progressive blur radius based on distance from hinge and fold progress.
    /// - Parameters:
    ///   - fromHinge: 0.0 at hinge (bottom of screen), 1.0 at top of screen.
    ///   - foldTurn: 0.0 when fully open (90°), 1.0 when fully closed (0°).
    ///   - strength: User multiplier.
    public static func blurRadius(fromHinge: Float, foldTurn: Float, strength: Float = 1.0) -> Float {
        let clampedHinge = min(1.0, max(0.0, fromHinge))
        let clampedTurn = min(1.0, max(0.0, foldTurn))
        
        // Defocus blur spreads outward nonlinearly from the hinge
        let blurSpread = pow(smoothstep(edge0: 0.0, edge1: 0.85, x: clampedHinge), 1.2)
        let motion = smoothstep(edge0: 0.0, edge1: 1.0, x: clampedTurn) * (0.20 + 0.80 * blurSpread)
        return 56.0 * motion * max(0.05, strength)
    }
    
    /// Computes dark void darkening factor
    public static func voidDarkening(fromHinge: Float, foldTurn: Float) -> Float {
        let clampedHinge = min(1.0, max(0.0, fromHinge))
        let clampedTurn = min(1.0, max(0.0, foldTurn))
        let fadeDistance = min(1.0, max(0.0, (clampedHinge - 0.20) / 0.80))
        return pow(clampedTurn, 1.1) * fadeDistance
    }
    
    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }
}
