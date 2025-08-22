import Foundation
import Vision
import Logging

struct FHPResult {
    let angle: Double?
    let confidence: Double
    let classification: Bool  // true if FHP detected (angle < 50°)
    let debugInfo: [String: Any]
    let analyzerName: String
}

protocol FHPAnalyzerProtocol {
    var name: String { get }
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult
}

// MARK: - Forward Head Posture Analyzer (Bilateral CVA Method)
class FHPAnalyzer: FHPAnalyzerProtocol {
    let name = "Face Aspect Ratio CVA"
    
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult {
        logger.info("Starting Face Aspect Ratio CVA analysis")
        
        var debugInfo: [String: Any] = [:]
        debugInfo["method"] = "Face aspect ratio analysis for forward head posture detection"
        debugInfo["landmarks_required"] = ["faceContour", "leftEye", "rightEye"]
        
        guard let faceLandmarks = landmarks.faceLandmarks else {
            logger.warning("Missing face landmarks for FHP analysis")
            debugInfo["error"] = "Missing face landmarks"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Get required face landmarks
        guard let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10,
              let leftEye = faceLandmarks.leftEye, leftEye.pointCount > 0,
              let rightEye = faceLandmarks.rightEye, rightEye.pointCount > 0 else {
            logger.warning("Required face landmarks not available")
            debugInfo["error"] = "Face contour or eye landmarks not detected"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate face dimensions
        let contourPoints = Array(faceContour.normalizedPoints[0..<faceContour.pointCount])
        let leftmostPoint = contourPoints.min(by: { $0.x < $1.x })!
        let rightmostPoint = contourPoints.max(by: { $0.x < $1.x })!
        let topmostPoint = contourPoints.min(by: { $0.y < $1.y })!
        let bottommostPoint = contourPoints.max(by: { $0.y < $1.y })!
        
        let faceWidth = rightmostPoint.x - leftmostPoint.x
        let faceHeight = bottommostPoint.y - topmostPoint.y
        
        // Calculate eye positions
        let leftEyeCenter = leftEye.normalizedPoints[0]
        let rightEyeCenter = rightEye.normalizedPoints[0]
        let eyeDistance = abs(rightEyeCenter.x - leftEyeCenter.x)
        
        // Face aspect ratio analysis
        let aspectRatio = faceWidth / faceHeight
        let eyeToFaceWidthRatio = eyeDistance / faceWidth
        
        debugInfo["face_width"] = faceWidth
        debugInfo["face_height"] = faceHeight
        debugInfo["aspect_ratio"] = aspectRatio
        debugInfo["eye_distance"] = eyeDistance
        debugInfo["eye_to_face_ratio"] = eyeToFaceWidthRatio
        
        // Forward head posture typically increases perceived face width relative to height
        // and changes eye positioning relative to face bounds
        let normalAspectRatio = 0.75  // Typical face width/height ratio
        let aspectDeviation = abs(aspectRatio - normalAspectRatio)
        
        // Convert to angle-like metric
        let normalizedAngle = 35.0 + (aspectDeviation * 200.0)  // Scale to degree range
        let clampedAngle = max(25.0, min(70.0, normalizedAngle))
        
        debugInfo["normal_aspect_ratio"] = normalAspectRatio
        debugInfo["aspect_deviation"] = aspectDeviation
        debugInfo["normalized_angle"] = normalizedAngle
        debugInfo["clamped_angle"] = clampedAngle
        
        // Classification: FHP if angle > 50° (significant aspect ratio deviation)
        let hasFHP = clampedAngle > 50.0
        let confidence = 0.75  // Moderate confidence for aspect ratio method
        
        debugInfo["threshold"] = 50.0
        debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
        debugInfo["confidence"] = confidence
        
        logger.info("Face Aspect Ratio CVA analysis completed", metadata: [
            "angle": "\(clampedAngle)°",
            "aspect_ratio": "\(aspectRatio)",
            "classification": hasFHP ? "FHP" : "NORMAL",
            "confidence": "\(confidence)"
        ])
        
        return FHPResult(
            angle: clampedAngle,
            confidence: confidence,
            classification: hasFHP,
            debugInfo: debugInfo,
            analyzerName: name
        )
    }
}

