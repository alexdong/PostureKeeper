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
        debugInfo["method"] = "Traditional craniovertebral angle using ear-to-shoulder vector vs vertical"
        debugInfo["landmarks_required"] = ["rightEar", "rightShoulder"]
        
        guard let faceLandmarks = landmarks.faceLandmarks,
              let bodyPose = landmarks.bodyPose else {
            logger.warning("Missing required landmarks for Direct CVA analysis")
            debugInfo["error"] = "Missing face landmarks or body pose"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Get face contour to approximate ear position
        guard let faceContour = faceLandmarks.faceContour,
              faceContour.pointCount > 10 else {
            logger.warning("Face contour landmarks not available for ear approximation")
            debugInfo["error"] = "Face contour landmarks not detected"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Get right shoulder from body pose
        do {
            let rightShoulderPoint = try bodyPose.recognizedPoint(.rightShoulder)
            
            guard rightShoulderPoint.confidence > 0.5 else {
                logger.warning("Right shoulder confidence too low", metadata: ["confidence": "\(rightShoulderPoint.confidence)"])
                debugInfo["error"] = "Right shoulder confidence too low: \(rightShoulderPoint.confidence)"
                return FHPResult(
                    angle: nil,
                    confidence: 0.0,
                    classification: false,
                    debugInfo: debugInfo,
                    analyzerName: name
                )
            }
            
            // Approximate right ear position from face contour
            // Face contour points are typically ordered clockwise, right side is roughly in first quarter
            let rightSideIndex = faceContour.pointCount / 4  // Approximate right ear area
            let earPoint = faceContour.normalizedPoints[rightSideIndex]
            let shoulderPoint = rightShoulderPoint.location
            
            debugInfo["ear_point"] = "(x: \(earPoint.x), y: \(earPoint.y))"
            debugInfo["shoulder_point"] = "(x: \(shoulderPoint.x), y: \(shoulderPoint.y))"
            
            // Calculate CVA angle
            // CVA = arctan2(horizontal_distance, vertical_distance) * 180/π
            let horizontalDistance = abs(earPoint.x - shoulderPoint.x)
            let verticalDistance = abs(earPoint.y - shoulderPoint.y)
            
            debugInfo["horizontal_distance"] = horizontalDistance
            debugInfo["vertical_distance"] = verticalDistance
            
            guard verticalDistance > 0.001 else {
                logger.warning("Vertical distance too small for reliable CVA calculation")
                debugInfo["error"] = "Vertical distance too small: \(verticalDistance)"
                return FHPResult(
                    angle: nil,
                    confidence: 0.0,
                    classification: false,
                    debugInfo: debugInfo,
                    analyzerName: name
                )
            }
            
            let angleRadians = atan2(horizontalDistance, verticalDistance)
            let angleDegrees = angleRadians * 180.0 / Double.pi
            
            debugInfo["angle_radians"] = angleRadians
            debugInfo["angle_degrees"] = angleDegrees
            
            // Classification: FHP if angle < 50°
            let hasFHP = angleDegrees < 50.0
            let confidence = Double(rightShoulderPoint.confidence)
            
            debugInfo["threshold"] = 50.0
            debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
            debugInfo["confidence"] = confidence
            
            logger.info("Direct CVA analysis completed", metadata: [
                "angle": "\(angleDegrees)°",
                "classification": hasFHP ? "FHP" : "NORMAL",
                "confidence": "\(confidence)"
            ])
            
            return FHPResult(
                angle: angleDegrees,
                confidence: confidence,
                classification: hasFHP,
                debugInfo: debugInfo,
                analyzerName: name
            )
            
        } catch {
            logger.error("Failed to get right shoulder joint", metadata: ["error": "\(error)"])
            debugInfo["error"] = "Right shoulder joint not available: \(error.localizedDescription)"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
    }
}

// MARK: - Approach 2: Bilateral CVA (Enhanced Robustness)
class BilateralCVAAnalyzer: FHPAnalyzer {
    let name = "Bilateral CVA"
    
    func analyzeFHP(landmarks: LandmarkResult, logger: Logger) -> FHPResult {
        logger.info("Starting Bilateral CVA analysis")
        
        var debugInfo: [String: Any] = [:]
        debugInfo["method"] = "Average CVA from both ears to improve accuracy and handle occlusion"
        debugInfo["landmarks_required"] = ["leftEar", "rightEar", "neck_or_shoulder_midpoint"]
        
        guard let faceLandmarks = landmarks.faceLandmarks,
              let bodyPose = landmarks.bodyPose else {
            logger.warning("Missing required landmarks for Bilateral CVA analysis")
            debugInfo["error"] = "Missing face landmarks or body pose"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        var leftEarPoint: CGPoint?
        var rightEarPoint: CGPoint?
        var leftEarAvailable = false
        var rightEarAvailable = false
        
        // Approximate ear positions from face contour
        if let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 {
            // Face contour points are typically ordered clockwise
            let rightSideIndex = faceContour.pointCount / 4  // Right ear area
            let leftSideIndex = (faceContour.pointCount * 3) / 4  // Left ear area
            
            rightEarPoint = faceContour.normalizedPoints[rightSideIndex]
            rightEarAvailable = true
            debugInfo["right_ear_point"] = "(x: \(rightEarPoint!.x), y: \(rightEarPoint!.y))"
            
            leftEarPoint = faceContour.normalizedPoints[leftSideIndex]
            leftEarAvailable = true
            debugInfo["left_ear_point"] = "(x: \(leftEarPoint!.x), y: \(leftEarPoint!.y))"
        }
        
        debugInfo["left_ear_available"] = leftEarAvailable
        debugInfo["right_ear_available"] = rightEarAvailable
        
        guard leftEarAvailable || rightEarAvailable else {
            logger.warning("Neither ear landmark available")
            debugInfo["error"] = "No ear landmarks detected"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Get reference point (neck or shoulder midpoint)
        var referencePoint: CGPoint?
        var referenceConfidence = 0.0
        
        // Try neck first
        do {
            let neckPoint = try bodyPose.recognizedPoint(.neck)
            if neckPoint.confidence > 0.5 {
                referencePoint = neckPoint.location
                referenceConfidence = Double(neckPoint.confidence)
                debugInfo["reference_point"] = "neck"
                debugInfo["neck_point"] = "(x: \(referencePoint!.x), y: \(referencePoint!.y))"
            }
        } catch {
            logger.debug("Neck point not available, trying shoulder midpoint")
        }
        
        // Fall back to shoulder midpoint if neck not available
        if referencePoint == nil {
            do {
                let leftShoulder = try bodyPose.recognizedPoint(.leftShoulder)
                let rightShoulder = try bodyPose.recognizedPoint(.rightShoulder)
                
                if leftShoulder.confidence > 0.5 && rightShoulder.confidence > 0.5 {
                    let midX = (leftShoulder.location.x + rightShoulder.location.x) / 2.0
                    let midY = (leftShoulder.location.y + rightShoulder.location.y) / 2.0
                    referencePoint = CGPoint(x: midX, y: midY)
                    referenceConfidence = Double(min(leftShoulder.confidence, rightShoulder.confidence))
                    debugInfo["reference_point"] = "shoulder_midpoint"
                    debugInfo["shoulder_midpoint"] = "(x: \(midX), y: \(midY))"
                }
            } catch {
                logger.warning("Failed to get shoulder reference points")
            }
        }
        
        guard let refPoint = referencePoint else {
            logger.warning("No suitable reference point found")
            debugInfo["error"] = "No suitable reference point (neck or shoulders) available"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate CVA angles for available ears
        var angles: [Double] = []
        var totalConfidence = 0.0
        var calculationCount = 0
        
        if let leftEar = leftEarPoint {
            let horizontalDistance = abs(leftEar.x - refPoint.x)
            let verticalDistance = abs(leftEar.y - refPoint.y)
            
            if verticalDistance > 0.001 {
                let angleRadians = atan2(horizontalDistance, verticalDistance)
                let angleDegrees = angleRadians * 180.0 / Double.pi
                angles.append(angleDegrees)
                totalConfidence += referenceConfidence
                calculationCount += 1
                debugInfo["left_cva_angle"] = angleDegrees
            }
        }
        
        if let rightEar = rightEarPoint {
            let horizontalDistance = abs(rightEar.x - refPoint.x)
            let verticalDistance = abs(rightEar.y - refPoint.y)
            
            if verticalDistance > 0.001 {
                let angleRadians = atan2(horizontalDistance, verticalDistance)
                let angleDegrees = angleRadians * 180.0 / Double.pi
                angles.append(angleDegrees)
                totalConfidence += referenceConfidence
                calculationCount += 1
                debugInfo["right_cva_angle"] = angleDegrees
            }
        }
        
        guard !angles.isEmpty else {
            logger.warning("No valid CVA angles calculated")
            debugInfo["error"] = "No valid CVA angles could be calculated"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate bilateral average
        let averageAngle = angles.reduce(0, +) / Double(angles.count)
        let averageConfidence = totalConfidence / Double(calculationCount)
        
        debugInfo["individual_angles"] = angles
        debugInfo["average_angle"] = averageAngle
        debugInfo["calculation_count"] = calculationCount
        debugInfo["average_confidence"] = averageConfidence
        
        // Classification: FHP if angle < 50°
        let hasFHP = averageAngle < 50.0
        debugInfo["threshold"] = 50.0
        debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
        
        logger.info("Bilateral CVA analysis completed", metadata: [
            "average_angle": "\(averageAngle)°",
            "calculation_count": "\(calculationCount)",
            "classification": hasFHP ? "FHP" : "NORMAL",
            "confidence": "\(averageConfidence)"
        ])
        
        return FHPResult(
            angle: averageAngle,
            confidence: averageConfidence,
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
        debugInfo["method"] = "Dynamic landmark selection based on Vision framework confidence scores"
        debugInfo["landmarks_considered"] = ["ears", "nose", "neck", "shoulders"]
        debugInfo["confidence_threshold"] = 0.5
        
        guard let faceLandmarks = landmarks.faceLandmarks,
              let bodyPose = landmarks.bodyPose else {
            logger.warning("Missing required landmarks for Confidence-Weighted CVA analysis")
            debugInfo["error"] = "Missing face landmarks or body pose"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Collect all potential head reference points with their confidence scores
        var headPoints: [(point: CGPoint, confidence: Double, type: String)] = []
        
        // Add ear landmarks approximated from face contour
        if let faceContour = faceLandmarks.faceContour, faceContour.pointCount > 10 {
            let confidence = 0.8  // Slightly lower confidence for approximated ear positions
            
            let rightSideIndex = faceContour.pointCount / 4
            headPoints.append((faceContour.normalizedPoints[rightSideIndex], confidence, "right_ear_approx"))
            debugInfo["right_ear_confidence"] = confidence
            
            let leftSideIndex = (faceContour.pointCount * 3) / 4
            headPoints.append((faceContour.normalizedPoints[leftSideIndex], confidence, "left_ear_approx"))
            debugInfo["left_ear_confidence"] = confidence
        }
        
        // Add nose landmarks if available
        if let nose = faceLandmarks.nose, nose.pointCount > 0 {
            let confidence = 0.85  // Nose is typically less reliable for CVA
            headPoints.append((nose.normalizedPoints[0], confidence, "nose"))
            debugInfo["nose_confidence"] = confidence
        }
        
        // Collect reference points (neck/shoulders) with their actual confidence scores
        var referencePoints: [(point: CGPoint, confidence: Double, type: String)] = []
        
        // Add neck
        do {
            let neckPoint = try bodyPose.recognizedPoint(.neck)
            if neckPoint.confidence > 0.5 {
                referencePoints.append((neckPoint.location, Double(neckPoint.confidence), "neck"))
                debugInfo["neck_confidence"] = Double(neckPoint.confidence)
            }
        } catch {
            logger.debug("Neck point not available")
        }
        
        // Add shoulders
        do {
            let leftShoulder = try bodyPose.recognizedPoint(.leftShoulder)
            if leftShoulder.confidence > 0.5 {
                referencePoints.append((leftShoulder.location, Double(leftShoulder.confidence), "left_shoulder"))
                debugInfo["left_shoulder_confidence"] = Double(leftShoulder.confidence)
            }
        } catch {
            logger.debug("Left shoulder not available")
        }
        
        do {
            let rightShoulder = try bodyPose.recognizedPoint(.rightShoulder)
            if rightShoulder.confidence > 0.5 {
                referencePoints.append((rightShoulder.location, Double(rightShoulder.confidence), "right_shoulder"))
                debugInfo["right_shoulder_confidence"] = Double(rightShoulder.confidence)
            }
        } catch {
            logger.debug("Right shoulder not available")
        }
        
        debugInfo["head_points_count"] = headPoints.count
        debugInfo["reference_points_count"] = referencePoints.count
        
        guard !headPoints.isEmpty && !referencePoints.isEmpty else {
            logger.warning("Insufficient high-confidence landmarks for analysis")
            debugInfo["error"] = "Insufficient high-confidence landmarks (head: \(headPoints.count), ref: \(referencePoints.count))"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate confidence-weighted CVA angles for all combinations
        var weightedAngles: [(angle: Double, weight: Double)] = []
        
        for headPoint in headPoints {
            for refPoint in referencePoints {
                let horizontalDistance = abs(headPoint.point.x - refPoint.point.x)
                let verticalDistance = abs(headPoint.point.y - refPoint.point.y)
                
                if verticalDistance > 0.001 {
                    let angleRadians = atan2(horizontalDistance, verticalDistance)
                    let angleDegrees = angleRadians * 180.0 / Double.pi
                    
                    // Combined confidence weight
                    let combinedConfidence = headPoint.confidence * refPoint.confidence
                    
                    weightedAngles.append((angleDegrees, combinedConfidence))
                    
                    debugInfo["\(headPoint.type)_to_\(refPoint.type)_angle"] = angleDegrees
                    debugInfo["\(headPoint.type)_to_\(refPoint.type)_weight"] = combinedConfidence
                }
            }
        }
        
        guard !weightedAngles.isEmpty else {
            logger.warning("No valid weighted angles calculated")
            debugInfo["error"] = "No valid weighted angles could be calculated"
            return FHPResult(
                angle: nil,
                confidence: 0.0,
                classification: false,
                debugInfo: debugInfo,
                analyzerName: name
            )
        }
        
        // Calculate confidence-weighted average
        let totalWeightedSum = weightedAngles.reduce(0) { $0 + ($1.angle * $1.weight) }
        let totalWeight = weightedAngles.reduce(0) { $0 + $1.weight }
        
        let weightedAverageAngle = totalWeightedSum / totalWeight
        let normalizedConfidence = totalWeight / Double(weightedAngles.count)
        
        debugInfo["weighted_angles_count"] = weightedAngles.count
        debugInfo["total_weight"] = totalWeight
        debugInfo["weighted_average_angle"] = weightedAverageAngle
        debugInfo["normalized_confidence"] = normalizedConfidence
        
        // Classification: FHP if angle < 50°
        let hasFHP = weightedAverageAngle < 50.0
        debugInfo["threshold"] = 50.0
        debugInfo["classification"] = hasFHP ? "FHP_DETECTED" : "NORMAL_POSTURE"
        
        logger.info("Confidence-Weighted CVA analysis completed", metadata: [
            "weighted_angle": "\(weightedAverageAngle)°",
            "combinations_used": "\(weightedAngles.count)",
            "classification": hasFHP ? "FHP" : "NORMAL",
            "confidence": "\(normalizedConfidence)"
        ])
        
        return FHPResult(
            angle: weightedAverageAngle,
            confidence: normalizedConfidence,
            classification: hasFHP,
            debugInfo: debugInfo,
            analyzerName: name
        )
    }
}