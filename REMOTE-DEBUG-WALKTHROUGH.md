# Remote Debugging Walkthrough - Method 3 (debugpy)

This walkthrough demonstrates how to debug Python code running on the OpenShift cluster from your local VSCode.

## What You'll Learn

- How to set up remote debugging with debugpy
- How to attach your local VSCode to code running on the cluster
- How to set breakpoints and step through code executing on 4x H100 GPUs

## Architecture

```
┌─────────────────────┐          ┌──────────────────────┐
│  Your Local VSCode  │          │  OpenShift Cluster   │
│                     │          │                      │
│  - Set breakpoints  │◄────────►│  - Python process    │
│  - Step through code│  Port    │  - debugpy server    │
│  - Inspect variables│  Forward │  - 4x H100 GPUs      │
│                     │  :5678   │                      │
└─────────────────────┘          └──────────────────────┘
```

## Prerequisites

- Local VSCode with Python extension installed
- OpenShift CLI (`oc`) configured
- Pod `ml-dev-env` running in `nccl-test` namespace

## Step-by-Step Instructions

### Step 1: Open Local VSCode

```bash
cd /Users/jschless/taj/cairo/ml-dev-env
code .
```

This opens the ml-dev-env project in VSCode.

### Step 2: Review the Launch Configuration

The file `.vscode/launch.json` has been created with this configuration:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python: Remote Attach to Cluster",
            "type": "python",
            "request": "attach",
            "connect": {
                "host": "localhost",
                "port": 5678
            },
            "pathMappings": [
                {
                    "localRoot": "${workspaceFolder}/workspace",
                    "remoteRoot": "/workspace"
                }
            ],
            "justMyCode": false
        }
    ]
}
```

**Key settings explained:**
- `"type": "python"` - Uses the Python debugger (debugpy protocol)
- `"port": 5678` - Debug server port (we'll forward this from the cluster)
- `"pathMappings"` - Maps local files to remote files so breakpoints work
- `"justMyCode": false` - Allows debugging into library code (PyTorch, etc.)

### Step 3: Open the Test Script in VSCode

Open the file: `workspace/test_debug.py`

This file exists both locally and on the cluster. They're identical, so breakpoints you set locally will work on the remote code.

### Step 4: Set Breakpoints

In `workspace/test_debug.py`, click in the left margin (gutter) to set breakpoints:

**Recommended breakpoints:**
- Line 11: `print(f"CUDA available: {torch.cuda.is_available()}")`
- Line 16: `print(f"GPU {i}: {device_name}")`
- Line 20: `z = torch.matmul(x, y)`

You should see red dots appear where you clicked.

### Step 5: Start Port-Forward (Terminal 1)

Open a new terminal and run:

```bash
oc port-forward -n nccl-test ml-dev-env 5678:5678
```

**Expected output:**
```
Forwarding from 127.0.0.1:5678 -> 5678
Forwarding from [::1]:5678 -> 5678
```

**Leave this running!** This creates a tunnel from your local port 5678 to the pod's port 5678.

### Step 6: Run the Python Script on the Cluster (Terminal 2)

Open another terminal and run:

```bash
oc exec -it ml-dev-env -n nccl-test -- python /workspace/test_debug.py
```

**Expected output:**
```
Waiting for debugger to attach...
```

The script is now paused, waiting for your VSCode to connect.

### Step 7: Attach the Debugger from VSCode

In VSCode:

1. **Click the "Run and Debug" icon** in the left sidebar (or press `Cmd+Shift+D`)
2. **Select "Python: Remote Attach to Cluster"** from the dropdown at the top
3. **Press the green "Start Debugging" button** (or press `F5`)

**What happens:**
- VSCode connects to localhost:5678 (which is forwarded to the pod)
- The script resumes and hits your first breakpoint
- VSCode opens the file and highlights the current line

### Step 8: Debug!

Now you can use all VSCode debugging features:

**Controls:**
- **Continue** (F5) - Run until next breakpoint
- **Step Over** (F10) - Execute current line, don't step into functions
- **Step Into** (F11) - Step into function calls
- **Step Out** (Shift+F11) - Step out of current function
- **Restart** - Restart debugging session
- **Stop** - Stop debugging

**Panels:**
- **Variables** - Inspect local variables, GPU tensors, etc.
- **Watch** - Add expressions to monitor (e.g., `x.shape`, `torch.cuda.memory_allocated()`)
- **Call Stack** - See the function call stack
- **Debug Console** - Run Python expressions in the current context

**Try this:**
1. When stopped at line 20 (`z = torch.matmul(x, y)`), open the Debug Console
2. Type: `x.device`
3. You'll see: `device(type='cuda', index=0)`
4. Type: `torch.cuda.get_device_name(0)`
5. You'll see: `'NVIDIA H100 80GB HBM3'`

### Step 9: Inspect GPU Tensors

When stopped at a breakpoint after the matrix multiplication (line 21), hover over variables:

- Hover over `x` - See tensor shape, device, dtype
- Hover over `z` - See the result tensor

In the Variables panel, expand `z` to see:
- `shape: (1000, 1000)`
- `device: cuda:0`
- `dtype: torch.float32`

You can even see tensor values! Click the expression icon and type:
```python
z[0, 0:5]  # First 5 elements of first row
```

### Step 10: Clean Up

When done debugging:

1. Press **Stop** in VSCode (red square button)
2. In Terminal 2 (where script is running), press `Ctrl+C`
3. In Terminal 1 (port-forward), press `Ctrl+C`

## Real-World Example: Debug Multi-GPU Training

Here's a more realistic example for distributed training:

### Create a Distributed Training Script

```bash
cat << 'EOF' | oc exec -i ml-dev-env -n nccl-test -- tee /workspace/distributed_debug.py
import debugpy
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

# Start debugpy on a unique port per process
rank = 0  # For single process debugging
debug_port = 5678 + rank
debugpy.listen(("0.0.0.0", debug_port))
print(f"Rank {rank} waiting for debugger on port {debug_port}")
debugpy.wait_for_client()
print(f"Debugger attached to rank {rank}")

# Your training code
print(f"Setting up process group...")
# Initialize NCCL (this will use your RoCE RDMA devices!)
torch.distributed.init_process_group(
    backend="nccl",
    init_method="tcp://localhost:23456",
    world_size=1,
    rank=0
)

print(f"Creating model on GPU 0...")
model = torch.nn.Linear(1000, 1000).cuda()
ddp_model = DDP(model, device_ids=[0])

print(f"Creating dummy batch...")
batch = torch.randn(32, 1000, device='cuda:0')

print(f"Forward pass...")
output = ddp_model(batch)
print(f"Output shape: {output.shape}")

print(f"Backward pass...")
loss = output.sum()
loss.backward()

print(f"Gradients computed!")
print(f"Model gradient: {model.weight.grad.shape}")

dist.destroy_process_group()
print("Done!")
EOF
```

Then copy locally and debug the same way!

## Advanced: Debug Multiple GPU Processes

For true multi-GPU debugging, you'd:

1. **Run 4 processes** (one per GPU), each listening on ports 5678, 5679, 5680, 5681
2. **Port-forward all 4 ports:**
   ```bash
   oc port-forward ml-dev-env -n nccl-test 5678:5678 5679:5679 5680:5680 5681:5681
   ```
3. **Create 4 launch configurations** (one per rank)
4. **Attach to each rank separately** to debug distributed training

## Tips & Tricks

### Conditional Breakpoints

Right-click a breakpoint → "Edit Breakpoint" → Add condition:
```python
i == 2  # Only break when loop variable i is 2
```

### Logpoints

Right-click in gutter → "Add Logpoint" → Enter message:
```
GPU {i}: {device_name}
```
Prints to Debug Console without stopping execution.

### Watch Expressions

Add to Watch panel:
- `torch.cuda.memory_allocated() / 1e9` - GPU memory in GB
- `x.is_cuda` - Check if tensor is on GPU
- `x.shape` - Tensor dimensions

### Debug Console Commands

While paused at a breakpoint, run any Python code:
```python
# Check all GPUs
[torch.cuda.get_device_name(i) for i in range(4)]

# Memory usage
torch.cuda.memory_summary()

# Move tensor to different GPU
x_gpu2 = x.to('cuda:2')
```

## Troubleshooting

### "Connection refused" when attaching

**Problem:** VSCode can't connect to localhost:5678

**Solutions:**
1. Check port-forward is running: Look for "Forwarding from 127.0.0.1:5678"
2. Verify script is running: Terminal 2 should show "Waiting for debugger to attach..."
3. Check firewall isn't blocking localhost connections

### "Breakpoint not hit"

**Problem:** Red breakpoint turns gray, never hits

**Solutions:**
1. Verify `pathMappings` in launch.json are correct
2. Make sure local and remote files are identical
3. Try setting breakpoint on a different line with actual code (not comments/blank lines)

### "Variables show `<unavailable>`"

**Problem:** Can't inspect variables

**Solutions:**
1. Set `"justMyCode": false` in launch.json
2. Step into the code, don't just continue
3. Some optimized code may not expose all variables

### Port-forward keeps disconnecting

**Problem:** Port-forward exits after a few minutes

**Solution:** Use a loop:
```bash
while true; do
    oc port-forward -n nccl-test ml-dev-env 5678:5678
    echo "Reconnecting..."
    sleep 2
done
```

## Next Steps

1. ✅ Try the basic example above
2. ✅ Experiment with inspecting GPU tensors
3. ✅ Try the distributed training example
4. ✅ Debug your own ML code on the cluster!

## Why This Method is Powerful

- **Debug production environments:** Test on actual H100 hardware, not your laptop
- **Inspect GPU state:** See exactly what's on the GPU, memory usage, etc.
- **Debug distributed code:** Attach to multiple processes simultaneously
- **No code changes needed:** Just add debugpy listener, no other modifications
- **Full VSCode features:** Breakpoints, watch expressions, call stack, everything

## Comparison to Other Methods

| Method | Pros | Cons |
|--------|------|------|
| **Method 3 (debugpy)** | Full local VSCode, powerful debugging | Requires port-forward, setup |
| Method 1 (code-server) | Easy, in-browser, no setup | Browser-based, less familiar |
| Method 2 (Remote-SSH) | Full VSCode desktop | Requires SSH setup |
| Method 4 (Jupyter) | Great for exploration | Not ideal for debugging scripts |

**Use Method 3 when:**
- You have complex debugging needs
- You're debugging distributed/multi-GPU code
- You want to use your local VSCode setup
- You need to debug long-running training jobs

---

**Ready to try it?** Run the commands in Steps 5-7 and start debugging on the cluster! 🚀
