import Foundation
import Vision
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers
import Logging

struct LandmarkResult {
    let faceLandmarks: VNFaceLandmarks2D?
    let bodyPose: VNHumanBodyPoseObservation?
    let confidence: Double
    let imageSize: CGSize
}

class VisionProcessor {
    private let logger = Logger(label: "VisionProcessor")
    
    func processImage(_ cgImage: CGImage) throws -> (landmarks: LandmarkResult, annotatedImage: CGImage) {
        logger.info("Processing image for Vision analysis", metadata: [
            "image_width": "\(cgImage.width)",
            "image_height": "\(cgImage.height)"
        ])
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        
        // Prepare Vision requests
        let faceRequest = VNDetectFaceLandmarksRequest()
        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
        
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        bodyRequest.revision = VNDetectHumanBodyPoseRequestRevision1
        
        var faceLandmarks: VNFaceLandmarks2D?
        var bodyPose: VNHumanBodyPoseObservation?
        var overallConfidence = 0.0
        
        do {
            // Execute face landmark detection
            logger.info("Executing face landmark detection request")
            try requestHandler.perform([faceRequest])
            
            if let faceObservation = faceRequest.results?.first {
                logger.info("Face detected", metadata: [
                    "confidence": "\(faceObservation.confidence)",
                    "face_bounds": "\(faceObservation.boundingBox)"
                ])
                
                faceLandmarks = faceObservation.landmarks
                overallConfidence = Double(faceObservation.confidence)
                
                // Log specific landmark availability
                if let landmarks = faceLandmarks {
                    logger.info("Face landmarks detected", metadata: [
                        "has_nose": "\(landmarks.nose != nil)",
                        "has_left_eye": "\(landmarks.leftEye != nil)",
                        "has_right_eye": "\(landmarks.rightEye != nil)",
                        "has_face_contour": "\(landmarks.faceContour != nil)"
                    ])
                }
            } else {
                logger.warning("No face detected in image")
            }
            
            // Execute body pose detection
            logger.info("Executing human body pose detection request")
            try requestHandler.perform([bodyRequest])
            
            if let poseObservation = bodyRequest.results?.first {
                logger.info("Body pose detected", metadata: [
                    "confidence": "\(poseObservation.confidence)",
                    "available_joints": "\(poseObservation.availableJointNames.count)"
                ])
                
                bodyPose = poseObservation
                overallConfidence = max(overallConfidence, Double(poseObservation.confidence))
                
                // Log key joint availability
                let keyJoints = [VNHumanBodyPoseObservation.JointName.neck,
                               .leftShoulder, .rightShoulder, .nose]
                for joint in keyJoints {
                    if let jointPoint = try? poseObservation.recognizedPoint(joint) {
                        logger.info("Joint detected", metadata: [
                            "joint": "\(joint.rawValue)",
                            "confidence": "\(jointPoint.confidence)",
                            "location": "(\(jointPoint.location.x), \(jointPoint.location.y))"
                        ])
                    }
                }
            } else {
                logger.warning("No body pose detected in image")
            }
            
        } catch {
            logger.error("Vision processing failed", metadata: ["error": "\(error)"])
            throw VisionError.processingFailed(error.localizedDescription)
        }
        
        let landmarkResult = LandmarkResult(
            faceLandmarks: faceLandmarks,
            bodyPose: bodyPose,
            confidence: overallConfidence,
            imageSize: imageSize
        )
        
        // Create annotated image
        logger.info("Creating annotated image with detected landmarks")
        let annotatedImage = try createAnnotatedImage(
            originalImage: cgImage,
            landmarks: landmarkResult
        )
        
        return (landmarks: landmarkResult, annotatedImage: annotatedImage)
    }
    
    private func createAnnotatedImage(originalImage: CGImage, landmarks: LandmarkResult) throws -> CGImage {
        logger.info("Starting image annotation process")
        
        let imageSize = landmarks.imageSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            logger.error("Failed to create graphics context for annotation")
            throw VisionError.annotationFailed("Could not create graphics context")
        }
        
        // Draw original image
        context.draw(originalImage, in: CGRect(origin: .zero, size: imageSize))
        
        // Configure drawing style
        context.setLineWidth(3.0)
        context.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.8))
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0))
        
        var annotationsCount = 0
        
        // Draw face landmarks
        if let faceLandmarks = landmarks.faceLandmarks {
            logger.info("Drawing face landmarks")
            annotationsCount += drawFaceLandmarks(context: context, landmarks: faceLandmarks, imageSize: imageSize)
        }
        
        // Draw body pose landmarks
        if let bodyPose = landmarks.bodyPose {
            logger.info("Drawing body pose landmarks")
            annotationsCount += drawBodyPoseLandmarks(context: context, bodyPose: bodyPose, imageSize: imageSize)
        }
        
        // Draw confidence text
        drawConfidenceInfo(context: context, confidence: landmarks.confidence, imageSize: imageSize)
        
        guard let annotatedCGImage = context.makeImage() else {
            logger.error("Failed to create annotated image from context")
            throw VisionError.annotationFailed("Could not create image from context")
        }
        
        logger.info("Image annotation completed", metadata: [
            "annotations_drawn": "\(annotationsCount)",
            "overall_confidence": "\(landmarks.confidence)"
        ])
        
        return annotatedCGImage
    }
    
    private func drawFaceLandmarks(context: CGContext, landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> Int {
        var count = 0
        
        // Draw nose landmarks
        if let nose = landmarks.nose {
            logger.debug("Drawing nose landmarks", metadata: ["point_count": "\(nose.pointCount)"])
            for i in 0..<nose.pointCount {
                let point = nose.normalizedPoints[i]
                let screenPoint = VNImagePointForNormalizedPoint(point, Int(imageSize.width), Int(imageSize.height))
                
                context.fillEllipse(in: CGRect(
                    x: screenPoint.x - 4,
                    y: screenPoint.y - 4,
                    width: 8,
                    height: 8
                ))
                count += 1
            }
        }
        
        // Draw face contour landmarks (approximating head boundary)
        if let faceContour = landmarks.faceContour {
            logger.debug("Drawing face contour landmarks", metadata: ["point_count": "\(faceContour.pointCount)"])
            for i in 0..<faceContour.pointCount {
                let point = faceContour.normalizedPoints[i]
                let screenPoint = VNImagePointForNormalizedPoint(point, Int(imageSize.width), Int(imageSize.height))
                
                context.setFillColor(CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.6))
                context.fillEllipse(in: CGRect(
                    x: screenPoint.x - 3,
                    y: screenPoint.y - 3,
                    width: 6,
                    height: 6
                ))
                count += 1
            }
        }
        
        // Draw eye landmarks as reference points
        if let leftEye = landmarks.leftEye {
            logger.debug("Drawing left eye landmarks", metadata: ["point_count": "\(leftEye.pointCount)"])
            for i in 0..<leftEye.pointCount {
                let point = leftEye.normalizedPoints[i]
                let screenPoint = VNImagePointForNormalizedPoint(point, Int(imageSize.width), Int(imageSize.height))
                
                context.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.8))
                context.fillEllipse(in: CGRect(
                    x: screenPoint.x - 4,
                    y: screenPoint.y - 4,
                    width: 8,
                    height: 8
                ))
                count += 1
            }
        }
        
        if let rightEye = landmarks.rightEye {
            logger.debug("Drawing right eye landmarks", metadata: ["point_count": "\(rightEye.pointCount)"])
            for i in 0..<rightEye.pointCount {
                let point = rightEye.normalizedPoints[i]
                let screenPoint = VNImagePointForNormalizedPoint(point, Int(imageSize.width), Int(imageSize.height))
                
                context.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.8))
                context.fillEllipse(in: CGRect(
                    x: screenPoint.x - 4,
                    y: screenPoint.y - 4,
                    width: 8,
                    height: 8
                ))
                count += 1
            }
        }
        
        logger.debug("Face landmarks drawn", metadata: ["total_points": "\(count)"])
        return count
    }
    
    private func drawBodyPoseLandmarks(context: CGContext, bodyPose: VNHumanBodyPoseObservation, imageSize: CGSize) -> Int {
        var count = 0
        
        // Key joints for posture analysis
        let keyJoints: [(VNHumanBodyPoseObservation.JointName, CGColor)] = [
            (.neck, CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.9)),
            (.leftShoulder, CGColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.9)),
            (.rightShoulder, CGColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.9)),
            (.nose, CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.9))
        ]
        
        for (joint, color) in keyJoints {
            do {
                let jointPoint = try bodyPose.recognizedPoint(joint)
                
                if jointPoint.confidence > 0.5 {
                    let screenPoint = VNImagePointForNormalizedPoint(
                        jointPoint.location, 
                        Int(imageSize.width), 
                        Int(imageSize.height)
                    )
                    
                    context.setFillColor(color)
                    context.fillEllipse(in: CGRect(
                        x: screenPoint.x - 6,
                        y: screenPoint.y - 6,
                        width: 12,
                        height: 12
                    ))
                    
                    logger.debug("Drew body joint", metadata: [
                        "joint": "\(joint.rawValue)",
                        "confidence": "\(jointPoint.confidence)",
                        "location": "(\(screenPoint.x), \(screenPoint.y))"
                    ])
                    count += 1
                }
            } catch {
                logger.debug("Joint not available", metadata: [
                    "joint": "\(joint.rawValue)",
                    "error": "\(error.localizedDescription)"
                ])
            }
        }
        
        logger.debug("Body pose landmarks drawn", metadata: ["total_joints": "\(count)"])
        return count
    }
    
    private func drawConfidenceInfo(context: CGContext, confidence: Double, imageSize: CGSize) {
        let _ = String(format: "Confidence: %.1f%%", confidence * 100)
        
        // Simple text drawing (basic implementation)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
        context.fill(CGRect(x: 10, y: imageSize.height - 40, width: 200, height: 30))
        
        context.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
        // Note: Core Graphics text rendering is complex, so this is a placeholder rectangle
        // In a full implementation, we'd use Core Text or overlay text differently
        
        logger.debug("Drew confidence info", metadata: ["confidence": "\(confidence)"])
    }
}

enum VisionError: Error, LocalizedError {
    case processingFailed(String)
    case annotationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .processingFailed(let message):
            return "Vision processing failed: \(message)"
        case .annotationFailed(let message):
            return "Image annotation failed: \(message)"
        }
    }
}