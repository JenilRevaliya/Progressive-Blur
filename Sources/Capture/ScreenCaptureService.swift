import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

public final class ScreenCaptureService: @unchecked Sendable {
    public static let shared = ScreenCaptureService()
    
    private init() {}
    
    /// Fast synchronous preflight check for Screen Recording permission
    public func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Asynchronous probe confirming functional capture capability without triggering unwanted system modals
    public func verifyPermissionAsync() async -> Bool {
        // Fast, silent preflight check. Returns true ONLY if macOS TCC has confirmed access.
        // Never invokes SCShareableContent when false to avoid triggering intrusive system modals!
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Prompt macOS TCC screen recording permission dialog (user explicitly requested)
    @discardableResult
    public func requestPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// Open System Settings directly to Privacy & Security -> Screen Recording
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Relaunches the application to pick up new TCC permissions granted in System Settings
    public func relaunchApp() {
        let url = Bundle.main.bundleURL
        let conf = NSWorkspace.OpenConfiguration()
        conf.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    /// Fetch screen image based on user preferences and current permissions
    public func fetchImage() async -> CGImage? {
        let settings = AppSettings.shared
        
        switch settings.imageSourceMode {
        case .liveCapture:
            // Only perform live ScreenCaptureKit capture if preflight explicitly confirms access is granted.
            // Never trigger intrusive system modals during clamshell fold or animation!
            if CGPreflightScreenCaptureAccess() {
                if let liveImg = await capturePrimaryDisplay() {
                    return liveImg
                }
            }
            // Seamless zero-permission fallback: actual macOS desktop wallpaper!
            return fetchDesktopWallpaper() ?? fetchBundledArtwork()
            
        case .desktopWallpaper:
            return fetchDesktopWallpaper() ?? fetchBundledArtwork()
            
        case .bundledArtwork:
            return fetchBundledArtwork()
            
        case .customImage:
            if !settings.customImagePath.isEmpty,
               let img = NSImage(contentsOfFile: settings.customImagePath),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
            return fetchBundledArtwork()
        }
    }
    
    /// High-resolution capture of the primary display via ScreenCaptureKit
    public func capturePrimaryDisplay() async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        
        do {
            let content: SCShareableContent
            if #available(macOS 14.4, *) {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } else {
                content = try await SCShareableContent.current
            }
            
            // Strictly select primary display (displayID 1 or matching main screen frame)
            guard let primaryDisplay = content.displays.first(where: { disp in
                if let mainScreen = NSScreen.main {
                    return Double(disp.width) == Double(mainScreen.frame.width) || disp.frame.origin.x == 0
                }
                return true
            }) ?? content.displays.first else {
                return nil
            }
            
            // Exclude our own application's windows
            let currentPID = NSRunningApplication.current.processIdentifier
            let excluded = content.windows.filter { $0.owningApplication?.processID == currentPID }
            
            let filter = SCContentFilter(display: primaryDisplay, excludingWindows: excluded)
            let config = SCStreamConfiguration()
            config.width = primaryDisplay.width
            config.height = primaryDisplay.height
            config.showsCursor = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            print("[ScreenCaptureService] SCKit error: \(error)")
            return nil
        }
    }
    
    /// Fetch current desktop wallpaper image
    public func fetchDesktopWallpaper() -> CGImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    /// Bundled dynamic fallback artwork
    public func fetchBundledArtwork() -> CGImage? {
        if let bundleUrl = Bundle.main.url(forResource: "default", withExtension: "png"),
           let img = NSImage(contentsOf: bundleUrl) {
            return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        
        // Generate a synthetic high-res gradient wallpaper in memory if no file exists
        return createSyntheticWallpaper(width: 2560, height: 1600)
    }
    
    /// Creates a crisp, beautiful Apple-inspired synthetic wallpaper in memory
    private func createSyntheticWallpaper(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        
        // Sleek macOS Sequoia / Dark Aurora gradient
        let colors = [
            CGColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1.0),
            CGColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1.0),
            CGColor(red: 0.18, green: 0.14, blue: 0.28, alpha: 1.0),
            CGColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1.0)
        ] as CFArray
        
        let locations: [CGFloat] = [0.0, 0.4, 0.75, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: width, y: 0),
                options: []
            )
        }
        
        return ctx.makeImage()
    }
}
