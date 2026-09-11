import SwiftUI

// Visual Graphic Resource Loader (supports PNG and SVG)
struct ResourcePNGView: View {
    let name: String
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    
    var body: some View {
        if let img = loadGraphic(name: name) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
        } else {
            EmptyView()
        }
    }
    
    private func loadGraphic(name: String) -> NSImage? {
        if let path = Bundle.main.path(forResource: name, ofType: "png"), let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: name, ofType: "svg"), let img = NSImage(contentsOfFile: path) {
            return img
        }
        let localDir = "/Users/jenilrevaliya/Desktop/Projects/Progressive Blur/Resources"
        if let img = NSImage(contentsOfFile: "\(localDir)/\(name).png") {
            return img
        }
        if let img = NSImage(contentsOfFile: "\(localDir)/\(name).svg") {
            return img
        }
        return nil
    }
}

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var sensor = LidSensorManager.shared
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("Dashboard").tag(0)
                Text("Telemetry").tag(1)
                Text("Optics & Notch").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
            
            Divider()
                .opacity(0.3)
            
            // Scrollable Tab Content
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        dashboardTabView
                    } else if selectedTab == 1 {
                        telemetryTabView
                    } else {
                        opticsTabView
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 590, height: 680)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.8), Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone Duo Progressive Blur")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Native Clamshell 3D Perspective & Hinge Defocus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Live Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(sensor.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(sensor.isConnected ? "Sensor: Online" : "Sensor: Simulated")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
        }
        .padding(20)
    }
    
    // MARK: - Tab 0: Dashboard
    private var dashboardTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Visual Clamshell Diagram Card
            VStack(alignment: .leading, spacing: 10) {
                ResourcePNGView(name: "clamshell_diagram", height: 175)
                    .cornerRadius(8)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Hinge Angle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f deg", sensor.calibratedAngle))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fold State")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%% Folded", settings.normalizedFoldTurn(for: sensor.calibratedAngle) * 100))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hinge Axis")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("100% Fixed")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top Width")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("46% Taper")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Input Mode Card
            VStack(alignment: .leading, spacing: 12) {
                Label("Tracking Source", systemImage: "slider.horizontal.below.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                
                Picker("", selection: $settings.trackingMode) {
                    ForEach(TrackingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                
                // Mode specifics
                if settings.trackingMode == .hardwareSensor {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sensor.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(sensor.isConnected ? "Reading Apple Hall Sensor (0x8104) at 60 Hz" : "Sensor Disconnected")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                } else if settings.trackingMode == .autoLidOpen {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Sweep Speed")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f s", settings.autoOpenDuration))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        Slider(value: $settings.autoOpenDuration, in: 0.2...3.0, step: 0.05)
                            .accentColor(.cyan)
                        
                        HStack(spacing: 10) {
                            Button("Test Open Sweep (0 to 90 deg)") {
                                LidOpenAnimator.shared.triggerOpenAnimation()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("Test Close Sweep (90 to 0 deg)") {
                                LidOpenAnimator.shared.triggerCloseAnimation()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else if settings.trackingMode == .trackpadGesture {
                    HStack {
                        Text("Trackpad Sensitivity")
                            .font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.2fx", settings.trackpadSensitivity))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    Slider(value: $settings.trackpadSensitivity, in: 0.1...1.5, step: 0.05)
                        .accentColor(.cyan)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Interactive Slider & Preset Buttons
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Interactive Simulator", systemImage: "hand.draw")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("Manual Override", isOn: $settings.isTestModeActive)
                        .toggleStyle(.switch)
                        .font(.system(size: 11))
                }
                
                HStack {
                    Text("0 deg")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Slider(value: $settings.testAngle, in: 0.0...120.0, step: 0.5)
                        .accentColor(.cyan)
                        .disabled(!settings.isTestModeActive && sensor.isConnected)
                    Text("120 deg")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    quickAngleButton("0 deg Closed", angle: 0.0)
                    quickAngleButton("30 deg Fold", angle: 30.0)
                    quickAngleButton("60 deg Mid", angle: 60.0)
                    quickAngleButton("85 deg Fold", angle: 85.0)
                    quickAngleButton("90 deg Open", angle: 90.0)
                    
                    Button("ESC Exit") {
                        OverlayWindowController.shared.exitAnimation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.orange)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Texture Source Card
            VStack(alignment: .leading, spacing: 10) {
                Label("Display Texture", systemImage: "photo")
                    .font(.system(size: 13, weight: .semibold))
                
                Picker("", selection: $settings.imageSourceMode) {
                    ForEach(ImageSourceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                
                HStack(spacing: 10) {
                    Button("Snap Screen") {
                        OverlayWindowController.shared.captureScreenAsync()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if !settings.hasScreenCapturePermission {
                        Button("Open Privacy Settings") {
                            ScreenCaptureService.shared.requestPermission()
                            ScreenCaptureService.shared.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Relaunch App") {
                            ScreenCaptureService.shared.relaunchApp()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Text("Screen Capture: Authorized")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private func quickAngleButton(_ title: String, angle: Double) -> some View {
        Button(title) {
            settings.isTestModeActive = true
            settings.testAngle = angle
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    // MARK: - Tab 1: Telemetry
    private var telemetryTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ResourcePNGView(name: "hardware_sensor_icon", width: 70, height: 70)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Hall-Effect Sensor")
                        .font(.system(size: 14, weight: .bold))
                    Text("Device ID: 0x8104 | Usage Page: 0x0020 | Usage: 0x008A")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(sensor.isConnected ? "Hardware Connection: Verified" : "Simulated Fallback Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(sensor.isConnected ? .green : .orange)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Grid Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricBox("Mac Model", HardwareCompat.current.modelIdentifier)
                metricBox("Sensor Status", sensor.isConnected ? "Online (0x8104)" : "Simulated")
                metricBox("Raw Hinge Angle", String(format: "%.1f deg", sensor.rawAngle))
                metricBox("Calibrated Angle", String(format: "%.1f deg", sensor.calibratedAngle))
                metricBox("Fold Turn Ratio", String(format: "%.3f", settings.normalizedFoldTurn(for: sensor.calibratedAngle)))
                metricBox("Motion Direction", sensor.isClosing ? "Closing Down" : "Opening / Still")
                metricBox("Polling Rate", String(format: "%.0f Hz", sensor.pollingFPS))
                metricBox("Render Rate", String(format: "%.0f FPS", OverlayWindowController.shared.renderedFPS))
                metricBox("GPU Frame Time", String(format: "%.2f ms", OverlayWindowController.shared.lastFrameTimeMs))
                metricBox("Display Notch", settings.shouldPortrayNotch ? "Active Cutout" : "Flat Top")
            }
            
            // Hardware Compatibility Details
            VStack(alignment: .leading, spacing: 6) {
                Text("Hardware Profile")
                    .font(.system(size: 12, weight: .semibold))
                Text(HardwareCompat.current.supportStatus.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private func metricBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
    
    // MARK: - Tab 2: Optics & Notch
    private var opticsTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Notch Section
            HStack(spacing: 14) {
                ResourcePNGView(name: "notch_display_icon", width: 65, height: 65)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Liquid Retina Notch Geometry")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Picker("Notch Mode", selection: $settings.notchDisplayMode) {
                        ForEach(NotchDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Blur & Shaders
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ResourcePNGView(name: "optical_blur_icon", width: 55, height: 55)
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Optics & Defocus Parameters")
                            .font(.system(size: 13, weight: .semibold))
                        Text("16-sample Fermat golden spiral bokeh blur")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                sliderRow("Blur Multiplier", value: $settings.blurStrength, range: 0.1...3.0, format: "%.2fx")
                sliderRow("Perspective Depth", value: $settings.perspectiveStrength, range: 0.2...2.0, format: "%.2fx")
                sliderRow("Dark Void Horizon", value: $settings.darkVoidIntensity, range: 0.2...2.0, format: "%.2fx")
                sliderRow("Rim Specular Highlight", value: $settings.reflectionIntensity, range: 0.0...1.0, format: "%.2f")
                sliderRow("Filter Responsiveness", value: $settings.followSpeed, range: 5.0...50.0, format: "%.0f")
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            // Lock Screen Safety Notice
            VStack(alignment: .leading, spacing: 6) {
                Label("Lock Screen & Login Pass-Through", systemImage: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                Text("Non-activating overlay panel with zero keyboard or mouse capture. The macOS password field receives 100% uninterrupted input focus when the lid opens.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            Slider(value: value, in: range)
                .accentColor(.cyan)
        }
    }
}

// Frosted glass background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
