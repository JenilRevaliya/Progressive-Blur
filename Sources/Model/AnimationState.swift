import Foundation

public enum AnimationState: String, Sendable, CaseIterable {
    case idleOpen = "IDLE_OPEN"
    case closingTransition = "CLOSING_TRANSITION"
    case openingTransition = "OPENING_TRANSITION"
    case nearClosed = "NEAR_CLOSED"
    case sensorUnavailable = "SENSOR_UNAVAILABLE"
    
    public var displayTitle: String {
        switch self {
        case .idleOpen: return "Fully Open (Normal macOS)"
        case .closingTransition: return "Closing Transition"
        case .openingTransition: return "Opening Transition"
        case .nearClosed: return "Near Closed"
        case .sensorUnavailable: return "Simulated / Diagnostic Mode"
        }
    }
}
