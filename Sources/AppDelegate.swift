import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Application did finish launching.")
        // Run as menu-bar utility with GUI window capability
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Setup menu bar item
        MenuBarController.shared.setupMenuBar()
        
        // Setup overlay window
        let overlay = OverlayWindowController.shared
        
        // Wire lid sensor updates directly to overlay renderer and menu bar
        LidSensorManager.shared.onAngleUpdate = { rawAngle, calibratedAngle, progress, isClosing in
            let foldTurn = AppSettings.shared.normalizedFoldTurn(for: calibratedAngle)
            overlay.update(foldTurn: foldTurn, angle: calibratedAngle)
            MenuBarController.shared.updateStatusItemTitle(angle: calibratedAngle)
        }
        
        // Wire Option A: Camera Optical Inclinometer
        OpticalHingeTracker.shared.onAngleUpdated = { angle in
            LidSensorManager.shared.setSimulatedAngle(angle)
        }
        
        // Wire Option B: Trackpad Haptic Clamshell Gesture
        TrackpadGestureTracker.shared.onAngleUpdated = { angle in
            LidSensorManager.shared.setSimulatedAngle(angle)
        }
        
        // Wire Option C: Automated Lid Open Sweep
        LidOpenAnimator.shared.onAngleUpdated = { angle in
            LidSensorManager.shared.setSimulatedAngle(angle)
        }
        
        // Start sensor polling (will auto-switch to simulated mode on M1 Air)
        LidSensorManager.shared.start()
        AppSettings.shared.checkInitialSensorState()
        AppSettings.shared.applyTrackingModeChange()
        
        // Check permissions and prefetch screen capture
        Task {
            let hasPerm = await ScreenCaptureService.shared.verifyPermissionAsync()
            await MainActor.run {
                AppSettings.shared.hasScreenCapturePermission = hasPerm
            }
        }
        
        // Open Settings window on launch so user can see diagnostics & test slider immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MenuBarController.shared.openSettings()
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        LidSensorManager.shared.stop()
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay running in menu bar
    }
}
