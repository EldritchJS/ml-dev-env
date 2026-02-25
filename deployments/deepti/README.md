# Deepti Deployment

Single-node Qwen2.5-Omni multimodal model testing on OpenShift with GPU acceleration.

## Overview

This deployment provides:
- **Single-node testing** of Qwen2.5-Omni-7B multimodal model
- **Multi-cluster support** (Barcelona RDMA, NERC)
- **Flash Attention 2** for optimal performance
- **Multiple PyTorch versions** (2.8, 2.9) support
- **Video/text multimodal** inference testing
- **4-GPU support** for model parallelism

## Project Structure

```
deployments/deepti/
├── README.md                           # This file
├── QUICKSTART.md                       # Quick start guide
├── MIGRATION.md                        # Migration guide
├── generated/                          # Kubernetes manifests
│   ├── pod-deepti-barcelona.yaml           Barcelona cluster (latest)
│   ├── pod-deepti-barcelona-pytorch28.yaml Barcelona with PyTorch 2.8
│   ├── pod-deepti-barcelona-pytorch29.yaml Barcelona with PyTorch 2.9
│   ├── pod-deepti-nerc.yaml                NERC cluster (latest)
│   ├── pod-deepti-nerc-pytorch29.yaml      NERC with PyTorch 2.9
│   ├── pod-deepti-nerc-pytorch29-test.yaml NERC test variant
│   └── pod-debug-deepti-nerc.yaml          Debug pod for NERC
├── scripts/                            # Deployment scripts
│   ├── deploy-deepti-barcelona.sh          Deploy to Barcelona
│   └── deploy-deepti-nerc.sh               Deploy to NERC
├── docs/                               # Documentation (empty, ready)
└── workspace/                          # Test scripts and outputs
    ├── deepti.py                           Full multimodal test
    ├── deepti-simple.py                    Simplified test
    └── deepti-test.txt                     Test output log
```

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

### Deploy to Barcelona Cluster

```bash
cd deployments/deepti
oc apply -f generated/pod-deepti-barcelona.yaml
```

### Deploy to NERC Cluster

```bash
cd deployments/deepti
oc apply -f generated/pod-deepti-nerc.yaml
```

### Using Deploy Scripts

```bash
# Barcelona (with RDMA)
./scripts/deploy-deepti-barcelona.sh

# NERC
./scripts/deploy-deepti-nerc.sh
```

## Key Features

### Multimodal Model Testing
- **Model**: Qwen2.5-Omni-7B
- **Capabilities**: Video + text understanding
- **Attention**: Flash Attention 2
- **Precision**: BF16 mixed precision
- **Device**: Multi-GPU (model parallelism)

### Cluster Support

**Barcelona Cluster:**
- RDMA/InfiniBand enabled
- 4x InfiniBand HCAs (mlx5_6, mlx5_7, mlx5_10, mlx5_11)
- GPUDirect RDMA support
- High-speed inter-GPU communication

**NERC Cluster:**
- Standard GPU networking
- No RDMA requirements
- Good for testing and development

### PyTorch Version Support

Multiple pod variants for different PyTorch versions:
- **pytorch28**: PyTorch 2.8.x
- **pytorch29**: PyTorch 2.9.x
- **Latest**: Current stable version

## Hardware Requirements

### Resources Per Pod
- **GPUs**: 4 GPUs (NVIDIA)
- **Memory**: 128Gi request, 256Gi limit
- **CPU**: 32 cores request, 64 cores limit
- **Storage**: Ephemeral (container storage)

### NCCL Configuration (Barcelona)

```bash
NCCL_IB_DISABLE=0                              # Enable InfiniBand
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11     # InfiniBand devices
NCCL_IB_GID_INDEX=3                            # RoCE v2
NCCL_NET_GDR_LEVEL=5                           # GPUDirect RDMA
NCCL_SOCKET_IFNAME=net1,net2,net3,net4        # RDMA interfaces
NCCL_P2P_LEVEL=NVL                             # NVLink preference
```

## Test Scripts

### deepti.py (Full Test)

Comprehensive multimodal test:
1. Creates dummy video with ffmpeg
2. Loads Qwen2.5-Omni-7B with Flash Attention 2
3. Processes video + text prompt
4. Generates multimodal response

**Features:**
- Flash Attention 2 optimization
- BF16 mixed precision
- Device auto-mapping
- Video processing with ffmpeg

### deepti-simple.py (Quick Test)

Simplified validation test for rapid iteration.

## Usage

### Deploy a Test Pod

```bash
# Barcelona cluster (with RDMA)
oc apply -f deployments/deepti/generated/pod-deepti-barcelona.yaml

# NERC cluster
oc apply -f deployments/deepti/generated/pod-deepti-nerc.yaml
```

### Monitor Test Execution

```bash
# Check pod status
oc get pod deepti-test

# View logs
oc logs -f deepti-test

# Expected output includes:
# - GPU detection
# - Model loading progress
# - Flash attention initialization
# - Video processing
# - Inference results
```

### Access Pod for Debugging

```bash
# Interactive shell
oc exec -it deepti-test -- bash

# Check GPU availability
oc exec deepti-test -- nvidia-smi

# Test model manually
oc exec deepti-test -- python /workspace/deepti-simple.py
```

### Run Tests Manually

```bash
# Shell into pod
oc exec -it deepti-test -- bash

# Run full test
cd /workspace
python deepti.py

# Run simple test
python deepti-simple.py
```

## Pod Variants

### Barcelona Cluster

**pod-deepti-barcelona.yaml** (Recommended)
- Latest PyTorch version
- RDMA enabled
- Full GPU support
- Production-ready

**pod-deepti-barcelona-pytorch28.yaml**
- PyTorch 2.8.x specific
- For compatibility testing

**pod-deepti-barcelona-pytorch29.yaml**
- PyTorch 2.9.x specific
- Latest features

### NERC Cluster

**pod-deepti-nerc.yaml** (Recommended)
- Standard GPU networking
- Latest stable configuration
- No RDMA requirements

**pod-deepti-nerc-pytorch29.yaml**
- PyTorch 2.9.x specific
- Testing variant

**pod-deepti-nerc-pytorch29-test.yaml**
- Experimental configuration
- Testing new features

**pod-debug-deepti-nerc.yaml**
- Debug mode enabled
- Extended logging
- For troubleshooting

## Environment Variables

### GPU Configuration
```bash
NVIDIA_VISIBLE_DEVICES=all          # All GPUs visible
NVIDIA_DRIVER_CAPABILITIES=compute,utility
CUDA_VISIBLE_DEVICES=0,1,2,3        # 4 GPUs
```

### NCCL (Barcelona Only)
```bash
NCCL_DEBUG=INFO                     # Debug output
NCCL_IB_DISABLE=0                   # Enable IB
NCCL_IB_HCA=mlx5_6,...              # IB devices
NCCL_NET_GDR_LEVEL=5                # GPUDirect
```

### Performance
```bash
OMP_NUM_THREADS=8                   # OpenMP threads
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
oc describe pod deepti-test

# Common issues:
# - Insufficient GPU resources
# - Image pull errors
# - Node capacity issues
```

### Model Loading Fails

```bash
# Check available memory
oc exec deepti-test -- nvidia-smi

# Check model cache
oc exec deepti-test -- ls -lh ~/.cache/huggingface/

# Verify PyTorch version
oc exec deepti-test -- python -c "import torch; print(torch.__version__)"
```

### CUDA/GPU Errors

```bash
# Verify GPU visibility
oc exec deepti-test -- nvidia-smi

# Check CUDA version
oc exec deepti-test -- nvcc --version

# Test PyTorch GPU access
oc exec deepti-test -- python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"
```

### Flash Attention Issues

```bash
# Check flash-attn installation
oc exec deepti-test -- python -c "import flash_attn; print(flash_attn.__version__)"

# Verify compatibility
# Flash Attention 2 requires:
# - PyTorch >= 2.0
# - CUDA >= 11.6
# - Ampere or newer GPUs (A100, H100)
```

### RDMA Issues (Barcelona Only)

```bash
# Check InfiniBand devices
oc exec deepti-test -- ls -la /sys/class/infiniband/

# Verify NCCL settings
oc exec deepti-test -- env | grep NCCL

# Test RDMA connectivity
oc exec deepti-test -- ibv_devices
```

## Performance Notes

### Expected Performance
- **Model loading**: ~30-60 seconds (depends on network/cache)
- **Inference**: ~1-5 seconds per request (depends on input)
- **GPU utilization**: High during inference
- **Memory**: ~20-30GB per GPU (for 7B model)

### Optimization Tips
1. **Use Flash Attention 2** for faster inference
2. **Enable BF16** for memory efficiency
3. **Use device_map="auto"** for optimal GPU distribution
4. **Pre-download model** to reduce startup time
5. **Monitor GPU memory** to avoid OOM

## Model Information

### Qwen2.5-Omni-7B

**Capabilities:**
- Multimodal understanding (text + video/audio)
- Text generation
- Video description
- Audio transcription

**Architecture:**
- 7 billion parameters
- Transformer-based
- Flash Attention compatible
- Multi-GPU friendly

**Requirements:**
- PyTorch >= 2.0
- Transformers library
- Flash Attention 2 (optional, recommended)
- ffmpeg (for video processing)

## Container Images

Images are built and stored in OpenShift internal registry:

```
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:pytorch-2.8-numpy2
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:pytorch-2.9-numpy2
```

## Related Documentation

- **PyTorch Documentation**: https://pytorch.org/docs/
- **Flash Attention**: https://github.com/Dao-AILab/flash-attention
- **Qwen2.5-Omni**: https://huggingface.co/Qwen/Qwen2.5-Omni-7B
- **Transformers Library**: https://huggingface.co/docs/transformers/

## Status

- ✅ Pod configurations available for both clusters
- ✅ Multiple PyTorch versions supported
- ✅ RDMA enabled on Barcelona cluster
- ✅ Test scripts included
- ✅ Deploy scripts ready
- ✅ Ready for multimodal model testing

## Notes

- Test pods use `restartPolicy: Never` (single-run tests)
- Barcelona cluster requires RDMA/InfiniBand setup
- Model downloads from HuggingFace Hub (requires internet)
- Flash Attention 2 significantly improves performance
- Multi-GPU setup uses device_map="auto" for automatic distribution
