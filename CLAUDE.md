# Swift Development Guidelines for PostureKeeper

## Project Overview

PostureKeeper is a real-time Swift CLI application that uses Vision framework and AVFoundation to detect posture problems in software engineers. This document provides comprehensive development guidelines for AI agents and developers working on the project.

## Development Environment

### Core Technologies
- **Swift**: 5.7+ with concurrency support
- **Platform**: macOS 13.0+ (Ventura or later)
- **Frameworks**: Vision, AVFoundation, Core Image, Combine
- **CLI**: Swift ArgumentParser
- **Build System**: Swift Package Manager
- **Testing**: XCTest with performance testing
- **Documentation**: DocC for API documentation

### Required Tools
- Xcode 14.0+ (for development and debugging)
- Swift Package Manager (integrated with Xcode)
- Git for version control
- Physical or virtual camera for testing

### System Requirements
- Apple Silicon Mac (M1/M2) recommended for optimal performance
- Built-in or external HD camera (1080p minimum)
- 8GB RAM minimum, 16GB recommended
- 2GB free disk space for development

## Project Structure

```
PostureKeeper/
├── Package.swift                           # Swift Package configuration
├── README.md                              # Project documentation
├── CLAUDE.md                              # This file - development guidelines
├── LICENSE                                # MIT license
├── Sources/
│   └── PostureKeeper/
│       ├── CLI/
│       │   ├── PostureKeeperCommand.swift    # @main entry point
│       │   ├── ConfigCommand.swift           # Configuration subcommands
│       │   ├── CalibrationCommand.swift      # Camera calibration CLI
│       │   ├── MonitorCommand.swift          # Real-time monitoring
│       │   ├── ReportCommand.swift           # Analytics and reporting
│       │   └── ExportCommand.swift           # Data export functionality
│       ├── Detection/
│       │   ├── PostureDetector.swift         # Core detection coordinator
│       │   ├── AngleCalculator.swift         # Geometric angle calculations
│       │   ├── PostureClassifier.swift       # Problem classification logic
│       │   ├── VisionPoseProcessor.swift     # Vision framework wrapper
│       │   └── PostureThresholds.swift       # Clinical threshold definitions
│       ├── Camera/
│       │   ├── CameraManager.swift           # AVFoundation session management
│       │   ├── CameraCalibrator.swift        # Positioning and setup
│       │   ├── FrameProcessor.swift          # Real-time frame processing
│       │   └── CameraPermissions.swift       # Privacy and permissions
│       ├── Analytics/
│       │   ├── PostureLogger.swift           # Data persistence and storage
│       │   ├── MetricsCalculator.swift       # Statistical analysis
│       │   ├── ReportGenerator.swift         # Health report generation
│       │   └── HealthKitIntegration.swift    # Apple Health sync
│       ├── Alerts/
│       │   ├── AlertManager.swift            # Notification coordination
│       │   ├── VoiceAlerts.swift             # Text-to-speech alerts
│       │   ├── VisualIndicators.swift        # On-screen feedback
│       │   └── NotificationCenter.swift      # System notifications
│       └── Models/
│           ├── PostureProblem.swift          # Problem type definitions
│           ├── PostureMetrics.swift          # Measurement data structures
│           ├── DetectionConfig.swift         # Configuration model
│           ├── CameraSettings.swift          # Camera configuration
│           └── UserProfile.swift             # User preferences and data
├── Tests/
│   ├── PostureKeeperTests/
│   │   ├── Unit/
│   │   │   ├── AngleCalculatorTests.swift    # Geometric calculation tests
│   │   │   ├── PostureClassifierTests.swift  # Classification logic tests
│   │   │   ├── MetricsCalculatorTests.swift  # Analytics tests
│   │   │   └── ModelTests.swift              # Data model tests
│   │   ├── Integration/
│   │   │   ├── DetectionPipelineTests.swift  # End-to-end detection
│   │   │   ├── CameraIntegrationTests.swift  # Camera functionality
│   │   │   └── CLIIntegrationTests.swift     # Command-line interface
│   │   └── Performance/
│   │       ├── RealTimePerformanceTests.swift # FPS and latency tests
│   │       ├── MemoryUsageTests.swift        # Memory profiling
│   │       └── BatteryImpactTests.swift      # Power consumption
└── Resources/
    ├── Calibration/
    │   ├── CalibrationGuide.md               # Setup instructions
    │   └── TestImages/                       # Reference posture images
    ├── Documentation/
    │   ├── ClinicalReferences.md             # Research citations
    │   ├── VisionFrameworkGuide.md           # Technical implementation
    │   └── DeploymentGuide.md                # Distribution instructions
    └── Configuration/
        ├── DefaultConfig.json                # Default settings
        └── TestConfig.json                   # Test configuration
```

## Swift Coding Standards

### Code Style and Conventions
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint for consistent formatting
- Maximum line length: 120 characters
- Use descriptive variable and function names
- Prefer explicit types for clarity in vision/camera code

### Naming Conventions
```swift
// Classes: PascalCase with descriptive names
class PostureDetector { }
class VisionPoseProcessor { }

// Functions: camelCase with action verbs
func calculateCraniovertebralAngle() -> Double
func processVideoFrame(_ frame: CVPixelBuffer) async

// Constants: camelCase with descriptive names
let defaultForwardHeadThreshold: Double = 50.0
let minimumDetectionConfidence: Float = 0.8

// Enums: PascalCase for types, camelCase for cases
enum PostureProblem {
    case forwardHeadPosture
    case roundedShoulders
    case textNeckSyndrome
}
```

### Documentation Requirements
```swift
/// Detects forward head posture using craniovertebral angle calculation.
/// 
/// The craniovertebral angle (CVA) is measured between a horizontal line through
/// the C7 vertebra and a line extending to the ear tragus. Clinical research
/// establishes normal CVA > 53°, with values < 50° indicating forward head posture.
///
/// - Parameter landmarks: Vision framework pose landmarks from current frame
/// - Returns: Tuple containing angle measurement and detection confidence
/// - Throws: `PostureDetectionError` if insufficient landmarks detected
func detectForwardHeadPosture(
    from landmarks: VNHumanBodyPoseObservation
) async throws -> (angle: Double, confidence: Float)
```

## Architecture Patterns

### Core Design Principles
1. **Single Responsibility**: Each class handles one aspect of posture detection
2. **Dependency Injection**: Use protocols for testability and modularity
3. **Async/Await**: Leverage Swift concurrency for real-time processing
4. **Combine Integration**: Reactive data flow for UI updates and alerts
5. **Error Handling**: Comprehensive error types and recovery strategies

### Protocol-Oriented Design
```swift
// Core detection protocol
protocol PostureDetecting {
    func detectPostureProblems(from landmarks: VNHumanBodyPoseObservation) async throws -> [PostureProblem]
}

// Camera management protocol
protocol CameraManaging {
    var isRunning: Bool { get }
    func startCapture() async throws
    func stopCapture()
    func configureCamera(with settings: CameraSettings) throws
}

// Alert system protocol
protocol AlertProviding {
    func presentAlert(for problem: PostureProblem, severity: AlertSeverity) async
    func configureAlerts(with preferences: AlertPreferences)
}
```

### Async/Await Implementation
```swift
class PostureDetector: PostureDetecting {
    private let visionProcessor: VisionPoseProcessor
    private let angleCalculator: AngleCalculator
    
    func detectPostureProblems(
        from landmarks: VNHumanBodyPoseObservation
    ) async throws -> [PostureProblem] {
        // Parallel processing of different posture checks
        async let fhpCheck = checkForwardHeadPosture(landmarks)
        async let shoulderCheck = checkRoundedShoulders(landmarks)
        async let neckCheck = checkTextNeck(landmarks)
        
        let results = try await [fhpCheck, shoulderCheck, neckCheck]
        return results.compactMap { $0 }
    }
}
```

## Vision Framework Integration

### Pose Detection Setup
```swift
class VisionPoseProcessor {
    private let poseRequest: VNDetectHumanBodyPoseRequest
    
    init() {
        poseRequest = VNDetectHumanBodyPoseRequest()
        poseRequest.revision = VNDetectHumanBodyPoseRequestRevision1
        
        // Configure for real-time performance
        poseRequest.preferBackgroundProcessing = false
        poseRequest.usesCPUOnly = false // Leverage Neural Engine when available
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer) async throws -> VNHumanBodyPoseObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            poseRequest.completionHandler = { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let observation = request.results?.first as? VNHumanBodyPoseObservation
                continuation.resume(returning: observation)
            }
            
            try handler.perform([poseRequest])
        }
    }
}
```

### Landmark Processing
```swift
extension VNHumanBodyPoseObservation {
    /// Extract specific joint positions for posture analysis
    func extractPostureKeypoints() throws -> PostureKeypoints {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .head, .neck, .rightShoulder, .leftShoulder,
            .rightEar, .leftEar, .nose
        ]
        
        var keypoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint] = [:]
        
        for joint in jointNames {
            guard let point = try? recognizedPoint(joint),
                  point.confidence > 0.5 else {
                throw PostureDetectionError.insufficientLandmarks(joint)
            }
            keypoints[joint] = point
        }
        
        return PostureKeypoints(landmarks: keypoints)
    }
}
```

## AVFoundation Camera Management

### Camera Session Setup
```swift
class CameraManager: NSObject, CameraManaging {
    private let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    @Published var isRunning: Bool = false
    
    func startCapture() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureCaptureSession()
                    self.captureSession.startRunning()
                    
                    DispatchQueue.main.async {
                        self.isRunning = true
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func configureCaptureSession() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, 
                                                   for: .video, 
                                                   position: .front) else {
            throw CameraError.deviceNotFound
        }
        
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw CameraError.inputConfigurationFailed
        }
        captureSession.addInput(input)
        
        // Configure for 30 FPS capture
        try camera.lockForConfiguration()
        camera.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
        camera.unlockForConfiguration()
        
        setupVideoOutput()
    }
}
```

### Real-time Frame Processing
```swift
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task {
            do {
                let landmarks = try await visionProcessor.processFrame(pixelBuffer)
                await handlePostureDetection(landmarks)
            } catch {
                logger.error("Frame processing failed: \\(error)")
            }
        }
    }
}
```

## Performance Requirements

### Real-time Processing Targets
- **Frame Rate**: Maintain 30 FPS processing
- **Latency**: < 33ms per frame analysis
- **Memory Usage**: < 100MB during active monitoring
- **CPU Usage**: < 15% on Apple Silicon Macs
- **Battery Impact**: Minimal background processing

### Performance Monitoring
```swift
class PerformanceMonitor {
    private var frameProcessingTimes: [CFTimeInterval] = []
    private let maxSamples = 100
    
    func measureFrameProcessing<T>(_ operation: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        recordProcessingTime(processingTime)
        return result
    }
    
    private func recordProcessingTime(_ time: CFTimeInterval) {
        frameProcessingTimes.append(time)
        if frameProcessingTimes.count > maxSamples {
            frameProcessingTimes.removeFirst()
        }
        
        // Alert if performance degrades
        let averageTime = frameProcessingTimes.reduce(0, +) / Double(frameProcessingTimes.count)
        if averageTime > 0.033 { // > 33ms (30 FPS threshold)
            logger.warning("Performance degradation detected: \\(averageTime * 1000)ms average")
        }
    }
}
```

## Testing Strategy

### Unit Testing Requirements
- **Coverage Target**: 90%+ code coverage
- **Test Categories**: Logic, calculations, data models
- **Mock Objects**: Camera, Vision framework responses
- **Performance Tests**: Frame processing timing

### Example Test Structure
```swift
class AngleCalculatorTests: XCTestCase {
    var calculator: AngleCalculator!
    
    override func setUp() {
        super.setUp()
        calculator = AngleCalculator()
    }
    
    func testCraniovertebralAngleCalculation() {
        // Given: Known landmark positions
        let earPoint = CGPoint(x: 0.5, y: 0.3)
        let c7Point = CGPoint(x: 0.5, y: 0.5)
        
        // When: Calculate CVA
        let angle = calculator.calculateCVA(ear: earPoint, c7: c7Point)
        
        // Then: Verify expected angle (90 degrees for vertical alignment)
        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }
    
    func testForwardHeadPostureDetection() {
        // Given: Forward head position (CVA < 50°)
        let earPoint = CGPoint(x: 0.6, y: 0.3) // Forward position
        let c7Point = CGPoint(x: 0.5, y: 0.5)
        
        // When: Calculate and classify
        let angle = calculator.calculateCVA(ear: earPoint, c7: c7Point)
        let isForwardHead = angle < PostureThresholds.forwardHeadThreshold
        
        // Then: Should detect forward head posture
        XCTAssertTrue(isForwardHead)
        XCTAssertLessThan(angle, 50.0)
    }
}
```

### Performance Testing
```swift
class RealTimePerformanceTests: XCTestCase {
    func testFrameProcessingSpeed() {
        measure {
            // Simulate 30 FPS for 1 second
            for _ in 0..<30 {
                let mockPixelBuffer = createMockPixelBuffer()
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Process frame synchronously for testing
                let landmarks = try! visionProcessor.processFrameSync(mockPixelBuffer)
                
                let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                XCTAssertLessThan(processingTime, 0.033) // Must complete within 33ms
            }
        }
    }
}
```

## CLI Development Guidelines

### Command Structure
```swift
import ArgumentParser

@main
struct PostureKeeperCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PostureKeeper",
        abstract: "Real-time posture monitoring for software engineers",
        subcommands: [
            MonitorCommand.self,
            CalibrationCommand.self,
            ConfigCommand.self,
            ReportCommand.self,
            ExportCommand.self
        ]
    )
}

struct MonitorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monitor",
        abstract: "Start real-time posture monitoring"
    )
    
    @Option(help: "Forward head posture threshold in degrees")
    var fhpThreshold: Double = 50.0
    
    @Option(help: "Alert interval in seconds")
    var alertInterval: Int = 30
    
    @Flag(help: "Run in background mode")
    var background: Bool = false
    
    func run() async throws {
        let detector = PostureDetector(
            fhpThreshold: fhpThreshold,
            alertInterval: alertInterval
        )
        
        try await detector.startMonitoring()
    }
}
```

## Development Workflow

### Daily Development Process
1. **Start**: Pull latest changes and run tests
2. **Development**: Implement features with TDD approach
3. **Testing**: Verify real-time performance requirements
4. **Integration**: Test with actual camera hardware
5. **Documentation**: Update DocC comments for public APIs
6. **Commit**: Atomic commits with descriptive messages

### Build and Test Commands
```bash
# Build project
swift build

# Run all tests
swift test

# Run specific test suite
swift test --filter PostureDetectorTests

# Performance testing
swift test --filter PerformanceTests

# Generate documentation
swift package generate-documentation

# Run CLI for testing
swift run PostureKeeper monitor --fhp-threshold 45
```

### Deployment Process
```bash
# Build release binary
swift build -c release

# Create distributable package
swift package archive

# Install system-wide
cp .build/release/PostureKeeper /usr/local/bin/

# Verify installation
PostureKeeper --help
```

## Error Handling and Logging

### Error Types
```swift
enum PostureDetectionError: LocalizedError {
    case cameraNotAvailable
    case insufficientLandmarks(VNHumanBodyPoseObservation.JointName)
    case processingFailed(underlying: Error)
    case calibrationRequired
    
    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera access is required for posture detection"
        case .insufficientLandmarks(let joint):
            return "Cannot detect \\(joint) landmark for accurate analysis"
        case .processingFailed(let error):
            return "Processing failed: \\(error.localizedDescription)"
        case .calibrationRequired:
            return "Camera calibration required. Run 'PostureKeeper calibrate'"
        }
    }
}
```

### Logging Strategy
```swift
import OSLog

extension Logger {
    static let detection = Logger(subsystem: "com.posturekeeper", category: "detection")
    static let camera = Logger(subsystem: "com.posturekeeper", category: "camera")
    static let performance = Logger(subsystem: "com.posturekeeper", category: "performance")
}

// Usage
Logger.detection.info("Starting posture monitoring session")
Logger.camera.error("Camera configuration failed: \\(error)")
Logger.performance.debug("Frame processed in \\(processingTime)ms")
```

## Security and Privacy

### Camera Permissions
```swift
func requestCameraPermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .video) { granted in
            continuation.resume(returning: granted)
        }
    }
}
```

### Data Privacy
- No video data stored permanently
- Only posture metrics logged locally
- HealthKit integration requires explicit user consent
- Optional cloud sync with end-to-end encryption

## Clinical Algorithm Implementation

### Validated Thresholds
```swift
struct PostureThresholds {
    // Clinical research-validated thresholds
    static let forwardHeadThreshold: Double = 50.0      // CVA < 50° indicates FHP
    static let severeForwardHeadThreshold: Double = 45.0 // Severe FHP
    static let shoulderProtractionThreshold: Double = 6.35 // 2.5 inches in cm
    static let cervicalFlexionThreshold: Double = 15.0   // Text neck threshold
    static let lateralTiltThreshold: Double = 5.0        // Head tilt limit
    static let shoulderAsymmetryThreshold: Double = 1.0   // 1cm difference
    
    // Temporal thresholds
    static let sustainedPostureThreshold: TimeInterval = 30.0 // 30 seconds
    static let alertCooldownPeriod: TimeInterval = 60.0       // 1 minute between alerts
}
```

This comprehensive development guide ensures consistent, high-quality implementation of the PostureKeeper Swift CLI application with clinical-grade accuracy and real-time performance.