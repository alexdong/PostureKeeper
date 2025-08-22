#!/usr/bin/env python3
"""
Synthetic Training Data Generator for PostureKeeper

PURPOSE:
This script generates synthetic webcam-style images of people with varying degrees of 
Forward Head Posture (FHP) and other posture problems using local diffusion models.
It addresses the critical need for large-scale, diverse training data to build robust
posture detection classifiers.

PROBLEM BEING SOLVED:
- Limited real-world posture data (only 16 example images)
- Need for demographic diversity in training data
- Requirement for precise posture severity labels
- Binary classification training ("interrupt-worthy" vs "leave-me-alone")

APPROACH:
Uses Stable Diffusion with systematic prompt engineering to generate thousands of
synthetic webcam images with controlled variations in:
- Posture severity (CVA angles from 30° to 70°)
- Demographics (age, gender, ethnicity, body type)
- Environmental conditions (lighting, background, camera angle)
- Clinical posture problems (10 types identified in research)

OUTPUT:
- Synthetic images saved to datasets/synthetic/[category]/
- Annotations in datasets/synthetic/annotations.jsonl with:
  - Image path
  - Posture classification (interrupt-worthy/leave-me-alone)
  - Clinical measurements (CVA angle, posture type)
  - Generation metadata (prompt, seed, model)

USAGE:
    make synth NUM=1       # Generate 1 test image
    make synth NUM=10      # Generate 10 images
    make synth             # Run continuously until stopped (4-day vacation mode)

REQUIREMENTS:
    pip install diffusers torch pillow accelerate transformers

NOTES:
- Designed for local execution with GPU (MPS on Mac, CUDA on Linux/Windows)
- Can fallback to CPU but will be significantly slower
- Images generated at 1024x768 (4:3 aspect ratio) for realistic webcam framing
- High quality mode: 45 inference steps for photorealistic results
- Graceful Ctrl+C handling in continuous mode
"""

import json
import random
import argparse
import signal
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import hashlib

try:
    import torch
    from diffusers import StableDiffusionPipeline, DPMSolverMultistepScheduler
    from PIL import Image
except ImportError:
    print("Required packages not installed. Please run:")
    print("pip install diffusers torch pillow accelerate transformers")
    exit(1)

# Optional: BitsAndBytes for quantization
try:
    import bitsandbytes as bnb
    HAS_BITSANDBYTES = True
except ImportError:
    HAS_BITSANDBYTES = False


class PostureDataGenerator:
    """Generates synthetic posture training data using Stable Diffusion."""
    
    # Demographic variations
    AGES = ["teenage", "young adult", "middle-aged", "senior", "in their 20s", "in their 30s", "in their 40s", "in their 50s"]
    GENDERS = ["man", "woman", "person", "male", "female"]
    ETHNICITIES = ["Asian", "Caucasian", "African American", "Hispanic", "Middle Eastern", "South Asian", "mixed ethnicity"]
    BUILDS = ["slim", "average build", "athletic", "heavy-set", "tall", "short", "medium height"]
    HAIR_STYLES = ["short hair", "long hair", "bald", "curly hair", "straight hair", "braided hair", "ponytail", "hair in a bun", "buzz cut"]
    GLASSES = ["wearing glasses", "without glasses", "with thick-framed glasses", "wearing reading glasses", ""]
    
    # Posture descriptions - concise for token limit
    POSTURE_SEVERE = [
        "severe forward head posture looking at screen",
        "extreme neck crane toward monitor",
        "pronounced turtle neck at computer",
        "severe text neck viewing display",
        "head far forward staring at screen"
    ]
    
    POSTURE_MODERATE = [
        "moderate forward head looking at screen",
        "head forward of shoulders viewing monitor",
        "mild turtle neck toward display",
        "slight neck strain at computer",
        "forward lean watching screen"
    ]
    
    POSTURE_NORMAL = [
        "good upright posture at monitor",
        "proper ergonomic position viewing screen",
        "neutral spine looking at display",
        "healthy posture at computer",
        "aligned posture watching screen"
    ]
    
    # Environmental settings
    LIGHTING = ["soft natural daylight", "warm indoor lighting", "cool white light", "gentle ambient lighting", "diffused window light", "soft evening light"]
    BACKGROUNDS = ["home interior", "room", "indoor space", "office", "living space", "workspace"]
    CAMERA_ANGLES = ["laptop webcam angle", "desktop webcam view", "slight upward angle from laptop", "eye-level webcam position"]
    
    # Clothing
    CLOTHING = ["wearing a t-shirt", "in a hoodie", "wearing a button-up shirt", "in a sweater", "wearing casual clothes", "in work attire"]
    COLORS = ["black", "white", "blue", "gray", "navy", "dark colored", "light colored"]
    
    # Activities - concise for token limit
    ACTIVITIES = ["looking at computer screen", "focused on monitor", "working at screen", "viewing display", "staring at monitor", "eyes on screen", "watching computer"]
    EXPRESSIONS = ["focused forward", "concentrated gaze", "attentive look", "eyes forward", "looking straight"]
    
    def __init__(self, model_id: str = "black-forest-labs/FLUX.1-dev", device: Optional[str] = None, use_quantization: bool = False, dry_run: bool = False):
        """Initialize the generator with a specific model.
        
        Recommended models for photorealistic humans (best to worst):
        - black-forest-labs/FLUX.1-dev (best quality, slower - 16GB+ VRAM, 12GB with Q8)
        - stabilityai/stable-diffusion-3-medium-diffusers (excellent, 8GB+ VRAM)
        - SG161222/RealVisXL_V4.0 (photorealistic SDXL, 8GB VRAM)
        - stabilityai/stable-diffusion-xl-base-1.0 (default, fast)
        
        Args:
            model_id: HuggingFace model ID
            device: Device to use (cuda/mps/cpu)
            use_quantization: Enable 8-bit quantization for FLUX (requires bitsandbytes)
            dry_run: If True, skip model loading for prompt generation only
        """
        self.model_id = model_id
        self.use_quantization = use_quantization
        self.dry_run = dry_run
        
        # Detect device
        if device:
            self.device = device
        elif torch.cuda.is_available():
            self.device = "cuda"
        elif torch.backends.mps.is_available():
            self.device = "mps"
            print("Note: MPS (Apple Silicon) detected. Some models may run slower than expected.")
        else:
            self.device = "cpu"
            print("WARNING: Running on CPU will be very slow. GPU strongly recommended.")
        
        # Skip device detection and model loading in dry_run mode
        if self.dry_run:
            print(f"DRY RUN MODE: Skipping model loading")
            self.is_sdxl = "sdxl" in model_id.lower() or "realvis" in model_id.lower()
            self.is_turbo = "turbo" in model_id.lower()
            self.is_lightning = "lightning" in model_id.lower()
            self.is_flux = "flux" in model_id.lower()
            self.is_sd3 = "stable-diffusion-3" in model_id.lower()
            self.pipe = None
            return
        
        print(f"Using device: {self.device}")
        
        # Check model type
        self.is_sdxl = "sdxl" in model_id.lower() or "realvis" in model_id.lower()
        self.is_turbo = "turbo" in model_id.lower()
        self.is_lightning = "lightning" in model_id.lower()
        self.is_flux = "flux" in model_id.lower()
        self.is_sd3 = "stable-diffusion-3" in model_id.lower()
        
        # Initialize pipeline
        print(f"Loading model {model_id}...")
        
        # Import appropriate pipeline
        if self.is_flux:
            from diffusers import FluxPipeline
            
            # Check if quantization is requested and available
            if self.use_quantization and self.device == "cuda":
                if not HAS_BITSANDBYTES:
                    print("WARNING: Quantization requested but bitsandbytes not installed.")
                    print("Install with: pip install bitsandbytes")
                    print("Falling back to fp16...")
                    self.use_quantization = False
                else:
                    print("Using 8-bit quantization for FLUX (reduces VRAM usage)")
            
            if self.device != "cpu":
                if self.use_quantization and HAS_BITSANDBYTES:
                    # Load with 8-bit quantization using bitsandbytes
                    # This reduces memory from ~16GB to ~12GB
                    from transformers import BitsAndBytesConfig
                    
                    quantization_config = BitsAndBytesConfig(
                        load_in_8bit=True,
                        bnb_8bit_compute_dtype=torch.bfloat16
                    )
                    
                    # Load FLUX with transformer quantized
                    self.pipe = FluxPipeline.from_pretrained(
                        model_id,
                        transformer_quantization_config=quantization_config,
                        torch_dtype=torch.bfloat16,
                        use_safetensors=True,
                        device_map="balanced"
                    )
                else:
                    # Standard loading
                    self.pipe = FluxPipeline.from_pretrained(
                        model_id,
                        torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float16,
                        use_safetensors=True
                    )
            else:
                self.pipe = FluxPipeline.from_pretrained(
                    model_id,
                    torch_dtype=torch.float32,
                    use_safetensors=True
                )
        elif self.is_sd3:
            from diffusers import StableDiffusion3Pipeline
            if self.device != "cpu":
                self.pipe = StableDiffusion3Pipeline.from_pretrained(
                    model_id,
                    torch_dtype=torch.float16,
                    use_safetensors=True
                )
            else:
                self.pipe = StableDiffusion3Pipeline.from_pretrained(
                    model_id,
                    torch_dtype=torch.float32,
                    use_safetensors=True
                )
        elif self.is_sdxl:
            from diffusers import DiffusionPipeline
            if self.device != "cpu":
                self.pipe = DiffusionPipeline.from_pretrained(
                    model_id,
                    torch_dtype=torch.float16,
                    use_safetensors=True,
                    variant="fp16" if "base" in model_id.lower() else None,
                    add_watermarker=False
                )
            else:
                self.pipe = DiffusionPipeline.from_pretrained(
                    model_id,
                    torch_dtype=torch.float32,
                    use_safetensors=True,
                    add_watermarker=False
                )
        else:
            self.pipe = StableDiffusionPipeline.from_pretrained(
                model_id,
                torch_dtype=torch.float16 if self.device != "cpu" else torch.float32,
                safety_checker=None,
                requires_safety_checker=False
            )
            # Use faster scheduler for SD1.5
            self.pipe.scheduler = DPMSolverMultistepScheduler.from_config(self.pipe.scheduler.config)
        
        # Memory optimizations
        if self.device == "cuda":
            # FLUX needs more memory, use aggressive offloading
            if self.is_flux:
                # Skip CPU offloading if using quantization (they conflict)
                if not self.use_quantization:
                    self.pipe.enable_model_cpu_offload()
                if hasattr(self.pipe, 'enable_vae_slicing'):
                    self.pipe.enable_vae_slicing()
            # SD3 also benefits from offloading
            elif self.is_sd3:
                self.pipe.enable_model_cpu_offload()
                if hasattr(self.pipe, 'enable_vae_slicing'):
                    self.pipe.enable_vae_slicing()
                if hasattr(self.pipe, 'enable_vae_tiling'):
                    self.pipe.enable_vae_tiling()
            # Standard optimizations for SDXL and others
            else:
                self.pipe.enable_model_cpu_offload()  # Crucial for 8GB VRAM
                if hasattr(self.pipe, 'enable_vae_slicing'):
                    self.pipe.enable_vae_slicing()        # Reduces VAE memory
                if hasattr(self.pipe, 'enable_vae_tiling'):
                    self.pipe.enable_vae_tiling()         # Further VAE optimization
                if hasattr(self.pipe, 'enable_attention_slicing'):
                    self.pipe.enable_attention_slicing()
                
                # SDXL specific optimizations
                if self.is_sdxl and hasattr(self.pipe.unet, 'to'):
                    self.pipe.unet.to(memory_format=torch.channels_last)
        elif self.device == "mps":
            self.pipe = self.pipe.to(self.device)
            if hasattr(self.pipe, 'enable_attention_slicing'):
                self.pipe.enable_attention_slicing()
        else:
            self.pipe = self.pipe.to(self.device)
        
        print("Model loaded successfully!")
        
        # Calculate and display time estimates
        if self.is_flux:
            self.steps = 28  # FLUX works best with 20-50 steps
            time_per_image = 30  # seconds - FLUX is slower but much higher quality
        elif self.is_sd3:
            self.steps = 28  # SD3 recommended steps
            time_per_image = 20  # seconds
        elif self.is_turbo or self.is_lightning:
            self.steps = 2
            time_per_image = 2  # seconds
        elif self.is_sdxl:
            self.steps = 45  # High quality default
            time_per_image = 12  # seconds with high quality
        else:
            self.steps = 40  # High quality for SD1.5
            time_per_image = 8  # seconds
        
        print(f"Estimated generation speed: ~{time_per_image}s per image")
        print(f"1000 images will take approximately {time_per_image * 1000 / 3600:.1f} hours")
    
    def generate_prompt(self, posture_type: str) -> Tuple[str, str, Dict]:
        """Generate a random prompt with metadata for posture type."""
        
        # Select posture severity
        if posture_type == "interrupt-worthy":
            posture_desc = random.choice(self.POSTURE_SEVERE)
            cva_angle = random.randint(30, 48)  # Severe FHP range
        elif posture_type == "borderline":
            posture_desc = random.choice(self.POSTURE_MODERATE)
            cva_angle = random.randint(48, 53)  # Borderline range
        else:  # leave-me-alone
            posture_desc = random.choice(self.POSTURE_NORMAL)
            cva_angle = random.randint(53, 70)  # Normal range
        
        # Build person description
        age = random.choice(self.AGES)
        gender = random.choice(self.GENDERS)
        ethnicity = random.choice(self.ETHNICITIES)
        build = random.choice(self.BUILDS)
        hair = random.choice(self.HAIR_STYLES)
        glasses = random.choice(self.GLASSES)
        
        # Environment
        lighting = random.choice(self.LIGHTING)
        background = random.choice(self.BACKGROUNDS)
        camera = random.choice(self.CAMERA_ANGLES)
        
        # Appearance
        clothing = random.choice(self.CLOTHING)
        color = random.choice(self.COLORS)
        
        # Activity
        activity = random.choice(self.ACTIVITIES)
        expression = random.choice(self.EXPRESSIONS)
        
        # Construct prompt - FLUX and SD3 handle longer, more detailed prompts better
        if self.model_id and ("flux" in self.model_id.lower() or "sd3" in self.model_id.lower()):
            # Detailed prompt for FLUX/SD3 - they follow instructions better with specificity
            prompt_parts = [
                f"A photorealistic webcam photograph of a {age} {ethnicity} {gender}",
                f"sitting at a desk {posture_desc}",
                f"The person has {hair}" if hair else "",
                glasses if glasses else "",
                f"wearing {color} {clothing}" if clothing and color else "",
                f"The person is {activity} with a {expression}",
                f"Shot from a {camera}, showing upper body and head",
                f"Indoor setting with {lighting} and a softly {background} in the background",
                "High quality, sharp focus on the person, natural skin tones",
                "Realistic office or home workspace environment"
            ]
            
            prompt = ". ".join(filter(None, prompt_parts))
            
            # More comprehensive negative prompt for better quality
            negative_prompt = ("cartoon, anime, illustration, painting, drawing, art, sketch, 3d render, "
                             "blurry, out of focus, distorted face, deformed, ugly, mutated, disfigured, "
                             "profile view, looking away from camera, eyes closed, looking down, looking up, "
                             "multiple people, cropped head, cut off, bad anatomy, worst quality, low quality")
        else:
            # Original concise prompt for SDXL/SD1.5 (token limit considerations)
            prompt_parts = [
                f"Webcam photo of {ethnicity} {gender} working in front of a computer or laptop",
                hair,
                glasses,
                posture_desc,
                activity,
                f"{lighting}, blurred background",
                "portrait, looking more or less straight at the screen"
            ]
            
            prompt = ", ".join(filter(None, prompt_parts))
            
            # Concise negative prompt for token limit
            negative_prompt = "cartoon, anime, blurry, distorted, profile view, looking away, looking sideways, eyes closed, looking down, looking up"
        
        metadata = {
            "posture_type": posture_type,
            "cva_angle": cva_angle,
            "demographics": {
                "age": age,
                "gender": gender,
                "ethnicity": ethnicity,
                "build": build,
                "hair": hair,
                "glasses": glasses
            },
            "appearance": {
                "clothing": clothing,
                "color": color
            },
            "environment": {
                "lighting": lighting,
                "background": background,
                "camera": camera
            },
            "context": {
                "activity": activity,
                "expression": expression
            },
            "posture": {
                "description": posture_desc,
                "type": posture_type,
                "cva_angle": cva_angle
            },
            "timestamp": datetime.now().isoformat()
        }
        
        return prompt, negative_prompt, metadata
    
    def generate_image(self, prompt: str, negative_prompt: str, seed: Optional[int] = None) -> Image.Image:
        """Generate a single image from a prompt."""
        if seed is None:
            seed = random.randint(0, 2**32 - 1)
        
        # Create generator with proper device handling
        if self.device == "cpu":
            generator = torch.Generator().manual_seed(seed)
        else:
            generator = torch.Generator(device="cuda" if self.device == "cuda" else "cpu").manual_seed(seed)
        
        # Adjust parameters based on model type
        if self.is_flux:
            # FLUX specific settings for best quality
            guidance_scale = 3.5  # FLUX works best with low guidance
            num_inference_steps = self.steps
        elif self.is_sd3:
            # SD3 specific settings
            guidance_scale = 7.0  # SD3 standard guidance
            num_inference_steps = self.steps
        elif self.is_turbo:
            # SDXL-Turbo specific settings
            guidance_scale = 0.0  # Turbo doesn't use CFG
            num_inference_steps = self.steps
        elif self.is_lightning:
            guidance_scale = 0.0  # Lightning also doesn't need CFG
            num_inference_steps = self.steps
        else:
            guidance_scale = 7.5
            num_inference_steps = self.steps
        
        # Use portrait aspect ratio to match webcam framing
        if self.is_flux:
            height, width = 1024, 768  # FLUX supports high resolution
        elif self.is_sd3:
            height, width = 1024, 768  # SD3 also supports high resolution
        elif self.is_sdxl:
            height, width = 1024, 768  # 4:3 aspect ratio for SDXL
        else:
            height, width = 512, 384  # 4:3 aspect ratio for SD1.5
        
        # Build pipeline arguments
        pipe_kwargs = {
            "prompt": prompt,
            "num_inference_steps": num_inference_steps,
            "guidance_scale": guidance_scale,
            "generator": generator,
            "height": height,
            "width": width
        }
        
        # Add negative prompt only if guidance scale > 0
        if guidance_scale > 0 and negative_prompt:
            pipe_kwargs["negative_prompt"] = negative_prompt
        
        # Generate image based on pipeline type
        image = self.pipe(**pipe_kwargs).images[0]
        
        return image, seed
    
    def generate_dataset(self, num_images: int, output_dir: Path, distribution: Dict[str, float] = None):
        """Generate a full dataset with annotations."""
        
        if distribution is None:
            distribution = {
                "interrupt-worthy": 0.5,  # 40% severe posture
                "leave-me-alone": 0.5     # 40% good posture
            }
        
        output_dir = Path(output_dir)
        annotations_file = output_dir / "annotations.jsonl"
        
        # Create output directories
        for category in distribution.keys():
            (output_dir / category).mkdir(parents=True, exist_ok=True)
        
        annotations = []
        interrupted = False
        
        # Setup graceful interrupt handler
        def signal_handler(sig, frame):
            nonlocal interrupted
            interrupted = True
            print("\n\nInterrupt received. Finishing current image and saving progress...")
        
        signal.signal(signal.SIGINT, signal_handler)
        
        print(f"Generating {'images continuously' if num_images > 10000 else f'{num_images} images'}...")
        print("Press Ctrl+C to stop gracefully.\n")
        
        for i in range(num_images):
            if interrupted:
                break
                
            # Select category based on distribution
            category = random.choices(
                list(distribution.keys()),
                weights=list(distribution.values())
            )[0]
            
            # Generate prompt and metadata
            prompt, negative_prompt, metadata = self.generate_prompt(category)
            
            # Generate image
            try:
                image, seed = self.generate_image(prompt, negative_prompt)
                
                # Create filename from prompt hash
                prompt_hash = hashlib.md5(prompt.encode()).hexdigest()[:8]
                filename = f"{category}_{i:05d}_{prompt_hash}.png"
                filepath = output_dir / category / filename
                
                # Save image
                image.save(filepath)
                
                # Create annotation
                annotation = {
                    "image_path": str(filepath.relative_to(output_dir)),
                    "category": category,
                    "classification": "interrupt-worthy" if category == "interrupt-worthy" else "leave-me-alone",
                    "metadata": metadata,
                    "generation": {
                        "prompt": prompt,
                        "negative_prompt": negative_prompt,
                        "seed": seed,
                        "model": self.model_id
                    }
                }
                
                annotations.append(annotation)
                
                # Write annotations incrementally
                with open(annotations_file, 'a') as f:
                    f.write(json.dumps(annotation) + '\n')
                
                if (i + 1) % 10 == 0:
                    if num_images > 10000:  # Continuous mode
                        print(f"Generated {i + 1} images... (continuous mode)")
                    else:
                        print(f"Generated {i + 1}/{num_images} images...")
                
            except Exception as e:
                import traceback
                print(f"Error generating image {i}: {e}")
                print(f"Traceback: {traceback.format_exc()}")
                continue
        
        print(f"\nDataset generation {'stopped' if interrupted else 'complete'}! Generated {len(annotations)} images.")
        print(f"Annotations saved to: {annotations_file}")
        
        # Print statistics
        stats = {}
        for ann in annotations:
            cat = ann['category']
            stats[cat] = stats.get(cat, 0) + 1
        
        print("\nDataset statistics:")
        for cat, count in stats.items():
            print(f"  {cat}: {count} images ({count/len(annotations)*100:.1f}%)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic posture training data",
        epilog="""
Model recommendations:
  --model black-forest-labs/FLUX.1-dev          # Best quality, 16GB+ VRAM, ~30s/image
  --model black-forest-labs/FLUX.1-dev --quantize  # With Q8: 12GB VRAM, ~35s/image
  --model stabilityai/stable-diffusion-3-medium-diffusers  # Excellent, 8GB+ VRAM, ~20s/image
  --model SG161222/RealVisXL_V4.0              # Photorealistic, 8GB VRAM, ~12s/image
  --model stabilityai/stable-diffusion-xl-base-1.0  # Default, fast, 8GB VRAM, ~12s/image
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--num-images", type=int, help="Number of images to generate (omit for continuous mode)")
    parser.add_argument("--continuous", action="store_true", help="Run continuously until interrupted")
    parser.add_argument("--output-dir", type=str, default="datasets/synthetic", help="Output directory")
    parser.add_argument("--model", type=str, default="SG161222/RealVisXL_V4.0", 
                       help="Diffusion model to use (default: RealVisXL for photorealistic humans)")
    parser.add_argument("--device", type=str, choices=["cuda", "mps", "cpu"], help="Device to use (auto-detect if not specified)")
    parser.add_argument("--quantize", action="store_true", help="Use 8-bit quantization for FLUX models (reduces VRAM)")
    parser.add_argument("--seed", type=int, help="Random seed for reproducibility")
    parser.add_argument("--dry-run", action="store_true", help="Only generate and display prompts without creating images")
    
    args = parser.parse_args()
    
    if args.seed:
        random.seed(args.seed)
        torch.manual_seed(args.seed)
    
    # Handle dry-run mode
    if args.dry_run:
        # Initialize a minimal generator (without loading models)
        generator = PostureDataGenerator(model_id=args.model, device=args.device, use_quantization=args.quantize, dry_run=True)
        
        # Generate and display prompts
        num_samples = args.num_images if args.num_images else 5
        print(f"\n=== DRY RUN MODE: Generating {num_samples} sample prompts ===\n")
        
        distribution = {
            "interrupt-worthy": 0.33,
            "borderline": 0.33,
            "leave-me-alone": 0.33
        }
        
        for i in range(num_samples):
            # Select category based on distribution
            category = random.choices(
                list(distribution.keys()),
                weights=list(distribution.values())
            )[0]
            
            # Generate prompt and metadata
            prompt, negative_prompt, metadata = generator.generate_prompt(category)
            
            print(f"--- Sample {i+1} ---")
            print(f"Category: {category}")
            print(f"Prompt: {prompt}")
            print(f"Negative Prompt: {negative_prompt}")
            print(f"Metadata: {json.dumps(metadata, indent=2)}")
            print()
        
        return
    
    # Initialize generator
    generator = PostureDataGenerator(model_id=args.model, device=args.device, use_quantization=args.quantize)
    
    # Determine mode
    if args.continuous or (args.num_images is None):
        # Continuous mode
        print("Running in continuous mode. Press Ctrl+C to stop.")
        generator.generate_dataset(
            num_images=1000000,  # Effectively infinite
            output_dir=Path(args.output_dir)
        )
    else:
        # Fixed number mode
        generator.generate_dataset(
            num_images=args.num_images,
            output_dir=Path(args.output_dir)
        )


if __name__ == "__main__":
    main()
