# H-Kim Deployment - Quick Start

Multi-node distributed training with RDMA/InfiniBand acceleration on OpenShift.

## 🚀 Quick Deploy (3 Steps)

### 1. Deploy the StatefulSet

```bash
cd deployments/h-kim
oc apply -f generated/statefulset-h-kim.yaml
```

Wait for pods to be ready:
```bash
oc get pods -l app=h-kim -w
```

### 2. Verify RDMA Configuration

```bash
oc exec h-kim-0 -- bash /workspace/check-rdma.sh
```

Expected output:
```
✅ RDMA Configuration:
  - 4 InfiniBand devices detected: mlx5_6,mlx5_7,mlx5_10,mlx5_11
  - Memlock: unlimited
  - NCCL_IB_DISABLE=0
  - GDR Level: 5
```

### 3. Run Training

```bash
# Start distributed training on both pods
oc exec h-kim-0 -- /workspace/lm-train.sh &
oc exec h-kim-1 -- /workspace/lm-train.sh &
```

Or with custom configuration:
```bash
oc exec h-kim-0 -- bash -c '
export TORCHTITAN_REPO=/workspace/torchtitan
export CONFIG_FILE=/workspace/torchtitan/train_configs/llama3_70b.toml
/workspace/lm-train.sh
' &

oc exec h-kim-1 -- bash -c '
export TORCHTITAN_REPO=/workspace/torchtitan
export CONFIG_FILE=/workspace/torchtitan/train_configs/llama3_70b.toml
/workspace/lm-train.sh
' &
```

---

## 📦 Alternative: Build Custom Image

### Option A: Use Pre-Built Image (Recommended)

The image is already built and available:
```bash
# Image is pushed to internal registry
oc get imagestream h-kim
```

### Option B: Build from Source

```bash
cd deployments/h-kim

# Create build resources
oc apply -f generated/imagestream-h-kim.yaml
oc apply -f generated/buildconfig-h-kim.yaml

# Start build
oc start-build h-kim --follow
```

Build takes ~10-15 minutes and includes:
- PyTorch 2.6.0 with CUDA 12.6
- NCCL with InfiniBand support
- Mellanox OFED drivers
- SR-IOV RDMA auto-detection
- TorchTitan framework
- Essential ML packages (transformers, datasets, etc.)

---

## 🧪 Test RDMA Performance

### Run NCCL Bandwidth Test

```bash
# Terminal 1 - Run on h-kim-0
oc exec h-kim-0 -- python /workspace/nccl_torch_bench.py

# Terminal 2 - Run on h-kim-1
oc exec h-kim-1 -- python /workspace/nccl_torch_bench.py
```

Expected performance:
- **RDMA Enabled**: 80+ GiB/s
- **TCP Fallback**: ~1 GiB/s

### Manual RDMA Check

```bash
# Check InfiniBand devices
oc exec h-kim-0 -- /workspace/get-ib-devices.sh

# Debug RDMA issues
oc exec h-kim-0 -- /workspace/debug-rdma.sh
```

---

## 📝 TorchTitan Training

### Environment Variables

The `lm-train.sh` script supports these environment variables:

```bash
# Required
TORCHTITAN_REPO=/workspace/torchtitan          # TorchTitan repo path
CONFIG_FILE=/path/to/config.toml               # Training config

# Optional (auto-detected)
NNODES=2                                        # Number of nodes
NPROC_PER_NODE=4                                # GPUs per node
NODE_RANK=0                                     # This node's rank
MASTER_ADDR=h-kim-0.h-kim-headless              # Rendezvous address
MASTER_PORT=29500                               # Rendezvous port

# RDMA (auto-configured by container)
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11     # InfiniBand devices
NCCL_IB_DISABLE=0                              # Enable IB
NCCL_IB_GID_INDEX=3                            # RoCE v2
NCCL_NET_GDR_LEVEL=5                           # GPUDirect RDMA
```

### Training Examples

**Basic Training:**
```bash
# Uses default TorchTitan config
oc exec h-kim-0 -- /workspace/lm-train.sh &
oc exec h-kim-1 -- /workspace/lm-train.sh &
```

**Custom Model:**
```bash
export CONFIG=/workspace/torchtitan/train_configs/llama3_70b.toml

oc exec h-kim-0 -- bash -c "CONFIG_FILE=$CONFIG /workspace/lm-train.sh" &
oc exec h-kim-1 -- bash -c "CONFIG_FILE=$CONFIG /workspace/lm-train.sh" &
```

**Monitor Training:**
```bash
# Follow logs
oc logs -f h-kim-0

# Check GPU utilization
oc exec h-kim-0 -- nvidia-smi
```

---

## 🔧 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
oc describe pod h-kim-0

# Check events
oc get events --sort-by='.lastTimestamp'

# Common issues:
# - No GPU nodes available (check node labels)
# - Image pull errors (check build status)
# - Resource limits (check GPU quota)
```

### RDMA Not Working

```bash
# Verify IOMMU passthrough on nodes
# See: docs/rdma/IOMMU-PASSTHROUGH-FIX.md

# Check if devices are detected
oc exec h-kim-0 -- ls -la /sys/class/infiniband/

# Verify SR-IOV network attachment
oc describe pod h-kim-0 | grep -A5 "Networks"

# Check NCCL environment
oc exec h-kim-0 -- env | grep NCCL
```

### Low Training Performance

```bash
# Test RDMA bandwidth
oc exec h-kim-0 -- python /workspace/nccl_torch_bench.py &
oc exec h-kim-1 -- python /workspace/nccl_torch_bench.py &

# Should see 80+ GiB/s
# If <10 GiB/s, RDMA is likely not working

# Check memlock limit
oc exec h-kim-0 -- ulimit -l
# Should show: unlimited

# Verify GDR is enabled
oc exec h-kim-0 -- env | grep NCCL_NET_GDR_LEVEL
# Should show: 5
```

### Training Fails on h-kim-1

```bash
# Verify TorchTitan is on both pods
oc exec h-kim-1 -- ls -la /workspace/torchtitan/

# If missing, copy from h-kim-0
# (Should be handled by init container, but can copy manually)

# Check rendezvous endpoint
oc exec h-kim-1 -- ping h-kim-0.h-kim-headless
```

---

## 📚 Documentation

### Quick References
- **[README.md](README.md)** - Full project overview
- **[scripts/lm-train.sh](scripts/lm-train.sh)** - Training script source
- **[../../docs/LM-TRAIN-USAGE.md](../../docs/LM-TRAIN-USAGE.md)** - lm-train.sh detailed docs

### Detailed Guides
- **[docs/H-KIM-TORCHTITAN-GUIDE.md](docs/H-KIM-TORCHTITAN-GUIDE.md)** - TorchTitan training guide
- **[docs/H-KIM-TEST-RESULTS.md](docs/H-KIM-TEST-RESULTS.md)** - Performance benchmarks
- **[docs/DEPLOY-H-KIM-IB-AUTODETECT.md](docs/DEPLOY-H-KIM-IB-AUTODETECT.md)** - RDMA implementation
- **[docs/EXAMPLE-DEPLOY-H-KIM.md](docs/EXAMPLE-DEPLOY-H-KIM.md)** - Step-by-step deployment

### RDMA Documentation
- **[../../docs/rdma/RDMA-SETUP-COMPLETE.md](../../docs/rdma/RDMA-SETUP-COMPLETE.md)** - RDMA setup details
- **[../../docs/rdma/IOMMU-PASSTHROUGH-FIX.md](../../docs/rdma/IOMMU-PASSTHROUGH-FIX.md)** - IOMMU configuration
- **[../../IB_AUTO_DETECTION.md](../../IB_AUTO_DETECTION.md)** - Auto-detection system

---

## 🎯 What You Get

### Hardware
- **2 nodes** (h-kim-0, h-kim-1)
- **4x H100 80GB GPUs** per node (8 total)
- **4x InfiniBand HCAs** per node (200 Gbps each)
- **GPUDirect RDMA** for direct GPU-to-GPU communication

### Software
- **PyTorch 2.6.0** with CUDA 12.6
- **NCCL** with InfiniBand support
- **TorchTitan** distributed training framework
- **Auto-configured RDMA** (no manual setup needed)
- **Multi-node coordination** via StatefulSet + headless service

### Performance
- **83+ GiB/s** NCCL bandwidth (measured)
- **85x faster** than TCP-only communication
- **GPUDirect enabled** (GDRDMA mode)
- **Production-ready** distributed training

---

## ⚡ Next Steps

1. **Run a test training job** to verify everything works
2. **Copy your training data** to `/workspace/data/`
3. **Customize TorchTitan config** for your model
4. **Monitor with TensorBoard** or your preferred tool
5. **Scale up** by adjusting `replicas` in StatefulSet

For more details, see the [full documentation](docs/).

---

## 🆘 Getting Help

**Check logs:**
```bash
oc logs h-kim-0 --tail=100
```

**Interactive debugging:**
```bash
oc exec -it h-kim-0 -- bash
```

**View RDMA status:**
```bash
oc exec h-kim-0 -- /workspace/check-rdma.sh
```

**Run diagnostics:**
```bash
oc exec h-kim-0 -- /workspace/debug-rdma.sh
```

See [README.md](README.md) for more troubleshooting tips.
