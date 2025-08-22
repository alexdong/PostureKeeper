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
    
    func run() throws {
        let logger = setupLogging()
        
        logger.info("PostureKeeper starting", metadata: ["debug_mode": "\(debug)"])
        
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