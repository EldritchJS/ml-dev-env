# Prism Deployment - BEACON Continued Pre-training

Multi-node distributed training deployment for Barcelona H100 cluster.

## Overview

This deployment provides:
- **NeMo Toolkit** for large-scale LLM training
- **DeepSpeed** for memory-efficient distributed training
- **HuggingFace ecosystem** (transformers, datasets, accelerate, peft, trl)
- **MXFP4 kernel support** (kernels>=0.12.0)
- **Multi-node NCCL** over RDMA/InfiniBand
- **5-node H100 setup** with GPUDirect RDMA

## Container Image

**Base:** `nvcr.io/nvidia/pytorch:25.06-py3`
- PyTorch 2.6+
- CUDA 12.8
- NCCL 2.24+

**Additions:**
- NeMo Toolkit 2.0.0 [nlp]
- DeepSpeed 0.15.4
- Lightning 2.4.0
- Full HuggingFace stack
- See `workspace/requirements.txt` for complete list

## Build Status

### Phase 1: Building Image ⏳

**Current status:**
```bash
oc get builds
# NAME                  TYPE     FROM          STATUS
# prism-image-build-1   Docker   Git@b9389e5   Running
```

**Follow build logs:**
```bash
oc logs -f bc/prism-image-build
```

**Build time:** ~15-20 minutes (NeMo installation is slow)

**Image location (after build):**
```
image-registry.openshift-image-registry.svc:5000/nccl-test/prism:test
```

### Phase 2: Test Single-Node Pod (Next)

After build completes:
```bash
# Deploy test pod
oc apply -f generated/pod-prism-test.yaml

# Monitor pod startup
oc get pod prism-test -w

# Check test results
oc logs prism-test
```

**Expected test output:**
- ✅ GPU detection (4x H100)
- ✅ RDMA device detection (mlx5_6, mlx5_7, mlx5_10, mlx5_11)
- ✅ All Python packages import successfully
- ✅ PyTorch CUDA operations work
- ✅ NCCL initialized correctly

### Phase 3: Push to Quay (If tests pass)

```bash
# Tag for quay
oc tag prism:test quay.io/jschless/ml-dev-env:prism

# Or manually push
podman pull image-registry.openshift-image-registry.svc:5000/nccl-test/prism:test
podman tag <image-id> quay.io/jschless/ml-dev-env:prism
podman push quay.io/jschless/ml-dev-env:prism
```

### Phase 4: Multi-Node Deployment (Future)

After image validated and pushed to quay:
- Create 5-node StatefulSet
- Configure NCCL for multi-node RDMA
- Set up shared PVCs for datasets/checkpoints

## Barcelona Cluster Configuration

### RDMA Devices (Auto-detected)
- **IB devices:** mlx5_6, mlx5_7, mlx5_10, mlx5_11
- **Network interfaces:** net1, net2, net3, net4
- **GID index:** 3 (RoCE v2)

### NCCL Settings
```bash
NCCL_IB_DISABLE=0                    # RDMA enabled
NCCL_IB_GID_INDEX=3                  # RoCE v2
NCCL_NET_GDR_LEVEL=5                 # GPUDirect RDMA
NCCL_IB_TIMEOUT=22                   
NCCL_DMABUF_ENABLE=1                 # GPUDirect without nvidia_peermem
NCCL_CROSS_NIC=1                     # Barcelona setting
NCCL_MIN_NCHANNELS=4
NCCL_P2P_LEVEL=NVL                   # NVLink intra-node
```

### Resource Allocation (per pod)
- **GPUs:** 4x H100 80GB
- **RDMA:** 4x rdma_shared_device_a
- **Memory:** 128Gi request, 256Gi limit
- **CPU:** 32 cores request, 64 cores limit

## Files

```
deployments/prism/
├── Dockerfile                           # Container image definition
├── README.md                            # This file
├── generated/
│   ├── buildconfig-prism.yaml          # OpenShift BuildConfig
│   └── pod-prism-test.yaml             # Single-node test pod
└── workspace/
    └── requirements.txt                # Python dependencies
```

## Troubleshooting

### Build Issues

**Check build logs:**
```bash
oc logs -f bc/prism-image-build
```

**Common issues:**
- NeMo installation timeout → Increase build resources
- Dependency conflicts → Check version compatibility
- Git clone failure → Verify GitHub repo accessibility

**Rebuild:**
```bash
oc start-build prism-image-build
```

### Test Pod Issues

**Pod won't start:**
```bash
oc describe pod prism-test
# Check Events section
```

**Package import failures:**
```bash
oc logs prism-test | grep -i error
```

**RDMA detection issues:**
```bash
# Check init container logs
oc logs prism-test -c detect-rdma

# Expected output:
# Detected IB devices: mlx5_6,mlx5_7,mlx5_10,mlx5_11
# Detected RDMA interfaces: net1,net2,net3,net4
```

**GPU not detected:**
```bash
oc exec prism-test -- nvidia-smi
```

## Next Steps

1. ⏳ **Wait for build to complete** (~15-20 min)
2. ✅ **Deploy test pod** and verify all packages work
3. ✅ **Run NCCL test** to confirm RDMA working
4. ✅ **Push to quay** if tests pass
5. ✅ **Build 5-node StatefulSet** for multi-node training

## Related Documentation

- Barcelona cluster config: `/clusters/barcelona.yaml`
- Deepti deployment (reference): `/deployments/deepti/`
- H100 NCCL gold standard: `/deployments/h-kim/GOLD-STANDARD-NCCL-BENCHMARK.yaml`
- NCCL configuration guide: `/claude_guidance/nccl-configuration-h100-cluster.md`
