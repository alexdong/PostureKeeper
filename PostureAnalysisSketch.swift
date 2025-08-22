// PostureAnalysis Interface Sketch - Section 4 Implementation
// This is exploratory code to demonstrate the interface design

import Vision
import CoreGraphics

// MARK: - Core Data Types

struct PostureMeasurement {
    let value: Double?
    let confidence: Double
    let isAlert: Bool
    let errorMessage: String?
    
    var displayString: String {
        if let error = errorMessage {
            return error
        }
        guard let value = value else {
            return "N/A"
        }
        let confidencePercent = Int(confidence * 100)
        return "(\(confidencePercent)%)"
    }
}

struct PostureAnalysisResult {
    let forwardHeadPosture: PostureMeasurement  // FHP: 47.2° (98%)
    let roundedShoulders: PostureMeasurement    // RS: 3.1cm (85%)
    let turtleNeck: PostureMeasurement          // TN: 0.73 (92%)
}

// MARK: - Core Analysis Interface

protocol PostureAnalyzer {
    func analyze(faceObservation: VNFaceObservation?, 
                bodyPoseObservation: VNHumanBodyPoseObservation?,
                imageSize: CGSize) -> PostureAnalysisResult
}

// MARK: - Individual Measurement Calculators

protocol ForwardHeadPostureCalculator {
    func calculate(faceObservation: VNFaceObservation, imageSize: CGSize) -> PostureMeasurement
}

protocol RoundedShouldersCalculator {
    func calculate(bodyPoseObservation: VNHumanBodyPoseObservation, 
                  faceWidth: Double?, 
                  imageSize: CGSize) -> PostureMeasurement
}

protocol TurtleNeckCalculator {
    func calculate(bodyPoseObservation: VNHumanBodyPoseObservation, 
                  imageSize: CGSize) -> PostureMeasurement
}

// MARK: - Main Implementation Sketch

class DefaultPostureAnalyzer: PostureAnalyzer {
    
    private let fhpCalculator: ForwardHeadPostureCalculator
    private let rsCalculator: RoundedShouldersCalculator
    private let tnCalculator: TurtleNeckCalculator
    
    init(fhpCalculator: ForwardHeadPostureCalculator,
         rsCalculator: RoundedShouldersCalculator,
         tnCalculator: TurtleNeckCalculator) {
        self.fhpCalculator = fhpCalculator
        self.rsCalculator = rsCalculator
        self.tnCalculator = tnCalculator
    }
    
    func analyze(faceObservation: VNFaceObservation?, 
                bodyPoseObservation: VNHumanBodyPoseObservation?,
                imageSize: CGSize) -> PostureAnalysisResult {
        
        // 4.1 Forward Head Posture - requires face landmarks
        let fhp: PostureMeasurement
        if let face = faceObservation {
            fhp = fhpCalculator.calculate(faceObservation: face, imageSize: imageSize)
        } else {
            fhp = PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                   errorMessage: "No face detected")
        }
        
        // Extract face width for scaling if available
        let faceWidth = extractFaceWidth(from: faceObservation, imageSize: imageSize)
        
        // 4.2 Rounded Shoulders - requires body pose + face width for scaling
        let rs: PostureMeasurement
        if let body = bodyPoseObservation {
            rs = rsCalculator.calculate(bodyPoseObservation: body, 
                                      faceWidth: faceWidth, 
                                      imageSize: imageSize)
        } else {
            rs = PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                  errorMessage: "Can't locate shoulders")
        }
        
        // 4.3 Turtle Neck - requires body pose for head-neck-chest angles
        let tn: PostureMeasurement
        if let body = bodyPoseObservation {
            tn = tnCalculator.calculate(bodyPoseObservation: body, imageSize: imageSize)
        } else {
            tn = PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                  errorMessage: "Can't locate chest")
        }
        
        return PostureAnalysisResult(forwardHeadPosture: fhp, 
                                   roundedShoulders: rs, 
                                   turtleNeck: tn)
    }
    
    private func extractFaceWidth(from observation: VNFaceObservation?, 
                                 imageSize: CGSize) -> Double? {
        // Extract face bounding box width for pixel-to-cm scaling
        // ~15cm average face width assumption
        guard let face = observation else { return nil }
        let faceWidthPixels = face.boundingBox.width * imageSize.width
        return Double(faceWidthPixels) // Will be converted to cm in RS calculator
    }
}

// MARK: - Concrete Calculator Sketches

class DefaultFHPCalculator: ForwardHeadPostureCalculator {
    
    func calculate(faceObservation: VNFaceObservation, imageSize: CGSize) -> PostureMeasurement {
        guard let landmarks = faceObservation.landmarks else {
            return PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                    errorMessage: "Insufficient data")
        }
        
        // Extract ear and neck approximation points
        guard let rightEar = extractRightEar(from: landmarks),
              let neckApprox = extractNeckApproximation(from: landmarks) else {
            return PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                    errorMessage: "Insufficient data")
        }
        
        // Calculate craniovertebral angle (CVA)
        let cvaAngle = calculateCraniovertebralAngle(ear: rightEar, neck: neckApprox)
        let confidence = min(rightEar.confidence, neckApprox.confidence)
        let isAlert = cvaAngle < 50.0  // Clinical threshold
        
        return PostureMeasurement(value: cvaAngle, confidence: confidence, 
                                isAlert: isAlert, errorMessage: nil)
    }
    
    private func extractRightEar(from landmarks: VNFaceLandmarks2D) -> (point: CGPoint, confidence: Double)? {
        // Implementation would extract right ear landmark with confidence
        return nil
    }
    
    private func extractNeckApproximation(from landmarks: VNFaceLandmarks2D) -> (point: CGPoint, confidence: Double)? {
        // Use nose base as neck approximation
        return nil
    }
    
    private func calculateCraniovertebralAngle(ear: (point: CGPoint, confidence: Double), 
                                             neck: (point: CGPoint, confidence: Double)) -> Double {
        // Calculate angle between ear-neck line and vertical
        let dx = ear.point.x - neck.point.x
        let dy = ear.point.y - neck.point.y
        let angleRadians = atan2(abs(dx), abs(dy))
        return angleRadians * 180.0 / .pi
    }
}

class DefaultRSCalculator: RoundedShouldersCalculator {
    
    func calculate(bodyPoseObservation: VNHumanBodyPoseObservation, 
                  faceWidth: Double?, 
                  imageSize: CGSize) -> PostureMeasurement {
        
        // Extract shoulder keypoints
        guard let leftShoulder = extractJoint(.leftShoulder, from: bodyPoseObservation),
              let rightShoulder = extractJoint(.rightShoulder, from: bodyPoseObservation) else {
            return PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                    errorMessage: "Can't locate shoulders")
        }
        
        // Calculate horizontal distance from midline
        let midlineX = imageSize.width / 2
        let leftDistance = abs(leftShoulder.point.x - midlineX)
        let rightDistance = abs(rightShoulder.point.x - midlineX)
        let avgDistancePixels = (leftDistance + rightDistance) / 2
        
        // Convert to centimeters using face width scaling
        let distanceCm: Double
        if let faceWidthPixels = faceWidth {
            let pixelToCmRatio = 15.0 / faceWidthPixels  // 15cm average face width
            distanceCm = avgDistancePixels * pixelToCmRatio
        } else {
            distanceCm = avgDistancePixels * 0.1  // Fallback scaling
        }
        
        let confidence = min(leftShoulder.confidence, rightShoulder.confidence)
        let isAlert = distanceCm > 2.5  // Clinical threshold
        
        return PostureMeasurement(value: distanceCm, confidence: confidence, 
                                isAlert: isAlert, errorMessage: nil)
    }
    
    private func extractJoint(_ joint: VNHumanBodyPoseObservation.JointName, 
                             from observation: VNHumanBodyPoseObservation) -> (point: CGPoint, confidence: Double)? {
        // Extract specific joint with confidence filtering
        return nil
    }
}

class DefaultTNCalculator: TurtleNeckCalculator {
    
    func calculate(bodyPoseObservation: VNHumanBodyPoseObservation, 
                  imageSize: CGSize) -> PostureMeasurement {
        
        // Extract head, neck, chest keypoints
        guard let head = extractJoint(.nose, from: bodyPoseObservation),
              let neck = extractJoint(.neck, from: bodyPoseObservation),
              let chest = extractJoint(.root, from: bodyPoseObservation) else {
            return PostureMeasurement(value: nil, confidence: 0.0, isAlert: false, 
                                    errorMessage: "Can't locate chest")
        }
        
        // Calculate dual angles: head-neck and neck-chest
        let headNeckAngle = calculateAngle(p1: head.point, p2: neck.point, p3: chest.point)
        let neckChestAngle = calculateAngle(p1: neck.point, p2: chest.point, p3: CGPoint(x: chest.point.x, y: chest.point.y + 100))
        
        // Turtle neck probability calculation per spec
        let headNeckDeviation = max(0, 70.0 - headNeckAngle)
        let neckChestDeviation = max(0, 80.0 - neckChestAngle)
        let probability = (headNeckDeviation + neckChestDeviation) / 50.0
        let clampedProbability = min(1.0, max(0.0, probability))
        
        let confidence = min(head.confidence, min(neck.confidence, chest.confidence))
        let isAlert = clampedProbability > 0.5  // Clinical threshold
        
        return PostureMeasurement(value: clampedProbability, confidence: confidence, 
                                isAlert: isAlert, errorMessage: nil)
    }
    
    private func extractJoint(_ joint: VNHumanBodyPoseObservation.JointName, 
                             from observation: VNHumanBodyPoseObservation) -> (point: CGPoint, confidence: Double)? {
        return nil
    }
    
    private func calculateAngle(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> Double {
        // Calculate angle at p2 formed by p1-p2-p3
        let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        let cos = dot / (mag1 * mag2)
        return acos(max(-1, min(1, cos))) * 180.0 / .pi
    }
}