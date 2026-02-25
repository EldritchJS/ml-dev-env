# How NCCL Uses GPU-to-NIC Affinity Configuration

## The Key Question

When we set:
```bash
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
```

How does NCCL know which GPU should use which HCA? Does it actually use affinity, or just pick randomly?

## The Answer: Two Approaches

### Approach 1: Auto-Detection (What We Currently Do)

**Configuration:**
```bash
# List ALL available HCAs
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
```

**How NCCL Uses This:**

1. **NCCL internally detects topology** using:
   - GPU PCIe bus topology (from CUDA)
   - HCA PCIe bus topology (from libibverbs)
   - NUMA node information (from sysfs)

2. **NCCL builds a cost matrix:**
   ```
   Cost to use each HCA from each GPU:
                mlx5_6  mlx5_7  mlx5_10  mlx5_11
   GPU 0 (NUMA 0):  1      1       3        3      <- Lower is better
   GPU 1 (NUMA 0):  1      1       3        3
   GPU 2 (NUMA 1):  3      3       1        1
   GPU 3 (NUMA 1):  3      3       1        1

   Cost 1 = Same NUMA node (local, fast)
   Cost 3 = Cross NUMA node (remote, slower)
   ```

3. **NCCL automatically prefers low-cost paths:**
   - When GPU 0 needs to communicate, NCCL prefers mlx5_6 or mlx5_7
   - When GPU 2 needs to communicate, NCCL prefers mlx5_10 or mlx5_11
   - Falls back to higher-cost paths if needed (e.g., congestion)

**Key Point:** By listing all HCAs, we let NCCL auto-detect and choose the best one for each GPU based on internal topology discovery.

**Pros:**
- ✅ Simple configuration
- ✅ NCCL is smart about topology
- ✅ Automatic load balancing across HCAs
- ✅ Works well for most cases

**Cons:**
- ⚠️ Relies on NCCL's internal heuristics
- ⚠️ Less explicit control
- ⚠️ Might not always choose optimally in complex topologies

### Approach 2: Explicit Per-Rank Configuration (Advanced)

For finer control, set `NCCL_IB_HCA` **per-rank** to only include local HCAs:

**Configuration (per-rank):**
```bash
# Rank 0 (GPU 0, NUMA 0)
export NCCL_IB_HCA="mlx5_6,mlx5_7"  # Only NUMA 0 HCAs

# Rank 1 (GPU 1, NUMA 0)
export NCCL_IB_HCA="mlx5_6,mlx5_7"  # Only NUMA 0 HCAs

# Rank 2 (GPU 2, NUMA 1)
export NCCL_IB_HCA="mlx5_10,mlx5_11"  # Only NUMA 1 HCAs

# Rank 3 (GPU 3, NUMA 1)
export NCCL_IB_HCA="mlx5_10,mlx5_11"  # Only NUMA 1 HCAs
```

**How NCCL Uses This:**

1. Each rank only sees its local HCAs
2. NCCL is **forced** to use local paths (can't use cross-NUMA)
3. Load balancing happens only among local HCAs

**Pros:**
- ✅ Explicit control
- ✅ Guaranteed local HCA usage
- ✅ No possibility of cross-NUMA selection
- ✅ Easier to debug (less guessing)

**Cons:**
- ⚠️ More complex setup
- ⚠️ No fallback if local HCAs are congested
- ⚠️ Requires per-rank wrapper scripts

## How NCCL Actually Detects Topology

### Step 1: GPU Topology Discovery

NCCL uses CUDA to query GPU PCIe topology:

```c
// NCCL internal code (simplified)
cudaDeviceGetPCIBusId(gpu_id, &pci_bus_id);
// Result: GPU 0 -> 0000:17:00.0

// Read NUMA node from sysfs
numa_node = read("/sys/bus/pci/devices/0000:17:00.0/numa_node");
// Result: GPU 0 -> NUMA 0
```

### Step 2: HCA Topology Discovery

NCCL uses libibverbs to query HCA topology:

```c
// NCCL internal code (simplified)
ibv_get_device_list(&num_devices);
for (each device) {
    device_name = ibv_get_device_name(device);  // "mlx5_6"

    // Read PCI bus ID
    pci_bus_id = read("/sys/class/infiniband/mlx5_6/device/uevent");
    // Result: mlx5_6 -> 0000:19:00.0

    // Read NUMA node
    numa_node = read("/sys/class/infiniband/mlx5_6/device/numa_node");
    // Result: mlx5_6 -> NUMA 0
}
```

### Step 3: Build Affinity Table

NCCL creates an internal affinity table:

```c
// Pseudo-code for NCCL's internal logic
for (each GPU) {
    gpu_numa = get_gpu_numa_node(gpu_id);

    for (each HCA in NCCL_IB_HCA) {
        hca_numa = get_hca_numa_node(hca_name);

        if (gpu_numa == hca_numa) {
            affinity[gpu_id][hca_name] = LOCAL;  // Cost = 1
        } else {
            affinity[gpu_id][hca_name] = REMOTE; // Cost = 3
        }
    }
}
```

### Step 4: Path Selection During Communication

When GPU 0 needs to send data to GPU 4 (on another node):

```c
// NCCL communication setup
src_gpu = 0;  // Local GPU
dst_gpu = 4;  // Remote GPU (on another node)

// Choose HCA for this GPU
hca = select_best_hca(src_gpu, available_hcas, affinity_table);
// Result: mlx5_6 (local to GPU 0, NUMA 0)

// Create RDMA connection
rdma_connect(hca, dst_node_ip);
```

**Selection logic:**
```c
select_best_hca(gpu_id, hcas, affinity) {
    // Prefer local HCAs
    local_hcas = filter(hcas, affinity[gpu_id] == LOCAL);
    if (local_hcas.size() > 0) {
        return round_robin(local_hcas);  // Load balance
    }

    // Fallback to remote HCAs if needed
    return round_robin(hcas);
}
```

## The Critical Configuration Variables

### NCCL_IB_HCA

**What it does:**
- Tells NCCL which InfiniBand HCAs are available
- NCCL probes each HCA to find NUMA affinity
- Creates topology map internally

**Affinity impact:**
```bash
# All HCAs - NCCL chooses based on topology
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"

# Only local HCAs (per-rank) - forces local usage
export NCCL_IB_HCA="mlx5_6,mlx5_7"  # For ranks on NUMA 0
```

### NCCL_IB_GID_INDEX

**What it does:**
- Specifies which GID (Global Identifier) to use
- GID index 3 is typically RoCE v2 (IP-based InfiniBand)
- Doesn't affect affinity, but needed for RDMA to work

**Why it matters:**
```bash
export NCCL_IB_GID_INDEX=3  # Use RoCE v2
# Without this, NCCL might use wrong GID and fail
```

### NCCL_NET_GDR_LEVEL

**What it does:**
- Controls GPUDirect RDMA (direct GPU-to-GPU memory access)
- Level 5 = Full GPUDirect (GPU memory → RDMA NIC directly)

**Affinity impact:**
```bash
export NCCL_NET_GDR_LEVEL=5

# With GPUDirect + local HCA:
# GPU memory → PCIe → Local HCA → Network (1 hop)

# With GPUDirect + remote HCA:
# GPU memory → PCIe → QPI/UPI → Remote HCA → Network (2 hops)

# Difference: ~2μs vs ~4μs latency!
```

### NCCL_P2P_LEVEL

**What it does:**
- Controls intra-node GPU communication method
- NVL = Prefer NVLink for direct GPU-GPU

**Why it matters:**
```bash
export NCCL_P2P_LEVEL=NVL

# Same-node GPU communication:
# GPU 0 ↔ GPU 1: Use NVLink (~600 GB/s)
#
# Cross-node GPU communication:
# GPU 0 ↔ GPU 4: Use RDMA via local HCA (~90 GB/s)
```

### NCCL_SOCKET_IFNAME

**What it does:**
- Lists network interfaces for socket-based communication
- Used as fallback if InfiniBand doesn't work
- Also used for initial connection setup

**Affinity impact:**
- Indirect - if RDMA fails, falls back to sockets
- Should list interfaces in affinity order

```bash
export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
# Same order as HCAs for consistency
```

## Verifying NCCL Is Using Affinity

### Method 1: NCCL Debug Logs

```bash
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET

python train.py 2>&1 | grep -E "NET|IB|Selected"
```

**Look for these lines:**

```
NCCL INFO NET/IB : Using [0]mlx5_6:1/RoCE ; OOB eth0:<ip>
                           ^^^^^^^^
                           This is the HCA NCCL selected!

NCCL INFO Selected interface mlx5_6:1 for GPU 0
                                ^^^^^^    ^^^^^
                                HCA name  GPU that will use it
```

**Verify affinity:**
- GPU 0 should use mlx5_6 or mlx5_7 (NUMA 0)
- GPU 2 should use mlx5_10 or mlx5_11 (NUMA 1)

### Method 2: Check NUMA Binding

```bash
# In training script
echo "Rank $RANK using HCA: $NCCL_IB_HCA"

# Should see per-rank:
# Rank 0 using HCA: mlx5_6,mlx5_7
# Rank 2 using HCA: mlx5_10,mlx5_11
```

### Method 3: Performance Test

```bash
# Test bandwidth with affinity
source /shared/nccl-env.sh
./nccl-tests/build/all_reduce_perf -b 1G -e 1G -f 2 -g 4

# Note the bandwidth

# Test without affinity (all HCAs, random)
export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
export CUDA_VISIBLE_DEVICES="0"  # Force cross-NUMA for GPU 0
export NCCL_IB_HCA="mlx5_10,mlx5_11"  # Only remote HCAs

./nccl-tests/build/all_reduce_perf -b 1G -e 1G -f 2 -g 1

# Should be slower!
```

## Implementation in Our Code

### Current Implementation (Auto-Detection)

In `scripts/detect-gpu-nic-affinity.sh`:

```bash
# Detect all HCAs
IB_DEVICES=$(ibv_devinfo -l | tr '\n' ',' | sed 's/,$//')

# Detect all RDMA interfaces
RDMA_IFACES=$(ip link show | grep net[0-9] | tr '\n' ',' | sed 's/,$//')

# Set for all ranks (NCCL will auto-detect topology)
export NCCL_IB_HCA="$IB_DEVICES"
export NCCL_SOCKET_IFNAME="$RDMA_IFACES"
```

**How NCCL uses this:**
1. Sees all 4 HCAs: mlx5_6,mlx5_7,mlx5_10,mlx5_11
2. Internally detects GPU 0 is on NUMA 0
3. Internally detects mlx5_6,mlx5_7 are on NUMA 0
4. **Automatically prefers mlx5_6 or mlx5_7 for GPU 0**
5. Load balances between mlx5_6 and mlx5_7

### Advanced Implementation (Explicit Per-Rank)

To make affinity explicit, we'd need a launcher wrapper:

```bash
#!/bin/bash
# launch_with_affinity.sh

LOCAL_RANK=$1
LOCAL_GPU=$CUDA_VISIBLE_DEVICES

# Detect which NUMA node this GPU is on
GPU_NUMA=$(nvidia-smi -i $LOCAL_RANK --query-gpu=numa_node --format=csv,noheader)

# Set NCCL_IB_HCA to only local HCAs
case $GPU_NUMA in
  0)
    export NCCL_IB_HCA="mlx5_6,mlx5_7"
    export NCCL_SOCKET_IFNAME="net1,net2"
    ;;
  1)
    export NCCL_IB_HCA="mlx5_10,mlx5_11"
    export NCCL_SOCKET_IFNAME="net3,net4"
    ;;
  *)
    # Unknown NUMA - use all HCAs
    export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
    ;;
esac

echo "Rank $LOCAL_RANK (GPU $LOCAL_RANK, NUMA $GPU_NUMA) using HCAs: $NCCL_IB_HCA"

# Run training
exec python train.py --local_rank=$LOCAL_RANK "$@"
```

**Usage:**
```bash
# Instead of:
torchrun --nproc_per_node=4 train.py

# Use:
torchrun --nproc_per_node=4 launch_with_affinity.sh
```

## Why Auto-Detection Works Well

**NCCL's topology detection is actually quite sophisticated:**

1. **PCIe tree traversal:** NCCL walks the PCIe topology to find shortest paths
2. **NUMA awareness:** NCCL reads `/sys/bus/pci/devices/*/numa_node`
3. **Cost modeling:** NCCL assigns costs based on PCIe hops
4. **Smart selection:** NCCL prefers low-cost paths automatically

**From NCCL source code (nvidia-nccl/src/transport/net.cc):**

```c
// NCCL ranks devices by their affinity to GPUs
static ncclResult_t getNetDeviceAffinity(int dev, int* affinity) {
  char* path;
  // Read NUMA node from sysfs
  NCCLCHECK(getNicNumaNode(dev, affinity));
  return ncclSuccess;
}

// When selecting a device for a GPU:
int bestDev = -1;
int bestAffinity = -1;

for (int d = 0; d < nDevs; d++) {
  int affinity;
  getNetDeviceAffinity(d, &affinity);

  // Prefer devices on the same NUMA node as GPU
  if (affinity == gpuNumaNode) {
    bestDev = d;
    break;
  }
}
```

## Summary: How Configuration Enables Affinity

### The Simple Answer

**Setting `NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"` enables affinity because:**

1. ✅ NCCL **internally detects** which HCAs are local to which GPUs
2. ✅ NCCL **automatically prefers** local HCAs when making connections
3. ✅ We don't need to do anything explicit - NCCL is smart!

### The More Explicit Answer

**For guaranteed affinity, set `NCCL_IB_HCA` per-rank:**

1. ✅ Each rank only sees its local HCAs
2. ✅ NCCL is **forced** to use local paths
3. ✅ No guessing, no auto-detection needed

### Configuration Comparison

| Configuration | NCCL Behavior | Affinity | Complexity |
|---------------|---------------|----------|------------|
| **All HCAs (current)** | Auto-detects topology, prefers local | ✅ Yes (automatic) | Simple |
| **Per-rank HCAs (advanced)** | Only sees local HCAs, must use them | ✅ Yes (forced) | Complex |
| **No HCA list** | Uses first found HCA | ❌ No | Very simple |
| **Wrong HCA list** | May use non-local HCAs | ⚠️ Partial | Broken |

### Best Practice

For most users: **Use auto-detection (current approach)**
- Simple configuration
- NCCL is smart about topology
- Good performance in 95% of cases

For advanced users with complex topologies: **Use per-rank configuration**
- Explicit control
- Guaranteed optimal paths
- Worth the extra complexity

## Related NCCL Variables for Debugging

```bash
# See all NCCL decisions
export NCCL_DEBUG=INFO

# See detailed network topology
export NCCL_DEBUG_SUBSYS=NET,INIT,GRAPH

# Force topology dump
export NCCL_TOPO_DUMP_FILE=/tmp/nccl-topo.xml

# Test specific HCA
export NCCL_IB_HCA=mlx5_6  # Test just one

# Disable RDMA (to compare)
export NCCL_IB_DISABLE=1
```

## References

- [NCCL Source Code - Net Transport](https://github.com/NVIDIA/nccl/blob/master/src/transport/net.cc)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [NCCL Topology Detection](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/topo.html)
- [InfiniBand Architecture](https://www.infinibandta.org/)
