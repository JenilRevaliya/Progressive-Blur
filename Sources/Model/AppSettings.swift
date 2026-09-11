import Foundation
import SwiftUI
import Combine

public enum ImageSourceMode: Int, CaseIterable, Identifiable, Sendable {
    case liveCapture = 0
    case desktopWallpaper = 1
    case bundledArtwork = 2
    case customImage = 3
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .liveCapture: return "Live Screen Capture"
        case .desktopWallpaper: return "Desktop Wallpaper"
        case .bundledArtwork: return "Bundled Dynamic Artwork"
        case .customImage: return "Custom Image File"
        }
    }
}

public enum TrackingMode: Int, CaseIterable, Identifiable, Sendable {
    case cameraOptical = 0
    case trackpadGesture = 1
    case autoLidOpen = 2
    case manualSimulator = 3
    case hardwareSensor = 4
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .cameraOptical: return "Option A: Camera Optical Inclinometer (Real Lid Tilt)"
        case .trackpadGesture: return "Option B: Trackpad Haptic Gesture"
        case .autoLidOpen: return "Option C: Automated Sweep on Lid Open (Custom Speed)"
        case .manualSimulator: return "Interactive Manual Preview Slider"
        case .hardwareSensor: return "Native Hardware Sensor (M2+ Air / 14\" & 16\" Pro)"
        }
    }
}

public enum NotchDisplayMode: Int, CaseIterable, Identifiable, Sendable {
    case auto = 0
    case always = 1
    case never = 2
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .auto: return "Auto-Detect (Enabled on Notch MacBooks)"
        case .always: return "Always Portray Notch (Simulate on All Macs)"
        case .never: return "Never Portray Notch (Classic Flat Top)"
        }
    }
}

public final class AppSettings: ObservableObject, @unchecked Sendable {
    public static let shared = AppSettings()
    
    // UserDefaults Keys
    private let kStartAngle = "pb_startAngle"
    private let kEndAngle = "pb_endAngle"
    private let kBlurStrength = "pb_blurStrength"
    private let kPerspectiveStrength = "pb_perspectiveStrength"
    private let kDarkVoidIntensity = "pb_darkVoidIntensity"
    private let kReflectionIntensity = "pb_reflectionIntensity"
    private let kFollowSpeed = "pb_followSpeed"
    private let kImageSourceMode = "pb_imageSourceMode"
    private let kCustomImagePath = "pb_customImagePath"
    private let kShowAngleInMenuBar = "pb_showAngleInMenuBar"
    private let kTrackingMode = "pb_trackingMode"
    private let kAutoOpenDuration = "pb_autoOpenDuration"
    private let kAutoOpenEasing = "pb_autoOpenEasing"
    private let kTrackpadSensitivity = "pb_trackpadSensitivity"
    private let kEnableLockScreenOverlay = "pb_enableLockScreenOverlay"
    private let kNotchDisplayMode = "pb_notchDisplayMode"
    
    // Configurable Tracking Mode
    @Published public var trackingMode: TrackingMode {
        didSet {
            UserDefaults.standard.set(trackingMode.rawValue, forKey: kTrackingMode)
            applyTrackingModeChange()
        }
    }
    
    @Published public var autoOpenDuration: Double {
        didSet { UserDefaults.standard.set(autoOpenDuration, forKey: kAutoOpenDuration) }
    }
    
    @Published public var autoOpenEasing: EasingType {
        didSet { UserDefaults.standard.set(autoOpenEasing.rawValue, forKey: kAutoOpenEasing) }
    }
    
    @Published public var trackpadSensitivity: Double {
        didSet { UserDefaults.standard.set(trackpadSensitivity, forKey: kTrackpadSensitivity) }
    }
    
    @Published public var enableTrackpadDirectDrag: Bool = true
    
    @Published public var enableLockScreenOverlay: Bool {
        didSet { UserDefaults.standard.set(enableLockScreenOverlay, forKey: kEnableLockScreenOverlay) }
    }
    
    @Published public var notchDisplayMode: NotchDisplayMode {
        didSet { UserDefaults.standard.set(notchDisplayMode.rawValue, forKey: kNotchDisplayMode) }
    }
    
    /// True if notch cutout and camera dot should be portrayed in the 3D clamshell
    public var shouldPortrayNotch: Bool {
        switch notchDisplayMode {
        case .always:
            return true
        case .never:
            return false
        case .auto:
            // Check hardware compatibility table for notch models
            if HardwareCompat.current.hasHardwareNotch {
                return true
            }
            // Dynamic check via AppKit screen safe area insets (non-zero top inset on notch screens)
            if let screen = NSScreen.main, screen.safeAreaInsets.top > 0 {
                return true
            }
            return false
        }
    }
    
    /// Normalized size of the notch (width, height) relative to screen aspect ratio
    public var notchNormalizedSize: SIMD2<Float> {
        if let screen = NSScreen.main, screen.safeAreaInsets.top > 0 {
            let screenH = Float(screen.frame.height)
            let topInset = Float(screen.safeAreaInsets.top)
            let notchW: Float = 0.138
            let notchH: Float = topInset / max(screenH, 1.0)
            return SIMD2<Float>(notchW, max(0.035, notchH))
        }
        // Standard Liquid Retina notch proportions: ~13.8% of width, ~3.8% of height
        return SIMD2<Float>(0.138, 0.038)
    }
    
    @Published public var startAngle: Double {
        didSet { UserDefaults.standard.set(startAngle, forKey: kStartAngle) }
    }
    
    @Published public var endAngle: Double {
        didSet { UserDefaults.standard.set(endAngle, forKey: kEndAngle) }
    }
    
    @Published public var blurStrength: Double {
        didSet { UserDefaults.standard.set(blurStrength, forKey: kBlurStrength) }
    }
    
    @Published public var perspectiveStrength: Double {
        didSet { UserDefaults.standard.set(perspectiveStrength, forKey: kPerspectiveStrength) }
    }
    
    @Published public var darkVoidIntensity: Double {
        didSet { UserDefaults.standard.set(darkVoidIntensity, forKey: kDarkVoidIntensity) }
    }
    
    @Published public var reflectionIntensity: Double {
        didSet { UserDefaults.standard.set(reflectionIntensity, forKey: kReflectionIntensity) }
    }
    
    @Published public var followSpeed: Double {
        didSet { UserDefaults.standard.set(followSpeed, forKey: kFollowSpeed) }
    }
    
    @Published public var imageSourceMode: ImageSourceMode {
        didSet { UserDefaults.standard.set(imageSourceMode.rawValue, forKey: kImageSourceMode) }
    }
    
    @Published public var customImagePath: String {
        didSet { UserDefaults.standard.set(customImagePath, forKey: kCustomImagePath) }
    }
    
    @Published public var showAngleInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showAngleInMenuBar, forKey: kShowAngleInMenuBar) }
    }
    
    // Interactive Simulation & Preview
    @Published public var isTestModeActive: Bool = false {
        didSet {
            LidSensorManager.shared.setSimulatedAngle(testAngle)
        }
    }
    @Published public var testAngle: Double = 90.0 {
        didSet {
            LidSensorManager.shared.setSimulatedAngle(testAngle)
        }
    }
    
    // Realtime Status
    @Published public var hasScreenCapturePermission: Bool = false
    @Published public var lastCaptureDate: Date? = nil
    
    private init() {
        let defaults = UserDefaults.standard
        
        // Exact 90° Rule default
        self.startAngle = defaults.object(forKey: kStartAngle) != nil ? defaults.double(forKey: kStartAngle) : 90.0
        self.endAngle = defaults.object(forKey: kEndAngle) != nil ? defaults.double(forKey: kEndAngle) : 2.0
        self.blurStrength = defaults.object(forKey: kBlurStrength) != nil ? defaults.double(forKey: kBlurStrength) : 1.0
        self.perspectiveStrength = defaults.object(forKey: kPerspectiveStrength) != nil ? defaults.double(forKey: kPerspectiveStrength) : 1.0
        self.darkVoidIntensity = defaults.object(forKey: kDarkVoidIntensity) != nil ? defaults.double(forKey: kDarkVoidIntensity) : 1.0
        self.reflectionIntensity = defaults.object(forKey: kReflectionIntensity) != nil ? defaults.double(forKey: kReflectionIntensity) : 0.3
        self.followSpeed = defaults.object(forKey: kFollowSpeed) != nil ? defaults.double(forKey: kFollowSpeed) : 22.0
        
        let savedMode = defaults.integer(forKey: kImageSourceMode)
        self.imageSourceMode = ImageSourceMode(rawValue: savedMode) ?? .liveCapture
        self.customImagePath = defaults.string(forKey: kCustomImagePath) ?? ""
        self.showAngleInMenuBar = defaults.object(forKey: kShowAngleInMenuBar) != nil ? defaults.bool(forKey: kShowAngleInMenuBar) : true
        
        let savedTracking = defaults.integer(forKey: kTrackingMode)
        self.trackingMode = defaults.object(forKey: kTrackingMode) != nil ? (TrackingMode(rawValue: savedTracking) ?? .autoLidOpen) : .autoLidOpen
        self.autoOpenDuration = defaults.object(forKey: kAutoOpenDuration) != nil ? defaults.double(forKey: kAutoOpenDuration) : 0.8
        let savedEase = defaults.string(forKey: kAutoOpenEasing) ?? EasingType.appleSpring.rawValue
        self.autoOpenEasing = EasingType(rawValue: savedEase) ?? .appleSpring
        self.trackpadSensitivity = defaults.object(forKey: kTrackpadSensitivity) != nil ? defaults.double(forKey: kTrackpadSensitivity) : 0.4
        self.enableLockScreenOverlay = defaults.object(forKey: kEnableLockScreenOverlay) != nil ? defaults.bool(forKey: kEnableLockScreenOverlay) : true
        
        let savedNotch = defaults.integer(forKey: kNotchDisplayMode)
        self.notchDisplayMode = defaults.object(forKey: kNotchDisplayMode) != nil ? (NotchDisplayMode(rawValue: savedNotch) ?? .auto) : .auto
    }
    
    public func applyTrackingModeChange() {
        switch trackingMode {
        case .cameraOptical:
            LidOpenAnimator.shared.stop()
            TrackpadGestureTracker.shared.stop()
            OpticalHingeTracker.shared.start()
            isTestModeActive = false
        case .trackpadGesture:
            LidOpenAnimator.shared.stop()
            OpticalHingeTracker.shared.stop()
            TrackpadGestureTracker.shared.start()
            isTestModeActive = false
        case .autoLidOpen:
            OpticalHingeTracker.shared.stop()
            TrackpadGestureTracker.shared.stop()
            isTestModeActive = false
        case .manualSimulator:
            OpticalHingeTracker.shared.stop()
            TrackpadGestureTracker.shared.stop()
            LidOpenAnimator.shared.stop()
            isTestModeActive = true
        case .hardwareSensor:
            OpticalHingeTracker.shared.stop()
            TrackpadGestureTracker.shared.stop()
            LidOpenAnimator.shared.stop()
            isTestModeActive = false
            LidSensorManager.shared.start()
        }
    }
    
    /// Returns 1.0 when fully open (>= 90°), and 0.0 when fully closed (<= 2°)
    public func normalizedProgress(for angle: Double) -> Double {
        if angle >= startAngle {
            return 1.0
        }
        if angle <= endAngle {
            return 0.0
        }
        let span = startAngle - endAngle
        guard span > 0.001 else { return 1.0 }
        return min(1.0, max(0.0, (angle - endAngle) / span))
    }
    
    /// Returns 0.0 when fully open (>= 90°), and 1.0 when fully closed (<= 2°)
    public func normalizedFoldTurn(for angle: Double) -> Double {
        let progress = normalizedProgress(for: angle)
        return 1.0 - progress
    }
    
    public func checkInitialSensorState() {
        if LidSensorManager.shared.isConnected {
            // Real continuous Apple Hall-effect sensor detected (14"/16" Pro or M2+ Air)!
            // Automatically activate native hardware sensor tracking
            trackingMode = .hardwareSensor
            isTestModeActive = false
            print("[AppSettings] Apple Hardware Lid Sensor detected! Auto-activated .hardwareSensor tracking.")
        } else {
            // No continuous hardware sensor (M1 Air or desktop Mac).
            // Default to Option C (Automated sweep on lid open) or manual simulator
            if trackingMode == .hardwareSensor {
                trackingMode = .autoLidOpen
            }
        }
    }
}
