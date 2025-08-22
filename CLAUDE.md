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

### Code Style and Conventions
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint for consistent formatting
- Maximum line length: 120 characters
- Use descriptive variable and function names
- Prefer explicit types for clarity in vision/camera code
- Use `assert` statements with clear messages liberally to catch unexpected conditions during development. 
- Avoid `try ... catch`
- Extensive logging can be found for each run as `logs/YYMMDD_HHMMSS.log` for debugging and monitoring
- During debugging, use the `grep` tool to filter log messages.
- Commit to git frequently with clear messages to capture the evolution of the codebase. Run `make lint` and `make test` before each commit.
