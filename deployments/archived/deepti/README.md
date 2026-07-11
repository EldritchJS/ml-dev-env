# Deepti Deployment

Multi-node GPU training and multimodal model testing on OpenShift NERC production cluster.

## Overview

This deployment provides:
- **Multi-node distributed training** using PyTorch DDP and NCCL
- **Single-node testing** of Qwen2.5-Omni-7B multimodal model
- **Flash Attention 2** for optimal performance
- **Multiple PyTorch versions** (2.8, 2.9) support
- **Video/text multimodal** inference testing
- **4-GPU support** per node for model parallelism
- **NCCL over TCP** for multi-node communication

## Project Structure

```
deployments/deepti/
├── README.md                           # This file
├── QUICKSTART.md                       # Quick start guide
├── MIGRATION.md                        # Migration guide
├── generated/                          # Kubernetes manifests
│   ├── pod-deepti-nerc.yaml                NERC cluster (latest)
│   ├── pod-deepti-nerc-pytorch29.yaml      NERC with PyTorch 2.9
│   ├── pod-deepti-nerc-pytorch29-test.yaml NERC test variant
│   └── pod-debug-deepti-nerc.yaml          Debug pod for NERC
├── scripts/                            # Deployment scripts
│   └── deploy-deepti-nerc.sh               Deploy to NERC
└── workspace/                          # Test scripts and outputs
    ├── deepti.py                           Full multimodal test
    ├── deepti-simple.py                    Simplified test
    └── deepti-test.txt                     Test output log
```

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

### Deploy to NERC Production Cluster

```bash
cd deployments/deepti
oc apply -f generated/pod-deepti-nerc.yaml
```

### Using Deploy Script

```bash
./scripts/deploy-deepti-nerc.sh
```

## Key Features

### Multimodal Model Testing
- **Model**: Qwen2.5-Omni-7B
- **Capabilities**: Video + text understanding
- **Attention**: Flash Attention 2
- **Precision**: BF16 mixed precision
- **Device**: Multi-GPU (model parallelism)

### Multi-Node Distributed Training
- **Framework**: PyTorch DistributedDataParallel (DDP)
- **Communication**: NCCL over TCP networking
- **Topology**: Multiple nodes with 4 GPUs each
- **Scaling**: Linear scaling across nodes
- **Network**: Standard Ethernet (no RDMA required)

### NERC Production Cluster
- **GPU Nodes**: H100 80GB HBM3 GPUs
- **Networking**: TCP/IP based NCCL communication
- **Storage**: Persistent volume claims (PVC) for shared data
- **Orchestration**: Kubernetes/OpenShift native

### PyTorch Version Support

Multiple pod variants for different PyTorch versions:
- **pytorch28**: PyTorch 2.8.x
- **pytorch29**: PyTorch 2.9.x
- **Latest**: Current stable version

## Hardware Requirements

### Resources Per Pod
- **GPUs**: 4 GPUs (NVIDIA H100 80GB)
- **Memory**: 128Gi request, 256Gi limit
- **CPU**: 32 cores request, 64 cores limit
- **Storage**: Persistent volume claims for datasets

## Multi-Node Training Setup

### NCCL Configuration for TCP Networking

When running multi-node training on NERC, use these NCCL settings:

```bash
# Disable RDMA/InfiniBand (not available on NERC)
export NCCL_IB_DISABLE=1

# Use TCP sockets for communication
export NCCL_SOCKET_IFNAME=eth0

# Enable debugging (optional, useful for troubleshooting)
export NCCL_DEBUG=INFO

# Performance tuning for TCP
export NCCL_SOCKET_NTHREADS=4
export NCCL_NSOCKS_PERTHREAD=4

# P2P settings
export NCCL_P2P_LEVEL=NVL  # NVLink for intra-node
export NCCL_NET_GDR_LEVEL=0  # No GPUDirect RDMA
```

### PyTorch Distributed Training

**Example multi-node training command:**

```bash
# On rank 0 (master node):
torchrun \
  --nnodes=2 \
  --nproc_per_node=4 \
  --node_rank=0 \
  --master_addr=deepti-train-0.deepti-train-svc \
  --master_port=29500 \
  train.py

# On rank 1 (worker node):
torchrun \
  --nnodes=2 \
  --nproc_per_node=4 \
  --node_rank=1 \
  --master_addr=deepti-train-0.deepti-train-svc \
  --master_port=29500 \
  train.py
```

**Key parameters:**
- `--nnodes`: Total number of nodes in the training job
- `--nproc_per_node`: GPUs per node (typically 4 for H100 nodes)
- `--node_rank`: Rank of this node (0 for master, 1+ for workers)
- `--master_addr`: Hostname or IP of the master node
- `--master_port`: Port for NCCL communication (default 29500)

### Setting Up Multi-Node Pods

Create a StatefulSet or multiple pods with a headless service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: deepti-train-svc
  namespace: your-namespace
spec:
  clusterIP: None  # Headless service
  selector:
    app: deepti-train
  ports:
  - port: 29500
    name: nccl
---
apiVersion: v1
kind: Pod
metadata:
  name: deepti-train-0
  labels:
    app: deepti-train
spec:
  hostname: deepti-train-0
  subdomain: deepti-train-svc
  # ... rest of pod spec
```

This creates predictable hostnames:
- `deepti-train-0.deepti-train-svc`
- `deepti-train-1.deepti-train-svc`
- etc.

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

# Check GPUs
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

### NERC Production Cluster

**pod-deepti-nerc.yaml** (Recommended)
- Latest PyTorch version
- Standard TCP networking
- Full GPU support
- Production-ready

**pod-deepti-nerc-pytorch29.yaml**
- PyTorch 2.9.x specific
- Latest features

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

### NCCL Configuration (TCP Mode)
```bash
NCCL_DEBUG=INFO                     # Debug output
NCCL_IB_DISABLE=1                   # Disable InfiniBand/RDMA
NCCL_SOCKET_IFNAME=eth0             # Use TCP sockets
NCCL_P2P_LEVEL=NVL                  # NVLink for intra-node
NCCL_NET_GDR_LEVEL=0                # No GPUDirect RDMA
```

### Performance
```bash
OMP_NUM_THREADS=8                   # OpenMP threads
```

## Multi-Node Training Performance

### Expected Bandwidth (TCP)

**Intra-node (NVLink):**
- 4 GPUs per node: 300-600 GB/s aggregate

**Inter-node (TCP/Ethernet):**
- 10-25 GB/s per connection (depends on network)
- Lower than RDMA but sufficient for most training workloads

### Scaling Efficiency

**Strong scaling** (fixed problem size):
- 2 nodes: ~90% efficiency
- 4 nodes: ~85% efficiency
- 8 nodes: ~75-80% efficiency

**Weak scaling** (problem size grows with nodes):
- Near-linear scaling up to 8+ nodes

### Performance Tuning Tips

1. **Batch size:** Increase per-GPU batch size to reduce communication overhead
2. **Gradient accumulation:** Use gradient accumulation to simulate larger batches
3. **Communication overlap:** PyTorch DDP automatically overlaps gradient communication with computation
4. **Mixed precision:** Use BF16/FP16 to reduce data transfer
5. **Network interface:** Ensure pods use the fastest network interface available

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

### NCCL Multi-Node Issues

```bash
# Check NCCL environment
oc exec deepti-train-0 -- env | grep NCCL

# Verify network connectivity between nodes
oc exec deepti-train-0 -- ping deepti-train-1.deepti-train-svc

# Check NCCL debug output
oc logs deepti-train-0 | grep NCCL

# Common issues:
# - NCCL_IB_DISABLE not set (tries to use RDMA)
# - Wrong master_addr (can't reach rank 0)
# - Port conflicts on master_port
# - Network policy blocking pod-to-pod communication
```

### Slow Multi-Node Training

```bash
# Check inter-node bandwidth
# Should see consistent throughput without drops

# Monitor GPU utilization
oc exec deepti-train-0 -- nvidia-smi dmon

# Check for stragglers
# All GPUs should show similar utilization

# Tune NCCL settings:
export NCCL_SOCKET_NTHREADS=8  # Increase for faster network
export NCCL_NSOCKS_PERTHREAD=8
```

## Performance Notes

### Expected Performance

**Single-node:**
- **Model loading**: ~30-60 seconds (depends on network/cache)
- **Inference**: ~1-5 seconds per request (depends on input)
- **GPU utilization**: High during inference
- **Memory**: ~20-30GB per GPU (for 7B model)

**Multi-node training:**
- **Initialization**: ~10-20 seconds for NCCL setup
- **Throughput**: 85-90% of single-node per-GPU throughput (2 nodes)
- **Communication**: 10-25 GB/s inter-node (TCP networking)
- **Scaling**: Near-linear for large batch sizes

### Optimization Tips

1. **Use Flash Attention 2** for faster inference
2. **Enable BF16** for memory efficiency
3. **Use device_map="auto"** for optimal GPU distribution
4. **Pre-download model** to reduce startup time
5. **Monitor GPU memory** to avoid OOM
6. **For multi-node:** Increase batch size to reduce communication overhead
7. **For multi-node:** Use gradient accumulation for effective larger batches

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

- **PyTorch Distributed**: https://pytorch.org/tutorials/beginner/dist_overview.html
- **NCCL Documentation**: https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/
- **PyTorch DDP**: https://pytorch.org/docs/stable/notes/ddp.html
- **Flash Attention**: https://github.com/Dao-AILab/flash-attention
- **Qwen2.5-Omni**: https://huggingface.co/Qwen/Qwen2.5-Omni-7B
- **Transformers Library**: https://huggingface.co/docs/transformers/

## Status

- ✅ Pod configurations available for NERC production cluster
- ✅ Multiple PyTorch versions supported
- ✅ TCP-based NCCL for multi-node training
- ✅ Test scripts included
- ✅ Deploy scripts ready
- ✅ Ready for multimodal model testing and distributed training

## Notes

- Test pods use `restartPolicy: Never` (single-run tests)
- Multi-node training uses NCCL over TCP (no RDMA)
- Model downloads from HuggingFace Hub (requires internet)
- Flash Attention 2 significantly improves performance
- Multi-GPU setup uses device_map="auto" for automatic distribution
- For best multi-node performance, use large batch sizes and gradient accumulation
