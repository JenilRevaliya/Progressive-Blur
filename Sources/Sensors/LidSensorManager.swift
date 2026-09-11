import Foundation
import IOKit.hid
import QuartzCore
import Combine

public final class LidSensorManager: ObservableObject, @unchecked Sendable {
    public static let shared = LidSensorManager()
    
    // Callbacks
    public typealias AngleCallback = (_ rawAngle: Double, _ calibratedAngle: Double, _ progress: Double, _ isClosing: Bool) -> Void
    public var onAngleUpdate: AngleCallback?
    public var onPreArmCapture: (() -> Void)?
    
    // Published diagnostics for SwiftUI
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isSimulated: Bool = false
    @Published public private(set) var rawAngle: Double = 90.0
    @Published public private(set) var calibratedAngle: Double = 90.0
    @Published public private(set) var currentProgress: Double = 0.0
    @Published public private(set) var isClosing: Bool = false
    @Published public private(set) var statusMessage: String = "Initializing..."
    @Published public private(set) var pollingFPS: Double = 0.0
    
    // IOHID internal state
    private var hidManager: IOHIDManager?
    private var hidDevice: IOHIDDevice?
    private var isDeviceOpen: Bool = false
    private var timer: Timer?
    private var hidReport = [UInt8](repeating: 0, count: 8)
    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)
    
    // Motion tracking & smoothing
    private var previousRawAngle: Double = 90.0
    private var stationaryCounter: Int = 0
    private var hasPreArmedInThisMotion: Bool = false
    private var lastPreArmTime: CFTimeInterval = 0
    private let angleFilter = SensorFilter(initialValue: 90.0)
    
    // FPS measurement
    private var frameCount: Int = 0
    private var lastFPSCheckTime: CFTimeInterval = CACurrentMediaTime()
    
    // Simulation state
    private var simulatedAngleValue: Double = 90.0
    
    private init() {
        setupSensor()
    }
    
    deinit {
        stop()
    }
    
    public func setupSensor() {
        let compat = HardwareCompat.current
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, Self.noOptions)
        guard IOHIDManagerOpen(manager, Self.noOptions) == kIOReturnSuccess else {
            statusMessage = "IOHIDManager initialization failed."
            isConnected = false
            enableSimulationFallback(reason: compat.supportStatus.summary)
            return
        }
        self.hidManager = manager
        
        // Tier 1: Primary match - Apple (0x05AC), Product (0x8104), Page (0x0020), Usage (0x008A)
        let primaryMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, primaryMatch as CFDictionary)
        var workingDevice = findWorkingLidDevice(in: manager)
        
        // Tier 2: Relaxed match - Apple (0x05AC), Page (0x0020), Usage (0x008A)
        if workingDevice == nil {
            let relaxedMatch: [String: Any] = [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDDeviceUsagePageKey as String: 0x0020,
                kIOHIDDeviceUsageKey as String: 0x008A
            ]
            IOHIDManagerSetDeviceMatching(manager, relaxedMatch as CFDictionary)
            workingDevice = findWorkingLidDevice(in: manager)
        }
        
        // Tier 3: Broad match - Page (0x0020), Usage (0x008A)
        if workingDevice == nil {
            let broadMatch: [String: Any] = [
                kIOHIDDeviceUsagePageKey as String: 0x0020,
                kIOHIDDeviceUsageKey as String: 0x008A
            ]
            IOHIDManagerSetDeviceMatching(manager, broadMatch as CFDictionary)
            workingDevice = findWorkingLidDevice(in: manager)
        }
        
        if let dev = workingDevice {
            self.hidDevice = dev
            self.isDeviceOpen = true
            self.isConnected = true
            self.isSimulated = false
            self.statusMessage = "Connected to Apple Lid Angle Sensor (0x8104)."
            print("[LidSensorManager] Successfully connected to verified Apple Lid Angle Sensor.")
        } else {
            self.isConnected = false
            self.enableSimulationFallback(reason: compat.supportStatus.summary)
        }
    }
    
    private func findWorkingLidDevice(in manager: IOHIDManager) -> IOHIDDevice? {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return nil }
        let count = CFSetGetCount(devices)
        guard count > 0 else { return nil }
        
        var values = Array<UnsafeRawPointer?>(repeating: nil, count: count)
        CFSetGetValues(devices, &values)
        
        for i in 0..<count {
            guard let raw = values[i] else { continue }
            let dev = unsafeBitCast(raw, to: IOHIDDevice.self)
            
            if IOHIDDeviceOpen(dev, Self.noOptions) == kIOReturnSuccess {
                var testReport = [UInt8](repeating: 0, count: 8)
                var length = CFIndex(testReport.count)
                let res = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, &testReport, &length)
                if res == kIOReturnSuccess && length >= 3 {
                    return dev
                }
                IOHIDDeviceClose(dev, Self.noOptions)
            }
        }
        return nil
    }
    
    private func enableSimulationFallback(reason: String) {
        self.isSimulated = true
        self.statusMessage = "Simulated Mode (\(reason))"
    }
    
    public func start() {
        guard timer == nil else { return }
        
        if let device = hidDevice, !isDeviceOpen {
            if IOHIDDeviceOpen(device, Self.noOptions) == kIOReturnSuccess {
                isDeviceOpen = true
            }
        }
        
        // 60 Hz polling timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        if isDeviceOpen, let device = hidDevice {
            IOHIDDeviceClose(device, Self.noOptions)
            isDeviceOpen = false
        }
    }
    
    public func setSimulatedAngle(_ angle: Double, direct: Bool = false) {
        simulatedAngleValue = angle
        
        let mode = AppSettings.shared.trackingMode
        // Option C (Lid Open Sweep) and Option B (Trackpad Gesture) are already mathematically smooth or event-driven.
        // Direct update eliminates EMA filter conflict, lag, and jitter completely!
        if direct || mode == .autoLidOpen || mode == .trackpadGesture {
            rawAngle = angle
            calibratedAngle = angle
            let progress = AppSettings.shared.normalizedProgress(for: angle)
            currentProgress = progress
            
            let delta = angle - previousRawAngle
            if delta < -0.1 {
                isClosing = true
            } else if delta > 0.1 {
                isClosing = false
            }
            previousRawAngle = angle
            onAngleUpdate?(angle, angle, progress, isClosing)
        } else {
            processAngleUpdate(angle)
        }
    }
    
    private func poll() {
        // Measure polling FPS
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFPSCheckTime >= 1.0 {
            pollingFPS = Double(frameCount) / (now - lastFPSCheckTime)
            frameCount = 0
            lastFPSCheckTime = now
        }
        
        // Polling timer only drives real hardware (0x8104).
        // Gestures, animations, and test sliders push updates directly with zero timer conflicts!
        guard !isSimulated && !AppSettings.shared.isTestModeActive && hidDevice != nil else {
            return
        }
        
        // Real hardware reading
        if isDeviceOpen, let device = hidDevice {
            var length = CFIndex(hidReport.count)
            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                1,
                &hidReport,
                &length
            )
            
            if result == kIOReturnSuccess, length >= 3 {
                let rawValue = UInt16(hidReport[2]) << 8 | UInt16(hidReport[1])
                let angle = Double(rawValue)
                processAngleUpdate(angle)
            }
        }
    }
    
    private func processAngleUpdate(_ currentAngle: Double) {
        let settings = AppSettings.shared
        
        // Filter angle with deadband
        let smoothedAngle = angleFilter.update(
            target: currentAngle,
            followSpeed: settings.followSpeed,
            deadband: 0.05
        )
        
        // Detect movement direction
        let delta = smoothedAngle - previousRawAngle
        let isMovingDownward = delta < -0.3
        let isMovingUpward = delta > 0.4
        
        if isMovingDownward {
            isClosing = true
            stationaryCounter = 0
        } else if isMovingUpward {
            isClosing = false
            hasPreArmedInThisMotion = false
            stationaryCounter = 0
        } else {
            stationaryCounter += 1
            if stationaryCounter > 15 { // ~250ms of stationary lid
                isClosing = false
            }
        }
        
        // Pre-arming capture: trigger capture asynchronously as angle nears start angle
        let now = CACurrentMediaTime()
        let preArmZone = settings.startAngle + 12.0
        if smoothedAngle <= preArmZone && smoothedAngle >= (settings.startAngle - 5.0) {
            if isClosing && !hasPreArmedInThisMotion && (now - lastPreArmTime > 1.5) {
                hasPreArmedInThisMotion = true
                lastPreArmTime = now
                onPreArmCapture?()
            }
        }
        
        // Normalization: progress from 0.0 (closed) to 1.0 (at or above 90°)
        let progress = settings.normalizedProgress(for: smoothedAngle)
        
        self.rawAngle = currentAngle
        self.calibratedAngle = smoothedAngle
        self.currentProgress = progress
        self.previousRawAngle = smoothedAngle
        
        onAngleUpdate?(currentAngle, smoothedAngle, progress, isClosing)
    }
}
