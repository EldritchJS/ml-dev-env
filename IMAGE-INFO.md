# ML Development Environment Image

**Repository:** `quay.io/jschless/ml-dev-env:pytorch-2.9-numpy2`
**Size:** 12.1 GB
**Last Updated:** 2026-02-05 01:13:55 UTC
**Manifest:** sha256:00419ba5649d4804df98fd3d972eb1cd0f4b824749a9479d41af122189548450

## Base Image

**NVIDIA PyTorch 25.09-py3**
- Ubuntu 24.04 LTS
- CUDA 13.0
- cuDNN 9.x
- NCCL optimized for multi-GPU training

## Core Versions

| Component | Version | Notes |
|-----------|---------|-------|
| **PyTorch** | 2.9.0a0+50eac811a6.nv25.09 | NVIDIA official build, fixes CVE-2025-32434, NumPy 2.x compatible |
| **Flash-Attention** | 2.7.4.post1 | Pre-installed by NVIDIA, tested for PyTorch 2.9 |
| **Python** | 3.12 | |
| **CUDA** | 13.0 | |
| **Transformers** | 4.52.4 | |
| **NumPy** | 2.2.6 | Latest version - fully compatible with all packages |

## ML Training & Fine-tuning

- **DeepSpeed** - Distributed training framework with ZeRO optimization
- **LLaMAFactory** - LLM fine-tuning framework
- **PEFT** - Parameter-Efficient Fine-Tuning (LoRA, QLoRA, etc.)
- **TRL** - Transformer Reinforcement Learning
- **BitsAndBytes** - 8-bit optimizers and quantization

## Model Support

### Multimodal Models
- **Qwen2.5-Omni** - Text, audio, video, vision multimodal model
  - qwen-omni-utils installed
  - Flash-attention 2 enabled for vision/text components
  - Verified working on 4x NVIDIA H100 GPUs

### Video/Vision Processing
- **einops** - Tensor operations
- **timm** - PyTorch Image Models
- **av** - PyAV video processing
- **opencv-python** - Computer vision
- **decord** - Video loading

## Data & Scientific Computing

- **NumPy** 2.2.6 - Latest version, fully tested
- **SciPy** - Scientific computing
- **scikit-learn** - Machine learning utilities
- **Matplotlib** - Plotting and visualization
- **Pandas** (via dependencies)

## Development Tools

### Interactive Computing
- **Jupyter** - Notebook server
- **ipykernel** - Jupyter kernel
- **IPython** - Enhanced Python shell
- **code-server** - VSCode in browser (port 8080)

### Code Quality
- **pytest** - Testing framework
- **black** - Code formatter
- **flake8** - Linting
- **debugpy** - Python debugger

### ML Experiment Tracking
- **TensorBoard** - Training visualization
- **Weights & Biases** - Experiment tracking and collaboration

## Networking & GPU Features

### RDMA/InfiniBand Support
- **libibverbs-dev** - InfiniBand verbs library
- **librdmacm-dev** - RDMA connection manager
- **rdma-core** - RDMA core userspace
- **infiniband-diags** - IB diagnostic tools
- **pciutils** - PCI utilities
- **numactl** - NUMA control

### NCCL Configuration (Pre-configured)
```bash
NCCL_DEBUG=INFO
NCCL_IB_DISABLE=0  # InfiniBand enabled
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_IB_GID_INDEX=3
NCCL_SOCKET_IFNAME=net1,net2,net3,net4
NCCL_NET_GDR_LEVEL=5  # GPUDirect RDMA enabled
```

## System Tools

- **git** - Version control
- **wget**, **curl** - File download
- **vim**, **less** - Text editors
- **bash-completion** - Shell completion
- **gcc**, **g++**, **make**, **cmake**, **ninja-build** - Build tools
- **ffmpeg** - Multimedia processing

## Exposed Ports

- **8080** - code-server (VSCode)
- **8888** - Jupyter notebook
- **6006** - TensorBoard

## Verified Functionality

✅ **PyTorch 2.9 + NumPy 2.2.6** - Full binary compatibility, no symbol mismatch errors
✅ **Flash-Attention 2.7.4.post1** - Optimized attention for transformers, compatible with NumPy 2.x
✅ **All ML Packages** - LLaMAFactory, TRL, Qwen2.5-Omni tested and working with NumPy 2.x
✅ **CVE-2025-32434 Fix** - PyTorch >= 2.6 security requirement met
✅ **4x NVIDIA H100 GPUs** - Multi-GPU support with NVLink verified on NERC Production and Barcelona
✅ **InfiniBand/RDMA** - Network configuration for distributed training
✅ **Qwen2.5-Omni Model** - Complete model loading and inference tested successfully

## Usage Examples

### Pull Image
```bash
# Default (recommended): PyTorch 2.9 with NumPy 2.2.6
podman pull quay.io/jschless/ml-dev-env:pytorch-2.9-numpy2

# Legacy: PyTorch 2.8 with NumPy 1.26.4 (only if you need PyTorch 2.8 specifically)
podman pull quay.io/jschless/ml-dev-env:pytorch-2.8-numpy1
```

### Run Interactive Container
```bash
podman run -it --rm \
  --gpus all \
  -p 8080:8080 -p 8888:8888 -p 6006:6006 \
  quay.io/jschless/ml-dev-env:latest \
  /bin/bash
```

### Kubernetes Deployment
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ml-workload
spec:
  containers:
  - name: ml-dev
    image: quay.io/jschless/ml-dev-env:pytorch-2.9-numpy2
    resources:
      limits:
        nvidia.com/gpu: 4  # Request 4 GPUs
```

### Start Jupyter Notebook
```bash
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

### Start VSCode Server
```bash
code-server --bind-addr 0.0.0.0:8080 --auth none
```

## Build Information

- **Built:** 2026-02-05
- **Build System:** OpenShift BuildConfig (Barcelona cluster)
- **Base:** NVIDIA PyTorch 25.09-py3
- **Strategy:** PyTorch version pinning via constraints to prevent upgrades during package installation

## Available Tags

- **`pytorch-2.9-numpy2`** ⭐ **Default/Recommended** - PyTorch 2.9 + NumPy 2.2.6 (latest, fully tested)
- **`pytorch-2.9`** - Alias for pytorch-2.9-numpy2
- **`pytorch-2.8-numpy1`** - PyTorch 2.8 + NumPy 1.26.4 (legacy - only use if you specifically need PyTorch 2.8)
- **`latest`** - Currently points to pytorch-2.8-numpy1 (use explicit tags instead)

## Key Design Decisions

1. **PyTorch 2.9 + NumPy 2.x** - Latest NVIDIA PyTorch build (25.09) with full NumPy 2.2.6 compatibility. This is the recommended version with all packages tested and working.

2. **Pre-installed Flash-Attention** - Using NVIDIA's pre-built flash-attn 2.7.4.post1 instead of compiling from source to avoid symbol mismatch issues with NVIDIA's custom PyTorch build

3. **Constraint-based Installation** - All packages installed with PyTorch version constraints to prevent accidental upgrades during dependency resolution

4. **NumPy 2.x Compatibility** - All packages (LLaMAFactory, TRL, Flash-Attention, Qwen2.5-Omni) work correctly with NumPy 2.2.6 despite pip warnings during build. PyTorch 2.9 has full binary compatibility with NumPy 2.x.

5. **General-Purpose ML** - Includes packages for various ML workloads (LLM fine-tuning, multimodal models, computer vision, etc.) not just Qwen2.5-Omni

**Note:** PyTorch 2.8 (image 25.08) has binary incompatibility with NumPy 2.x and MUST use NumPy 1.26.4. Use pytorch-2.9-numpy2 for the modern NumPy 2.x experience.

## Security

- ✅ CVE-2025-32434 (torch.load vulnerability) - Fixed with PyTorch 2.8
- Container runs as root (standard for NVIDIA containers)
- RDMA/InfiniBand capabilities require privileged or specific capabilities

## Known Warnings (Expected)

When using Qwen2.5-Omni:
```
You are attempting to use Flash Attention 2.0 without specifying a torch dtype.
```
**Expected** - Model uses bfloat16 for vision/text, fp32 for audio generation

```
Qwen2_5OmniToken2WavModel must inference with fp32, but flash_attention_2 only supports fp16 and bf16
```
**Expected** - Audio component uses SDPA instead of flash-attention, text/vision components still use flash-attention

## Maintenance

**Image Registry:** https://quay.io/repository/jschless/ml-dev-env
**Source BuildConfig:** `/Users/jschless/nairr/deepti/ml-dev-env/k8s/buildconfig.yaml`

## License

Based on NVIDIA PyTorch container - see [NVIDIA Deep Learning Container License](https://docs.nvidia.com/deeplearning/frameworks/licenses/index.html)
