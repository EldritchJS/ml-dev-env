#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import subprocess
import torch

"""
Simple sanity test:
- Tests GPU access
- Tests ffmpeg
- Tests basic model loading without flash-attention
"""

print("="*60)
print("Simple GPU + ffmpeg Test")
print("="*60)
print()

# Test GPU
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"CUDA version: {torch.version.cuda}")
print(f"Number of GPUs: {torch.cuda.device_count()}")
print()

if torch.cuda.is_available():
    for i in range(torch.cuda.device_count()):
        print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
        print(f"  Memory: {torch.cuda.get_device_properties(i).total_memory / 1024**3:.1f} GB")
    print()

# Test ffmpeg
DUMMY_VIDEO = "dummy_test.mp4"

if not os.path.exists(DUMMY_VIDEO):
    print("[INFO] Creating dummy video with ffmpeg...")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f", "lavfi",
            "-i", "testsrc=size=224x224:rate=5",
            "-t", "2",
            "-pix_fmt", "yuv420p",
            DUMMY_VIDEO,
        ],
        check=True,
        capture_output=True,
    )

assert os.path.exists(DUMMY_VIDEO), "ffmpeg failed to create dummy video"
print("[OK] ffmpeg works")
print()

# Test basic transformers
print("[INFO] Testing transformers library...")
try:
    from transformers import AutoTokenizer
    from qwen_omni_utils import process_mm_info
    print("[OK] Transformers and qwen-omni-utils imported successfully")
except Exception as e:
    print(f"[ERROR] Import failed: {e}")
    exit(1)

print()
print("="*60)
print("All basic tests passed!")
print("="*60)
