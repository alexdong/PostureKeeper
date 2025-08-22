# PostureKeeper Implementation Plan

## Overview

This document outlines a modular, bottom-up implementation approach for PostureKeeper. Following Unix philosophy, we'll build individual CLI tools as composable building blocks, each thoroughly tested, before integrating them into the complete application.

## Architecture Philosophy

### Design Principles
- **Single Responsibility**: Each tool handles one specific aspect of posture detection
- **Unix Composability**: Tools can be piped together for complex workflows
- **Test-First Development**: 90%+ coverage before integration
- **Performance Isolation**: Each tool meets real-time requirements independently
- **Standard Interfaces**: JSON data exchange between components
- **Independent Deployment**: Tools work standalone for debugging and testing

### Data Flow Architecture
```
Camera → Pose Detection → Angle Calculation → Problem Classification → Alerts
   ↓           ↓               ↓                    ↓                  ↓
Data Logging ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
   ↓
Report Generation
```

## Building Blocks

### 1. camera-capture
**Purpose**: AVFoundation camera session management and frame streaming
**Input**: Camera device selection, resolution, FPS configuration
**Output**: Raw video frames (CVPixelBuffer stream to stdout or files)

**CLI Interface:**
```bash
# Basic usage
camera-capture --device front --fps 30 --resolution 1080p

# Stream to file for testing
camera-capture --output frames/ --format png --duration 10s

# Live stream to next tool
camera-capture --stream | pose-detect --input stream
```

**Core Implementation:**
- `CameraManager.swift`: AVFoundation session configuration
- `FrameStreamer.swift`: Output frame delivery
- `CameraDeviceInfo.swift`: Device enumeration and capabilities
- `FrameFormatConverter.swift`: CVPixelBuffer to various formats

**Test Coverage:**
- Device detection and configuration
- Frame rate consistency (30 FPS ±2%)
- Memory usage < 50MB during streaming
- Graceful error handling for missing cameras

**Performance Requirements:**
- Maintain 30 FPS capture rate
- < 20ms latency from capture to output
- Support for built-in and external cameras
- Background capture capability

---

### 2. pose-detect
**Purpose**: Vision framework wrapper for real-time pose detection
**Input**: Video frames (CVPixelBuffer, images, or camera stream)
**Output**: Pose landmarks in standardized JSON format

**CLI Interface:**
```bash
# Process single image
pose-detect --input image.jpg --output landmarks.json

# Process video frames from directory
pose-detect --input-dir frames/ --output-dir poses/

# Real-time processing from camera stream
camera-capture --stream | pose-detect --input stream --format json
```

**Core Implementation:**
- `VisionPoseProcessor.swift`: Vision framework integration
- `LandmarkExtractor.swift`: Joint position extraction
- `PoseConfidenceValidator.swift`: Quality assessment
- `JSONPoseSerializer.swift`: Standardized output format

**JSON Output Format:**
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "frame_id": 1234,
  "confidence": 0.95,
  "landmarks": {
    "head": {"x": 0.5, "y": 0.3, "confidence": 0.98},
    "neck": {"x": 0.5, "y": 0.4, "confidence": 0.96},
    "rightShoulder": {"x": 0.4, "y": 0.5, "confidence": 0.94},
    "leftShoulder": {"x": 0.6, "y": 0.5, "confidence": 0.93},
    "rightEar": {"x": 0.45, "y": 0.25, "confidence": 0.89},
    "leftEar": {"x": 0.55, "y": 0.25, "confidence": 0.87}
  }
}
```

**Test Coverage:**
- Landmark detection accuracy on reference images
- Performance with 30 FPS input stream
- Error handling for poor lighting/occlusion
- Confidence score validation

**Performance Requirements:**
- Process frames in < 25ms (30 FPS capability)
- Maintain >0.8 confidence for primary landmarks
- Memory usage < 75MB during processing
- CPU usage < 10% on Apple Silicon

---

### 3. angle-calc
**Purpose**: Pure geometric calculations for clinical angle measurements
**Input**: Pose landmarks JSON
**Output**: Clinical angles and measurements JSON

**CLI Interface:**
```bash
# Process single pose
angle-calc --input pose.json --output angles.json

# Batch processing
angle-calc --input-dir poses/ --output-dir angles/

# Real-time calculation
pose-detect --stream | angle-calc --input stream --format json
```

**Core Implementation:**
- `AngleCalculator.swift`: Core geometric calculations
- `ClinicalMeasurements.swift`: Research-validated formulas
- `PostureAngles.swift`: Angle data structures
- `GeometryUtils.swift`: Vector math utilities

**JSON Output Format:**
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "source_confidence": 0.95,
  "measurements": {
    "craniovertebral_angle": {
      "value": 45.3,
      "unit": "degrees",
      "confidence": 0.94,
      "landmarks_used": ["rightEar", "c7"]
    },
    "shoulder_protraction": {
      "left": {"value": 2.8, "unit": "cm", "confidence": 0.91},
      "right": {"value": 3.2, "unit": "cm", "confidence": 0.89}
    },
    "cervical_flexion": {
      "value": 18.7,
      "unit": "degrees", 
      "confidence": 0.87
    },
    "lateral_head_tilt": {
      "value": 3.2,
      "unit": "degrees",
      "direction": "right",
      "confidence": 0.95
    }
  }
}
```

**Clinical Calculations:**
- **Craniovertebral Angle (CVA)**: `atan2(ear.y - c7.y, ear.x - c7.x) * 180/π`
- **Shoulder Protraction**: Horizontal distance from acromion to plumb line
- **Cervical Flexion**: Angle between head and vertical reference
- **Lateral Tilt**: Deviation from vertical using ear positions

**Test Coverage:**
- Mathematical accuracy with known point sets
- Edge case handling (missing landmarks)
- Numerical stability and precision
- Clinical threshold validation

**Performance Requirements:**
- Process pose data in < 5ms
- Memory usage < 10MB
- Deterministic calculations (same input = same output)
- Support for batch processing

---

### 4. posture-classify
**Purpose**: Apply clinical thresholds to classify posture problems
**Input**: Clinical angles JSON
**Output**: Detected posture problems with severity and confidence

**CLI Interface:**
```bash
# Classify single measurement
posture-classify --input angles.json --config clinical-thresholds.json

# Custom thresholds
posture-classify --input angles.json --fhp-threshold 45.0 --severe-threshold 40.0

# Real-time classification
angle-calc --stream | posture-classify --input stream --alert-format json
```

**Core Implementation:**
- `PostureClassifier.swift`: Problem detection logic
- `ClinicalThresholds.swift`: Research-validated thresholds
- `SeverityAssessment.swift`: Problem severity calculation
- `ConfidenceCalculator.swift`: Detection confidence scoring

**JSON Output Format:**
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "session_id": "session-uuid",
  "detected_problems": [
    {
      "type": "forward_head_posture",
      "severity": "moderate",
      "confidence": 0.94,
      "measurements": {
        "craniovertebral_angle": 45.3,
        "threshold": 50.0,
        "deviation": -4.7
      },
      "duration": 35.2,
      "alert_worthy": true
    },
    {
      "type": "rounded_shoulders",
      "severity": "mild", 
      "confidence": 0.87,
      "measurements": {
        "protraction_left": 2.8,
        "protraction_right": 3.2,
        "threshold": 2.5,
        "max_deviation": 0.7
      },
      "duration": 12.8,
      "alert_worthy": false
    }
  ],
  "posture_score": 72,
  "overall_risk": "moderate"
}
```

**Clinical Thresholds (Research-Validated):**
```json
{
  "forward_head_posture": {
    "normal": "> 53°",
    "mild": "50-53°", 
    "moderate": "45-50°",
    "severe": "< 45°"
  },
  "shoulder_protraction": {
    "normal": "< 2.5cm",
    "mild": "2.5-4.0cm",
    "moderate": "4.0-6.0cm", 
    "severe": "> 6.0cm"
  },
  "cervical_flexion": {
    "normal": "< 15°",
    "sustained_threshold": "15°",
    "severe": "> 30°"
  }
}
```

**Test Coverage:**
- Threshold boundary testing
- Severity classification accuracy
- Confidence calculation validation
- Multi-problem detection scenarios

**Performance Requirements:**
- Classification in < 2ms per measurement
- Memory usage < 5MB
- Support for real-time streaming
- Configurable threshold loading

**Detailed Analysis:**
See [POSTURE_ANALYSIS.md](POSTURE_ANALYSIS.md) for comprehensive clinical analysis of all 10 posture patterns, including detection algorithms, confidence frameworks, and reliability assessments for each specific posture problem.

---

### 5. alert-notify
**Purpose**: Generate user notifications for detected posture problems
**Input**: Posture problems JSON
**Output**: Voice alerts, visual notifications, system alerts

**CLI Interface:**
```bash
# Basic alert generation
alert-notify --input problems.json --voice enabled --visual popup

# Custom alert configuration
alert-notify --input problems.json --config alert-preferences.json

# Real-time alerting
posture-classify --stream | alert-notify --input stream --cooldown 60s
```

**Core Implementation:**
- `AlertManager.swift`: Notification coordination
- `VoiceAlerts.swift`: Text-to-speech synthesis
- `VisualIndicators.swift`: On-screen notifications
- `SystemNotifications.swift`: macOS notification center
- `AlertCooldown.swift`: Prevents alert spam

**Alert Configuration:**
```json
{
  "voice_alerts": {
    "enabled": true,
    "language": "en-US",
    "speed": 1.0,
    "phrases": {
      "forward_head": "Please check your head position",
      "rounded_shoulders": "Straighten your shoulders",
      "general": "Consider adjusting your posture"
    }
  },
  "visual_alerts": {
    "enabled": true,
    "style": "subtle",
    "duration": 3.0,
    "position": "top-right"
  },
  "system_notifications": {
    "enabled": false,
    "persistent": false
  },
  "cooldown_periods": {
    "forward_head_posture": 60,
    "rounded_shoulders": 90,
    "default": 45
  }
}
```

**Test Coverage:**
- Alert generation accuracy
- Cooldown period enforcement
- Multi-modal notification testing
- User preference handling

**Performance Requirements:**
- Alert generation in < 10ms
- Non-blocking notification delivery
- Minimal system resource usage
- Graceful degradation if TTS unavailable

---

### 6. data-log
**Purpose**: Persistent storage and retrieval of posture metrics
**Input**: Posture data (angles, problems, alerts)
**Output**: Stored data with efficient querying

**CLI Interface:**
```bash
# Log data to default database
data-log --input problems.json --database ~/.posturekeeper/data.sqlite

# Export data for analysis
data-log --export --format csv --timerange "last 7 days"

# Real-time logging
posture-classify --stream | data-log --input stream --database live.sqlite
```

**Core Implementation:**
- `PostureLogger.swift`: Data persistence coordination
- `SQLiteManager.swift`: Database operations
- `DataModels.swift`: Core data structures
- `QueryBuilder.swift`: Flexible data retrieval
- `DataExporter.swift`: Multiple export formats

**Database Schema:**
```sql
CREATE TABLE posture_sessions (
    id TEXT PRIMARY KEY,
    start_time DATETIME,
    end_time DATETIME,
    total_frames INTEGER,
    average_confidence REAL
);

CREATE TABLE posture_measurements (
    id INTEGER PRIMARY KEY,
    session_id TEXT,
    timestamp DATETIME,
    cva_angle REAL,
    shoulder_protraction_left REAL,
    shoulder_protraction_right REAL,
    cervical_flexion REAL,
    lateral_tilt REAL,
    confidence REAL,
    FOREIGN KEY (session_id) REFERENCES posture_sessions(id)
);

CREATE TABLE detected_problems (
    id INTEGER PRIMARY KEY,
    session_id TEXT,
    timestamp DATETIME,
    problem_type TEXT,
    severity TEXT,
    confidence REAL,
    duration REAL,
    alert_triggered BOOLEAN,
    FOREIGN KEY (session_id) REFERENCES posture_sessions(id)
);
```

**Test Coverage:**
- Database integrity and constraints
- Concurrent write operations
- Data export accuracy
- Query performance with large datasets

**Performance Requirements:**
- Insert operations < 1ms each
- Query response < 10ms for typical operations
- Database size management (rotation/archiving)
- Concurrent access support


---

### 8. report-generate
**Purpose**: Analytics and trend visualization from stored data
**Input**: Historical posture data from database
**Output**: Reports in multiple formats (CSV, PDF, charts)

**CLI Interface:**
```bash
# Generate weekly report
report-generate --timerange "last 7 days" --format pdf --output weekly-report.pdf

# Export raw data
report-generate --timerange "last 30 days" --format csv --include-raw-data

# Health summary
report-generate --summary --format json --include-trends
```

**Core Implementation:**
- `ReportGenerator.swift`: Report coordination
- `TrendAnalyzer.swift`: Statistical analysis
- `ChartGenerator.swift`: Visualization creation
- `HealthMetrics.swift`: Clinical assessment
- `ExportFormatters.swift`: Multiple output formats

**Report Sections:**
1. **Executive Summary**: Overall posture health score
2. **Problem Frequency**: Most common issues and trends
3. **Time Analysis**: Problem patterns by hour/day
4. **Severity Trends**: Improvement or degradation over time
5. **Alert Effectiveness**: Response to notifications
6. **Recommendations**: Personalized improvement suggestions

**Health Metrics:**
```json
{
  "reporting_period": {
    "start": "2024-01-08T00:00:00Z",
    "end": "2024-01-15T00:00:00Z",
    "total_monitoring_hours": 42.5
  },
  "posture_health_score": 78,
  "problem_summary": {
    "forward_head_posture": {
      "frequency": 23.4,
      "average_severity": "moderate", 
      "improvement_trend": "+5.2%"
    },
    "rounded_shoulders": {
      "frequency": 18.7,
      "average_severity": "mild",
      "improvement_trend": "-2.1%"
    }
  },
  "recommendations": [
    "Consider ergonomic monitor positioning",
    "Take posture breaks every 30 minutes",
    "Strengthen neck and shoulder muscles"
  ]
}
```

**Test Coverage:**
- Statistical calculation accuracy
- Report generation performance
- Data visualization correctness
- Export format integrity

**Performance Requirements:**
- Generate reports for 30 days of data in < 5 seconds
- Memory efficient processing of large datasets
- High-quality chart generation
- Multiple concurrent export formats

## Integration Phases

### Phase 1: Core Detection Pipeline (Weeks 1-4)
**Goal**: Establish real-time posture detection capability

**Implementation Order:**
1. `camera-capture` (Week 1)
   - AVFoundation integration
   - Frame streaming capability
   - Performance optimization
   - Basic tests

2. `pose-detect` (Week 1-2)
   - Vision framework integration
   - Landmark extraction
   - JSON output format
   - Accuracy testing

3. `angle-calc` (Week 2-3)
   - Geometric calculations
   - Clinical angle formulas
   - Mathematical validation
   - Performance optimization

4. `posture-classify` (Week 3-4)
   - Clinical threshold application
   - Problem detection logic
   - Confidence scoring
   - Integration testing

**Milestone**: Real-time detection pipeline processing 30 FPS with clinical accuracy

**Pipeline Test:**
```bash
camera-capture --fps 30 | pose-detect --format json | angle-calc --format json | posture-classify --output problems.json
```

### Phase 2: User Experience (Weeks 5-6)
**Goal**: Complete user-facing functionality

**Implementation Order:**
1. `alert-notify` (Week 5)
   - Voice alert system
   - Visual notifications
   - Alert cooldown logic
   - User preferences

2. `camera-calibrate` (Week 6)
   - Interactive calibration
   - Positioning guidance
   - Profile management
   - Validation testing

**Milestone**: Complete monitoring experience with alerts and calibration

### Phase 3: Analytics and Persistence (Weeks 7-8)
**Goal**: Data storage and analysis capabilities

**Implementation Order:**
1. `data-log` (Week 7)
   - Database design
   - Real-time logging
   - Data export
   - Performance optimization

2. `report-generate` (Week 8)
   - Statistical analysis
   - Report generation
   - Visualization
   - Health metrics

**Milestone**: Complete analytics and reporting system

### Phase 4: Main CLI Integration (Weeks 9-10)
**Goal**: Unified PostureKeeper CLI orchestrating all tools

**Main CLI Features:**
- Subcommand structure using Swift ArgumentParser
- Configuration management
- Session orchestration
- Health data integration
- Daemon mode for background monitoring

**CLI Structure:**
```bash
PostureKeeper monitor [options]          # Real-time monitoring
PostureKeeper calibrate [options]        # Camera setup
PostureKeeper config [subcommands]       # Configuration management
PostureKeeper report [options]           # Analytics and reporting
PostureKeeper export [options]           # Data export
PostureKeeper daemon [options]           # Background monitoring
```

**Integration Architecture:**
```swift
@main
struct PostureKeeperCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PostureKeeper",
        abstract: "Real-time posture monitoring for software engineers",
        subcommands: [
            MonitorCommand.self,      // Orchestrates full pipeline
            CalibrationCommand.self,  // Wraps camera-calibrate
            ConfigCommand.self,       // System configuration
            ReportCommand.self,       // Wraps report-generate
            ExportCommand.self,       // Wraps data export
            DaemonCommand.self        # Background monitoring
        ]
    )
}
```

## Development Standards

### Testing Requirements
- **Integration Tests**: Pipeline functionality
- **Performance Tests**: Real-time requirements
- **Clinical Tests**: Accuracy validation with reference data

### Build System
```swift
// Package.swift structure
let package = Package(
    name: "PostureKeeper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PostureKeeper", targets: ["PostureKeeper"]),
        .executable(name: "camera-capture", targets: ["CameraCapture"]),
        .executable(name: "pose-detect", targets: ["PoseDetect"]),
        .executable(name: "angle-calc", targets: ["AngleCalc"]),
        .executable(name: "posture-classify", targets: ["PostureClassify"]),
        .executable(name: "alert-notify", targets: ["AlertNotify"]),
        .executable(name: "data-log", targets: ["DataLog"]),
        .executable(name: "report-generate", targets: ["ReportGenerate"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
    ],
    targets: [
        // Shared library
        .target(name: "PostureCore", dependencies: []),
        
        // Individual tools
        .executableTarget(name: "CameraCapture", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "PoseDetect", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "AngleCalc", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "PostureClassify", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "AlertNotify", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "DataLog", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "ReportGenerate", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        
        // Main CLI
        .executableTarget(name: "PostureKeeper", dependencies: ["PostureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        
        // Tests
        .testTarget(name: "PostureCoreTests", dependencies: ["PostureCore"]),
        .testTarget(name: "CameraCaptureTests", dependencies: ["CameraCapture"]),
        .testTarget(name: "PoseDetectTests", dependencies: ["PoseDetect"]),
        .testTarget(name: "AngleCalcTests", dependencies: ["AngleCalc"]),
        .testTarget(name: "PostureClassifyTests", dependencies: ["PostureClassify"]),
        .testTarget(name: "AlertNotifyTests", dependencies: ["AlertNotify"]),
        .testTarget(name: "DataLogTests", dependencies: ["DataLog"]),
        .testTarget(name: "ReportGenerateTests", dependencies: ["ReportGenerate"])
    ]
)
```

### Quality Gates
Each tool must pass these quality gates before integration:

1. **Functionality**: All core features working
2. **Performance**: Real-time requirements met
3. **Testing**: 90%+ coverage achieved
4. **Documentation**: Complete usage guides
5. **Integration**: Works in pipeline with other tools

## Success Metrics

### Technical Metrics
- **Detection Accuracy**: >85% agreement with clinical assessment
- **Real-time Performance**: 30 FPS processing maintained
- **Memory Efficiency**: <100MB total memory usage
- **CPU Efficiency**: <15% CPU usage on Apple Silicon
- **Test Coverage**: >90% for all components

### User Experience Metrics
- **Calibration Time**: <2 minutes for complete setup
- **Alert Relevance**: <5% false positive rate
- **System Integration**: Seamless macOS integration
- **Battery Impact**: <5% additional battery drain

### Clinical Validation Metrics
- **Forward Head Posture**: >90% detection accuracy
- **Rounded Shoulders**: >85% detection accuracy  
- **Text Neck**: >85% detection accuracy
- **Overall Posture Score**: Correlates with clinical assessment

This modular implementation plan ensures each component is independently tested and validated before integration, leading to a robust, maintainable, and clinically accurate posture monitoring system.

## Additional Documentation

- **[POSTURE_ANALYSIS.md](POSTURE_ANALYSIS.md)** - Comprehensive clinical analysis of all 10 posture patterns with detection algorithms and confidence frameworks
- **[RESEARCH.md](RESEARCH.md)** - Clinical research foundation and evidence-based thresholds
- **[README.md](README.md)** - Project overview and technical architecture
- **[CLAUDE.md](CLAUDE.md)** - Swift development guidelines and coding standards