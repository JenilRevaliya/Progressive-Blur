import Foundation
import AppKit
import SwiftUI

public final class MenuBarController: NSObject, @unchecked Sendable {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    
    public override init() {
        super.init()
    }
    
    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle(angle: 90.0)
        rebuildMenu()
    }
    
    private var lastRoundedAngle: Int = -999
    private var lastTitleUpdateTime: CFTimeInterval = 0
    
    public func updateStatusItemTitle(angle: Double) {
        guard let button = statusItem?.button else { return }
        let now = CACurrentMediaTime()
        let rounded = Int(round(angle))
        
        // Only update status item if integer degree changed and at least 80ms elapsed
        guard rounded != lastRoundedAngle && (now - lastTitleUpdateTime > 0.08) else { return }
        lastRoundedAngle = rounded
        lastTitleUpdateTime = now
        
        let settings = AppSettings.shared
        if settings.showAngleInMenuBar {
            button.title = String(format: " ◩ %d°", rounded)
        } else {
            button.image = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: "Progressive Blur")
            button.title = ""
        }
    }
    
    public func rebuildMenu() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "iPhone Duo Progressive Blur", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        let sensor = LidSensorManager.shared
        let statusTitle = sensor.isConnected ? "Sensor: Online (0x8104)" : "Sensor: Simulated Mode"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick Tracking Mode Submenu
        let trackingSubmenu = NSMenu()
        for mode in TrackingMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(changeTrackingMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = (AppSettings.shared.trackingMode == mode) ? .on : .off
            trackingSubmenu.addItem(item)
        }
        let trackingItem = NSMenuItem(title: "Tracking Source", action: nil, keyEquivalent: "")
        trackingItem.submenu = trackingSubmenu
        menu.addItem(trackingItem)
        
        // Notch Toggle Submenu
        let notchSubmenu = NSMenu()
        for nMode in NotchDisplayMode.allCases {
            let item = NSMenuItem(title: nMode.title, action: #selector(changeNotchMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = nMode.rawValue
            item.state = (AppSettings.shared.notchDisplayMode == nMode) ? .on : .off
            notchSubmenu.addItem(item)
        }
        let notchItem = NSMenuItem(title: "Camera Notch Portrayal", action: nil, keyEquivalent: "")
        notchItem.submenu = notchSubmenu
        menu.addItem(notchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings & Interactive Preview…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let snapItem = NSMenuItem(title: "Capture Screen Now", action: #selector(captureScreen), keyEquivalent: "s")
        snapItem.target = self
        menu.addItem(snapItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Progressive Blur", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
    }
    
    @objc public func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "iPhone Duo Progressive Blur Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc public func captureScreen() {
        OverlayWindowController.shared.captureScreenAsync()
    }
    
    @objc public func changeTrackingMode(_ sender: NSMenuItem) {
        if let mode = TrackingMode(rawValue: sender.tag) {
            AppSettings.shared.trackingMode = mode
            rebuildMenu()
        }
    }
    
    @objc public func changeNotchMode(_ sender: NSMenuItem) {
        if let mode = NotchDisplayMode(rawValue: sender.tag) {
            AppSettings.shared.notchDisplayMode = mode
            rebuildMenu()
        }
    }
    
    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
