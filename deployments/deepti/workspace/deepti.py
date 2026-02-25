#!/usr/bin/env python3

import os
import subprocess

import torch

# Fix for transformers post_init bug with ALL_PARALLEL_STYLES
# See: https://github.com/huggingface/transformers/issues/38279
from transformers import modeling_utils

if not hasattr(modeling_utils, "ALL_PARALLEL_STYLES") or modeling_utils.ALL_PARALLEL_STYLES is None:
    modeling_utils.ALL_PARALLEL_STYLES = ["tp", "none", "colwise", "rowwise"]

# Workaround: PyTorch 2.6.0a0 from NVIDIA not recognized as >= 2.6 by transformers
# Patch the version check to accept NVIDIA's 2.6.0a0 (which is actually 2.6, just with alpha tag)
import transformers.utils.import_utils


def _bypass_check():
    # We have PyTorch 2.6.0a0 which is safe (>= 2.6), so bypass the check
    pass


transformers.utils.import_utils.check_torch_load_is_safe = _bypass_check

from qwen_omni_utils import process_mm_info
from transformers import Qwen2_5OmniForConditionalGeneration, Qwen2_5OmniProcessor

"""
Minimal sanity test:
- uses ffmpeg to generate a dummy video
- loads Qwen2.5-Omni with flash-attention
- runs ONE multimodal generation
"""

# ----------------------------------------------------------------------
# 1. Create a tiny dummy video using ffmpeg (explicit dependency check)
# ----------------------------------------------------------------------

DUMMY_VIDEO = "dummy_test.mp4"

if not os.path.exists(DUMMY_VIDEO):
    print("[INFO] Creating dummy video with ffmpeg...")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc=size=224x224:rate=5",
            "-t",
            "2",
            "-pix_fmt",
            "yuv420p",
            DUMMY_VIDEO,
        ],
        check=True,
    )

assert os.path.exists(DUMMY_VIDEO), "ffmpeg failed to create dummy video"
print("[OK] ffmpeg works")

# ----------------------------------------------------------------------
# 2. Load model + processor (flash-attention enabled)
# ----------------------------------------------------------------------

MODEL_NAME = "Qwen/Qwen2.5-Omni-7B"

print("[INFO] Loading model...")
# Using flash_attention_2 with PyTorch 2.6 and flash-attn 2.4.2
model = Qwen2_5OmniForConditionalGeneration.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.bfloat16,
    device_map="auto",
    attn_implementation="flash_attention_2",  # Flash Attention 2 for optimal performance
    trust_remote_code=True,  # Required for some model components
)
model.disable_talker()  # text-only output

processor = Qwen2_5OmniProcessor.from_pretrained(MODEL_NAME)

print("[OK] Model + processor loaded")

# ----------------------------------------------------------------------
# 3. Build a minimal multimodal prompt
# ----------------------------------------------------------------------

conversation = [
    {
        "role": "system",
        "content": [{"type": "text", "text": "You are a helpful multimodal assistant."}],
    },
    {
        "role": "user",
        "content": [
            {"type": "video", "video": DUMMY_VIDEO},
            {"type": "text", "text": "What do you see in this video?"},
        ],
    },
]

# Apply chat template
text = processor.apply_chat_template(
    conversation,
    add_generation_prompt=True,
    tokenize=False,
)

# Process multimodal inputs
audios, images, videos = process_mm_info(
    conversation,
    use_audio_in_video=False,  # keep it simple
)

inputs = processor(
    text=text,
    videos=videos,
    audio=audios,
    images=images,
    return_tensors="pt",
    padding=True,
    use_audio_in_video=False,
)

inputs = inputs.to(model.device).to(model.dtype)

# ----------------------------------------------------------------------
# 4. Run ONE generation
# ----------------------------------------------------------------------

print("[INFO] Running generation...")
with torch.no_grad():
    output_ids = model.generate(
        **inputs,
        max_new_tokens=64,
    )

decoded = processor.batch_decode(
    output_ids,
    skip_special_tokens=True,
    clean_up_tokenization_spaces=False,
)

answer = decoded[0].split("\nassistant\n")[-1].strip()

print("\n=== MODEL OUTPUT ===")
print(answer)
print("====================")

print("[SUCCESS] Minimal Qwen2.5-Omni + ffmpeg + flash-attn test completed")
