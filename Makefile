.PHONY: build run run-debug clean dev lint test

# Default target
build:
	swift build

# Run the application
run: build
	swift run PostureKeeper

# Run with debug flag
run-debug: build
	swift run PostureKeeper --debug

# Development workflow - build, lint, and typecheck
dev: build
	@echo "PostureKeeper built successfully"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Lint (placeholder for future SwiftLint integration)
lint:
	@echo "Linting not yet configured"

# Test (placeholder for future tests)
test:
	@echo "Tests not yet configured"
