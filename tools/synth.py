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


class PostureDataGenerator:
    """Generates synthetic posture training data using Stable Diffusion."""
    
    # Demographic variations
    AGES = ["teenage", "young adult", "middle-aged", "senior", "in their 20s", "in their 30s", "in their 40s", "in their 50s"]
    GENDERS = ["man", "woman", "person", "male", "female"]
    ETHNICITIES = ["Asian", "Caucasian", "African American", "Hispanic", "Middle Eastern", "South Asian", "mixed ethnicity"]
    BUILDS = ["slim", "average build", "athletic", "heavy-set", "tall", "short", "medium height"]
    HAIR_STYLES = ["short hair", "long hair", "bald", "curly hair", "straight hair", "braided hair", "ponytail", "hair in a bun", "buzz cut"]
    GLASSES = ["wearing glasses", "without glasses", "with thick-framed glasses", "wearing reading glasses", ""]
    
    # Posture descriptions
    POSTURE_SEVERE = [
        "severe forward head posture with chin jutting forward",
        "extreme neck crane toward screen with head far forward",
        "pronounced turtle neck posture with compressed cervical spine",
        "severe text neck with head tilted down at sharp angle",
        "extreme forward head position with craniovertebral angle less than 45 degrees"
    ]
    
    POSTURE_MODERATE = [
        "moderate forward head posture",
        "noticeable head forward of shoulders",
        "mild turtle neck with head pushed forward",
        "some neck strain with forward positioning",
        "craniovertebral angle around 50 degrees"
    ]
    
    POSTURE_NORMAL = [
        "good upright posture with head aligned over shoulders",
        "proper ergonomic sitting position",
        "neutral spine alignment with head balanced",
        "healthy posture with ears aligned over shoulders",
        "correct craniovertebral angle over 55 degrees"
    ]
    
    # Environmental settings
    LIGHTING = ["soft natural daylight", "warm indoor lighting", "cool white light", "gentle ambient lighting", "diffused window light", "soft evening light"]
    BACKGROUNDS = ["home interior", "room", "indoor space", "office", "living space", "workspace"]
    CAMERA_ANGLES = ["laptop webcam angle", "desktop webcam view", "slight upward angle from laptop", "eye-level webcam position"]
    
    # Clothing
    CLOTHING = ["wearing a t-shirt", "in a hoodie", "wearing a button-up shirt", "in a sweater", "wearing casual clothes", "in work attire"]
    COLORS = ["black", "white", "blue", "gray", "navy", "dark colored", "light colored"]
    
    # Activities
    ACTIVITIES = ["at computer", "at desk", "working", "in video call", "at workstation"]
    EXPRESSIONS = ["neutral expression", "natural look", "relaxed face", "casual expression", "normal expression"]
    
    def __init__(self, model_id: str = "stabilityai/stable-diffusion-xl-base-1.0", device: Optional[str] = None):
        """Initialize the generator with a specific model."""
        self.model_id = model_id
        
        # Detect device
        if device:
            self.device = device
        elif torch.cuda.is_available():
            self.device = "cuda"
        elif torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"
            print("WARNING: Running on CPU will be slow. GPU recommended.")
        
        print(f"Using device: {self.device}")
        
        # Check if SDXL model
        self.is_sdxl = "sdxl" in model_id.lower()
        self.is_turbo = "turbo" in model_id.lower()
        self.is_lightning = "lightning" in model_id.lower()
        
        # Initialize pipeline
        print(f"Loading model {model_id}...")
        
        # Import appropriate pipeline
        if self.is_sdxl:
            from diffusers import AutoPipelineForText2Image
            self.pipe = AutoPipelineForText2Image.from_pretrained(
                model_id,
                torch_dtype=torch.float16 if self.device != "cpu" else torch.float32,
                variant="fp16" if self.device != "cpu" else None,
                use_safetensors=True
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
        
        # Memory optimizations for 8GB cards
        if self.device == "cuda":
            self.pipe.enable_model_cpu_offload()  # Crucial for 8GB VRAM
            self.pipe.enable_vae_slicing()        # Reduces VAE memory
            self.pipe.enable_vae_tiling()         # Further VAE optimization
            if hasattr(self.pipe, 'enable_attention_slicing'):
                self.pipe.enable_attention_slicing()
            
            # SDXL specific optimizations
            if self.is_sdxl and hasattr(self.pipe.unet, 'to'):
                self.pipe.unet.to(memory_format=torch.channels_last)
        elif self.device == "mps":
            self.pipe = self.pipe.to(self.device)
            self.pipe.enable_attention_slicing()
        else:
            self.pipe = self.pipe.to(self.device)
        
        print("Model loaded successfully!")
        
        # Calculate and display time estimates
        if self.is_turbo or self.is_lightning:
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
    
    def generate_prompt(self, posture_type: str) -> Tuple[str, Dict]:
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
        
        # Construct prompt
        prompt_parts = [
            f"Webcam selfie photo of {age} {ethnicity} {gender}",
            f"{build} with {hair}",
            glasses,
            f"{clothing} in {color}",
            posture_desc,
            activity,
            expression,
            f"with {lighting}",
            f"heavily blurred {background} background with bokeh",
            camera,
            "head and shoulders portrait, shallow depth of field, realistic webcam quality"
        ]
        
        prompt = ", ".join(filter(None, prompt_parts))
        
        # Negative prompt to avoid unwanted elements
        negative_prompt = "cartoon, anime, drawing, sketch, painting, artistic, blurry face, low quality, distorted face, extra limbs, bad anatomy, full body, wide shot, zoomed out, multiple people, profile view"
        
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
        if self.is_turbo:
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
        if self.is_sdxl:
            height, width = 1024, 768  # 4:3 aspect ratio for SDXL
        else:
            height, width = 512, 384  # 4:3 aspect ratio for SD1.5
        
        image = self.pipe(
            prompt=prompt,
            negative_prompt=negative_prompt if guidance_scale > 0 else None,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            generator=generator,
            height=height,
            width=width
        ).images[0]
        
        return image, seed
    
    def generate_dataset(self, num_images: int, output_dir: Path, distribution: Dict[str, float] = None):
        """Generate a full dataset with annotations."""
        
        if distribution is None:
            distribution = {
                "interrupt-worthy": 0.4,  # 40% severe posture
                "borderline": 0.2,        # 20% borderline cases
                "leave-me-alone": 0.4      # 40% good posture
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
                print(f"Error generating image {i}: {e}")
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
    parser = argparse.ArgumentParser(description="Generate synthetic posture training data")
    parser.add_argument("--num-images", type=int, help="Number of images to generate (omit for continuous mode)")
    parser.add_argument("--continuous", action="store_true", help="Run continuously until interrupted")
    parser.add_argument("--output-dir", type=str, default="datasets/synthetic", help="Output directory")
    parser.add_argument("--model", type=str, default="stabilityai/stable-diffusion-xl-base-1.0", help="Diffusion model to use")
    parser.add_argument("--device", type=str, choices=["cuda", "mps", "cpu"], help="Device to use (auto-detect if not specified)")
    parser.add_argument("--seed", type=int, help="Random seed for reproducibility")
    
    args = parser.parse_args()
    
    if args.seed:
        random.seed(args.seed)
        torch.manual_seed(args.seed)
    
    # Initialize generator
    generator = PostureDataGenerator(model_id=args.model, device=args.device)
    
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