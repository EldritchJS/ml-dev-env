# ML Development Environment Image

**Repository:** `quay.io/jschless/ml-dev-env:latest`
**Size:** 12.1 GB
**Last Updated:** 2026-02-04 06:21:12 UTC
**Manifest:** sha256:675ae091bdb6104782ba716e87778fd46f496322bf2a2d1b0b12ec24010fd1d0

## Base Image

**NVIDIA PyTorch 25.08-py3**
- Ubuntu 24.04 LTS
- CUDA 12.8
- cuDNN 9.x
- NCCL optimized for multi-GPU training

## Core Versions

| Component | Version | Notes |
|-----------|---------|-------|
| **PyTorch** | 2.8.0a0+34c6371d24.nv25.08 | NVIDIA official build, fixes CVE-2025-32434 |
| **Flash-Attention** | 2.7.4.post1 | Pre-installed by NVIDIA, tested for PyTorch 2.8 |
| **Python** | 3.12 | |
| **CUDA** | 12.8 | |
| **Transformers** | 4.52.4 | |

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

- **NumPy** < 2.0 (for compatibility)
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

✅ **PyTorch 2.8 + Flash-Attention 2.7.4.post1** - No symbol mismatch errors
✅ **CVE-2025-32434 Fix** - PyTorch >= 2.6 security requirement met
✅ **Qwen2.5-Omni Model** - Loading and inference tested successfully
✅ **4x NVIDIA H100 GPUs** - Multi-GPU support with NVLink verified
✅ **InfiniBand/RDMA** - Network configuration for distributed training
✅ **Flash-Attention** - Optimized attention for transformers

## Usage Examples

### Pull Image
```bash
podman pull quay.io/jschless/ml-dev-env:latest
# or
docker pull quay.io/jschless/ml-dev-env:latest
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
    image: quay.io/jschless/ml-dev-env:latest
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

- **Built:** 2026-02-04
- **Build System:** OpenShift BuildConfig (Barcelona cluster)
- **Build Number:** ml-dev-env-13
- **Base:** NVIDIA PyTorch 25.08-py3
- **Strategy:** PyTorch version pinning via constraints to prevent upgrades during package installation

## Key Design Decisions

1. **Pre-installed Flash-Attention** - Using NVIDIA's pre-built flash-attn 2.7.4.post1 instead of compiling from source to avoid symbol mismatch issues with NVIDIA's custom PyTorch build

2. **PyTorch 2.8** - Chosen for CVE-2025-32434 fix and compatibility with flash-attention 2.7.4.post1

3. **Constraint-based Installation** - All packages installed with PyTorch version constraints to prevent accidental upgrades during dependency resolution

4. **NumPy < 2.0** - Force-reinstalled to prevent compatibility warnings from packages compiled against NumPy 1.x

5. **General-Purpose ML** - Includes packages for various ML workloads (LLM fine-tuning, multimodal models, computer vision, etc.) not just Qwen2.5-Omni

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
