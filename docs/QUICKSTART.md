# Quick Start Guide

## TL;DR - Get Running in 3 Commands

> **Note:** The container image should already be built by your administrator.
> If you need to build it yourself, see [BUILD-ON-CLUSTER.md](BUILD-ON-CLUSTER.md).

> **Important:** The environment uses **NumPy 1.26.4** (not 2.x) for optimal compatibility with PyTorch and ML packages.

```bash
# 1. Deploy everything
make deploy

# 2. Test GPUs
make test

# 3. Open shell
make shell
```

**Optional:** Get VSCode URL with `make vscode`

## Step-by-Step Deployment

### 1. Prerequisites

Ensure you have:

- [ ] OpenShift CLI (`oc`) installed
- [ ] Logged into your OpenShift cluster
- [ ] Access to target namespace (default: `nccl-test`)
- [ ] GPU nodes available in your cluster

```bash
# Check cluster access
oc whoami

# Create/use namespace (default: nccl-test)
oc new-project nccl-test
# Or use existing: oc project nccl-test

# Check GPU nodes
oc get nodes -l 'node.kubernetes.io/instance-type'
```

### 1.1. Configure Namespace (Optional)

The default namespace is `nccl-test`, but you can use any namespace:

**Option A: Environment variable (one-time)**

```bash
NAMESPACE=my-ml-project make deploy
```

**Option B: Export (persistent in session)**

```bash
export NAMESPACE=my-ml-project
make deploy
make status
make shell
```

**Option C: Use deploy script**

```bash
NAMESPACE=my-ml-project ./scripts/deploy.sh deploy
```

**Option D: Create .env file**

```bash
cp .env.example .env
# Edit .env and change NAMESPACE=my-namespace
source .env
make deploy
```

> **Note:** If the container image doesn't exist yet, an administrator will need to build it first.
> See [BUILD-ON-CLUSTER.md](BUILD-ON-CLUSTER.md) for build instructions (admin only).

### 2. Deploy Environment

```bash
# Deploy everything
make deploy

# This will:
# - Create 2 PVCs (workspace: 100GB, datasets: 500GB)
# - Deploy pod with 4 GPUs
# - Create services and routes
# - Wait for pod to be ready
```

### 3. Verify Deployment

```bash
# Check everything
make status

# Should show:
# - Pod: Running
# - Build: Complete
# - PVCs: Bound
# - Routes: 3 routes created
```

### 4. Access Development Environment

**Option A: VSCode in Browser**

```bash
make vscode
# Opens browser-based VSCode
# Go to the URL shown
```

**Option B: Shell Access**

```bash
make shell
# Direct terminal access
# Run: nvidia-smi
```

**Option C: Jupyter Notebook**

```bash
make jupyter
# Starts Jupyter server
# Go to the URL shown
```

## Common Tasks

### Run GPU Tests

```bash
# Test all GPUs and NCCL
make test

# Check GPU topology
make gpu-info
```

### Start a Training Job

```bash
# Shell into pod
make shell

# Inside pod:
cd /workspace

# Clone your project
git clone https://github.com/your/project.git

# Single GPU training
python train.py

# Multi-GPU with DeepSpeed
deepspeed --num_gpus=4 train.py --deepspeed ds_config.json

# Multi-GPU with torchrun
torchrun --nproc_per_node=4 train.py
```

### Copy Files In/Out

```bash
# Copy file to pod
oc cp local_file.py nccl-test/ml-dev-env:/workspace/

# Copy from pod
oc cp nccl-test/ml-dev-env:/workspace/model.pt ./local_model.pt

# Copy entire directory
oc cp my_project/ nccl-test/ml-dev-env:/workspace/
```

### Download Data from URLs

Download datasets directly to the pod (faster than local download + upload):

```bash
# Using wget
oc exec ml-dev-env -n nccl-test -- \
  wget -P /datasets/ https://example.com/dataset.tar.gz

# Using curl with progress bar
oc exec ml-dev-env -n nccl-test -- \
  curl -# -L -o /datasets/data.zip https://example.com/data.zip

# Download and extract in one step
oc exec ml-dev-env -n nccl-test -- \
  bash -c "wget -O- https://example.com/data.tar.gz | tar -xzf - -C /datasets/"
```

**From HuggingFace:**

```bash
# Install huggingface-hub if needed
oc exec ml-dev-env -n nccl-test -- pip install huggingface-hub

# Download dataset
oc exec ml-dev-env -n nccl-test -- \
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='username/dataset-name',
    repo_type='dataset',
    local_dir='/datasets/my-dataset'
)
"
```

**From Google Drive:**

```bash
# Install gdown
oc exec ml-dev-env -n nccl-test -- pip install gdown

# Download file (replace FILE_ID)
oc exec ml-dev-env -n nccl-test -- \
  gdown https://drive.google.com/uc?id=FILE_ID -O /datasets/file.zip
```

### Monitor Training

```bash
# Watch GPU usage
oc exec ml-dev-env -n nccl-test -- watch -n 1 nvidia-smi

# Follow logs
make logs

# Or tail logs
oc logs -f ml-dev-env -n nccl-test
```

### Use TensorBoard

```bash
# In your training code, log to /workspace/runs/experiment1

# Start TensorBoard (in pod or via exec)
tensorboard --logdir=/workspace/runs --bind_all

# Get URL
TENSORBOARD_URL=$(oc get route ml-dev-tensorboard -n nccl-test -o jsonpath='{.spec.host}')
echo "TensorBoard: https://$TENSORBOARD_URL"
```

## Debugging

### Pod Won't Start

```bash
# Check events
oc describe pod ml-dev-env -n nccl-test

# Common issues:
# - No GPU nodes available
# - PVCs not bound
# - Image pull errors
```

### No GPUs Detected

```bash
# Check GPU allocation
oc describe pod ml-dev-env -n nccl-test | grep -A 5 "Limits"

# Should show:
#   nvidia.com/gpu: 4

# Inside pod, check:
nvidia-smi
# Should show 4 GPUs
```

### RDMA Not Working

```bash
# Check if host network is enabled
oc get pod ml-dev-env -n nccl-test -o yaml | grep hostNetwork
# Should show: hostNetwork: true

# Inside pod:
ibstat
# Should show InfiniBand devices

# If not found:
# - Host network may not be enabled
# - Node may not have IB devices
# - May need to run on specific nodes
```

### Build Fails

```bash
# Check build logs
oc logs -f bc/ml-dev-env

# Common failures:
# - flash-attn compilation (needs lots of memory)
# - Network timeouts (PyPI)

# Retry build:
oc start-build ml-dev-env

# If flash-attn fails, you can remove it from the BuildConfig
```

## Development Workflow with Makefile

The fastest way to develop and debug is using the Makefile commands:

### Quick Start - Automated Dev Session

```bash
# Start everything in one command (sync + port-forward + watch)
make dev-session
```

This automatically:
1. Syncs your local code to the pod
2. Watches for changes and auto-syncs
3. Sets up port-forwarding for debugging (port 5678)
4. Keeps everything running

**See [QUICK-DEV-GUIDE.md](QUICK-DEV-GUIDE.md) for complete details**

### Individual Commands

```bash
# One-time code sync
make sync-once

# Auto-sync on file changes (watch mode)
make sync-code

# Port-forward for debugging
make port-forward

# Shell into pod
make shell
```

### Configuration

Customize namespace, pod name, directories:

```bash
# Set environment variables
export NAMESPACE=nccl-test
export POD_NAME=ml-dev-env
export LOCAL_DIR=./workspace
export REMOTE_DIR=/workspace
export DEBUG_PORT=5678

# Then use Makefile commands
make dev-session
```

## VSCode Debugging Setup

### Quick Setup

1. **Install VSCode Python extension** - See [VSCODE-SETUP.md](VSCODE-SETUP.md)
2. **Start dev session** - `make dev-session` (auto-syncs code + port-forwards)
3. **Set breakpoints** in your Python files
4. **Press F5** in VSCode to attach debugger

### Debugging Controls

Once attached to the debugger:

- **F10** - Step Over (execute current line)
- **F11** - Step Into (enter function calls)
- **Shift+F11** - Step Out (exit current function)
- **F5** - Continue (run until next breakpoint)
- **Shift+F5** - Stop Debugging

### Debug Console

At the bottom, use the Debug Console to run commands while paused:

```python
# Check GPU memory
>>> import torch
>>> torch.cuda.memory_allocated(0) / 1024**3  # GB

# Inspect variables
>>> print(tensor.shape)
>>> type(model)

# Check all GPUs
>>> for i in range(4):
...     print(f"GPU {i}: {torch.cuda.memory_allocated(i) / 1024**3:.2f} GB")
```

### Detailed Guides

For step-by-step debugging tutorials, see:
- **[REMOTE-DEBUG-WALKTHROUGH.md](REMOTE-DEBUG-WALKTHROUGH.md)** - Complete walkthrough
- **[VSCODE-DEBUG-GUIDE.md](VSCODE-DEBUG-GUIDE.md)** - All debugging methods
- **[VSCODE-DEBUG-TROUBLESHOOTING.md](VSCODE-DEBUG-TROUBLESHOOTING.md)** - Common issues

## Example Workflows

### Fine-tune LLaMA with LLaMAFactory

```bash
make shell

# Inside pod:
cd /workspace
git clone https://github.com/hiyouga/LLaMA-Factory.git
cd LLaMA-Factory

# Edit config, then run:
deepspeed --num_gpus=4 src/train_bash.py \
  --deepspeed examples/deepspeed/ds_config.json \
  --model_name_or_path meta-llama/Llama-2-7b-hf \
  --output_dir /workspace/output
```

### Video Processing

```bash
# Process video with ffmpeg
ffmpeg -i input.mp4 -vf scale=512:512 output.mp4

# Use VideoLLaMA2
python << 'EOF'
import torch
from transformers import AutoModel

model = AutoModel.from_pretrained("DAMO-NLP-SG/VideoLLaMA2-7B")
model = model.cuda()
# Your code here
EOF
```

### Distributed Training

```python
# train.py
import torch
import torch.distributed as dist

def main():
    dist.init_process_group(backend='nccl')
    local_rank = int(os.environ['LOCAL_RANK'])
    torch.cuda.set_device(local_rank)

    model = YourModel().cuda()
    model = torch.nn.parallel.DistributedDataParallel(model)

    # Training loop
    ...

if __name__ == "__main__":
    main()
```

Run:

```bash
torchrun --nproc_per_node=4 train.py
```

## Performance Tips

### Multi-GPU Training

```bash
# Check GPU topology first
nvidia-smi topo -m

# For best performance:
# - Use all GPUs on a single node
# - Enable host networking (already done)
# - Use NCCL backend
# - Enable GPUDirect RDMA (already configured)
```

### Optimize Batch Size

```python
# Find optimal batch size
import torch

def find_max_batch_size(model, input_shape):
    batch_size = 1
    while True:
        try:
            x = torch.randn(batch_size, *input_shape).cuda()
            y = model(x)
            del x, y
            torch.cuda.empty_cache()
            batch_size *= 2
        except RuntimeError:
            return batch_size // 2
```

### Use Mixed Precision

```python
# Automatic mixed precision
from torch.cuda.amp import autocast, GradScaler

scaler = GradScaler()

for batch in dataloader:
    with autocast():
        output = model(batch)
        loss = criterion(output, target)

    scaler.scale(loss).backward()
    scaler.step(optimizer)
    scaler.update()
```

## Cleanup

### Remove Everything

```bash
# This will delete:
# - Pod
# - Services/Routes
# - PVCs (all your data!)
# - BuildConfig

make clean
```

### Keep Data, Remove Pod

```bash
# Just delete pod
oc delete pod ml-dev-env -n nccl-test

# Redeploy later
make deploy
```

## Troubleshooting Checklist

- [ ] `oc whoami` - logged into cluster?
- [ ] `oc project nccl-test` - in correct namespace?
- [ ] `make status` - what's the current state?
- [ ] `make logs` - any errors in pod logs?
- [ ] `make gpu-info` - are GPUs detected?
- [ ] `oc get pvc` - are PVCs bound?
- [ ] `oc get routes` - are routes created?

## Getting Help

1. Check logs: `make logs`
2. Check status: `make status`
3. Check GPU info: `make gpu-info`
4. Describe pod: `oc describe pod ml-dev-env -n nccl-test`
5. Check events: `oc get events -n nccl-test --sort-by='.lastTimestamp'`

## Next Steps

Once everything is running:

1. ✅ Clone your code to `/workspace`
2. ✅ Download datasets to `/datasets`
3. ✅ Configure experiment tracking (wandb, tensorboard)
4. ✅ Start training!
5. ✅ Monitor with `make logs` or TensorBoard

Happy training! 🚀
