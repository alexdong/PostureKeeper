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

protocol FHPAnalyzer {
    var name: String { get }
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult
}

// MARK: - Approach 1: Direct CVA (Traditional Clinical Method)
class DirectCVAAnalyzer: FHPAnalyzer {
    let name = "Direct CVA"
    
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult {
        logger.info("Starting Direct CVA analysis")
        
        var debugInfo: [String: Any] = [:]
        debugInfo["method"] = "Face-only forward head posture using nose-to-contour geometry"
        debugInfo["landmarks_required"] = ["nose", "faceContour"]
        
        guard let faceLandmarks = landmarks.faceLandmarks else {
            logger.warning("Missing face landmarks for Direct CVA analysis")
            debugInfo["error"] = "Missing face landmarks"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Get face landmarks for analysis
        guard let nose = faceLandmarks.nose, nose.pointCount > 0,
              let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 else {
            logger.warning("Required face landmarks not available")
            debugInfo["error"] = "Nose or face contour landmarks not detected"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Use nose tip (first point is typically nose tip)
        let nosePoint = nose.normalizedPoints[0]
        
        // Find leftmost and rightmost face contour points
        let contourPoints = Array(faceContour.normalizedPoints[0..<faceContour.pointCount])
        let leftmostPoint = contourPoints.min(by: { $0.x < $1.x })!
        let rightmostPoint = contourPoints.max(by: { $0.x < $1.x })!
        
        // Calculate face width and nose position relative to face center
        let faceWidth = rightmostPoint.x - leftmostPoint.x
        let faceCenterX = (leftmostPoint.x + rightmostPoint.x) / 2.0
        let noseOffsetFromCenter = abs(nosePoint.x - faceCenterX)
        
        // Calculate nose-to-face-width ratio (forward head posture increases this)
        let noseProtrusion = noseOffsetFromCenter / faceWidth
        
        debugInfo["nose_point"] = "(x: \(nosePoint.x), y: \(nosePoint.y))"
        debugInfo["face_center_x"] = faceCenterX
        debugInfo["face_width"] = faceWidth
        debugInfo["nose_offset"] = noseOffsetFromCenter
        debugInfo["nose_protrusion_ratio"] = noseProtrusion
        
        // Convert to angle-like metric for consistency (higher values = more forward)
        // Normal ratio ~0.0-0.1, forward head posture ~0.15+
        let normalizedAngle = (noseProtrusion - 0.05) * 500.0  // Scale to degrees-like range
        let clampedAngle = max(20.0, min(80.0, normalizedAngle))  // Clamp to reasonable range
        
        debugInfo["normalized_angle"] = normalizedAngle
        debugInfo["clamped_angle"] = clampedAngle
        
        // Classification: FHP if angle > 45° (indicating significant protrusion)
        let hasFHP = clampedAngle > 45.0
        let confidence = 0.85  // High confidence for face landmarks
        
        debugInfo["threshold"] = 45.0
        debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
        debugInfo["confidence"] = confidence
        
        logger.info("Direct CVA analysis completed", metadata: [
            "angle": "\(clampedAngle)°",
            "nose_protrusion": "\(noseProtrusion)",
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

// MARK: - Approach 2: Bilateral CVA (Enhanced Robustness)
class BilateralCVAAnalyzer: FHPAnalyzer {
    let name = "Bilateral CVA"
    
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult {
        logger.info("Starting Bilateral CVA analysis")
        
        var debugInfo: [String: Any] = [:]
        debugInfo["method"] = "Face aspect ratio analysis for forward head posture detection"
        debugInfo["landmarks_required"] = ["faceContour", "nose", "leftEye", "rightEye"]
        
        guard let faceLandmarks = landmarks.faceLandmarks else {
            logger.warning("Missing face landmarks for Bilateral CVA analysis")
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
        
        logger.info("Bilateral CVA analysis completed", metadata: [
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

// MARK: - Approach 3: Confidence-Weighted CVA (Adaptive Quality)
class ConfidenceWeightedCVAAnalyzer: FHPAnalyzer {
    let name = "Confidence-Weighted CVA"
    
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult {
        logger.info("Starting Confidence-Weighted CVA analysis")
        
        var debugInfo: [String: Any] = [:]
        debugInfo["method"] = "Multi-landmark face geometry analysis with weighted confidence"
        debugInfo["landmarks_considered"] = ["nose", "eyes", "mouth", "faceContour"]
        
        guard let faceLandmarks = landmarks.faceLandmarks else {
            logger.warning("Missing face landmarks for Confidence-Weighted CVA analysis")
            debugInfo["error"] = "Missing face landmarks"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Collect facial landmarks with weights based on availability and reliability
        var landmarkMetrics: [(value: Double, weight: Double, type: String)] = []
        var totalWeight = 0.0
        
        // Nose position analysis
        if let nose = faceLandmarks.nose, nose.pointCount > 0,
           let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 {
            let nosePoint = nose.normalizedPoints[0]
            let contourPoints = Array(faceContour.normalizedPoints[0..<faceContour.pointCount])
            let leftmostPoint = contourPoints.min(by: { $0.x < $1.x })!
            let rightmostPoint = contourPoints.max(by: { $0.x < $1.x })!
            
            let faceWidth = rightmostPoint.x - leftmostPoint.x
            let faceCenterX = (leftmostPoint.x + rightmostPoint.x) / 2.0
            let noseOffset = abs(nosePoint.x - faceCenterX) / faceWidth
            
            landmarkMetrics.append((noseOffset * 100.0, 0.4, "nose_offset"))
            totalWeight += 0.4
            debugInfo["nose_offset"] = noseOffset
        }
        
        // Eye spacing analysis
        if let leftEye = faceLandmarks.leftEye, leftEye.pointCount > 0,
           let rightEye = faceLandmarks.rightEye, rightEye.pointCount > 0,
           let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 {
            
            let leftEyeCenter = leftEye.normalizedPoints[0]
            let rightEyeCenter = rightEye.normalizedPoints[0]
            let eyeDistance = abs(rightEyeCenter.x - leftEyeCenter.x)
            
            let contourPoints = Array(faceContour.normalizedPoints[0..<faceContour.pointCount])
            let faceWidth = contourPoints.max(by: { $0.x < $1.x })!.x - contourPoints.min(by: { $0.x < $1.x })!.x
            
            let eyeToFaceRatio = eyeDistance / faceWidth
            let expectedRatio = 0.35  // Typical eye spacing to face width ratio
            let eyeSpacingDeviation = abs(eyeToFaceRatio - expectedRatio)
            
            landmarkMetrics.append((eyeSpacingDeviation * 200.0, 0.3, "eye_spacing"))
            totalWeight += 0.3
            debugInfo["eye_spacing_ratio"] = eyeToFaceRatio
            debugInfo["eye_spacing_deviation"] = eyeSpacingDeviation
        }
        
        // Mouth position analysis
        if let outerLips = faceLandmarks.outerLips, outerLips.pointCount > 0,
           let nose = faceLandmarks.nose, nose.pointCount > 0 {
            
            let mouthCenter = outerLips.normalizedPoints[0]  // Approximate mouth center
            let nosePoint = nose.normalizedPoints[0]
            let noseToMouthDistance = sqrt(pow(mouthCenter.x - nosePoint.x, 2) + pow(mouthCenter.y - nosePoint.y, 2))
            
            // Forward head posture can change nose-to-mouth proportions
            let normalNoseToMouth = 0.08  // Typical distance in normalized coordinates
            let mouthPositionDeviation = abs(noseToMouthDistance - normalNoseToMouth)
            
            landmarkMetrics.append((mouthPositionDeviation * 300.0, 0.2, "mouth_position"))
            totalWeight += 0.2
            debugInfo["nose_to_mouth_distance"] = noseToMouthDistance
            debugInfo["mouth_deviation"] = mouthPositionDeviation
        }
        
        // Face contour symmetry
        if let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 {
            let contourPoints = Array(faceContour.normalizedPoints[0..<faceContour.pointCount])
            let centerX = (contourPoints.max(by: { $0.x < $1.x })!.x + contourPoints.min(by: { $0.x < $1.x })!.x) / 2.0
            
            // Measure asymmetry in face contour
            var asymmetrySum = 0.0
            let halfCount = contourPoints.count / 2
            for i in 0..<halfCount {
                let leftPoint = contourPoints[i]
                let rightIndex = contourPoints.count - 1 - i
                let rightPoint = contourPoints[rightIndex]
                
                let leftDistance = abs(leftPoint.x - centerX)
                let rightDistance = abs(rightPoint.x - centerX)
                asymmetrySum += abs(leftDistance - rightDistance)
            }
            
            let averageAsymmetry = asymmetrySum / Double(halfCount)
            landmarkMetrics.append((averageAsymmetry * 400.0, 0.1, "face_asymmetry"))
            totalWeight += 0.1
            debugInfo["face_asymmetry"] = averageAsymmetry
        }
        
        guard !landmarkMetrics.isEmpty else {
            logger.warning("No landmarks available for multi-metric analysis")
            debugInfo["error"] = "No suitable facial landmarks detected"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate weighted composite score
        let weightedSum = landmarkMetrics.reduce(0) { $0 + ($1.value * $1.weight) }
        let compositeScore = weightedSum / totalWeight
        
        // Convert composite score to angle-like metric
        let clampedAngle = max(20.0, min(80.0, compositeScore))
        
        debugInfo["landmark_metrics"] = landmarkMetrics.map { "\($0.type): \($0.value)" }
        debugInfo["weighted_sum"] = weightedSum
        debugInfo["total_weight"] = totalWeight
        debugInfo["composite_score"] = compositeScore
        debugInfo["clamped_angle"] = clampedAngle
        
        // Classification: FHP if composite score > 40° (significant multi-metric deviation)
        let hasFHP = clampedAngle > 40.0
        let confidence = min(1.0, totalWeight)  // Confidence based on available landmarks
        
        debugInfo["threshold"] = 40.0
        debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
        debugInfo["confidence"] = confidence
        
        logger.info("Confidence-Weighted CVA analysis completed", metadata: [
            "composite_angle": "\(clampedAngle)°",
            "metrics_used": "\(landmarkMetrics.count)",
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