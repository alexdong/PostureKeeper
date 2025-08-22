import Foundation
import CoreGraphics
import ImageIO
import Logging

struct DatasetResult {
    let imagePath: String
    let groundTruth: Bool  // true = FHP (interruption-worthy), false = normal (leave-me-alone)
    let results: [FHPResult]
}

struct ConfusionMatrix {
    let truePositive: Int
    let falsePositive: Int
    let trueNegative: Int
    let falseNegative: Int
    
    var accuracy: Double {
        let total = truePositive + falsePositive + trueNegative + falseNegative
        return total > 0 ? Double(truePositive + trueNegative) / Double(total) : 0.0
    }
    
    var precision: Double {
        let positives = truePositive + falsePositive
        return positives > 0 ? Double(truePositive) / Double(positives) : 0.0
    }
    
    var recall: Double {
        let actualPositives = truePositive + falseNegative
        return actualPositives > 0 ? Double(truePositive) / Double(actualPositives) : 0.0
    }
    
    var f1Score: Double {
        let p = precision
        let r = recall
        return (p + r) > 0 ? 2 * p * r / (p + r) : 0.0
    }
}

class EvaluationRunner {
    private let visionProcessor = VisionProcessor()
    private let analyzers: [FHPAnalyzer] = [
        DirectCVAAnalyzer(),
        BilateralCVAAnalyzer(), 
        ConfidenceWeightedCVAAnalyzer()
    ]
    
    func evaluateDataset(logger: Logger) throws {
        logger.info("Starting FHP dataset evaluation")
        print("📊 Starting FHP dataset evaluation with 3 approaches...")
        
        // Load dataset
        let datasetResults = try loadDataset(logger: logger)
        logger.info("Dataset loaded", metadata: [
            "total_images": "\(datasetResults.count)",
            "normal_images": "\(datasetResults.filter { !$0.groundTruth }.count)",
            "fhp_images": "\(datasetResults.filter { $0.groundTruth }.count)"
        ])
        
        print("\n📈 EVALUATION RESULTS")
        print("====================")
        
        // Process each image through all analyzers
        print("\n🔍 Processing images...")
        var results: [DatasetResult] = []
        
        for (index, item) in datasetResults.enumerated() {
            print("Processing \(index + 1)/\(datasetResults.count): \(URL(fileURLWithPath: item.imagePath).lastPathComponent)")
            
            do {
                let processedResult = try processImageForEvaluation(item, logger: logger)
                results.append(processedResult)
                
                // Show quick result
                let validResults = processedResult.results.compactMap { $0.angle != nil ? $0 : nil }
                if !validResults.isEmpty {
                    let predictions = validResults.map { $0.classification ? "FHP" : "Normal" }
                    let groundTruthStr = processedResult.groundTruth ? "FHP" : "Normal"
                    print("  Ground Truth: \(groundTruthStr) | Predictions: \(predictions.joined(separator: ", "))")
                } else {
                    print("  ❌ No valid predictions (insufficient landmarks)")
                }
                
            } catch {
                logger.error("Failed to process image", metadata: [
                    "path": "\(item.imagePath)",
                    "error": "\(error)"
                ])
                print("  ❌ Processing failed: \(error.localizedDescription)")
                
                // Create failed result
                let failedResults = analyzers.map { analyzer in
                    FHPResult(
                        angle: nil,
                        confidence: 0.0,
                        classification: false,
                        debugInfo: ["error": error.localizedDescription],
                        analyzerName: analyzer.name
                    )
                }
                results.append(DatasetResult(
                    imagePath: item.imagePath,
                    groundTruth: item.groundTruth,
                    results: failedResults
                ))
            }
        }
        
        // Generate detailed per-image results
        print("\n📋 DETAILED RESULTS")
        print("==================")
        generateDetailedResults(results: results, logger: logger)
        
        // Generate confusion matrices for each analyzer
        print("\n📊 CONFUSION MATRICES")
        print("=====================")
        for (index, analyzer) in analyzers.enumerated() {
            print("\n--- \(analyzer.name) ---")
            let confusionMatrix = calculateConfusionMatrix(results: results, analyzerIndex: index)
            printConfusionMatrix(confusionMatrix, analyzerName: analyzer.name)
            
            logger.info("Confusion matrix calculated", metadata: [
                "analyzer": "\(analyzer.name)",
                "accuracy": "\(confusionMatrix.accuracy)",
                "precision": "\(confusionMatrix.precision)",
                "recall": "\(confusionMatrix.recall)",
                "f1_score": "\(confusionMatrix.f1Score)"
            ])
        }
        
        print("\n✅ Dataset evaluation complete!")
        logger.info("Dataset evaluation completed", metadata: ["total_processed": "\(results.count)"])
    }
    
    private func loadDataset(logger: Logger) throws -> [(imagePath: String, groundTruth: Bool)] {
        let datasetPath = "datasets/FHP"
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: datasetPath) else {
            logger.error("Dataset directory not found", metadata: ["path": "\(datasetPath)"])
            throw EvaluationError.datasetNotFound(datasetPath)
        }
        
        var results: [(String, Bool)] = []
        
        // Load normal posture images (leave-me-alone = false)
        let normalPath = "\(datasetPath)/leave-me-alone"
        if fileManager.fileExists(atPath: normalPath) {
            let normalImages = try loadImagesFromDirectory(normalPath, groundTruth: false, logger: logger)
            results.append(contentsOf: normalImages)
            logger.info("Loaded normal posture images", metadata: ["count": "\(normalImages.count)"])
        } else {
            logger.warning("Normal posture directory not found", metadata: ["path": "\(normalPath)"])
        }
        
        // Load FHP images (interrupt-worthy = true)  
        let fhpPath = "\(datasetPath)/interrupt-worthy"
        if fileManager.fileExists(atPath: fhpPath) {
            let fhpImages = try loadImagesFromDirectory(fhpPath, groundTruth: true, logger: logger)
            results.append(contentsOf: fhpImages)
            logger.info("Loaded FHP images", metadata: ["count": "\(fhpImages.count)"])
        } else {
            logger.warning("FHP directory not found", metadata: ["path": "\(fhpPath)"])
        }
        
        guard !results.isEmpty else {
            logger.error("No images found in dataset")
            throw EvaluationError.noImagesInDataset
        }
        
        // Convert to DatasetResult format
        return results.map { (imagePath, groundTruth) in
            (imagePath: imagePath, groundTruth: groundTruth)
        }
    }
    
    private func loadImagesFromDirectory(_ path: String, groundTruth: Bool, logger: Logger) throws -> [(String, Bool)] {
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: path)
            let imageFiles = files.filter { filename in
                let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
                return ["jpg", "jpeg", "png"].contains(pathExtension)
            }.map { filename in
                ("\(path)/\(filename)", groundTruth)
            }
            
            logger.debug("Images loaded from directory", metadata: [
                "path": "\(path)",
                "count": "\(imageFiles.count)",
                "ground_truth": "\(groundTruth)"
            ])
            
            return imageFiles
            
        } catch {
            logger.error("Failed to read directory", metadata: [
                "path": "\(path)",
                "error": "\(error)"
            ])
            throw EvaluationError.directoryReadFailed(path, error.localizedDescription)
        }
    }
    
    private func processImageForEvaluation(_ item: (imagePath: String, groundTruth: Bool), logger: Logger) throws -> DatasetResult {
        // Load image
        let cgImage = try loadImage(from: item.imagePath, logger: logger)
        
        // Process with Vision framework
        let (landmarks, _) = try visionProcessor.processImage(cgImage)
        
        // Run all analyzers
        var results: [FHPResult] = []
        for analyzer in analyzers {
            let result = analyzer.analyzeFHP(landmarks: landmarks, logger: logger)
            results.append(result)
        }
        
        return DatasetResult(
            imagePath: item.imagePath,
            groundTruth: item.groundTruth,
            results: results
        )
    }
    
    private func loadImage(from path: String, logger: Logger) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw EvaluationError.invalidImageFile(path)
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw EvaluationError.imageCreationFailed(path)
        }
        
        return cgImage
    }
    
    private func generateDetailedResults(results: [DatasetResult], logger: Logger) {
        print("=== FHP Evaluation Results ===")
        print("Image                     | GT    | D-CVA  | B-CVA  | CW-CVA | Status")
        print("--------------------------|-------|--------|--------|--------|--------")
        
        for result in results {
            let filename = URL(fileURLWithPath: result.imagePath).lastPathComponent
            let truncatedName = String(filename.prefix(24)).padding(toLength: 24, withPad: " ", startingAt: 0)
            let gtStr = result.groundTruth ? "FHP  " : "Normal"
            
            // Get predictions from each analyzer
            let predictions = result.results.map { fhpResult -> String in
                if fhpResult.angle != nil {
                    return fhpResult.classification ? "FHP" : "Norm"
                } else {
                    return "N/A"
                }
            }
            
            // Check if any valid prediction matches ground truth
            let validPredictions = result.results.compactMap { result -> Bool? in
                guard result.angle != nil else { return nil }
                return result.classification
            }
            
            let status: String
            if validPredictions.isEmpty {
                status = "❌ N/A"
            } else {
                let correctPredictions = validPredictions.filter { $0 == result.groundTruth }.count
                status = correctPredictions > validPredictions.count / 2 ? "✅ OK" : "❌ ERR"
            }
            
            print("\(truncatedName) | \(gtStr) | \(predictions[0].padding(toLength: 6, withPad: " ", startingAt: 0)) | \(predictions[1].padding(toLength: 6, withPad: " ", startingAt: 0)) | \(predictions[2].padding(toLength: 6, withPad: " ", startingAt: 0)) | \(status)")
        }
    }
    
    private func calculateConfusionMatrix(results: [DatasetResult], analyzerIndex: Int) -> ConfusionMatrix {
        var truePositive = 0
        var falsePositive = 0
        var trueNegative = 0
        var falseNegative = 0
        
        for result in results {
            let fhpResult = result.results[analyzerIndex]
            
            // Skip if no valid prediction
            guard fhpResult.angle != nil else { continue }
            
            let prediction = fhpResult.classification
            let groundTruth = result.groundTruth
            
            switch (prediction, groundTruth) {
            case (true, true):   truePositive += 1
            case (true, false):  falsePositive += 1
            case (false, false): trueNegative += 1
            case (false, true):  falseNegative += 1
            }
        }
        
        return ConfusionMatrix(
            truePositive: truePositive,
            falsePositive: falsePositive,
            trueNegative: trueNegative,
            falseNegative: falseNegative
        )
    }
    
    private func printConfusionMatrix(_ matrix: ConfusionMatrix, analyzerName: String) {
        print("                Predicted")
        print("                False  True")
        print("Actual False      \(String(format: "%3d", matrix.trueNegative))    \(String(format: "%3d", matrix.falsePositive))")
        print("Actual True       \(String(format: "%3d", matrix.falseNegative))    \(String(format: "%3d", matrix.truePositive))")
        print("")
        print("Accuracy:  \(String(format: "%.1f", matrix.accuracy * 100))%")
        print("Precision: \(String(format: "%.1f", matrix.precision * 100))%")
        print("Recall:    \(String(format: "%.1f", matrix.recall * 100))%")
        print("F1-Score:  \(String(format: "%.1f", matrix.f1Score * 100))%")
    }
}

enum EvaluationError: Error, LocalizedError {
    case datasetNotFound(String)
    case noImagesInDataset
    case directoryReadFailed(String, String)
    case invalidImageFile(String)
    case imageCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .datasetNotFound(let path):
            return "Dataset directory not found: \(path)"
        case .noImagesInDataset:
            return "No images found in dataset directories"
        case .directoryReadFailed(let path, let error):
            return "Failed to read directory \(path): \(error)"
        case .invalidImageFile(let path):
            return "Invalid image file: \(path)"
        case .imageCreationFailed(let path):
            return "Failed to create image from file: \(path)"
        }
    }
}