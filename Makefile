.PHONY: build run run-debug analyze eval clean dev lint test synth

# Default target
build:
	swift build

# Run the application
run: build
	swift run PostureKeeper

# Run with debug flag
run-debug: build
	swift run PostureKeeper --debug

# Analyze single image (specify IMAGE=path or use latest from .output)
analyze: build
ifdef IMAGE
	swift run PostureKeeper --analyze $(IMAGE)
else
	swift run PostureKeeper --analyze latest
endif

# Evaluate FHP detection on datasets/FHP/ with 3 approaches
eval: build
	swift run PostureKeeper --eval

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

# Generate synthetic training data
# Usage: make synth NUM=10  (generates 10 images)
# Usage: make synth         (runs continuously until stopped)
synth:
ifdef NUM
	@echo "Generating $(NUM) synthetic training images..."
	@python tools/synth.py --num-images $(NUM) --output-dir datasets/synthetic
else
	@echo "Starting continuous synthetic data generation (Ctrl+C to stop)..."
	@python tools/synth.py --continuous --output-dir datasets/synthetic
endif
