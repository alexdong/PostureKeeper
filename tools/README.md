# Synthetic Data Generation Setup

## Quick Start with UV

```bash
# Install uv if you haven't already
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment and install dependencies
uv venv
uv pip sync

# Activate environment
source .venv/bin/activate  # On Linux/Mac
# or
.venv\Scripts\activate     # On Windows
```

## Usage

```bash
# Quick test (1 image)
make synth NUM=1

# Generate specific number of images
make synth NUM=100

# Continuous generation for vacation mode (4 days)
make synth
# Press Ctrl+C to stop gracefully
```

## Time Estimates

Using default high-quality settings (SDXL Base, 45 inference steps):

| Images | Time | Use Case |
|--------|------|----------|
| 10 | ~2 minutes | Quick test |
| 100 | ~20 minutes | Small dataset |
| 1,000 | ~3.3 hours | Standard training set |
| 10,000 | ~33 hours | Large dataset (1.5 days) |
| 20,000 | ~66 hours | Vacation mode (3 days) |

## Alternative Models for Different Speed/Quality Tradeoffs

```bash
# Fastest: SDXL-Turbo (2 steps, ~2s/image)
python tools/synth.py --model "stabilityai/sdxl-turbo" --num-images 1000

# High quality (default): SDXL Base (45 steps, ~12s/image)
python tools/synth.py --model "stabilityai/stable-diffusion-xl-base-1.0" --num-images 1000

# Photorealistic: Realistic Vision V6 (40 steps, ~8s/image)
python tools/synth.py --model "SG161222/Realistic_Vision_V6.0_B1_noVAE" --num-images 1000
```

## Memory Usage

With the optimizations in place (model CPU offloading, VAE slicing/tiling), SDXL-Turbo uses approximately:
- **Peak VRAM**: ~6.5GB
- **System RAM**: ~8GB
- **Disk space**: ~10GB for model + ~2GB for 1000 images

## Output Structure

```
datasets/synthetic/
├── interrupt-worthy/     # Severe posture (CVA < 48°)
├── borderline/          # Moderate posture (CVA 48-53°)
├── leave-me-alone/      # Good posture (CVA > 53°)
└── annotations.jsonl    # Complete metadata for each image
```

Each JSONL entry contains:
- Image path and classification
- Full demographic details (age, gender, ethnicity, etc.)
- Posture measurements (CVA angle, description)
- Environment settings (lighting, camera angle)
- Generation parameters (prompt, seed, model)