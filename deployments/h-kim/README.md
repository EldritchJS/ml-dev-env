# H-Kim Deployment

Multi-node distributed training deployment with RDMA/InfiniBand acceleration on OpenShift.

## Overview

This deployment provides:
- **2-node StatefulSet** with 4x H100 GPUs per node (8 GPUs total)
- **RDMA/InfiniBand** auto-detection and configuration
- **GPUDirect RDMA** for high-speed inter-node communication (80+ GiB/s)
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

## Key Features

### RDMA Auto-Detection
- Automatically detects all SR-IOV InfiniBand devices
- Configures NCCL for optimal RDMA performance
- Sets unlimited memlock for RDMA operations
- No manual device configuration needed

### Performance
- **NCCL Bandwidth**: 83+ GiB/s (measured with 8GB transfers)
- **85x improvement** over non-RDMA configuration
- **GPUDirect RDMA** enabled (GDRDMA mode)
- **4x InfiniBand HCAs** per node (mlx5_6, mlx5_7, mlx5_10, mlx5_11)

### NCCL Configuration
```bash
NCCL_IB_DISABLE=0                              # Enable InfiniBand
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11     # Auto-detected devices
NCCL_IB_GID_INDEX=3                            # RoCE v2
NCCL_NET_GDR_LEVEL=5                           # GPUDirect RDMA
NCCL_SOCKET_IFNAME=eth0                        # Out-of-band communication
```

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

- ✅ RDMA auto-detection implemented and tested
- ✅ IOMMU passthrough configured on all worker nodes
- ✅ 83+ GiB/s RDMA bandwidth achieved
- ✅ lm-train.sh verified working on both pods
- ✅ Multi-node TorchTitan setup validated
- ✅ Ready for production distributed training
