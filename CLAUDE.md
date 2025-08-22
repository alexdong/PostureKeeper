# Swift Development Guidelines for PostureKeeper

## Project Overview

PostureKeeper is a real-time Swift CLI application that uses Vision framework and AVFoundation to detect posture problems in software engineers. This document provides comprehensive development guidelines for AI agents and developers working on the project.

## Development Environment

### Core Technologies
- **Swift**: 6.1+ with concurrency support, Swift Package Manager
- **Platform**: macOS 15.5+ (Sequoia or later)
- **Frameworks**: Vision, AVFoundation, Core Image
- **CLI**: Swift ArgumentParser
- **Build System**: Swift Package Manager
- **Testing**: XCTest with performance testing
- **Documentation**: DocC for API documentation

## Project Structure

```
PostureKeeper/
├── Package.swift                          # Swift Package configuration
├── README.md                              # Project documentation
├── CLAUDE.md                              # This file - development guidelines
├── LICENSE                                # MIT license
├── Sources/
│   └── PostureKeeper/
│       ├── CLI/
│       │   ├── PostureKeeperCommand.swift    # @main entry point
│       │   ├── ConfigCommand.swift           # Configuration subcommands
│       │   ├── CalibrationCommand.swift      # Camera calibration CLI
│       │   ├── MonitorCommand.swift          # Real-time monitoring
│       │   ├── ReportCommand.swift           # Analytics and reporting
│       │   └── ExportCommand.swift           # Data export functionality
│       ├── Detection/
│       │   ├── PostureDetector.swift         # Core detection coordinator
│       │   ├── AngleCalculator.swift         # Geometric angle calculations
│       │   ├── PostureClassifier.swift       # Problem classification logic
│       │   ├── VisionPoseProcessor.swift     # Vision framework wrapper
│       │   └── PostureThresholds.swift       # Clinical threshold definitions
│       ├── Camera/
│       │   ├── CameraManager.swift           # AVFoundation session management
│       │   ├── CameraCalibrator.swift        # Positioning and setup
│       │   ├── FrameProcessor.swift          # Real-time frame processing
│       │   └── CameraPermissions.swift       # Privacy and permissions
```

## Swift Coding Standards

### Code Style and Conventions
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint for consistent formatting
- Maximum line length: 120 characters
- Use descriptive variable and function names
- Prefer explicit types for clarity in vision/camera code