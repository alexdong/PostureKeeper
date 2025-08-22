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
- [ ] 1.1 Create Package.swift with AVFoundation, Vision, and swift-log dependencies
- [ ] 1.2 Create Makefile with build, run, and clean targets
- [ ] 1.3 Set up basic project directory structure (Sources/PostureKeeper/)
- [ ] 1.4 Create minimal main.swift with --debug argument handling and exit
- [ ] 1.5 Set up swift-log to write messages to `logs/YYMMDD_HHMMSS.log`
- [ ] 1.6 Add `output/` and `logs/` to .gitignore

### 2. Camera Infrastructure
- [ ] 2.1 Implement CameraCapture.swift class with AVCaptureSession setup
- [ ] 2.2 Add camera device discovery and first-available selection logic
- [ ] 2.3 Implement camera permission request and error handling
- [ ] 2.4 Create Timer-based frame capture at 1 FPS with CVPixelBuffer output
- [ ] 2.5 Add --debug mode to save captured frames to `./output` (gitignored)

### 3. Vision Framework Integration
- [ ] 3.1 Set up VNDetectFaceLandmarksRequest and VNDetectHumanBodyPoseRequest
- [ ] 3.2 Implement landmark extraction for ears, nose, shoulders, and chest keypoints
- [ ] 3.3 Add confidence validation and filtering for reliable landmarks
- [ ] 3.4 Create coordinate system conversion from Vision to geometric calculations
- [ ] 3.5 Add --debug mode annotation output for landmarks and keypoints

### 4. Posture Analysis Implementation
- [ ] 4.1 Implement Forward Head Posture angle calculation using ear-to-vertical
- [ ] 4.2 Implement Rounded Shoulders distance using body pose shoulder keypoints
- [ ] 4.3 Implement Turtle Neck probability using head-neck-chest angle calculations
- [ ] 4.4 Add "Can't locate chest" and similar error messages for missing keypoints
- [ ] 4.5 Add clinical threshold validation and severity classification

### 5. Output and Integration
- [ ] 5.1 Create OutputFormatter.swift with formatted text generation
- [ ] 5.2 Implement confidence percentage display and error state messages
- [ ] 5.3 Integrate all components in main.swift with --debug flag support
- [ ] 5.4 Test end-to-end functionality: `make run` (normal) and `make run --debug`
- [ ] 5.5 Refine output format and debug annotations