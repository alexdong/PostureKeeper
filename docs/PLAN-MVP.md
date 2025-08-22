# PostureKeeper MVP Plan

## Core MVP Features
A minimal Swift CLI that captures webcam frames at 1 FPS, detects facial landmarks, calculates three key posture measurements, and outputs real-time text values.

**Output Format:**

Three measurements will be outputted for each frame, along with their confidence scores.

```bash
$ make run
FHP: 52.1° (95%) | RS: 2.1cm (88%) | TN: 0.42 (91%)
FHP: 48.3° (97%) | RS: 3.2cm (86%) | TN: 0.58 (89%)
FHP: 46.7° (94%) | RS: 3.8cm (82%) | TN: 0.71 (87%)
No face detected
FHP: 51.9° (96%) | RS: 2.3cm (90%) | TN: 0.39 (93%)
```

## Technical Architecture

### Project Structure
```
PostureKeeper/
├── Package.swift
├── Sources/
│   └── PostureKeeper/
│       ├── main.swift
│       ├── CameraCapture.swift
│       ├── PostureAnalyzer.swift
│       └── OutputFormatter.swift
└── README.md
```

### Core Components

**1. CameraCapture.swift**
- AVFoundation camera session
- 1 FPS timer-based capture
- First available camera selection
- CVPixelBuffer output

**2. PostureAnalyzer.swift**
- Vision framework face landmark detection
- Three measurement calculations:
  - Forward Head Posture (CVA angle)
  - Rounded Shoulders (distance estimation)
  - Turtle Neck (probability score)

**3. OutputFormatter.swift**
- Simple text formatting
- Confidence percentage display
- Single line output per frame

**4. main.swift**
- Entry point
- Camera permission handling
- Continuous loop execution

## Measurement Specifications

### Forward Head Posture (FHP)
- **Landmarks:** `rightEar`, `neck` (nose base approximation)
- **Calculation:** Craniovertebral angle from ear to vertical
- **Threshold:** Alert when < 50°
- **Output:** `FHP: 47.2° (98%)`

### Rounded Shoulders (RS)
- **Keypoints:** VNDetectHumanBodyPoseRequest shoulder points
- **Calculation:** Average horizontal distance from shoulders to vertical midline
- **Scaling:** Use face width as reference (~15cm average) for pixel-to-cm conversion
- **Threshold:** Alert when > 2.5cm
- **Output:** `RS: 3.1cm (85%)` or `Can't locate shoulders`

### Turtle Neck (TN)
- **Keypoints:** Head, neck, and chest from body pose detection
- **Calculation:** Probability score based on combined head-neck-chest angle deviations
- **Method:** Score = (max(0, 70° - head_neck_angle) + max(0, 80° - neck_chest_angle)) / 50
- **Range:** 0.0 to 1.0 probability
- **Threshold:** Alert when > 0.5
- **Output:** `TN: 0.73 (92%)` or `Can't locate chest`

## Implementation Details

### Core Processing Flow
1. **Initialize:** Camera session + Vision requests
2. **Capture:** Timer fires every 1 second
3. **Analyze:** Vision face landmarks on captured frame
4. **Calculate:** Three posture measurements
5. **Output:** Single formatted line to console
6. **Repeat:** Continue until interrupted

### Error Handling
- Camera unavailable: Exit with error message
- No face detected: Output `No face detected`
- Low confidence landmarks: Output `Insufficient data`
- Permission denied: Exit with permission prompt with a message on how to grant camera access

### Platform Requirements
- macOS 15.5+
- Swift 6.1+
- Built-in camera required

## Clinical Thresholds (Simplified)

| Measurement | Normal Range | Alert Threshold | Severe |
|-------------|--------------|-----------------|--------|
| FHP Angle | > 53° | < 50° | < 45° |
| Shoulder Distance | < 2.5cm | > 2.5cm | > 4.0cm |
| Turtle Neck Probability | < 0.3 | > 0.5 | > 0.8 |


## Limitations Acknowledged
- Simplified shoulder distance scaling using face width
- No temporal analysis (sustained posture)
- No data logging or history
- Basic error handling only
- Single camera support

This MVP demonstrates the core computer vision capabilities for real-time posture analysis using standard Swift frameworks and clinical research thresholds.

## Implementation Plan

### 1. Project Foundation
- [x] 1.1 Create Package.swift with AVFoundation, Vision, and swift-log dependencies
- [x] 1.2 Create Makefile with build, run, and clean targets
- [x] 1.3 Set up basic project directory structure (Sources/PostureKeeper/)
- [x] 1.4 Create minimal main.swift with --debug argument handling and exit
- [x] 1.5 Set up swift-log to write messages to `.logs/YYMMDD_HHMMSS.log`
- [x] 1.6 Add `.output/` and `.logs/` to .gitignore

**Section 1 Acceptance Tests:**
After completing all tasks in this section, verify the foundation is working correctly:

1. **Build System Verification**: Run `make build` and confirm it compiles without errors
2. **CLI Argument Testing**: 
   - Run `make run` and verify normal mode output appears
   - Run `make run-debug` and verify debug mode messaging is different
   - Confirm both modes exit cleanly without hanging
3. **Logging Infrastructure**: 
   - After running the application, check that a new log file appears in `.logs/YYMMDD_HHMMSS.log`
   - Verify the log contains timestamped entries with appropriate log levels
   - Confirm different log messages appear for normal vs debug mode
4. **Project Structure**: 
   - Verify `Sources/PostureKeeper/` directory exists with main.swift and Logger.swift
   - Confirm `.gitignore` properly excludes `.logs/`, `.output/`, and `.build/` directories
   - Check that Swift Package Manager resolves dependencies without errors

**Expected Outcome**: A functional Swift CLI foundation that builds, runs, handles arguments, and logs to timestamped files.

### 2. Camera Infrastructure
- [x] 2.1 Implement CameraCapture.swift class with AVCaptureSession setup
- [x] 2.2 Add camera device discovery and first-available selection logic
- [x] 2.3 Implement camera permission request and error handling
- [x] 2.4 Create Timer-based frame capture at 1 FPS with CVPixelBuffer output
- [x] 2.5 Add --debug mode to save captured frames to `./.output/` (gitignored)
- [x] 2.6 Integrate camera with main application (async support)

**Section 2 Acceptance Tests:**
After implementing camera infrastructure, verify the camera system works correctly:

1. **Camera Permission Handling**:
   - Run the application on a fresh system and verify it requests camera permissions properly
   - Test permission denied scenario - app should exit gracefully with helpful message
   - Confirm camera access works after granting permissions

2. **Camera Device Detection**:
   - Verify the app detects and selects the first available camera (built-in or external)
   - Test with multiple cameras connected - confirm it picks the first one consistently
   - Check error handling when no cameras are available

3. **Frame Capture Verification**:
   - Run `make run-debug` and verify frames are saved to `./.output/` directory
   - Confirm frames are captured at approximately 1 FPS (check timestamps)
   - Verify frames are valid image files that can be opened/viewed
   - Check that normal mode (`make run`) doesn't save frames

4. **Performance and Stability**:
   - Let camera run for 30+ seconds without crashes or memory leaks
   - Verify CPU usage remains reasonable during capture
   - Test clean shutdown with Ctrl+C - no hanging processes

**Expected Outcome**: Stable 1 FPS camera capture with proper permissions, device selection, and optional frame saving in debug mode.

### 3. Vision Framework Integration
I have setup some test data in `datasets/FHP/**/*.png`. These are photos of myself. 
There are two folders: `leave-me-alone` (posture is ok) and `interruption-worthy` (posture is not ok).

- [ ] 3.1 Set up VNDetectFaceLandmarksRequest and VNDetectHumanBodyPoseRequest
- [ ] 3.2 Implement landmark extraction for ears, nose, shoulders, and chest keypoints
- [ ] 3.3 Add confidence validation and filtering for reliable landmarks
- [ ] 3.4 Create coordinate system conversion from Vision to geometric calculations
- [ ] 3.5 Add --debug mode annotation output for landmarks and keypoints
- [ ] 3.6 Implement evaluation framework for FHP dataset analysis

**Section 3 Acceptance Tests:**
After implementing Vision framework integration, verify landmark detection works properly:

1. **Face Landmark Detection**:
   - Test with clear frontal face view - verify ears and nose landmarks are detected
   - Check confidence scores are >0.8 for primary facial landmarks
   - Test with profile/side views - verify ear detection still works
   - Confirm graceful handling when no face is detected

2. **Body Pose Detection**:
   - Test with upper body visible - verify shoulder and chest keypoints are found
   - Check that confidence filtering works (landmarks <0.7 confidence are rejected)
   - Test edge cases: partial occlusion, clothing affecting shoulder detection
   - Verify appropriate error messages when body parts aren't detected

3. **Debug Mode Visualization**:
   - Run `make run-debug` and check that landmark coordinates are logged/printed
   - Verify debug output shows confidence scores for each detected point
   - Confirm coordinate system makes sense (0-1 normalized coordinates)
   - Test that debug annotations don't appear in normal mode

4. **Integration Reliability**:
   - Process 100+ frames and verify consistent landmark detection
   - Check that coordinate conversion from Vision to geometric space works
   - Verify memory usage doesn't grow over time during processing
   - Test performance - ensure Vision processing stays under 25ms per frame

**Expected Outcome**: Reliable detection of facial landmarks and body keypoints with proper confidence filtering and debug visualization.

### 4. Posture Analysis Implementation

Based on comprehensive research findings from RESEARCH.md, implement 3 clinically-validated Forward Head Posture calculation approaches using Apple Vision framework with proven CVA methodology.

**Research Foundation**: Apple Vision framework achieves 85-97% accuracy for upper body landmarks with <33ms latency, while clinical CVA measurement demonstrates ICC = 0.88-0.92 reliability. The universally accepted threshold of CVA <50° for FHP detection provides validated clinical foundation.

- [ ] 4.1 Implement 3 Apple Vision-based CVA calculation approaches
- [ ] 4.2 Implement `make benchmark` to exercise all 3 options against FHP dataset
- [ ] 4.3 Output Confusion Matrix and clinical metrics (ICC, sensitivity, specificity) for each approach
- [ ] 4.4 Generate detailed per-image prediction results with confidence scores and CVA angles

#### 4.1 Three Apple Vision CVA Calculation Approaches

**Approach 1: "Direct CVA" (Traditional Clinical Method)**
- **Method**: Standard craniovertebral angle using ear-to-shoulder vector vs vertical
- **Landmarks**: `rightEar` → `rightShoulder` (C7 approximation) 
- **Calculation**: `CVA = arctan2(|ear.x - shoulder.x|, |ear.y - shoulder.y|) * 180/π`
- **Rationale**: Direct implementation of clinical gold standard, proven reliability

**Approach 2: "Bilateral CVA" (Enhanced Robustness)**
- **Method**: Average CVA from both ears to improve accuracy and handle occlusion
- **Landmarks**: `leftEar` + `rightEar` → `neck` landmark (if available) or shoulder midpoint
- **Calculation**: `CVA = (CVA_left + CVA_right) / 2` with confidence weighting
- **Rationale**: Reduces single-landmark noise, handles partial face occlusion

**Approach 3: "Confidence-Weighted CVA" (Adaptive Quality)**
- **Method**: Dynamic landmark selection based on Vision framework confidence scores
- **Landmarks**: Best available combination of ears, nose, neck, shoulders (confidence >0.7)
- **Calculation**: Weighted average based on landmark confidence and temporal smoothing
- **Rationale**: Adapts to varying webcam conditions and lighting changes

**Section 4 Acceptance Tests:**
After implementing the three CVA approaches, verify clinical accuracy against research standards:

1. **Clinical Threshold Validation**:
   - Test with dataset images: verify CVA >50° classified as normal posture
   - Confirm CVA <50° triggers FHP detection across all three approaches
   - Validate against RESEARCH.md thresholds: normal CVA 53-55°, severe <45°
   - Compare approach accuracy using ICC calculation (target >0.88)

2. **Apple Vision Integration**:
   - Verify VNHumanBodyPoseObservation landmark extraction works reliably
   - Test confidence filtering: landmarks <0.7 confidence excluded from calculations
   - Confirm processing speed <33ms per frame matching research specifications
   - Validate coordinate system conversion from Vision normalized coordinates

3. **Benchmark Performance**:
   - Run all three approaches on FHP dataset (leave-me-alone vs interruption-worthy)
   - Generate confusion matrices with sensitivity/specificity metrics
   - Calculate ICC values for test-retest reliability assessment
   - Compare against research benchmarks: target 85-97% accuracy

4. **Robustness Testing**:
   - Test with varying lighting conditions and camera angles
   - Verify graceful degradation with partial face occlusion
   - Confirm temporal smoothing reduces measurement noise
   - Validate error handling for missing landmarks

**Expected Outcome**: Three clinically-validated CVA calculation methods demonstrating >85% accuracy, ICC >0.88 reliability, and proven correlation with research standards from RESEARCH.md.

### 5. Output and Integration
- [ ] 5.1 Create OutputFormatter.swift with formatted text generation
- [ ] 5.2 Implement confidence percentage display and error state messages
- [ ] 5.3 Integrate all components in main.swift with --debug flag support
- [ ] 5.4 Test end-to-end functionality: `make run` (normal) and `make run --debug`
- [ ] 5.5 Refine output format and debug annotations

**Section 5 Acceptance Tests:**
After final integration, verify the complete MVP works as specified:

1. **Output Format Verification**:
   - Confirm output matches specification: `FHP: 47.2° (98%) | RS: 3.1cm (85%) | TN: 0.42 (91%)`
   - Test all three measurements appear in single line format
   - Verify confidence percentages are displayed correctly
   - Check error messages like "No face detected" appear when appropriate

2. **End-to-End Integration**:
   - Run `make run` and verify 1 FPS real-time posture analysis output
   - Test `make run-debug` shows same output plus debug annotations and saves frames
   - Confirm smooth operation: camera → landmarks → calculations → formatted output
   - Verify no crashes or hangs during 5+ minutes of continuous operation

3. **Clinical Accuracy Validation**:
   - Test with known good posture - verify normal readings
   - Test with exaggerated poor posture - confirm threshold violations detected
   - Validate output against manual measurements when possible
   - Check that confidence scores reflect landmark detection quality

4. **Performance and Usability**:
   - Verify 1 FPS output rate is maintained consistently
   - Confirm startup time is reasonable (<10 seconds to first output)
   - Test graceful shutdown with Ctrl+C
   - Check that log files contain useful debugging information
   - Verify memory usage stays stable over extended runtime

**Expected Outcome**: Complete MVP delivering real-time posture analysis with clinical accuracy, proper formatting, and reliable operation.

## Evaluation Framework Design

### Overview
A comprehensive evaluation system for validating Forward Head Posture (FHP) detection accuracy using the test dataset in `datasets/FHP/`. This framework enables data-driven threshold optimization and performance validation against ground truth labels.

### Dataset Structure
```
datasets/FHP/
├── leave-me-alone/          # Good posture samples (FHP = False)
│   ├── image_001.png
│   ├── image_002.png
│   └── ...
└── interruption-worthy/     # Bad posture samples (FHP = True)
    ├── image_001.png
    ├── image_002.png
    └── ...
```

### Core Components

**1. StaticImageAnalyzer.swift**
- Reuses Vision framework pipeline from real-time system
- Processes static PNG images instead of camera frames
- Extracts facial landmarks and calculates FHP angles
- Handles missing landmark scenarios gracefully

**2. EvaluationRunner.swift**
- Loads dataset with ground truth labels from folder structure
- Processes all images through FHP analysis pipeline
- Calculates confusion matrix and classification metrics
- Generates detailed per-image prediction logs

**3. ThresholdOptimizer.swift**
- Tests multiple FHP angle thresholds (40°, 45°, 50°, 55°, 60°)
- Reports accuracy, precision, recall, and F1-score for each threshold
- Identifies optimal threshold for maximum F1-score
- Validates against clinical research baseline (50°)

### Implementation Tasks

#### 3.6 Evaluation Framework Implementation
- [ ] 3.6.1 Create StaticImageAnalyzer.swift for processing PNG files
- [ ] 3.6.2 Implement dataset loader with folder-based ground truth parsing
- [ ] 3.6.3 Build EvaluationRunner.swift with confusion matrix calculation
- [ ] 3.6.4 Add ThresholdOptimizer.swift for automated threshold selection
- [ ] 3.6.5 Create detailed logging system for per-image predictions
- [ ] 3.6.6 Add `make eval` command to Makefile for running evaluation
- [ ] 3.6.7 Implement performance metrics (accuracy, precision, recall, F1)

### Output Specifications

#### Per-Image Prediction Log
```
=== FHP Evaluation Results ===
image_001.png | angle: 47.2° | confidence: 0.94 | prediction: True | ground_truth: True | ✓
image_002.png | angle: 53.1° | confidence: 0.89 | prediction: False | ground_truth: False | ✓
image_003.png | angle: N/A | confidence: 0.00 | prediction: False | ground_truth: True | ✗
image_004.png | angle: 45.8° | confidence: 0.92 | prediction: True | ground_truth: True | ✓
```

#### Confusion Matrix and Metrics
```
=== Confusion Matrix (Threshold: 50°) ===
                Predicted
                False  True
Actual False      85     12
Actual True        8     43

Accuracy: 85.3%
Precision: 78.2%
Recall: 84.3%
F1-Score: 81.1%
```

#### Threshold Optimization Results
```
=== Threshold Analysis ===
40°: Acc=78.4% P=72.1% R=92.2% F1=80.9%
45°: Acc=82.7% P=75.8% R=88.2% F1=81.5%
50°: Acc=85.3% P=78.2% R=84.3% F1=81.1% ← Clinical Baseline
55°: Acc=87.8% P=82.4% R=78.4% F1=80.4%
60°: Acc=84.2% P=85.7% R=68.6% F1=76.2%

Optimal F1-Score: 81.5% at 45° threshold
```

### Error Handling Strategy

**Missing Landmarks**: When facial landmarks cannot be detected (confidence <0.7), classify as "False" (no bad posture detected). This conservative approach avoids false positives when landmark detection fails.

**Low Confidence Predictions**: Include confidence scores in evaluation but treat all predictions equally for metrics calculation. Low confidence cases are logged for analysis but not excluded from confusion matrix.

**Invalid Images**: Skip corrupted or unreadable image files with warning message. Continue evaluation with remaining dataset.

### Performance Requirements

**Processing Speed**: Evaluation should process 100+ images in under 30 seconds
**Memory Usage**: Maintain stable memory footprint during batch processing
**Accuracy Target**: Aim for >80% F1-score on test dataset
**Robustness**: Handle missing landmarks gracefully without crashes

### Integration with Development Workflow

1. **Continuous Validation**: Run `make eval` after posture analysis changes
2. **Threshold Tuning**: Use evaluation results to optimize clinical thresholds
3. **Regression Testing**: Ensure algorithm changes don't degrade performance
4. **Dataset Expansion**: Framework supports adding more test images easily

This evaluation framework provides quantitative validation of FHP detection accuracy and enables data-driven optimization of the clinical posture analysis system.