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
        
        print("Camera infrastructure implemented but async integration pending")
        print("All camera components ready: CameraCapture.swift with:")
        print("  ✓ AVFoundation session management")
        print("  ✓ Device discovery and selection")
        print("  ✓ Permission handling")
        print("  ✓ 1 FPS timer-based capture") 
        print("  ✓ Debug mode frame saving")
        logger.info("Camera infrastructure complete - async integration needed for full operation")
    }
}

// Entry point
PostureKeeper.main()