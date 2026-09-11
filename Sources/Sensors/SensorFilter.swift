import Foundation
import QuartzCore

/// Low-latency, physically responsive smoothing filter for lid angle & animation turn.
public final class SensorFilter: @unchecked Sendable {
    private var lastTime: CFTimeInterval?
    private var smoothedValue: Double
    private var velocity: Double = 0.0
    
    public init(initialValue: Double = 0.0) {
        self.smoothedValue = initialValue
    }
    
    public func reset(to value: Double) {
        smoothedValue = value
        velocity = 0.0
        lastTime = nil
    }
    
    /// Updates and returns the smoothed value using exponential follow physics.
    ///
    /// - Parameters:
    ///   - target: The raw or target value to track.
    ///   - followSpeed: Responsiveness coefficient (e.g. 16.0 - 24.0).
    ///   - deadband: Minimum change needed to trigger filtering.
    /// - Returns: Smoothed value tracking the target with zero perceptible lag.
    public func update(target: Double, followSpeed: Double = 20.0, deadband: Double = 0.0005) -> Double {
        let now = CACurrentMediaTime()
        let dt: Double
        if let last = lastTime {
            dt = min(now - last, 0.05) // Cap dt to avoid large delta spikes during hiccups
        } else {
            dt = 1.0 / 60.0
        }
        lastTime = now
        
        let delta = target - smoothedValue
        if abs(delta) < deadband {
            smoothedValue = target
            velocity = 0.0
            return smoothedValue
        }
        
        // Asymptotically approach target: factor = 1 - e^(-dt * speed)
        let factor = 1.0 - exp(-dt * followSpeed)
        let step = delta * factor
        smoothedValue += step
        velocity = dt > 0 ? (step / dt) : 0.0
        
        if abs(target - smoothedValue) < deadband {
            smoothedValue = target
        }
        
        return smoothedValue
    }
    
    public var currentSmoothedValue: Double {
        smoothedValue
    }
    
    public var currentVelocity: Double {
        velocity
    }
}
