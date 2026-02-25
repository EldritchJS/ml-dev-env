# GPU-to-NIC Affinity for Optimal RDMA Performance

## Overview

This guide explains how GPU-to-NIC affinity detection works and why it matters for high-performance distributed training with RDMA/InfiniBand.

## Why GPU-to-NIC Affinity Matters

### The Problem

Modern GPU servers have:
- Multiple GPUs (e.g., 4-8 GPUs)
- Multiple InfiniBand NICs/HCAs (e.g., 4 HCAs)
- Multiple CPU sockets/NUMA nodes (e.g., 2 sockets)

These devices are connected via PCIe buses to specific NUMA nodes:

```
NUMA Node 0                    NUMA Node 1
  │                              │
  ├─ GPU 0                       ├─ GPU 2
  ├─ GPU 1                       ├─ GPU 3
  ├─ mlx5_6 (IB HCA)             ├─ mlx5_10 (IB HCA)
  └─ mlx5_7 (IB HCA)             └─ mlx5_11 (IB HCA)
```

### Performance Impact

**Without affinity awareness:**
- GPU 0 might use mlx5_10 (cross-NUMA)
- Requires PCIe hop: GPU → CPU socket 0 → CPU socket 1 → HCA
- **Higher latency, lower bandwidth**

**With affinity awareness:**
- GPU 0 uses mlx5_6 or mlx5_7 (same NUMA node)
- Direct PCIe path: GPU → HCA
- **Lower latency, higher bandwidth**

**Performance difference:**
- Same-NUMA: ~100 GB/s, <2μs latency
- Cross-NUMA: ~80 GB/s, ~3-4μs latency
- **20-25% performance difference!**

## How It Works

### Detection Process

Our affinity detection script (`detect-gpu-nic-affinity.sh`) performs:

1. **GPU NUMA Discovery**
   - Uses `nvidia-smi --query-gpu=numa_node`
   - Falls back to `/sys/bus/pci/devices/.../numa_node`

2. **NIC NUMA Discovery**
   - Reads `/sys/class/net/<interface>/device/numa_node`
   - Maps network interfaces to NUMA topology

3. **IB Device Mapping**
   - Uses `ibdev2netdev` to map mlx5_X → net1, net2, etc.
   - Falls back to sysfs traversal

4. **Topology Analysis**
   - Parses `nvidia-smi topo -m` for hints
   - Builds GPU-to-NIC affinity map

5. **NCCL Configuration**
   - Generates optimal `NCCL_IB_HCA` setting
   - Creates `NCCL_SOCKET_IFNAME` for all interfaces
   - Sets GPUDirect RDMA parameters

### Output Files

The script generates three files in `/shared/`:

#### 1. `nccl-env.sh` - NCCL Configuration

```bash
# NCCL configuration with GPU-to-NIC affinity awareness
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
export NCCL_NET_GDR_LEVEL=5
export NCCL_IB_DISABLE=0
export NCCL_IB_GID_INDEX=3
export NCCL_P2P_LEVEL=NVL
```

**Usage in training:**
```bash
source /shared/nccl-env.sh
torchrun --nproc_per_node=4 train.py
```

#### 2. `gpu-nic-affinity.txt` - Human-Readable Report

```
GPU-to-NIC Affinity Report
==========================

GPU Topology:
  GPU 0: NUMA node 0
  GPU 1: NUMA node 0
  GPU 2: NUMA node 1
  GPU 3: NUMA node 1

NIC Topology:
  net1: NUMA node 0, IB device mlx5_6
  net2: NUMA node 0, IB device mlx5_7
  net3: NUMA node 1, IB device mlx5_10
  net4: NUMA node 1, IB device mlx5_11

Affinity Recommendations:
  GPU 0 (NUMA 0): Prefer NICs net1 net2
  GPU 1 (NUMA 0): Prefer NICs net1 net2
  GPU 2 (NUMA 1): Prefer NICs net3 net4
  GPU 3 (NUMA 1): Prefer NICs net3 net4
```

#### 3. `nccl-topology.xml` - NCCL Topology File (Advanced)

Optional XML file for explicit topology description. Currently a placeholder; NCCL auto-detection works well with environment variables.

## Using Affinity Detection

### In Pod Manifests (Automatic)

Use the affinity detection script in an init container:

```yaml
initContainers:
- name: detect-rdma-affinity
  image: your-ml-image
  command:
  - /bin/bash
  - -c
  - |
    # Install script if not in image
    curl -Lo /tmp/detect-affinity.sh \
      https://raw.githubusercontent.com/your-repo/ml-dev-env/main/scripts/detect-gpu-nic-affinity.sh
    chmod +x /tmp/detect-affinity.sh

    # Run detection
    /tmp/detect-affinity.sh

    # Show results
    echo "=== GPU-NIC Affinity ==="
    cat /shared/gpu-nic-affinity.txt

  volumeMounts:
  - name: shared-config
    mountPath: /shared
  securityContext:
    capabilities:
      add:
      - IPC_LOCK
      - SYS_ADMIN  # Needed for NUMA queries

containers:
- name: training
  command:
  - /bin/bash
  - -c
  - |
    # Source NCCL configuration
    source /shared/nccl-env.sh

    # Show affinity info
    cat /shared/gpu-nic-affinity.txt

    # Run training
    torchrun --nproc_per_node=4 train.py

  volumeMounts:
  - name: shared-config
    mountPath: /shared

volumes:
- name: shared-config
  emptyDir: {}
```

### Manual Usage

Run the script manually to understand your system:

```bash
# In a pod with GPUs and RDMA
./scripts/detect-gpu-nic-affinity.sh

# View the report
cat /shared/gpu-nic-affinity.txt

# Source NCCL config
source /shared/nccl-env.sh

# Verify
echo $NCCL_IB_HCA
echo $NCCL_SOCKET_IFNAME
```

## How NCCL Uses This Information

### Automatic Path Selection

With affinity-aware configuration, NCCL:

1. **Knows all available HCAs** (`NCCL_IB_HCA`)
2. **Can choose the best path** for each GPU-to-GPU communication
3. **Minimizes PCIe hops** by preferring local NICs
4. **Falls back to cross-NUMA** when needed (e.g., inter-node)

### Communication Patterns

**Intra-node (GPU 0 ↔ GPU 1):**
- Uses NVLink (fastest) if available
- Or uses local PCIe switches
- NCCL_P2P_LEVEL=NVL enables this

**Inter-node (GPU 0 ↔ Remote GPU):**
- GPU 0 uses mlx5_6 or mlx5_7 (local to NUMA 0)
- Remote GPU uses its local HCA
- GPUDirect RDMA with NCCL_NET_GDR_LEVEL=5

### Advanced: Per-Rank HCA Selection

For even finer control, you can set HCA per NCCL rank:

```bash
# In your training script wrapper
LOCAL_RANK=$1  # From torchrun
GPU_ID=$CUDA_VISIBLE_DEVICES

# Determine which HCAs are local to this GPU
case $GPU_ID in
  0|1) export NCCL_IB_HCA="mlx5_6,mlx5_7" ;;  # NUMA 0
  2|3) export NCCL_IB_HCA="mlx5_10,mlx5_11" ;;  # NUMA 1
esac

# Run training
python train.py --local_rank=$LOCAL_RANK
```

## PyTorch Integration

### Automatic with NCCL

PyTorch uses NCCL for GPU communication, so NCCL environment variables are automatically used:

```python
import torch
import torch.distributed as dist

# Initialize with NCCL backend
dist.init_process_group(backend="nccl")

# NCCL automatically uses:
# - NCCL_IB_HCA for available HCAs
# - NCCL_SOCKET_IFNAME for network interfaces
# - Affinity info to choose best paths

# Your training code
model = torch.nn.parallel.DistributedDataParallel(model)
```

### Process Binding (Advanced)

For maximum performance, also bind processes to NUMA nodes:

```bash
# Wrapper script that runs before training
LOCAL_RANK=$1

# Determine NUMA node for this GPU
case $LOCAL_RANK in
  0|1) NUMA_NODE=0 ;;
  2|3) NUMA_NODE=1 ;;
esac

# Bind process to NUMA node
numactl --cpunodebind=$NUMA_NODE --membind=$NUMA_NODE \
  python train.py --local_rank=$LOCAL_RANK
```

**Combined wrapper:**
```bash
#!/bin/bash
LOCAL_RANK=$1

# Set NUMA and HCA based on GPU
case $LOCAL_RANK in
  0|1)
    NUMA_NODE=0
    export NCCL_IB_HCA="mlx5_6,mlx5_7"
    ;;
  2|3)
    NUMA_NODE=1
    export NCCL_IB_HCA="mlx5_10,mlx5_11"
    ;;
esac

# Run with NUMA binding
numactl --cpunodebind=$NUMA_NODE --membind=$NUMA_NODE \
  python train.py --local_rank=$LOCAL_RANK
```

## Verifying Affinity Usage

### Check NCCL Initialization

Look for NCCL initialization logs:

```bash
export NCCL_DEBUG=INFO
python -c "import torch; torch.distributed.init_process_group(backend='nccl'); ..."
```

Look for:
```
NCCL INFO Using network IB
NCCL INFO Selected interface mlx5_6:1
NCCL INFO NET/IB: Using interface mlx5_6 for sideband communication
```

This confirms NCCL is using InfiniBand and which HCA.

### Benchmark with/without Affinity

Compare performance:

```bash
# Without affinity (all HCAs, random selection)
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
export NCCL_DEBUG=INFO
python train.py

# With per-GPU affinity
# Use wrapper script above
./train_with_affinity.sh
```

Measure:
- **Training throughput** (samples/sec)
- **Communication time** (from NCCL DEBUG logs)
- **Bandwidth** (from nvidia-smi or nvbandwidth)

## Troubleshooting

### Affinity Detection Fails

**Problem:** Script doesn't detect NUMA nodes correctly

**Solution:**
```bash
# Check if NUMA info is available
nvidia-smi --query-gpu=index,numa_node --format=csv

# Check NIC NUMA manually
for nic in net1 net2 net3 net4; do
  echo -n "$nic: "
  cat /sys/class/net/$nic/device/numa_node 2>/dev/null || echo "unknown"
done

# Verify ibdev2netdev works
ibdev2netdev
```

### NCCL Not Using Detected HCAs

**Problem:** NCCL ignores NCCL_IB_HCA setting

**Check:**
```bash
# Verify HCA names are correct
ibv_devinfo -l

# Check if HCAs are actually usable
for hca in mlx5_6 mlx5_7 mlx5_10 mlx5_11; do
  ibv_devinfo -d $hca | grep state
done

# Should show: state: PORT_ACTIVE
```

**Fix:** Ensure HCAs are in ACTIVE state and accessible from the container.

### Performance Still Poor

**Debug checklist:**
1. ✅ Verify GPUDirect RDMA is enabled: `NCCL_NET_GDR_LEVEL=5`
2. ✅ Check RDMA is enabled: `NCCL_IB_DISABLE=0`
3. ✅ Verify HCAs are local to GPUs (check affinity report)
4. ✅ Ensure processes are NUMA-bound
5. ✅ Check for PCIe bottlenecks: `nvidia-smi topo -m`
6. ✅ Run `nvbandwidth` to test peak bandwidth

## Examples

### Example 1: 4-GPU Single Node (Barcelona)

**Topology:**
```
NUMA 0: GPU 0, GPU 1, mlx5_6, mlx5_7
NUMA 1: GPU 2, GPU 3, mlx5_10, mlx5_11
```

**Generated NCCL config:**
```bash
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
```

**Training:**
```bash
source /shared/nccl-env.sh
torchrun --nproc_per_node=4 train.py
```

**Result:**
- GPU 0↔1 communication: NVLink (same NUMA)
- GPU 0↔2 communication: mlx5_6 → mlx5_10 (cross-NUMA but optimal)

### Example 2: Multi-Node Training

**2 nodes, 4 GPUs each:**

```bash
# Node 0
source /shared/nccl-env.sh
torchrun --nnodes=2 --node_rank=0 --nproc_per_node=4 \
  --master_addr=node-0 --master_port=29500 \
  train.py

# Node 1
source /shared/nccl-env.sh
torchrun --nnodes=2 --node_rank=1 --nproc_per_node=4 \
  --master_addr=node-0 --master_port=29500 \
  train.py
```

**NCCL will:**
- Use NVLink for same-node GPU communication
- Use local HCAs for inter-node communication
- Automatically select best path per communication pair

## Best Practices

1. **Always run affinity detection** in init container for multi-GPU RDMA setups
2. **Review affinity report** (`gpu-nic-affinity.txt`) to understand topology
3. **Enable NCCL_DEBUG=INFO** during first runs to verify HCA selection
4. **Benchmark** with and without affinity to measure impact
5. **Bind processes to NUMA nodes** for maximum performance
6. **Monitor PCIe bandwidth** with `nvidia-smi topo -m` or `nvbandwidth`
7. **Use GPUDirect RDMA** (`NCCL_NET_GDR_LEVEL=5`) when available

## Performance Expectations

With proper affinity configuration:

**Single Node (4 GPUs):**
- GPU-GPU bandwidth: 90-100 GB/s (NVLink)
- GPU-GPU latency: <5μs (NVLink)
- Cross-NUMA efficiency: 95%+

**Multi-Node (RDMA):**
- Inter-node bandwidth: 80-90 GB/s (GPUDirect RDMA)
- Inter-node latency: 2-5μs
- Same-NUMA HCA preference: 10-20% faster

**Without affinity awareness:**
- Random HCA selection: 20-30% slower
- Cross-NUMA penalties: 15-25% overhead

## References

- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [NVIDIA GPU Topology](https://docs.nvidia.com/cuda/gpudirect-rdma/index.html)
- [NUMA Architecture](https://en.wikipedia.org/wiki/Non-uniform_memory_access)
- [InfiniBand Architecture](https://www.infinibandta.org/)

## Related Documentation

- [MULTI-NODE-GUIDE.md](MULTI-NODE-GUIDE.md) - Multi-node training setup
- [RDMA-AUTODETECT-IMPLEMENTATION.md](../RDMA-AUTODETECT-IMPLEMENTATION.md) - Basic RDMA detection
- [SCC-MEMLOCK-COMPLETE.md](../SCC-MEMLOCK-COMPLETE.md) - Memory locking for RDMA
