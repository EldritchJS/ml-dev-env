import debugpy
import torch

# Listen on port 5678 for debugger connection
debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger to attach...")
debugpy.wait_for_client()
print("Debugger attached!")

# Your code here - this is where you'll set breakpoints
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")

for i in range(torch.cuda.device_count()):
    device_name = torch.cuda.get_device_name(i)
    print(f"GPU {i}: {device_name}")

# Test some GPU operations
x = torch.randn(1000, 1000, device="cuda:0")
y = torch.randn(1000, 1000, device="cuda:0")
z = torch.matmul(x, y)
print(f"Matrix multiplication result shape: {z.shape}")
print(f"Result sum: {z.sum().item():.2f}")

print("Done!")
