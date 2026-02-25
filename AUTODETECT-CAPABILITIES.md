# Auto-Detection Capabilities

## Overview

The ML dev environment now includes **comprehensive auto-detection** that eliminates most hardcoded configuration values.

## What's Auto-Detected

### Current Simple Detection (Basic RDMA)

**Script:** Init container in manifests

**Detects:**
- ✅ **InfiniBand devices** (`NCCL_IB_HCA`)
  - Uses `ibv_devinfo -l`
  - Example: `mlx5_6,mlx5_7,mlx5_10,mlx5_11`

- ✅ **RDMA network interfaces** (`NCCL_SOCKET_IFNAME`)
  - Uses `ip link show | grep net[0-9]`
  - Example: `net1,net2,net3,net4`

**Still Hardcoded:**
- ❌ GPU count (`nvidia.com/gpu: 4`)
- ❌ `WORLD_SIZE` (`value: "8"`)
- ❌ `GPUS_PER_NODE` (`value: "4"`)
- ❌ `OMP_NUM_THREADS` (`value: "8"`)
- ❌ `NCCL_IB_GID_INDEX` (`value: "3"`)
- ❌ `NCCL_NET_GDR_LEVEL` (`value: "5"`)
- ❌ `NCCL_P2P_LEVEL` (`value: "NVL"`)

### Enhanced Detection (Comprehensive)

**Script:** `scripts/autodetect-full-nccl-config.sh`

**Detects Everything:**

#### 1. GPU Detection
```bash
# Auto-detects GPU count
GPUS_PER_NODE=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
# Result: 4 (or however many GPUs are present)
```

**Benefit:** No more hardcoding `nvidia.com/gpu: 4` in manifests

#### 2. NVLink Detection
```bash
# Checks if NVLink is present
nvidia-smi topo -m | grep "NV"
# Sets: NCCL_P2P_LEVEL=NVL (if NVLink found) or PIX (PCIe only)
```

**Benefit:** Automatically uses NVLink if available

#### 3. GPUDirect RDMA Detection
```bash
# Checks for nv_peer_mem kernel module
lsmod | grep nv_peer_mem
# Sets: NCCL_NET_GDR_LEVEL=5 (if supported) or 0 (if not)
```

**Benefit:** Only enables GPUDirect if hardware supports it

#### 4. RoCE GID Index Detection
```bash
# Finds the correct GID index for RoCE v2
ibv_devinfo -d mlx5_6 | grep "GID.*RoCE v2"
# Sets: NCCL_IB_GID_INDEX=3 (or whichever index is RoCE v2)
```

**Benefit:** No more trial-and-error with GID indices

#### 5. Optimal OMP Threads
```bash
# Intelligently calculates based on CPU/GPU ratio
CPU_COUNT=$(nproc)  # e.g., 64
GPU_COUNT=4
OMP_THREADS=$((CPU_COUNT / GPU_COUNT))  # = 16
# Clamps to 4-16 range
```

**Benefit:** Optimal CPU thread allocation per GPU

#### 6. Transport Detection (RDMA vs TCP)
```bash
# Automatically detects if RDMA is available
if [[ -d /sys/class/infiniband ]]; then
  TRANSPORT=rdma
  export NCCL_IB_DISABLE=0
else
  TRANSPORT=tcp
  export NCCL_IB_DISABLE=1
fi
```

**Benefit:** Automatically falls back to TCP if no RDMA hardware

#### 7. InfiniBand Device Detection (Multiple Methods)
```bash
# Method 1: ibv_devinfo
IB_DEVICES=$(ibv_devinfo -l | tr '\n' ',')

# Fallback to alternative methods if needed
```

**Benefit:** Works across different InfiniBand configurations

#### 8. Network Interface Detection (Multiple Methods)
```bash
# Method 1: netX interfaces
IFACES=$(ip link show | grep -E '^net[0-9]+$')

# Method 2: ibX interfaces (if netX not found)
IFACES=$(ip link show | grep -E '^ib[0-9]+$')

# Method 3: ibdev2netdev mapping
IFACES=$(ibdev2netdev | awk '{print $5}')

# Fallback: eth0
```

**Benefit:** Works across different network naming schemes

## Comparison: Before vs After

### Before (Hardcoded)

```yaml
# In pod manifest
resources:
  limits:
    nvidia.com/gpu: 4  # ← Hardcoded!

env:
- name: WORLD_SIZE
  value: "8"  # ← Hardcoded!
- name: GPUS_PER_NODE
  value: "4"  # ← Hardcoded!
- name: OMP_NUM_THREADS
  value: "8"  # ← Hardcoded!
- name: NCCL_IB_GID_INDEX
  value: "3"  # ← Hardcoded!
- name: NCCL_NET_GDR_LEVEL
  value: "5"  # ← Hardcoded!
- name: NCCL_P2P_LEVEL
  value: "NVL"  # ← Hardcoded!

# If we move to different hardware: manual updates needed!
```

### After (Auto-Detected)

```yaml
# In pod manifest
initContainers:
- name: autodetect
  command:
  - /bin/bash
  - -c
  - ./scripts/autodetect-full-nccl-config.sh

containers:
- name: training
  command:
  - /bin/bash
  - -c
  - |
    source /shared/nccl-env.sh
    # All variables auto-detected!
    # GPUS_PER_NODE, OMP_NUM_THREADS, NCCL_*, etc.
    torchrun --nproc_per_node=$GPUS_PER_NODE train.py

# Works on ANY hardware automatically!
```

## What's Still Needed (By Design)

Some values **should** be specified by the user:

### 1. Number of Replicas
```yaml
spec:
  replicas: 2  # User decides: 2 nodes, 4 nodes, etc.
```

**Why:** This is a deployment decision, not hardware detection

### 2. Resource Limits
```yaml
resources:
  limits:
    nvidia.com/gpu: 4  # Could be auto-detected!
    memory: 128Gi      # User decision (depends on model)
    cpu: 32            # User decision (depends on workload)
```

**Note:** We **could** auto-detect GPU count and set this, but memory/CPU are deployment decisions.

### 3. World Size (Partially Auto)
```bash
# Can be calculated from replicas × GPUs per node
# But replicas is a deployment decision
WORLD_SIZE=$((REPLICAS × GPUS_PER_NODE))
```

**Solution:** Set `WORLD_SIZE` in pod environment or calculate at runtime

### 4. Application-Specific Settings
```yaml
- name: MASTER_ADDR
  value: "pod-0.service.namespace"  # User-specified

- name: MASTER_PORT
  value: "29500"  # User-specified
```

**Why:** These depend on your deployment structure

## Usage Examples

### Example 1: Use Enhanced Auto-Detection

```bash
# In init container
./scripts/autodetect-full-nccl-config.sh

# Generates /shared/nccl-env.sh with:
# - DETECTED_GPU_COUNT=4
# - GPUS_PER_NODE=4
# - OMP_NUM_THREADS=16
# - NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
# - NCCL_SOCKET_IFNAME=net1,net2,net3,net4
# - NCCL_IB_GID_INDEX=3
# - NCCL_NET_GDR_LEVEL=5
# - NCCL_P2P_LEVEL=NVL
# - DETECTED_TRANSPORT=rdma
```

### Example 2: Use in Training

```bash
# Source auto-detected config
source /shared/nccl-env.sh

echo "Detected configuration:"
echo "  GPUs per node: $GPUS_PER_NODE"
echo "  Transport: $DETECTED_TRANSPORT"
echo "  OMP threads: $OMP_NUM_THREADS"
echo "  IB HCAs: $NCCL_IB_HCA"

# Launch training with detected GPU count
torchrun --nproc_per_node=$GPUS_PER_NODE train.py
```

### Example 3: Calculate World Size at Runtime

```bash
#!/bin/bash
# In pod startup

source /shared/nccl-env.sh

# Calculate WORLD_SIZE from StatefulSet
POD_NAME=$(hostname)
POD_ORDINAL=${POD_NAME##*-}
export NODE_RANK=$POD_ORDINAL

# Get number of pods in StatefulSet
NUM_NODES=$(kubectl get statefulset $STATEFULSET_NAME -o jsonpath='{.spec.replicas}')

# Calculate world size
export WORLD_SIZE=$((NUM_NODES * GPUS_PER_NODE))

echo "Multi-node configuration:"
echo "  Nodes: $NUM_NODES"
echo "  GPUs per node: $GPUS_PER_NODE"
echo "  World size: $WORLD_SIZE"

torchrun \
  --nnodes=$NUM_NODES \
  --nproc_per_node=$GPUS_PER_NODE \
  --node_rank=$NODE_RANK \
  train.py
```

## What Can Be Auto-Detected vs What Can't

| Configuration | Auto-Detectable? | Reason |
|---------------|------------------|--------|
| **GPU count** | ✅ Yes | `nvidia-smi` can count GPUs |
| **IB devices** | ✅ Yes | `ibv_devinfo` lists HCAs |
| **Network interfaces** | ✅ Yes | `ip link show` lists interfaces |
| **NVLink presence** | ✅ Yes | `nvidia-smi topo -m` shows topology |
| **GPUDirect support** | ✅ Yes | `lsmod` checks for `nv_peer_mem` |
| **RoCE GID index** | ✅ Yes | `ibv_devinfo` shows GID table |
| **OMP threads** | ✅ Yes | Calculate from CPU/GPU ratio |
| **Transport (RDMA/TCP)** | ✅ Yes | Check for `/sys/class/infiniband` |
| | | |
| **Number of nodes** | ⚠️ Partially | Can read StatefulSet spec |
| **World size** | ⚠️ Partially | `nodes × GPUs per node` |
| | | |
| **Replicas** | ❌ No | User deployment decision |
| **Memory limits** | ❌ No | User workload decision |
| **CPU limits** | ❌ No | User workload decision |
| **Master address** | ❌ No | User deployment structure |
| **Application args** | ❌ No | User application logic |

## Benefits of Enhanced Auto-Detection

### 1. Portability
```bash
# Same manifest works on:
# - 2-GPU nodes
# - 4-GPU nodes
# - 8-GPU nodes
# - Systems with/without NVLink
# - Systems with/without RDMA
```

### 2. Reduced Errors
```bash
# No more:
# - Mismatched GPU counts in manifest vs environment
# - Wrong GID index causing RDMA failures
# - Incorrect OMP thread counts
# - Hardcoded values that break on different hardware
```

### 3. Easier Maintenance
```bash
# Change hardware? No manifest updates needed!
# Auto-detection adapts automatically
```

### 4. Better Performance
```bash
# Automatically uses optimal settings:
# - NVLink if available
# - GPUDirect if supported
# - Correct GID index
# - Optimal thread count
```

## Migration Guide

### Old Way (Hardcoded)
```yaml
env:
- name: NCCL_IB_HCA
  value: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"
- name: GPUS_PER_NODE
  value: "4"
- name: OMP_NUM_THREADS
  value: "8"
```

### New Way (Auto-Detected)
```yaml
initContainers:
- name: autodetect
  command: ["./scripts/autodetect-full-nccl-config.sh"]
  volumeMounts:
  - name: shared
    mountPath: /shared

containers:
- name: training
  command:
  - /bin/bash
  - -c
  - |
    source /shared/nccl-env.sh
    echo "Using $GPUS_PER_NODE GPUs"
    torchrun --nproc_per_node=$GPUS_PER_NODE train.py
  volumeMounts:
  - name: shared
    mountPath: /shared
```

## User Overrides

Auto-detection supports **user overrides** for any value. You get smart defaults with full control when needed.

### Override in Pod Spec

```yaml
containers:
- name: training
  env:
  # Override specific values
  - name: NCCL_IB_GID_INDEX
    value: "1"  # Force GID 1 instead of auto-detected
  - name: OMP_NUM_THREADS
    value: "8"  # Use 8 threads instead of auto-detected

  # These use auto-detected values (not overridden)
  # - NCCL_IB_HCA
  # - NCCL_SOCKET_IFNAME
  # - GPUS_PER_NODE
  # etc.

  command:
  - /bin/bash
  - -c
  - source /shared/nccl-env.sh && torchrun train.py
```

The autodetect script uses: `export VAR="${VAR:-autodetected_value}"`

This means:
- If user sets the variable → **use user's value**
- If not set → **use auto-detected value**

See **AUTODETECT-OVERRIDES.md** for detailed examples and common scenarios.

## Summary

**Auto-detected (no manual config needed):**
- ✅ GPU count
- ✅ InfiniBand devices
- ✅ Network interfaces
- ✅ NVLink availability
- ✅ GPUDirect RDMA support
- ✅ RoCE GID index
- ✅ OMP thread count
- ✅ Transport type (RDMA vs TCP)

**User-specified (deployment decisions):**
- Number of nodes (replicas)
- Memory/CPU resource limits
- Application-specific configuration

**User-overridable (optional tuning):**
- Any auto-detected value can be overridden
- Set env vars in pod spec before sourcing config
- Useful for debugging, experimentation, or performance tuning

**Calculated at runtime:**
- World size (nodes × GPUs per node)
- Node rank (from pod ordinal)

**Result:** Smart defaults + full control = best of both worlds! 🎉
