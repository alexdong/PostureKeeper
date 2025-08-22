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
- [ ] 2.1 Implement CameraCapture.swift class with AVCaptureSession setup
- [ ] 2.2 Add camera device discovery and first-available selection logic
- [ ] 2.3 Implement camera permission request and error handling
- [ ] 2.4 Create Timer-based frame capture at 1 FPS with CVPixelBuffer output
- [ ] 2.5 Add --debug mode to save captured frames to `./.output/` (gitignored)

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
- [ ] 3.1 Set up VNDetectFaceLandmarksRequest and VNDetectHumanBodyPoseRequest
- [ ] 3.2 Implement landmark extraction for ears, nose, shoulders, and chest keypoints
- [ ] 3.3 Add confidence validation and filtering for reliable landmarks
- [ ] 3.4 Create coordinate system conversion from Vision to geometric calculations
- [ ] 3.5 Add --debug mode annotation output for landmarks and keypoints

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
- [ ] 4.1 Implement Forward Head Posture angle calculation using ear-to-vertical
- [ ] 4.2 Implement Rounded Shoulders distance using body pose shoulder keypoints
- [ ] 4.3 Implement Turtle Neck probability using head-neck-chest angle calculations
- [ ] 4.4 Add "Can't locate chest" and similar error messages for missing keypoints
- [ ] 4.5 Add clinical threshold validation and severity classification

**Section 4 Acceptance Tests:**
After implementing posture analysis algorithms, verify clinical calculations work accurately:

1. **Forward Head Posture Calculation**:
   - Test with known good posture - verify CVA angle >53° is calculated correctly
   - Test with forward head position - confirm angles <50° trigger FHP detection
   - Validate angle calculation math using test cases with known ear/neck positions
   - Check confidence propagation from landmark detection to angle measurement

2. **Rounded Shoulders Analysis**:
   - Test shoulder protraction calculation with normal posture (<2.5cm expected)
   - Verify scaling from pixel coordinates to real-world centimeters using face width
   - Test with obviously rounded shoulders - confirm >2.5cm measurements
   - Validate bilateral shoulder measurement and averaging logic

3. **Turtle Neck Detection**:
   - Test dual-angle algorithm: head-neck <70° AND neck-chest <80°
   - Verify probability calculation: (deviation1 + deviation2) / 50
   - Check that single-angle violations don't trigger turtle neck detection
   - Confirm probability range stays within 0.0-1.0 bounds

4. **Error Handling and Thresholds**:
   - Test missing keypoints - verify "Can't locate chest" type messages appear
   - Confirm clinical thresholds match research values (CVA <50°, shoulders >2.5cm, etc.)
   - Test edge cases: exactly threshold values, very low confidence landmarks
   - Verify severity classification (normal/mild/moderate/severe) works correctly

**Expected Outcome**: Accurate clinical posture measurements with proper error handling and research-validated thresholds.

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