# ML Development Environment for OpenShift

A comprehensive GPU-accelerated machine learning development environment with **multi-node distributed training** and RDMA support.

## 🚀 Two Deployment Modes

### Single-Node (4 GPUs)
Development and testing on one node with 4x H100 GPUs.

### **Multi-Node (16 GPUs) - NEW!**
Distributed training across **4 nodes × 4 GPUs = 16 H100s** using DeepSpeed.

**Two networking modes available:**
- **RDMA/RoCE** (faster, requires InfiniBand) - See [MULTI-NODE-QUICKSTART.md](docs/MULTI-NODE-QUICKSTART.md)
- **TCP/Ethernet** (slower, works anywhere) - See [MULTI-NODE-TCP-GUIDE.md](docs/MULTI-NODE-TCP-GUIDE.md)

## Features

### ML Frameworks & Libraries
- ✅ **LLaMAFactory** - Efficient fine-tuning of large language models
- ✅ **VideoLLaMA2** - Video understanding with LLMs
- ✅ **EasyR1** - Reinforcement learning tools
- ✅ **transformers** - Hugging Face transformers library
- ✅ **flash-attn** - Flash Attention for efficient attention computation
- ✅ **deepspeed** - Distributed training optimization
- ✅ **PyTorch 2.5.0** with CUDA 12.6 support
- ✅ **NumPy 1.26.4** - Pinned to 1.x for package compatibility
- ✅ **ffmpeg** - Video/audio processing

### Development Tools
- ✅ **VSCode Server (code-server)** - Browser-based IDE with debugging
- ✅ **Jupyter Notebook** - Interactive development
- ✅ **TensorBoard** - Training visualization
- ✅ **debugpy** - Python debugging
- ✅ **wandb** - Experiment tracking

### Multi-GPU & Multi-Node Support
- ✅ **Single-node:** 4x NVIDIA H100 GPUs
- ✅ **Multi-node:** 4 nodes × 4 GPUs = 16 H100s with DeepSpeed
- ✅ **RDMA/RoCE** networking (mlx5_6,7,10,11 on net1-4)
- ✅ **NCCL** with GPUDirect RDMA for optimal performance
- ✅ **DeepSpeed** ZeRO-2/3 optimization
- ✅ **StatefulSet** for distributed training pods
- ✅ **GPU topology** aware configuration

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   OpenShift Cluster                 │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │          ML Development Pod                   │ │
│  │                                               │ │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────────┐ │ │
│  │  │ VSCode  │  │ Jupyter │  │ TensorBoard  │ │ │
│  │  │  :8080  │  │  :8888  │  │    :6006     │ │ │
│  │  └─────────┘  └─────────┘  └──────────────┘ │ │
│  │                                               │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │   Python 3.10 Environment               │ │ │
│  │  │   - PyTorch + CUDA                      │ │ │
│  │  │   - Transformers, DeepSpeed             │ │ │
│  │  │   - LLaMAFactory, VideoLLaMA2           │ │ │
│  │  │   - Flash Attention                     │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  │                                               │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │   GPU Resources (4x H100)               │ │ │
│  │  │   - CUDA 12.1                           │ │ │
│  │  │   - NCCL with GPUDirect RDMA            │ │ │
│  │  │   - InfiniBand (mlx5)                   │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  │                                               │ │
│  │  ┌─────────────┐  ┌─────────────────────┐   │ │
│  │  │  Workspace  │  │     Datasets        │   │ │
│  │  │   (100GB)   │  │      (500GB)        │   │ │
│  │  └─────────────┘  └─────────────────────┘   │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  Routes (HTTPS):                                    │
│  - ml-dev-vscode.apps.cluster.com                  │
│  - ml-dev-jupyter.apps.cluster.com                 │
│  - ml-dev-tensorboard.apps.cluster.com             │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### 0. Configure Namespace (Optional)

By default, all resources are deployed to the `nccl-test` namespace. To use a different namespace:

```bash
# Option 1: Set via environment variable
export NAMESPACE=my-ml-namespace

# Option 2: Pass to make commands
NAMESPACE=my-ml-namespace make deploy

# Option 3: Use deploy script
NAMESPACE=my-ml-namespace ./scripts/deploy.sh deploy

# Option 4: Create .env file
cp .env.example .env
# Edit .env: NAMESPACE=my-namespace
source .env
```

> **Note:** The container image should already be built by your administrator.
> If you need to build it yourself, see [BUILD-ON-CLUSTER.md](docs/BUILD-ON-CLUSTER.md).

### 1. Create Persistent Storage

```bash
# Create PVCs for workspace and datasets
oc apply -f k8s/pvcs.yaml

# Verify PVCs
oc get pvc
```

### 2. Deploy the Development Environment

```bash
# Deploy the pod
oc apply -f k8s/pod-multi-gpu.yaml

# Wait for pod to be ready
oc wait --for=condition=Ready pod/ml-dev-env --timeout=300s

# Check pod logs
oc logs ml-dev-env
```

### 3. Create Services and Routes

```bash
# Create service and routes for VSCode, Jupyter, TensorBoard
oc apply -f k8s/service.yaml

# Get the URLs
oc get routes
```

### 4. Access Development Environment

**VSCode (Browser-based IDE):**
```bash
# Get the URL
VSCode_URL=$(oc get route ml-dev-vscode -o jsonpath='{.spec.host}')
echo "VSCode: https://$VSCode_URL"
```

**Jupyter Notebook:**
```bash
# Start Jupyter in the pod
oc exec -it ml-dev-env -- bash -c "jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root &"

# Get the URL
JUPYTER_URL=$(oc get route ml-dev-jupyter -o jsonpath='{.spec.host}')
echo "Jupyter: https://$JUPYTER_URL"
```

**Shell Access:**
```bash
# Direct shell access
oc rsh ml-dev-env
```

## Configuration

### GPU Configuration

The pod is configured to use **4 GPUs** by default. To change:

Edit `k8s/pod-multi-gpu.yaml`:
```yaml
resources:
  requests:
    nvidia.com/gpu: 2  # Change to desired number
  limits:
    nvidia.com/gpu: 2
```

### NCCL Configuration

NCCL is pre-configured for optimal RDMA performance:

```bash
NCCL_DEBUG=INFO                  # Verbose logging
NCCL_IB_DISABLE=0                # Enable InfiniBand
NCCL_IB_HCA=mlx5_0,mlx5_1,...   # Mellanox adapters
NCCL_IB_GID_INDEX=3              # RoCE v2
NCCL_NET_GDR_LEVEL=5             # GPUDirect RDMA
```

To adjust, edit the `env` section in `k8s/pod-multi-gpu.yaml`.

### Storage Configuration

Two PVCs are created:
- **ml-dev-workspace** (100GB): Your code, models, checkpoints
- **ml-datasets** (500GB): Training datasets

To adjust sizes, edit `k8s/pvcs.yaml`.

## VSCode Debugging

### 1. Install Extensions in VSCode

Once VSCode is open in browser, install:
- Python
- Pylance
- Jupyter

### 2. Configure Workspace

Copy VSCode configuration:
```bash
# From your local machine
oc cp examples/vscode/launch.json ml-dev-env:/workspace/.vscode/launch.json
oc cp examples/vscode/settings.json ml-dev-env:/workspace/.vscode/settings.json
```

### 3. Debugging Configurations

Three debug configurations are provided:

**Single GPU Debugging:**
- Select "Python: Current File"
- Set breakpoints
- Press F5

**Multi-GPU Debugging:**
- Select "Python: Multi-GPU Training"
- Uses `torch.distributed.launch` with 4 GPUs
- Press F5

**DeepSpeed Debugging:**
- Select "Python: DeepSpeed"
- Uses DeepSpeed launcher
- Press F5

### 4. Remote Debugging

For remote debugging from your local VSCode:

```python
# Add to your training script
import debugpy
debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger...")
debugpy.wait_for_client()
```

Then use "Python: Attach to Remote" configuration.

## Testing the Environment

### 1. Test GPU Access

```bash
oc exec ml-dev-env -- python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"
```

### 2. Test Multi-GPU

```bash
# Copy test script
oc cp examples/test_multi_gpu.py ml-dev-env:/workspace/

# Run test
oc exec ml-dev-env -- python /workspace/test_multi_gpu.py
```

Expected output:
```
==============================================================
GPU Availability Test
==============================================================
CUDA Available: True
Number of GPUs: 4

GPU 0: NVIDIA H100 80GB HBM3
  Compute Capability: 9.0
  Total Memory: 80.00 GB
  ...
```

### 3. Test NCCL and RDMA

```bash
oc exec ml-dev-env -- bash -c "nvidia-smi topo -m"
oc exec ml-dev-env -- ibstat
```

### 4. Test DeepSpeed

```bash
# Copy DeepSpeed test
oc cp examples/test_deepspeed.py ml-dev-env:/workspace/

# Run with DeepSpeed
oc exec ml-dev-env -- deepspeed --num_gpus=4 /workspace/test_deepspeed.py
```

## Example Workflows

### LLaMAFactory Fine-tuning

```bash
# Clone LLaMAFactory examples
oc exec ml-dev-env -- git clone https://github.com/hiyouga/LLaMA-Factory.git /workspace/LLaMA-Factory

# Run fine-tuning with 4 GPUs
oc exec ml-dev-env -- bash -c "cd /workspace/LLaMA-Factory && \
    deepspeed --num_gpus=4 src/train_bash.py \
    --deepspeed ds_config.json \
    --model_name_or_path meta-llama/Llama-2-7b-hf \
    --output_dir /workspace/output"
```

### Video Processing with VideoLLaMA2

```bash
# Process videos with ffmpeg and VideoLLaMA2
oc exec ml-dev-env -- python << 'EOF'
import torch
from transformers import AutoModel, AutoTokenizer

model = AutoModel.from_pretrained("DAMO-NLP-SG/VideoLLaMA2-7B")
model = model.cuda()

# Your video processing code here
EOF
```

### Distributed Training with DeepSpeed

```python
# training.py
import deepspeed

# Your model definition
model = YourModel()

# DeepSpeed config
ds_config = {
    "train_batch_size": 32,
    "zero_optimization": {"stage": 2},
    "fp16": {"enabled": True}
}

# Initialize
model_engine, optimizer, _, _ = deepspeed.initialize(
    model=model,
    config=ds_config
)

# Training loop
for epoch in range(epochs):
    for batch in dataloader:
        loss = model_engine(batch)
        model_engine.backward(loss)
        model_engine.step()
```

Run:
```bash
deepspeed --num_gpus=4 training.py
```

## Monitoring and Profiling

### TensorBoard

```bash
# Start TensorBoard
oc exec ml-dev-env -- tensorboard --logdir=/workspace/runs --bind_all &

# Access via route
TENSORBOARD_URL=$(oc get route ml-dev-tensorboard -o jsonpath='{.spec.host}')
echo "TensorBoard: https://$TENSORBOARD_URL"
```

### GPU Monitoring

```bash
# Real-time GPU monitoring
oc exec ml-dev-env -- watch -n 1 nvidia-smi

# GPU topology
oc exec ml-dev-env -- nvidia-smi topo -m
```

### NCCL Performance Testing

```bash
# Test NCCL all-reduce performance
oc exec ml-dev-env -- python -m torch.distributed.launch \
    --nproc_per_node=4 \
    /workspace/nccl_test.py
```

## Troubleshooting

### GPUs Not Detected

```bash
# Check GPU resources
oc describe pod ml-dev-env | grep -A 5 "Limits"

# Check NVIDIA driver
oc exec ml-dev-env -- nvidia-smi
```

### RDMA/InfiniBand Issues

```bash
# Check IB devices
oc exec ml-dev-env -- ibstat

# Check NCCL can see IB
oc exec ml-dev-env -- bash -c "NCCL_DEBUG=INFO python -c 'import torch; torch.cuda.init()'"

# Verify host network
oc exec ml-dev-env -- ip addr
```

### Build Failures

If the build fails during flash-attn or other CUDA extensions:

```bash
# Check build logs
oc logs bc/ml-dev-env

# Rebuild with more resources
oc patch bc/ml-dev-env -p '{"spec":{"resources":{"limits":{"memory":"16Gi","cpu":"8"}}}}'
oc start-build ml-dev-env
```

### Out of Memory

Increase shared memory or adjust batch sizes:

```yaml
# In pod-multi-gpu.yaml
volumes:
- name: shm
  emptyDir:
    medium: Memory
    sizeLimit: 64Gi  # Increase from 32Gi
```

### NumPy Compatibility Warnings

The environment uses **NumPy 1.26.4** (latest 1.x) for compatibility with packages compiled against NumPy 1.x.

If you see NumPy version warnings, the image may need to be rebuilt:

```bash
# Rebuild the image (admin/maintainer only)
oc start-build ml-dev-env -n nccl-test

# Or verify current NumPy version
oc exec ml-dev-env -- python -c "import numpy; print(numpy.__version__)"
# Should show: 1.26.4
```

**Note:** NumPy 2.x causes compatibility warnings with PyTorch and other packages. The BuildConfig is configured to force NumPy 1.x for optimal compatibility.

## File Organization

```
ml-dev-env/
├── README.md                  # This file
├── Makefile                   # Build and deployment automation
│
├── k8s/                       # Kubernetes/OpenShift manifests
│   ├── buildconfig.yaml       # OpenShift build configuration
│   ├── imagestream.yaml       # Image registry
│   ├── pod-multi-gpu.yaml     # Single-node pod (4 GPUs)
│   ├── pvcs.yaml              # Persistent storage
│   ├── service.yaml           # Services and routes
│   ├── statefulset-multi-node-rdma.yaml  # Multi-node (RDMA/RoCE)
│   └── statefulset-multi-node-tcp.yaml  # Multi-node (TCP/Ethernet)
│
├── docs/                      # Documentation
│   ├── QUICKSTART.md
│   ├── MULTI-NODE-QUICKSTART.md
│   ├── MULTI-NODE-TCP-GUIDE.md     # TCP/Ethernet mode (no RDMA)
│   ├── AUTOMATION-GUIDE.md
│   └── ... (13 documentation files)
│
├── scripts/                   # Automation scripts (7 files)
│   ├── deploy.sh
│   ├── deploy-multi-node-rdma.sh   # RDMA/RoCE deployment
│   ├── deploy-multi-node-tcp.sh    # TCP/Ethernet deployment
│   ├── dev-session.sh
│   └── ...
│
├── examples/                  # Example code and configs
│   ├── test_multi_gpu.py
│   ├── test_deepspeed.py
│   ├── test_flash_attn.py
│   └── vscode/               # VSCode configs for pod
│       ├── launch.json
│       └── settings.json
│
├── workspace/                 # Development workspace (syncs to pod)
│   ├── ds_config.json
│   ├── launch_deepspeed.sh
│   ├── test_debug.py
│   └── train_multi_node.py
│
└── .vscode/                   # VSCode configuration
    └── launch.json            # Debug configurations
```

## Resource Requirements

### Minimum
- 1x NVIDIA GPU (Compute Capability >= 7.0)
- 32 GB RAM
- 50 GB storage

### Recommended (for multi-GPU training)
- 4x NVIDIA H100 GPUs
- 128 GB RAM
- 500 GB+ storage
- InfiniBand network (for optimal performance)

## Security Considerations

The pod runs with elevated privileges (`privileged: true`) to access GPUs and InfiniBand devices. In production:

1. Use dedicated GPU nodes with node selectors
2. Apply appropriate RBAC policies
3. Use network policies to restrict access
4. Enable authentication for VSCode/Jupyter
5. Use secrets for API keys (wandb, HuggingFace)

## Next Steps

1. **Clone your code**: `git clone <repo> /workspace/my-project`
2. **Download datasets**: Use `/datasets` for large datasets
3. **Configure wandb**: `wandb login` for experiment tracking
4. **Start training**: Use DeepSpeed or native PyTorch DDP
5. **Monitor**: TensorBoard and wandb dashboards

## Resources

- [PyTorch Distributed Training](https://pytorch.org/tutorials/beginner/dist_overview.html)
- [DeepSpeed Documentation](https://www.deepspeed.ai/)
- [LLaMAFactory](https://github.com/hiyouga/LLaMA-Factory)
- [Flash Attention](https://github.com/Dao-AILab/flash-attention)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)

## License

This example configuration is provided as-is for educational and development purposes.
