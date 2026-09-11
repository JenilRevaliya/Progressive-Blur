import Foundation
import AppKit
import QuartzCore
import IOKit.pwr_mgt

public final class NonActivatingOverlayPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
    public override var acceptsFirstResponder: Bool { false }
}

public final class OverlayWindowController: NSObject, @unchecked Sendable {
    public static let shared = OverlayWindowController()
    
    private var window: NonActivatingOverlayPanel?
    private var metalView: MetalFoldView?
    private var isCapturing: Bool = false
    private var wasZeroTurn: Bool = true
    
    public override init() {
        super.init()
        setupWindow()
        setupNotifications()
        setupPreArming()
    }
    
    private var assertionID: IOPMAssertionID = 0
    
    private func setupNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSleep()
        }
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSleep()
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWake()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowFrame()
        }
        
        // Lock screen notifications
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenLocked()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenUnlocked()
        }
    }
    
    private func setupPreArming() {
        LidSensorManager.shared.onPreArmCapture = { [weak self] in
            self?.captureScreenAsync()
        }
    }
    
    private func handleSleep() {
        metalView?.isPaused = true
        window?.alphaValue = 0.0
        releaseDisplayAssertion()
    }
    
    private func handleWake() {
        // Trigger opening sweep or ensure hardware sensor updates are active
        if AppSettings.shared.trackingMode == .autoLidOpen {
            LidOpenAnimator.shared.triggerOpenAnimation()
        }
    }
    
    private func handleScreenLocked() {
        // Pre-arm wallpaper for lock screen
        captureScreenAsync()
        acquireDisplayAssertion()
    }
    
    private func handleScreenUnlocked() {
        releaseDisplayAssertion()
        if AppSettings.shared.trackingMode == .autoLidOpen {
            LidOpenAnimator.shared.triggerOpenAnimation()
        }
    }
    
    public func acquireDisplayAssertion() {
        guard assertionID == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Progressive Blur Lock Screen Display" as CFString,
            &assertionID
        )
    }
    
    public func releaseDisplayAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
    
    private func updateWindowFrame() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let win = window else { return }
        win.setFrame(screen.frame, display: true)
        metalView?.frame = win.contentView?.bounds ?? screen.frame
    }
    
    public func setupWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        let win = NonActivatingOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isFloatingPanel = true
        win.hidesOnDeactivate = false
        
        // Critical: Elevate above macOS lock screen shield window level
        let shieldLevel = Int(CGShieldingWindowLevel()) + 1
        win.level = NSWindow.Level(rawValue: shieldLevel)
        
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.alphaValue = 0.0
        
        let mtkView = MetalFoldView(frame: win.contentView?.bounds ?? screen.frame)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.isPaused = true
        win.contentView = mtkView
        
        self.window = win
        self.metalView = mtkView
        
        setupEscapeKeyMonitors()
        
        // Background initial image load
        Task {
            if let img = await ScreenCaptureService.shared.fetchImage() {
                await MainActor.run {
                    self.metalView?.updateImage(img)
                    AppSettings.shared.lastCaptureDate = Date()
                }
            }
        }
    }
    
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    
    private func setupEscapeKeyMonitors() {
        // Local key monitor (catches Escape when app or settings window is focused)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 = Escape key
                self?.exitAnimation()
                return nil
            }
            return event
        }
        
        // Global key monitor (catches Escape system-wide)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.exitAnimation()
                }
            }
        }
    }
    
    /// Instantly aborts any active animation or fold simulation and restores normal desktop display at 90°
    public func exitAnimation() {
        // 1. Stop Option C automated lid animator
        LidOpenAnimator.shared.stop()
        
        // 2. Reset Option B trackpad gesture tracker
        TrackpadGestureTracker.shared.reset()
        
        // 3. Reset Option A camera optical tracker
        OpticalHingeTracker.shared.reset()
        
        // 4. Reset manual preview slider / test mode
        AppSettings.shared.isTestModeActive = false
        AppSettings.shared.testAngle = 90.0
        
        // 5. Reset sensor angle to fully open 90.0°
        LidSensorManager.shared.setSimulatedAngle(90.0)
        
        // 6. Instantly dismiss overlay window and pause Metal rendering
        metalView?.currentTurn = 0.0
        metalView?.isPaused = true
        window?.alphaValue = 0.0
        wasZeroTurn = true
        releaseDisplayAssertion()
        
        print("[OverlayWindowController] ESC: Successfully exited animation and restored macOS desktop.")
    }
    
    /// Updates overlay animation state from normalized turn ($0.0$ = open, $1.0$ = closed) and lid angle
    public func update(foldTurn: Double, angle: Double) {
        guard let win = self.window, let mv = self.metalView else { return }
        
        mv.currentTurn = Float(foldTurn)
        
        // Critical 90° Rule & Butter-Smooth Crossfade:
        // foldTurn > 0.0001 only occurs when angle < 90.0°
        if foldTurn > 0.0001 {
            if wasZeroTurn {
                wasZeroTurn = false
                win.orderFrontRegardless()
                // Trigger screen snapshot in background if needed
                if AppSettings.shared.imageSourceMode == .liveCapture && !isCapturing {
                    captureScreenAsync()
                }
            }
            mv.isPaused = false
            
            // Continuous, buttery-smooth crossfade between native screen and 3D overlay:
            // 90.0° -> 0.0 alpha (native screen 100% visible)
            // 88.0° -> 1.0 alpha (3D folding overlay 100% visible)
            // Smoothly interpolates across 2.0° to eliminate any pop or lag
            let startDeg = AppSettings.shared.startAngle
            let crossfadeDegrees = 2.0
            let transitionAlpha = min(1.0, max(0.0, (startDeg - angle) / crossfadeDegrees))
            win.alphaValue = CGFloat(transitionAlpha)
        } else {
            // >= 90°: fully open, completely transparent, paused rendering
            if !wasZeroTurn {
                wasZeroTurn = true
                win.alphaValue = 0.0
                mv.isPaused = true
            }
        }
    }
    
    public func captureScreenAsync() {
        guard !isCapturing else { return }
        isCapturing = true
        
        Task {
            if let image = await ScreenCaptureService.shared.fetchImage() {
                await MainActor.run {
                    self.metalView?.updateImage(image)
                    self.isCapturing = false
                    AppSettings.shared.lastCaptureDate = Date()
                }
            } else {
                await MainActor.run {
                    self.isCapturing = false
                }
            }
        }
    }
    
    public var renderedFPS: Double {
        metalView?.renderedFPS ?? 0.0
    }
    
    public var lastFrameTimeMs: Double {
        metalView?.lastFrameTimeMs ?? 0.0
    }
}
