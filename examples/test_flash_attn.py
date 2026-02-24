import debugpy

# Listen on port 5678 for debugger connection
debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger to attach...")
debugpy.wait_for_client()
print("Debugger attached!")

# Your code here
from flash_attn import flash_attn_func
import torch

print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")

for i in range(torch.cuda.device_count()):
    print(f"GPU {i}: {torch.cuda.get_device_name(i)}")

# Test flash-attn
q = k = v = torch.randn(1, 512, 8, 64, device="cuda", dtype=torch.float16)
out = flash_attn_func(q, k, v)
print(f"flash-attn output: {out.shape}")
