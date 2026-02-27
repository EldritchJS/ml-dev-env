# H-Kim Deployment

Multi-node distributed training deployment with RDMA/InfiniBand acceleration on OpenShift.

## Overview

This deployment provides:
- **Dynamically scalable StatefulSet** from 2 to 6 nodes (8 to 24 H100 GPUs)
- **SR-IOV high-performance networking** with 4x RDMA NICs per node
- **GPUDirect RDMA** for high-speed inter-node communication (194 GB/s)
- **NCCL Ring algorithm** optimized for multi-node AllReduce
- **Auto-detection** of network topology and RDMA devices
- **TorchTitan** distributed training framework
- **Custom container image** with NCCL, PyTorch, and RDMA support

## Project Structure

```
deployments/h-kim/
├── README.md                      # This file
├── QUICKSTART.md                  # Quick start guide
├── Dockerfile.nccl-autodetect     # Container image definition
├── nccl_torch_bench.py            # RDMA bandwidth testing tool
├── generated/                     # Generated Kubernetes manifests
│   ├── statefulset-h-kim.yaml    # Main StatefulSet deployment
│   ├── pod-h-kim.yaml            # Single pod deployment (testing)
│   ├── job-h-kim-torchtitan.yaml # TorchTitan training job
│   ├── imagestream-h-kim.yaml    # Container image stream
│   └── buildconfig-h-kim.yaml    # Container build configuration
├── scripts/                       # Deployment and training scripts
│   ├── h-kim-openshift.sh        # OpenShift deployment script
│   ├── h-kim.sh                  # Alternative deployment script
│   ├── lm-train.sh               # TorchTitan training launcher
│   ├── autodetect-nccl.sh        # Comprehensive NCCL auto-detection
│   ├── get-ib-devices.sh         # InfiniBand device detection
│   ├── check-rdma.sh             # RDMA status verification
│   └── debug-rdma.sh             # RDMA debugging utility
├── docs/                          # Documentation
│   ├── H-KIM-QUICKSTART.md       # Original quick start
│   ├── H-KIM-TORCHTITAN-GUIDE.md # TorchTitan usage guide
│   ├── H-KIM-TEST-RESULTS.md     # Performance test results
│   ├── DEPLOY-H-KIM-IB-AUTODETECT.md # RDMA setup details
│   └── EXAMPLE-DEPLOY-H-KIM.md   # Example deployment walkthrough
└── workspace/                     # Workspace for training code/data
```

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions.

### 1. Deploy the StatefulSet

```bash
cd deployments/h-kim
oc apply -f generated/statefulset-h-kim.yaml
```

### 2. Verify RDMA Configuration

```bash
oc exec h-kim-0 -n <namespace> -- bash scripts/check-rdma.sh
```

### 3. Run Training

```bash
# On both pods simultaneously
oc exec h-kim-0 -n <namespace> -- /workspace/lm-train.sh &
oc exec h-kim-1 -n <namespace> -- /workspace/lm-train.sh &
```

## Dynamic Scaling

The h-kim statefulset supports dynamic scaling without YAML editing:

### Scale Up to 6 Nodes (24 GPUs)
```bash
oc scale statefulset h-kim --replicas=6 -n b-efficient-memory-offloading-765cab
```

### Scale Down to 2 Nodes (8 GPUs)
```bash
oc scale statefulset h-kim --replicas=2 -n b-efficient-memory-offloading-765cab
```

### Scale to 0 (Dormant - No Cost)
```bash
oc scale statefulset h-kim --replicas=0 -n b-efficient-memory-offloading-765cab
```

**Note:** When running distributed training or benchmarks, specify `--nnodes` to match your current replica count.

### Workspace Persistence

Each pod has a dedicated 100Gi persistent volume that survives pod deletion:
- Workspace PVCs remain when scaling to 0 replicas
- Training code, datasets, and checkpoints persist
- Scale back up to resume work without data loss

```bash
# View persistent workspaces
oc get pvc -n b-efficient-memory-offloading-765cab | grep workspace-h-kim
```

### Running Benchmarks

To verify NCCL performance across nodes:

```bash
# Copy benchmark script to all pods
for i in {0..N}; do
  oc exec h-kim-$i -n <namespace> -- mkdir -p /workspace/benchmark
  oc cp allreduce-loop.py <namespace>/h-kim-$i:/workspace/benchmark/
done

# Run benchmark on each node (replace N with node count - 1)
for rank in {0..N}; do
  oc exec h-kim-$rank -n <namespace> -- bash -c \
    "cd /workspace/benchmark && \
     torchrun --nnodes=<TOTAL_NODES> --nproc_per_node=4 --node_rank=$rank \
     --master_addr=h-kim-0.h-kim-headless.<namespace>.svc.cluster.local \
     --master_port=29500 --rdzv_backend=c10d \
     --rdzv_endpoint=h-kim-0.h-kim-headless.<namespace>.svc.cluster.local:29500 \
     allreduce-loop.py --multiplier 1" &
done
```

**Example benchmark scripts:**
- `pytorch-benchmark-optimized.yaml` - 2-node automated benchmark
- `pytorch-benchmark-6-nodes.yaml` - 6-node automated benchmark

## Key Features

### Comprehensive Auto-Detection

The deployment uses **comprehensive auto-detection** for all NCCL and hardware parameters:

**Auto-detected at runtime:**
- ✅ GPU count (`GPUS_PER_NODE`)
- ✅ InfiniBand devices (`NCCL_IB_HCA`)
- ✅ RDMA network interfaces (`NCCL_SOCKET_IFNAME`)
- ✅ NVLink topology (`NCCL_P2P_LEVEL`)
- ✅ GPUDirect RDMA support (`NCCL_NET_GDR_LEVEL`)
- ✅ RoCE GID index (`NCCL_IB_GID_INDEX`)
- ✅ Optimal OMP threads (`OMP_NUM_THREADS`)
- ✅ Transport type (RDMA vs TCP)

**Benefits:**
- No hardcoded configuration needed
- Portable across different hardware
- Automatically uses optimal settings
- User can override any detected value

See [../../AUTODETECT-CAPABILITIES.md](../../AUTODETECT-CAPABILITIES.md) for details.

### SR-IOV High-Performance Networking

The deployment uses **SR-IOV** for high-bandwidth RDMA communication:

**Network Configuration:**
- 4x SR-IOV virtual functions per node (net1, net2, net3, net4)
- Multus CNI network attachments (eno5np0-eno8np0)
- MTU 9000 (Jumbo frames)
- RDMA device resources requested per NIC

**NCCL Configuration:**
- `NCCL_SOCKET_IFNAME=net1,net2,net3,net4` - Use all 4 SR-IOV interfaces
- `NCCL_IB_HCA=""` - Auto-detect InfiniBand HCA from socket interfaces
- `NCCL_ALGO=Ring` - Ring algorithm for consistent multi-node performance
- `CUDA_VISIBLE_DEVICES=0,1,2,3` - All 4 GPUs per node

**Node Affinity:**
- moc-r4pcc04u09-nairr
- moc-r4pcc04u11-nairr
- moc-r4pcc04u12-nairr
- moc-r4pcc04u16-nairr
- moc-r4pcc04u25-nairr
- moc-r4pcc04u36-nairr

### Performance

**Validated Performance (Ring Algorithm):**
- **2-node (8 GPUs):** 194 GB/s AllReduce bandwidth
- **6-node (24 GPUs):** 194 GB/s AllReduce bandwidth
- **GPUDirect RDMA** enabled (GDR Level 5)
- **Consistent scaling** across all node configurations

### NCCL Configuration

The deployment combines explicit SR-IOV networking with auto-detected parameters:

**Explicitly Configured:**
```bash
NCCL_SOCKET_IFNAME=net1,net2,net3,net4        # SR-IOV interfaces
NCCL_IB_HCA=""                                 # Let NCCL auto-detect from SOCKET_IFNAME
NCCL_ALGO=Ring                                 # Ring algorithm for multi-node
CUDA_VISIBLE_DEVICES=0,1,2,3                   # All GPUs
```

**Auto-Detected by Init Container:**
```bash
GPUS_PER_NODE=4                                # Detected: nvidia-smi count
OMP_NUM_THREADS=16                             # Detected: 64 CPUs / 4 GPUs
NCCL_IB_DISABLE=0                              # Detected: RDMA available
NCCL_IB_GID_INDEX=3                            # Detected: RoCE v2 in GID table
NCCL_NET_GDR_LEVEL=5                           # Detected: nv_peer_mem module
NCCL_P2P_LEVEL=NVL                             # Detected: nvidia-smi topo -m
DETECTED_TRANSPORT=rdma                        # Detected: InfiniBand present
```

The IB HCA devices (mlx5_*) are auto-detected by NCCL based on the SOCKET_IFNAME mapping, providing portable configuration across nodes with different device numbering.

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide
- **[docs/H-KIM-QUICKSTART.md](docs/H-KIM-QUICKSTART.md)** - Original detailed guide
- **[docs/H-KIM-TORCHTITAN-GUIDE.md](docs/H-KIM-TORCHTITAN-GUIDE.md)** - TorchTitan training guide
- **[docs/H-KIM-TEST-RESULTS.md](docs/H-KIM-TEST-RESULTS.md)** - Performance benchmarks
- **[docs/DEPLOY-H-KIM-IB-AUTODETECT.md](docs/DEPLOY-H-KIM-IB-AUTODETECT.md)** - RDMA implementation details
- **[../../docs/LM-TRAIN-USAGE.md](../../docs/LM-TRAIN-USAGE.md)** - lm-train.sh usage guide

## Container Image

The container image is built from `Dockerfile.nccl-autodetect` and includes:
- PyTorch with CUDA support
- NCCL with InfiniBand support
- Mellanox OFED drivers
- SR-IOV device auto-detection script
- TorchTitan training framework
- Custom optimizer hooks

## Scripts

### Deployment Scripts
- **h-kim-openshift.sh** - Full OpenShift deployment automation
- **h-kim.sh** - Alternative deployment script

### Training Scripts
- **lm-train.sh** - TorchTitan distributed training launcher
  - Auto-detects RDMA devices
  - Configures multi-node setup
  - Handles rendezvous coordination

### RDMA Tools
- **get-ib-devices.sh** - Detect InfiniBand devices
- **check-rdma.sh** - Verify RDMA configuration
- **debug-rdma.sh** - Debug RDMA issues
- **nccl_torch_bench.py** - Benchmark RDMA bandwidth

## Troubleshooting

### Check Pod Status
```bash
oc get pods -l app=h-kim
oc describe pod h-kim-0
```

### View Logs
```bash
oc logs h-kim-0 --tail=100
```

### Verify RDMA
```bash
oc exec h-kim-0 -- bash /workspace/check-rdma.sh
```

### Test RDMA Bandwidth
```bash
# Run on both pods
oc exec h-kim-0 -- python /workspace/nccl_torch_bench.py &
oc exec h-kim-1 -- python /workspace/nccl_torch_bench.py &
```

### Common Issues

**No RDMA devices detected**
- Check IOMMU passthrough: `docs/rdma/IOMMU-PASSTHROUGH-FIX.md`
- Verify SR-IOV configuration
- Check node labels

**Low bandwidth**
- Verify NCCL_IB_HCA is set correctly
- Check memlock is unlimited
- Ensure GDR is enabled (NCCL_NET_GDR_LEVEL=5)

**Training fails on h-kim-1**
- Verify TorchTitan files exist on both pods
- Check TORCHTITAN_REPO environment variable
- Ensure both pods can reach rendezvous endpoint

## Related Documentation

- **RDMA Implementation**: `../../docs/rdma/RDMA-SETUP-COMPLETE.md`
- **IOMMU Fix**: `../../docs/rdma/IOMMU-PASSTHROUGH-FIX.md`
- **Auto-Detection**: `../../IB_AUTO_DETECTION.md`
- **Main Deployment Guide**: `../../docs/H-KIM-RDMA-SETUP.md`

## Status

- ✅ SR-IOV high-performance networking configured
- ✅ NCCL auto-detects IB HCA from SOCKET_IFNAME
- ✅ 194 GB/s NCCL AllReduce bandwidth achieved (Ring algorithm)
- ✅ Dynamic scaling from 0 to 6 nodes via `oc scale`
- ✅ Validated on 2-node (8 GPU) and 6-node (24 GPU) configurations
- ✅ Workspace persistence across pod lifecycle
- ✅ lm-train.sh verified working on both pods
- ✅ Multi-node TorchTitan setup validated
- ✅ Ready for production distributed training
