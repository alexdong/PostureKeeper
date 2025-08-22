import ArgumentParser
import Foundation
import Logging

struct PostureKeeper: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PostureKeeper",
        abstract: "Real-time posture monitoring for software engineers using computer vision"
    )
    
    @Flag(name: .long, help: "Enable debug mode with frame saving and annotation output")
    var debug = false
    
    @Option(name: .long, help: "Analyze single image file or 'latest' from .output/")
    var analyze: String?
    
    @Flag(name: .long, help: "Evaluate FHP detection on datasets/FHP/ with 3 approaches")
    var eval = false
    
    func run() throws {
        let logger = setupLogging()
        
        // Determine operation mode
        if let imagePath = analyze {
            logger.info("PostureKeeper starting in analysis mode", metadata: ["image": "\(imagePath)"])
            try runAnalysis(imagePath: imagePath, logger: logger)
            return
        }
        
        if eval {
            logger.info("PostureKeeper starting in evaluation mode")
            try runEvaluation(logger: logger)
            return
        }
        
        // Default: Camera capture mode
        logger.info("PostureKeeper starting in camera mode", metadata: ["debug_mode": "\(debug)"])
        try runCameraCapture(logger: logger)
    }
    
    private func runAnalysis(imagePath: String, logger: Logger) throws {
        print("🔍 Starting single image analysis...")
        logger.info("Single image analysis starting", metadata: ["image_path": "\(imagePath)"])
        
        let analyzer = ImageAnalyzer()
        try analyzer.processImage(path: imagePath, logger: logger)
    }
    
    private func runEvaluation(logger: Logger) throws {
        print("📊 Starting FHP dataset evaluation with 3 approaches...")
        logger.info("Dataset evaluation starting")
        
        let evaluationRunner = EvaluationRunner()
        try evaluationRunner.evaluateDataset(logger: logger)
    }
    
    private func runCameraCapture(logger: Logger) throws {
        if debug {
            print("PostureKeeper starting in debug mode...")
            print("Debug features:")
            print("- Frames will be saved to ./.output/")
            print("- Landmark and keypoint annotations will be displayed")
            logger.info("Debug mode enabled - frames will be saved to ./.output/")
        } else {
            print("PostureKeeper starting in normal mode...")
            logger.info("Normal mode - real-time analysis only")
        }
        
        // Initialize camera
        let camera = CameraCapture()
        camera.debugMode = debug
        camera.frameHandler = { pixelBuffer in
            logger.debug("Received frame for processing")
            if debug {
                print("📸 Frame captured and saved to .output/")
            } else {
                print("📸 Frame captured - analysis not yet implemented")
            }
        }
        
        // Use async task wrapper with run loop
        let semaphore = DispatchSemaphore(value: 0)
        var cameraError: Error?
        
        Task {
            do {
                print("🔐 Requesting camera permissions...")
                try await camera.setupSession()
                camera.startSession()
                
                print("📹 Camera started! Capturing frames at 1 FPS...")
                if debug {
                    print("💾 Debug mode: Frames being saved to ./.output/ directory")
                }
                print("Press Ctrl+C to stop")
                logger.info("Camera session active")
                
                // Keep the main thread alive to process timer events
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        continuation.resume()
                    }
                }
                
            } catch {
                logger.error("Camera setup failed", metadata: ["error": "\(error)"])
                print("❌ Error: \(error.localizedDescription)")
                cameraError = error
            }
            
            camera.stopSession()
            print("📱 Camera stopped")
            logger.info("Application exiting normally")
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = cameraError {
            throw ExitCode.failure
        }
    }
}

// Entry point
PostureKeeper.main()