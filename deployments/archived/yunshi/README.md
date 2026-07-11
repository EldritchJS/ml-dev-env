# Yunshi Deployment

Multi-node distributed training deployment for Time Series Foundation Model (TSFM) with RDMA/InfiniBand acceleration on OpenShift.

## Overview

This deployment provides:
- **2-node StatefulSet** with 4 GPUs per node (8 GPUs total)
- **RDMA/InfiniBand** networking for high-speed inter-node communication
- **PyTorch DDP** (DistributedDataParallel) training
- **Time Series Foundation Model** pretraining and fine-tuning
- **Jupyter notebook** environment for development
- **Persistent storage** for datasets and checkpoints

## Project Structure

```
deployments/yunshi/
├── README.md                           # This file
├── QUICKSTART.md                       # Quick start guide
├── MIGRATION.md                        # Migration guide
├── generated/                          # Kubernetes manifests
│   ├── statefulset-yunshi.yaml        # Main StatefulSet (TSFM training)
│   ├── large_zero_shot_rdma.yaml      # Large-scale zero-shot training variant
│   └── jupyter.yaml                    # Jupyter notebook environment
├── scripts/                            # Scripts (empty for now)
├── docs/                               # Documentation (empty for now)
└── workspace/                          # Training workspace
```

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

### 1. Deploy the StatefulSet

```bash
cd deployments/yunshi
oc apply -f generated/statefulset-yunshi.yaml
```

### 2. Wait for Pods to Start

```bash
oc get pods -l app=tsfm-ddp -w
```

### 3. Monitor Training

```bash
# View logs from node 0
oc logs -f tsfm-node-0

# View logs from node 1
oc logs -f tsfm-node-1
```

## Key Features

### Multi-Node Distributed Training
- **2 nodes** (tsfm-node-0, tsfm-node-1)
- **4 GPUs per node** (8 total)
- **PyTorch DistributedDataParallel** (DDP)
- **Automatic rendezvous** via headless service

### RDMA/InfiniBand Networking
- **4x InfiniBand HCAs** per node
- **SR-IOV** for device isolation
- **GPUDirect RDMA** enabled
- **NCCL optimized** for InfiniBand

### NCCL Configuration
```bash
NCCL_IB_DISABLE=0                              # Enable InfiniBand
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11     # InfiniBand devices
NCCL_IB_GID_INDEX=3                            # RoCE v2
NCCL_NET_GDR_LEVEL=5                           # GPUDirect RDMA
NCCL_SOCKET_IFNAME=eth0                        # Out-of-band communication
```

### Time Series Foundation Model
- **Hybrid architecture** with patch-based encoding
- **Multi-scale processing** (1, 4, 8, 12, 20, 32, 48, 72, 128)
- **VQ-VAE codebook** for discrete representations
- **Student-teacher distillation**
- **Zero-shot transfer** capabilities

## Hardware Setup

### Nodes
- **moc-r4pcc02u15-yunshi** (node 0)
- **moc-r4pcc02u16-yunshi** (node 1)

### Resources Per Node
- **4x GPUs** (NVIDIA, likely H100 or A100)
- **1000Gi memory**
- **32 CPUs**
- **4x InfiniBand SR-IOV VFs** (eno5np0rdma, eno6np0rdma, eno7np0rdma, eno8np0rdma)

### Storage
- **PVC**: `tsfm` (persistent volume claim)
- **Mount point**: `/mnt/tsfm`
- **Contains**: datasets, checkpoints, logs, code

## Training Configuration

### Model Parameters
```
Context Length: 8192
Patch Size: 16
Model Dimension: 1024
Attention Heads: 16
Layers: 20
Scales: 1_4_8_12_20_32_48_72_128
```

### Training Hyperparameters
```
Batch Size: 64 (per GPU)
Gradient Accumulation: 4
Learning Rate: 3e-4
Min LR: 1e-5
Weight Decay: 0.1
Max Steps: 100,000
Precision: BF16
```

### Datasets
Training data stored in:
- `/mnt/tsfm/data/GiftEval`
- `/mnt/tsfm/data/GiftPretrain`
- `/mnt/tsfm/data/kernel_synth_10M`
- `/mnt/tsfm/data/tsmixup`
- `/mnt/tsfm/data/tsmixup_v01`

## Deployment Variants

### 1. Standard Training (statefulset-yunshi.yaml)
- Basic 2-node setup
- Default configuration
- Good for initial testing

### 2. Large Zero-Shot (large_zero_shot_rdma.yaml)
- Optimized for large-scale zero-shot learning
- Enhanced affinity rules
- Production-ready configuration

### 3. Jupyter Environment (jupyter.yaml)
- Interactive development
- Notebook access
- Exploratory analysis

## Environment Variables

### NCCL/Distributed Training
```bash
NCCL_IB_DISABLE=0               # Enable InfiniBand
NCCL_P2P_DISABLE=0              # Enable peer-to-peer
NCCL_DEBUG=INFO                 # Debug level
NCCL_IB_HCA=mlx5_6,...          # IB devices
NCCL_SOCKET_IFNAME=eth0         # OOB interface
NCCL_IB_GID_INDEX=3             # RoCE v2
NCCL_NET_GDR_LEVEL=5            # GPUDirect
CUDA_VISIBLE_DEVICES=0,1,2,3    # GPU visibility
OMP_NUM_THREADS=8               # OpenMP threads
```

### Project Paths
```bash
PROJECT_ROOT=/mnt/tsfm/hybrid_tsfm
GIFT_EVAL=/mnt/tsfm/data/GiftEval
GIFT_EVAL_PRETRAIN=/mnt/tsfm/data/GiftPretrain
KERNEL_SYNTH=/mnt/tsfm/data/kernel_synth_10M
TSMIXUP=/mnt/tsfm/data/tsmixup
TSMIXUP_ZERO=/mnt/tsfm/data/tsmixup_v01
```

## Usage

### Deploy Training Job

```bash
# Standard training
oc apply -f deployments/yunshi/generated/statefulset-yunshi.yaml

# Large zero-shot variant
oc apply -f deployments/yunshi/generated/large_zero_shot_rdma.yaml
```

### Monitor Progress

```bash
# Check pod status
oc get pods -l app=tsfm-ddp

# View training logs
oc logs -f tsfm-node-0
oc logs -f tsfm-node-1

# Check NCCL initialization
oc logs tsfm-node-0 | grep NCCL
```

### Access Pods

```bash
# Shell into node 0
oc exec -it tsfm-node-0 -- bash

# Shell into node 1
oc exec -it tsfm-node-1 -- bash

# Check storage
oc exec tsfm-node-0 -- ls -lh /mnt/tsfm
```

### Stop Training

```bash
# Delete StatefulSet (keeps PVC)
oc delete statefulset tsfm-node

# Delete everything
oc delete -f deployments/yunshi/generated/statefulset-yunshi.yaml
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
oc describe pod tsfm-node-0

# Check node capacity
oc describe node moc-r4pcc02u15-yunshi
oc describe node moc-r4pcc02u16-yunshi

# Common issues:
# - Insufficient GPU resources
# - PVC not bound
# - Node not ready
```

### Training Not Starting

```bash
# Check rendezvous
oc exec tsfm-node-0 -- nslookup tsfm-headless

# Check NCCL initialization
oc logs tsfm-node-0 | grep -i "nccl\|rank"

# Check GPU visibility
oc exec tsfm-node-0 -- nvidia-smi
```

### RDMA Issues

```bash
# Check SR-IOV device allocation
oc exec tsfm-node-0 -- ls -la /sys/class/infiniband/

# Check RDMA connectivity
oc exec tsfm-node-0 -- ibv_devices

# Verify NCCL settings
oc exec tsfm-node-0 -- env | grep NCCL
```

### Storage Issues

```bash
# Check PVC status
oc get pvc tsfm

# Check mount
oc exec tsfm-node-0 -- df -h /mnt/tsfm

# Check permissions
oc exec tsfm-node-0 -- ls -la /mnt/tsfm
```

## Performance Notes

### Expected Performance
- **RDMA bandwidth**: ~80+ GiB/s (with proper IOMMU configuration)
- **GPU utilization**: Near 100% during training
- **Training throughput**: Depends on model size and batch size

### Optimization Tips
1. **Use BF16 precision** (`--precision "bf16"`)
2. **Enable torch.compile** (`--torch_compile`)
3. **Optimize batch size** for GPU memory
4. **Tune gradient accumulation** for effective batch size
5. **Monitor NCCL bandwidth** during training

## Related Documentation

- **RDMA Setup**: `../../docs/rdma/RDMA-SETUP-COMPLETE.md`
- **IOMMU Configuration**: `../../docs/rdma/IOMMU-PASSTHROUGH-FIX.md`
- **InfiniBand Auto-Detection**: `../../IB_AUTO_DETECTION.md`

## Status

- ✅ StatefulSet configurations available
- ✅ RDMA/InfiniBand enabled
- ✅ Multi-node DDP setup
- ✅ Persistent storage configured
- ✅ Ready for TSFM training

## Notes

- Uses the same RDMA infrastructure as h-kim deployment
- Requires IOMMU passthrough on worker nodes
- Service account `h-kim-sa` provides necessary permissions
- Training automatically resumes on pod restart (checkpoints in /mnt/tsfm)
