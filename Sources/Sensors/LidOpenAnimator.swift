import Foundation
import AppKit
import QuartzCore

public enum EasingType: String, CaseIterable, Identifiable, Sendable {
    case appleSpring = "Apple Spring (Natural)"
    case easeOut = "Smooth Ease-Out"
    case easeInOut = "Ease-In-Out"
    case linear = "Linear Physical"
    
    public var id: String { rawValue }
    
    public func evaluate(t: Double) -> Double {
        let clamped = min(1.0, max(0.0, t))
        switch self {
        case .linear:
            return clamped
        case .easeOut:
            return 1.0 - pow(1.0 - clamped, 3.0)
        case .easeInOut:
            return clamped < 0.5 ? 4.0 * clamped * clamped * clamped : 1.0 - pow(-2.0 * clamped + 2.0, 3.0) / 2.0
        case .appleSpring:
            // Damped harmonic oscillation easing
            let c4 = (2.0 * Double.pi) / 3.0
            if clamped == 0 { return 0 }
            if clamped == 1 { return 1 }
            return pow(2.0, -10.0 * clamped) * sin((clamped * 10.0 - 0.75) * c4) + 1.0
        }
    }
}

public final class LidOpenAnimator: @unchecked Sendable {
    public static let shared = LidOpenAnimator()
    
    public var onAngleUpdated: ((Double) -> Void)?
    public var onAnimationCompleted: (() -> Void)?
    
    private var displayTimer: Timer?
    private var startTime: CFTimeInterval = 0
    private var startAngle: Double = 0.0
    private var targetAngle: Double = 90.0
    private var duration: Double = 0.8
    private var easing: EasingType = .appleSpring
    
    @Published public private(set) var isAnimating: Bool = false
    
    private init() {
        setupWakeObservers()
    }
    
    private func setupWakeObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            if AppSettings.shared.trackingMode == .autoLidOpen {
                self?.triggerOpenAnimation()
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            if AppSettings.shared.trackingMode == .autoLidOpen {
                self?.triggerOpenAnimation()
            }
        }
    }
    
    public func triggerOpenAnimation(from start: Double = 0.0, to target: Double = 90.0, customDuration: Double? = nil) {
        let dur = customDuration ?? AppSettings.shared.autoOpenDuration
        let ease = AppSettings.shared.autoOpenEasing
        
        startAnimation(from: start, to: target, duration: dur, easing: ease)
    }
    
    public func triggerCloseAnimation(from start: Double = 90.0, to target: Double = 0.0, customDuration: Double? = nil) {
        let dur = customDuration ?? AppSettings.shared.autoOpenDuration
        let ease = AppSettings.shared.autoOpenEasing
        
        startAnimation(from: start, to: target, duration: dur, easing: ease)
    }
    
    public func startAnimation(from: Double, to: Double, duration: Double, easing: EasingType) {
        displayTimer?.invalidate()
        self.startAngle = from
        self.targetAngle = to
        self.duration = max(0.1, duration)
        self.easing = easing
        self.startTime = CACurrentMediaTime()
        self.isAnimating = true
        
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = displayTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        let t = min(1.0, elapsed / duration)
        
        let eased = easing.evaluate(t: t)
        let currentAngle = startAngle + (targetAngle - startAngle) * eased
        
        onAngleUpdated?(currentAngle)
        
        if t >= 1.0 {
            displayTimer?.invalidate()
            displayTimer = nil
            isAnimating = false
            onAngleUpdated?(targetAngle)
            onAnimationCompleted?()
        }
    }
    
    public func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        isAnimating = false
    }
}
