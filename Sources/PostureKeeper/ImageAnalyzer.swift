import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Logging

class ImageAnalyzer {
    private let visionProcessor = VisionProcessor()
    private let analyzers: [FHPAnalyzer] = [
        DirectCVAAnalyzer(),
        BilateralCVAAnalyzer(),
        ConfidenceWeightedCVAAnalyzer()
    ]
    
    func processImage(path: String, logger: Logger) throws {
        logger.info("Starting single image analysis", metadata: ["path": "\(path)"])
        print("🔍 Analyzing image: \(path)")
        
        // Resolve image path
        let imagePath = try resolveImagePath(path, logger: logger)
        logger.info("Resolved image path", metadata: ["resolved_path": "\(imagePath)"])
        
        // Load image
        let cgImage = try loadImage(from: imagePath, logger: logger)
        logger.info("Image loaded successfully", metadata: [
            "width": "\(cgImage.width)",
            "height": "\(cgImage.height)"
        ])
        
        // Process with Vision framework
        print("🧠 Running Vision framework analysis...")
        let (landmarks, annotatedImage) = try visionProcessor.processImage(cgImage)
        
        // Save annotated image
        let annotatedPath = try saveAnnotatedImage(annotatedImage, originalPath: imagePath, logger: logger)
        print("🎨 Annotated image saved: \(annotatedPath)")
        
        // Run all FHP analyzers
        print("\n📐 Running 3 FHP analysis approaches...")
        var results: [FHPResult] = []
        
        for (index, analyzer) in analyzers.enumerated() {
            print("\n--- Approach \(index + 1): \(analyzer.name) ---")
            let result = analyzer.analyzeFHP(landmarks: landmarks, logger: logger)
            results.append(result)
            
            // Display results
            if let angle = result.angle {
                let status = result.classification ? "⚠️ FHP DETECTED" : "✅ NORMAL"
                print("CVA Angle: \(String(format: "%.1f", angle))° | Confidence: \(String(format: "%.1f", result.confidence * 100))% | \(status)")
            } else {
                print("❌ Analysis failed - insufficient landmarks")
            }
            
            // Log detailed debug info
            logger.info("FHP analysis result", metadata: [
                "analyzer": "\(analyzer.name)",
                "angle": result.angle.map { "\($0)" } ?? "nil",
                "confidence": "\(result.confidence)",
                "classification": "\(result.classification)"
            ])
            
            if logger.logLevel <= .debug {
                for (key, value) in result.debugInfo {
                    logger.debug("Debug info", metadata: ["key": "\(key)", "value": "\(value)"])
                }
            }
        }
        
        // Summary comparison
        print("\n📊 ANALYSIS SUMMARY")
        print("==================")
        let validResults = results.compactMap { result -> (String, Double, Bool, Double)? in
            guard let angle = result.angle else { return nil }
            return (result.analyzerName, angle, result.classification, result.confidence)
        }
        
        if !validResults.isEmpty {
            print("Method                    | Angle  | Classification | Confidence")
            print("--------------------------|--------|----------------|------------")
            for (name, angle, classification, confidence) in validResults {
                let nameFormatted = String(name.prefix(24)).padding(toLength: 24, withPad: " ", startingAt: 0)
                let angleFormatted = String(format: "%.1f°", angle).padding(toLength: 6, withPad: " ", startingAt: 0)
                let classificationFormatted = (classification ? "FHP" : "Normal").padding(toLength: 14, withPad: " ", startingAt: 0)
                let confidenceFormatted = String(format: "%.1f%%", confidence * 100)
                
                print("\(nameFormatted) | \(angleFormatted) | \(classificationFormatted) | \(confidenceFormatted)")
            }
            
            // Calculate consensus
            let fhpCount = validResults.filter { $0.2 }.count
            let consensus = fhpCount > validResults.count / 2
            print("\nCONSENSUS: \(consensus ? "⚠️ Forward Head Posture Detected" : "✅ Normal Posture") (\(fhpCount)/\(validResults.count) methods agree)")
            
            // Average angle (for valid results)
            let averageAngle = validResults.map { $0.1 }.reduce(0, +) / Double(validResults.count)
            print("Average CVA: \(String(format: "%.1f", averageAngle))°")
            
            logger.info("Image analysis completed", metadata: [
                "valid_results": "\(validResults.count)",
                "consensus": consensus ? "FHP" : "NORMAL"
            ])
            
        } else {
            print("❌ No valid analysis results - insufficient landmarks detected")
            logger.info("Image analysis completed", metadata: [
                "valid_results": "0",
                "consensus": "NO_DATA"
            ])
        }
        
        print("\n✅ Analysis complete!")
    }
    
    private func resolveImagePath(_ path: String, logger: Logger) throws -> String {
        if path == "latest" {
            logger.info("Resolving 'latest' image from .output/ directory")
            return try findLatestOutputImage(logger: logger)
        } else {
            // Check if file exists
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: path) {
                return path
            } else {
                logger.error("Image file not found", metadata: ["path": "\(path)"])
                throw ImageAnalysisError.fileNotFound(path)
            }
        }
    }
    
    private func findLatestOutputImage(logger: Logger) throws -> String {
        let outputDir = URL(fileURLWithPath: ".output")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: outputDir.path) else {
            logger.error(".output directory not found")
            throw ImageAnalysisError.outputDirectoryNotFound
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            
            // Filter for image files and sort by modification date
            let imageFiles = files.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["jpg", "jpeg", "png"].contains(pathExtension) && !url.lastPathComponent.contains("_annotated")
            }.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            
            guard let latestFile = imageFiles.first else {
                logger.error("No image files found in .output directory")
                throw ImageAnalysisError.noImagesFound
            }
            
            logger.info("Found latest image", metadata: ["path": "\(latestFile.path)"])
            return latestFile.path
            
        } catch {
            logger.error("Failed to read .output directory", metadata: ["error": "\(error)"])
            throw ImageAnalysisError.directoryReadFailed(error.localizedDescription)
        }
    }
    
    private func loadImage(from path: String, logger: Logger) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.error("Failed to create image source", metadata: ["path": "\(path)"])
            throw ImageAnalysisError.invalidImageFile(path)
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            logger.error("Failed to create CGImage from source", metadata: ["path": "\(path)"])
            throw ImageAnalysisError.imageCreationFailed(path)
        }
        
        logger.info("Image loaded successfully", metadata: [
            "path": "\(path)",
            "width": "\(cgImage.width)",
            "height": "\(cgImage.height)"
        ])
        
        return cgImage
    }
    
    private func saveAnnotatedImage(_ cgImage: CGImage, originalPath: String, logger: Logger) throws -> String {
        let originalURL = URL(fileURLWithPath: originalPath)
        let filename = originalURL.deletingPathExtension().lastPathComponent
        let directory = originalURL.deletingLastPathComponent()
        
        let annotatedFilename = "\(filename)_annotated.jpg"
        let annotatedURL = directory.appendingPathComponent(annotatedFilename)
        
        guard let destination = CGImageDestinationCreateWithURL(
            annotatedURL as CFURL, 
            UTType.jpeg.identifier as CFString, 
            1, 
            nil
        ) else {
            logger.error("Failed to create image destination for annotated image")
            throw ImageAnalysisError.saveImageFailed("Could not create image destination")
        }
        
        // Set JPEG quality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            logger.error("Failed to save annotated image", metadata: ["path": "\(annotatedURL.path)"])
            throw ImageAnalysisError.saveImageFailed("Could not finalize image destination")
        }
        
        logger.info("Annotated image saved", metadata: ["path": "\(annotatedURL.path)"])
        return annotatedURL.path
    }
}

enum ImageAnalysisError: Error, LocalizedError {
    case fileNotFound(String)
    case outputDirectoryNotFound
    case noImagesFound
    case directoryReadFailed(String)
    case invalidImageFile(String)
    case imageCreationFailed(String)
    case saveImageFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found: \(path)"
        case .outputDirectoryNotFound:
            return ".output directory not found - run camera capture first with 'make run-debug'"
        case .noImagesFound:
            return "No image files found in .output directory"
        case .directoryReadFailed(let message):
            return "Failed to read directory: \(message)"
        case .invalidImageFile(let path):
            return "Invalid image file: \(path)"
        case .imageCreationFailed(let path):
            return "Failed to create image from file: \(path)"
        case .saveImageFailed(let message):
            return "Failed to save annotated image: \(message)"
        }
    }
}