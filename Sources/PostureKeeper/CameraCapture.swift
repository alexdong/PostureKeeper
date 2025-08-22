@preconcurrency import AVFoundation
import Foundation
import Logging
import VideoToolbox
import UniformTypeIdentifiers

class CameraCapture: NSObject {
    private let logger = Logger(label: "CameraCapture")
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    
    private let outputQueue = DispatchQueue(label: "camera.output.queue")
    private var frameTimer: Timer?
    private var latestPixelBuffer: CVPixelBuffer?
    
    var frameHandler: ((CVPixelBuffer) -> Void)?
    var debugMode: Bool = false
    
    override init() {
        super.init()
        logger.info("CameraCapture initialized")
    }
    
    func setupSession() async throws {
        logger.info("Setting up camera session")
        
        // Check camera permissions first
        try await requestCameraPermission()
        
        captureSession = AVCaptureSession()
        guard let session = captureSession else {
            logger.error("Failed to create AVCaptureSession")
            throw CameraError.sessionCreationFailed
        }
        
        session.beginConfiguration()
        
        // Discover and configure camera device
        try setupCameraDevice(session: session)
        
        // Configure video output
        try setupVideoOutput(session: session)
        
        // Set session preset for good quality but reasonable performance
        session.sessionPreset = .medium
        
        session.commitConfiguration()
        logger.info("Camera session setup completed")
    }
    
    private func requestCameraPermission() async throws {
        logger.info("Checking camera permissions")
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            logger.info("Camera permission already granted")
            return
            
        case .notDetermined:
            logger.info("Requesting camera permission from user")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                logger.info("Camera permission granted by user")
            } else {
                logger.error("Camera permission denied by user")
                throw CameraError.permissionDenied
            }
            
        case .denied, .restricted:
            logger.error("Camera permission denied or restricted")
            print("Camera access is required for PostureKeeper to work.")
            print("Please grant camera permission in System Preferences > Security & Privacy > Camera")
            throw CameraError.permissionDenied
            
        @unknown default:
            logger.error("Unknown camera permission status")
            throw CameraError.permissionDenied
        }
    }
    
    private func setupCameraDevice(session: AVCaptureSession) throws {
        logger.info("Discovering camera devices")
        
        // Get first available camera device
        guard let device = discoverFirstAvailableCamera() else {
            logger.error("No camera devices found")
            throw CameraError.deviceNotFound
        }
        
        currentDevice = device
        logger.info("Selected camera device", metadata: [
            "device_name": "\(device.localizedName)",
            "device_id": "\(device.uniqueID)"
        ])
        
        // Create input from device
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("Failed to create camera input")
            throw CameraError.inputCreationFailed
        }
        
        // Add input to session
        if session.canAddInput(input) {
            session.addInput(input)
            logger.info("Camera input added to session")
        } else {
            logger.error("Cannot add camera input to session")
            throw CameraError.inputCreationFailed
        }
    }
    
    private func discoverFirstAvailableCamera() -> AVCaptureDevice? {
        // Try to get built-in cameras first
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        logger.info("Found \(devices.count) camera device(s)")
        
        for (index, device) in devices.enumerated() {
            logger.info("Camera \(index)", metadata: [
                "name": "\(device.localizedName)",
                "id": "\(device.uniqueID)",
                "position": "\(device.position.rawValue)"
            ])
        }
        
        // Return first available device
        return devices.first
    }
    
    private func setupVideoOutput(session: AVCaptureSession) throws {
        logger.info("Setting up video output")
        
        videoOutput = AVCaptureVideoDataOutput()
        guard let output = videoOutput else {
            logger.error("Failed to create video output")
            throw CameraError.outputConfigurationFailed
        }
        
        // Configure output for CVPixelBuffer
        output.setSampleBufferDelegate(self, queue: outputQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Add output to session
        if session.canAddOutput(output) {
            session.addOutput(output)
            logger.info("Video output added to session")
        } else {
            logger.error("Cannot add video output to session")
            throw CameraError.outputConfigurationFailed
        }
    }
    
    func startSession() {
        guard let session = captureSession else {
            logger.error("Cannot start session - not configured")
            return
        }
        
        outputQueue.async {
            self.logger.info("Starting camera session")
            session.startRunning()
            self.logger.info("Camera session started")
        }
        
        // Start 1 FPS timer
        startFrameTimer()
    }
    
    func stopSession() {
        guard let session = captureSession else { return }
        
        // Stop frame timer
        stopFrameTimer()
        
        outputQueue.async {
            self.logger.info("Stopping camera session")
            session.stopRunning()
            self.logger.info("Camera session stopped")
        }
    }
    
    private func startFrameTimer() {
        logger.info("Starting 1 FPS frame timer")
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processLatestFrame()
        }
    }
    
    private func stopFrameTimer() {
        logger.info("Stopping frame timer")
        frameTimer?.invalidate()
        frameTimer = nil
    }
    
    private func processLatestFrame() {
        guard let pixelBuffer = latestPixelBuffer else {
            logger.debug("No frame available for processing")
            return
        }
        
        logger.debug("Processing frame at 1 FPS")
        
        // Save frame to disk if in debug mode
        if debugMode {
            saveFrameToDebugOutput(pixelBuffer)
        }
        
        frameHandler?(pixelBuffer)
    }
    
    private func saveFrameToDebugOutput(_ pixelBuffer: CVPixelBuffer) {
        let outputDir = URL(fileURLWithPath: ".output")
        
        // Create output directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create output directory", metadata: ["error": "\(error)"])
            return
        }
        
        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd_HHmmss_SSS"
        let timestamp = formatter.string(from: Date())
        let filename = "frame_\(timestamp).jpg"
        let fileURL = outputDir.appendingPathComponent(filename)
        
        // Convert CVPixelBuffer to CGImage
        guard let cgImage = createCGImage(from: pixelBuffer) else {
            logger.error("Failed to convert pixel buffer to CGImage")
            return
        }
        
        // Save as JPEG
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            logger.error("Failed to create image destination")
            return
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        if CGImageDestinationFinalize(destination) {
            logger.debug("Saved debug frame", metadata: ["file": "\(filename)"])
        } else {
            logger.error("Failed to save debug frame", metadata: ["file": "\(filename)"])
        }
    }
    
    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.debug("Failed to get pixel buffer from sample")
            return
        }
        
        // Store latest frame for 1 FPS processing
        latestPixelBuffer = pixelBuffer
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        logger.debug("Dropped camera frame")
    }
}

enum CameraError: Error, LocalizedError {
    case sessionCreationFailed
    case deviceNotFound
    case inputCreationFailed
    case outputConfigurationFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create camera session"
        case .deviceNotFound:
            return "No camera device found"
        case .inputCreationFailed:
            return "Failed to create camera input"
        case .outputConfigurationFailed:
            return "Failed to configure camera output"
        case .permissionDenied:
            return "Camera permission denied"
        }
    }
}