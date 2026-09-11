import Foundation
import AppKit

public final class TrackpadGestureTracker: @unchecked Sendable {
    public static let shared = TrackpadGestureTracker()
    
    public var onAngleUpdated: ((Double) -> Void)?
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var currentAngle: Double = 90.0
    
    private var eventMonitor: Any?
    private var lastHapticAngle: Double = 90.0
    
    private init() {}
    
    public func start() {
        guard eventMonitor == nil else { return }
        isEnabled = true
        currentAngle = 90.0
        
        // Monitor global scroll, trackpad, and key events (Escape cancels)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown]) { [weak self] event in
            guard let self = self, self.isEnabled else { return event }
            
            if event.type == .keyDown && event.keyCode == 53 { // 53 = Escape
                self.reset()
                return nil
            }
            
            if event.type == .scrollWheel {
                // If Command or Control or 2-finger scroll is moving vertically
                let dy = event.scrollingDeltaY
                if abs(dy) > 0.01 && (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || AppSettings.shared.enableTrackpadDirectDrag) {
                    let sensitivity = AppSettings.shared.trackpadSensitivity
                    // Natural clamshell physics: dragging downwards folds the lid down (decreases angle)
                    let newAngle = min(120.0, max(0.0, self.currentAngle - Double(dy) * sensitivity))
                    
                    if newAngle != self.currentAngle {
                        self.currentAngle = newAngle
                        self.checkHapticFeedback(newAngle)
                        self.onAngleUpdated?(newAngle)
                    }
                }
            } else if event.type == .magnify {
                // Pinch to fold (pinch inwards closes, spread outwards opens)
                let mag = Double(event.magnification)
                let delta = mag * 60.0
                let newAngle = min(120.0, max(0.0, self.currentAngle + delta))
                if newAngle != self.currentAngle {
                    self.currentAngle = newAngle
                    self.checkHapticFeedback(newAngle)
                    self.onAngleUpdated?(newAngle)
                }
            }
            
            return event
        }
    }
    
    public func reset() {
        currentAngle = 90.0
        lastHapticAngle = 90.0
        onAngleUpdated?(90.0)
    }
    
    public func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isEnabled = false
    }
    
    private func checkHapticFeedback(_ angle: Double) {
        // Fire haptic notch every 15 degrees
        if abs(angle - lastHapticAngle) >= 15.0 {
            lastHapticAngle = angle
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }
}
