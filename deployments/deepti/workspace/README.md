# Deepti Workspace

This directory contains test scripts and outputs for Qwen2.5-Omni multimodal model testing.

## Test Scripts

### deepti.py - Full Multimodal Test

Comprehensive test that validates the complete Qwen2.5-Omni pipeline:

**What it does:**
1. Creates a dummy video using ffmpeg (224x224, 2 seconds)
2. Loads Qwen2.5-Omni-7B model with Flash Attention 2
3. Processes multimodal prompt (video + text)
4. Generates response using the model
5. Validates all components work correctly

**Requirements:**
- 4 GPUs (NVIDIA A100 or H100)
- PyTorch >= 2.0
- Flash Attention 2 (optional, recommended)
- ffmpeg installed
- ~20-30GB GPU memory
- Internet access (for model download)

**Usage:**
```bash
# Inside pod
python deepti.py

# Or from outside
oc exec -it deepti-test -- python /workspace/deepti.py
```

**Expected output:**
```
[INFO] Creating dummy video with ffmpeg...
[OK] ffmpeg works
[INFO] Loading model...
[OK] Model + processor loaded
[INFO] Running multimodal generation...
[OK] Generated response: [model output]
```

### deepti-simple.py - Quick Validation

Simplified version for rapid testing and iteration.

**Usage:**
```bash
python deepti-simple.py
```

## Test Outputs

### deepti-test.txt

Sample test output showing expected results from a successful run.

Reference this file to verify your test completed correctly.

## Model Information

### Qwen2.5-Omni-7B

**Model Card**: https://huggingface.co/Qwen/Qwen2.5-Omni-7B

**Capabilities:**
- Text understanding and generation
- Video understanding and description
- Audio transcription
- Multimodal reasoning

**Optimizations:**
- Flash Attention 2 support
- BF16 mixed precision
- Multi-GPU distribution via `device_map="auto"`

## Modifying Tests

### Change Model

Edit `deepti.py` to use a different model:

```python
# Original
MODEL_NAME = "Qwen/Qwen2.5-Omni-7B"

# Try different size
MODEL_NAME = "Qwen/Qwen2.5-Omni-14B"  # Requires more GPU memory
```

### Adjust Video Input

Modify ffmpeg parameters:

```bash
# Larger video
ffmpeg -f lavfi -i testsrc=size=512x512:rate=30 -t 5 video.mp4

# Different pattern
ffmpeg -f lavfi -i mandelbrot=size=224x224:rate=5 -t 2 video.mp4
```

### Custom Prompts

Change the conversation in `deepti.py`:

```python
conversation = [
    {
        "role": "system",
        "content": [{"type": "text", "text": "Custom system prompt here."}],
    },
    {
        "role": "user",
        "content": [
            {"type": "video", "video": DUMMY_VIDEO},
            {"type": "text", "text": "Your custom question?"},
        ],
    },
]
```

## Performance Tips

### Memory Optimization

If you encounter OOM (Out of Memory) errors:

1. **Reduce precision**: Use BF16 (already enabled)
2. **Enable Flash Attention**: Already enabled in deepti.py
3. **Reduce video resolution**: Change ffmpeg size parameter
4. **Use gradient checkpointing**: Add to model loading

### Speed Optimization

To improve inference speed:

1. **Use Flash Attention 2**: Already enabled
2. **Compile model**: Add `torch.compile()` (PyTorch 2.0+)
3. **Batch processing**: Process multiple inputs together
4. **GPU warm-up**: Run a dummy inference first

### GPU Utilization

Monitor GPU usage:

```bash
# Inside pod
nvidia-smi dmon -c 10

# Check memory
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

## Adding New Tests

Create new test scripts in this directory:

```python
#!/usr/bin/env python3
# my_custom_test.py

import torch
from transformers import Qwen2_5OmniForConditionalGeneration

# Your custom test logic here
```

Make it executable and run:

```bash
chmod +x my_custom_test.py
python my_custom_test.py
```

## Debugging

### Enable Debug Output

Add to top of script:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

### CUDA Debugging

Enable CUDA debugging:

```python
import os
os.environ['CUDA_LAUNCH_BLOCKING'] = '1'
```

### Transformers Debug

Enable transformers logging:

```python
import transformers
transformers.logging.set_verbosity_debug()
```

## Common Issues

### Model Download Fails

Check internet connectivity:
```bash
curl -I https://huggingface.co
```

Cache models locally if needed:
```python
model = Qwen2_5OmniForConditionalGeneration.from_pretrained(
    MODEL_NAME,
    cache_dir="/local/path/to/cache",
    ...
)
```

### ffmpeg Not Found

Verify ffmpeg installation:
```bash
which ffmpeg
ffmpeg -version
```

### Flash Attention Errors

Check if compatible GPU:
```bash
nvidia-smi --query-gpu=compute_cap --format=csv
```

Needs compute capability >= 8.0 (Ampere or newer).

## Resources

- **Qwen Documentation**: https://github.com/QwenLM/Qwen
- **Transformers Docs**: https://huggingface.co/docs/transformers/
- **Flash Attention**: https://github.com/Dao-AILab/flash-attention
- **ffmpeg Guide**: https://ffmpeg.org/documentation.html
