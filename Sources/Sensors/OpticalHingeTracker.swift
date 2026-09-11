import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import QuartzCore

public final class OpticalHingeTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let shared = OpticalHingeTracker()
    
    public var onAngleUpdated: ((Double) -> Void)?
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var hasPermission: Bool = false
    @Published public private(set) var currentEstimatedAngle: Double = 90.0
    
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.progressiveblur.opticaltracker", qos: .userInteractive)
    
    // Tracking state
    private var previousBrightness: Float = 0.5
    private var baselineBrightness: Float = 0.5
    private var integratedPitch: Double = 0.0
    private var lastFrameTime: CFTimeInterval = 0
    
    private override init() {
        super.init()
    }
    
    public func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.hasPermission = true
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.hasPermission = granted
                    completion(granted)
                }
            }
        default:
            self.hasPermission = false
            completion(false)
        }
    }
    
    public func start() {
        guard !isRunning else { return }
        
        requestPermission { [weak self] granted in
            guard granted, let self = self else { return }
            self.sessionQueue.async {
                self.setupAndStartSession()
            }
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    public func reset() {
        integratedPitch = 0.0
        currentEstimatedAngle = 90.0
        onAngleUpdated?(90.0)
    }
    
    private func setupAndStartSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .low // Lightweight, lowest CPU & GPU footprint
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        
        session.startRunning()
        self.captureSession = session
        
        DispatchQueue.main.async {
            self.isRunning = true
            self.integratedPitch = 0.0
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        
        // Fast sparse luminance sampling (top third vs bottom third)
        let topSampleCount = 64
        var topSum: Float = 0
        var botSum: Float = 0
        
        let yBytes = yPlane.assumingMemoryBound(to: UInt8.self)
        
        for i in 0..<topSampleCount {
            let x = (width / (topSampleCount + 1)) * (i + 1)
            let topY = height / 6
            let botY = (height * 5) / 6
            
            topSum += Float(yBytes[topY * bytesPerRow + x])
            botSum += Float(yBytes[botY * bytesPerRow + x])
        }
        
        let avgTop = topSum / Float(topSampleCount)
        let avgBot = botSum / Float(topSampleCount)
        let overallBrightness = (avgTop + avgBot) * 0.5 / 255.0
        
        let now = CACurrentMediaTime()
        lastFrameTime = now
        
        // When lid closes downward, the bottom of the camera view gets dark first as it faces the keyboard,
        // and overall brightness drops logarithmically as it seals against the chassis.
        let brightnessRatio = min(1.0, max(0.02, overallBrightness / max(0.01, baselineBrightness)))
        
        // Calculate estimated angle: when brightness drops, angle decreases from 90° towards 0°
        let angleFromBrightness = Double(brightnessRatio) * 90.0
        
        // Smooth and update
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let targetAngle = min(90.0, max(0.0, angleFromBrightness))
            self.currentEstimatedAngle = self.currentEstimatedAngle * 0.85 + targetAngle * 0.15
            self.onAngleUpdated?(self.currentEstimatedAngle)
        }
    }
}
