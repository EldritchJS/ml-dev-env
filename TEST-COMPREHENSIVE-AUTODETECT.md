# Testing Comprehensive Auto-Detection with H-Kim

## Overview

This test deploys a **separate** StatefulSet (`h-kim-test`) that uses comprehensive auto-detection, **without modifying the actual h-kim deployment**.

## What This Tests

### Current H-Kim (Hardcoded Values)

```yaml
env:
- name: WORLD_SIZE
  value: "8"  # ← Hardcoded
- name: GPUS_PER_NODE
  value: "4"  # ← Hardcoded
- name: NCCL_IB_GID_INDEX
  value: "3"  # ← Hardcoded
- name: NCCL_NET_GDR_LEVEL
  value: "5"  # ← Hardcoded
- name: NCCL_P2P_LEVEL
  value: "NVL"  # ← Hardcoded
# Plus: NCCL_IB_HCA and NCCL_SOCKET_IFNAME auto-detected
```

### Test H-Kim (Comprehensive Auto-Detection)

```bash
# Everything auto-detected:
GPUS_PER_NODE=$(nvidia-smi --query-gpu=count --format=csv,noheader)  # Detected!
WORLD_SIZE=$((REPLICAS × GPUS_PER_NODE))  # Calculated!
NCCL_IB_GID_INDEX=$(scan for RoCE v2 in ibv_devinfo)  # Detected!
NCCL_NET_GDR_LEVEL=$(check for nv_peer_mem module)  # Detected!
NCCL_P2P_LEVEL=$(check nvidia-smi topo -m for NVLink)  # Detected!
OMP_NUM_THREADS=$((CPU_COUNT / GPU_COUNT))  # Detected!
# Plus: NCCL_IB_HCA and NCCL_SOCKET_IFNAME auto-detected
```

## Quick Start

### 1. Deploy Test StatefulSet

```bash
# Deploy the test version (separate from h-kim)
oc apply -f test-h-kim-autodetect.yaml
```

This creates:
- Service: `h-kim-test-headless`
- StatefulSet: `h-kim-test` (2 replicas)
- Pods: `h-kim-test-0`, `h-kim-test-1`

**Note:** This does NOT affect your actual h-kim deployment!

### 2. Watch Pod Startup

```bash
# Watch pods start
oc get pods -l app=h-kim-test -w

# Should show:
# h-kim-test-0   0/1   Init:0/1   0s
# h-kim-test-0   0/1   Init:0/1   5s
# h-kim-test-0   0/1   PodInitializing   10s
# h-kim-test-0   1/1   Running   15s
```

### 3. Check Init Container Logs (Auto-Detection)

```bash
# View auto-detection output
oc logs h-kim-test-0 -c comprehensive-autodetect

# Should show:
# ==========================================
# Comprehensive NCCL Auto-Detection
# ==========================================
#
# [AUTODETECT] Starting comprehensive auto-detection...
# [AUTODETECT] Detection results:
# [AUTODETECT]   GPUs: 4
# [AUTODETECT]   IB devices: mlx5_6,mlx5_7,mlx5_10,mlx5_11
# [AUTODETECT]   RDMA interfaces: net1,net2,net3,net4
# [AUTODETECT]   NVLink: NVL
# [AUTODETECT]   GPUDirect: level 5
# [AUTODETECT]   GID index: 3
# [AUTODETECT]   OMP threads: 16
# [AUTODETECT]   Transport: rdma
```

### 4. Check Main Container Logs (Configuration)

```bash
# View the configuration being used
oc logs h-kim-test-0 | head -100
```

**Expected output:**

```
Memlock limit: unlimited

==========================================
Loading Comprehensive Auto-Detected Config
==========================================

==========================================
H-Kim Test - Comprehensive Autodetect
==========================================
Pod: h-kim-test-0
Node Rank: 0

AUTO-DETECTED VALUES:
  GPUs per node: 4 (detected!)
  World size: 8 (calculated: 2 × 4)
  OMP threads: 16 (detected!)
  Transport: rdma (detected!)

NCCL Configuration (all auto-detected):
NCCL_DEBUG=INFO
NCCL_IB_DISABLE=0
NCCL_IB_GID_INDEX=3
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_IB_RETRY_CNT=7
NCCL_IB_TIMEOUT=22
NCCL_NET_GDR_LEVEL=5
NCCL_P2P_LEVEL=NVL
NCCL_SOCKET_IFNAME=net1,net2,net3,net4

Master: h-kim-test-0.h-kim-test-headless.nccl-test.svc.cluster.local:29500
==========================================

GPU Topology:
        GPU0    GPU1    GPU2    GPU3    mlx5_6  mlx5_7  mlx5_10 mlx5_11 CPU Affinity    NUMA Affinity
GPU0     X      NV12    SYS     SYS     PXB     PXB     SYS     SYS     0-31    0
GPU1    NV12     X      SYS     SYS     PXB     PXB     SYS     SYS     0-31    0
GPU2    SYS     SYS      X      NV12    SYS     SYS     PXB     PXB     32-63   1
GPU3    SYS     SYS     NV12     X      SYS     SYS     PXB     PXB     32-63   1

Detected GPUs:
0, NVIDIA H100 80GB HBM3, 81559 MiB
1, NVIDIA H100 80GB HBM3, 81559 MiB
2, NVIDIA H100 80GB HBM3, 81559 MiB
3, NVIDIA H100 80GB HBM3, 81559 MiB

==========================================
Comparison with Hardcoded Values:
==========================================
BEFORE (hardcoded in h-kim):
  GPUS_PER_NODE: 4 (hardcoded)
  WORLD_SIZE: 8 (hardcoded)
  OMP_NUM_THREADS: 8 (hardcoded)
  NCCL_IB_GID_INDEX: 3 (hardcoded)
  NCCL_NET_GDR_LEVEL: 5 (hardcoded)
  NCCL_P2P_LEVEL: NVL (hardcoded)

AFTER (auto-detected):
  GPUS_PER_NODE: 4 (detected!)
  WORLD_SIZE: 8 (calculated!)
  OMP_NUM_THREADS: 16 (detected!)  ← Different! (64 CPUs / 4 GPUs = 16)
  NCCL_IB_GID_INDEX: 3 (detected!)
  NCCL_NET_GDR_LEVEL: 5 (detected!)
  NCCL_P2P_LEVEL: NVL (detected!)
==========================================
```

## Verification Steps

### 1. Verify Auto-Detection Worked

```bash
# Check that all values were detected
oc exec h-kim-test-0 -- bash -c 'source /shared/nccl-env.sh && env | grep -E "DETECTED|GPUS_PER_NODE|OMP_NUM_THREADS|NCCL_"'
```

**Should see:**
```
DETECTED_GPU_COUNT=4
DETECTED_TRANSPORT=rdma
GPUS_PER_NODE=4
OMP_NUM_THREADS=16
NCCL_IB_DISABLE=0
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_IB_GID_INDEX=3
NCCL_NET_GDR_LEVEL=5
NCCL_P2P_LEVEL=NVL
NCCL_SOCKET_IFNAME=net1,net2,net3,net4
```

### 2. Compare with Actual H-Kim

```bash
# Check current h-kim environment
oc exec h-kim-0 -- env | grep -E "GPUS_PER_NODE|OMP_NUM_THREADS|NCCL_IB_GID_INDEX"

# Should show hardcoded values:
# GPUS_PER_NODE=4
# OMP_NUM_THREADS=8  ← Different from auto-detected!
# NCCL_IB_GID_INDEX=3
```

### 3. Test NCCL Communication

```bash
# Simple NCCL test on auto-detected config
oc exec h-kim-test-0 -- bash -c '
source /shared/nccl-env.sh
export NCCL_DEBUG=INFO
python3 -c "
import torch
import torch.distributed as dist
import os

os.environ[\"MASTER_ADDR\"] = \"h-kim-test-0.h-kim-test-headless.nccl-test.svc.cluster.local\"
os.environ[\"MASTER_PORT\"] = \"29500\"
os.environ[\"RANK\"] = \"0\"
os.environ[\"WORLD_SIZE\"] = str(int(os.environ[\"GPUS_PER_NODE\"]))

dist.init_process_group(backend=\"nccl\")
print(f\"✅ NCCL initialized with auto-detected config!\")
print(f\"   Rank: {dist.get_rank()}\")
print(f\"   World size: {dist.get_world_size()}\")
dist.destroy_process_group()
"
'
```

### 4. Check Auto-Detected Config File

```bash
# View the full auto-generated config
oc exec h-kim-test-0 -- cat /shared/nccl-env.sh
```

## What to Look For

### Key Differences from Current H-Kim

1. **OMP_NUM_THREADS**
   - Hardcoded: `8`
   - Auto-detected: `16` (because 64 CPUs / 4 GPUs = 16)
   - **Better performance!**

2. **All NCCL values confirmed**
   - Auto-detection should match hardcoded values
   - Validates that detection works correctly

3. **Portability**
   - Same manifest would work on nodes with different GPU counts
   - Would auto-detect 2 GPUs, 8 GPUs, etc.

## Testing Different Scenarios

### Scenario 1: What if GPUs Change?

The test manifest would automatically adapt:

```bash
# On 2-GPU node (hypothetical):
GPUS_PER_NODE=2 (detected!)
WORLD_SIZE=4 (calculated: 2 nodes × 2 GPUs)
OMP_NUM_THREADS=32 (64 CPUs / 2 GPUs)

# On 8-GPU node (hypothetical):
GPUS_PER_NODE=8 (detected!)
WORLD_SIZE=16 (calculated: 2 nodes × 8 GPUs)
OMP_NUM_THREADS=8 (64 CPUs / 8 GPUs)
```

### Scenario 2: What if No NVLink?

```bash
# Auto-detection would show:
NCCL_P2P_LEVEL=PIX (detected: no NVLink)
# Instead of hardcoded NVL
```

### Scenario 3: What if No GPUDirect RDMA?

```bash
# Auto-detection would show:
NCCL_NET_GDR_LEVEL=0 (detected: no nv_peer_mem)
# Instead of hardcoded 5
```

## Performance Comparison (Optional)

Run the same benchmark on both deployments:

```bash
# On h-kim (hardcoded OMP_NUM_THREADS=8)
oc exec h-kim-0 -- bash -c 'OMP_NUM_THREADS=8 python benchmark.py'

# On h-kim-test (auto-detected OMP_NUM_THREADS=16)
oc exec h-kim-test-0 -- bash -c 'source /shared/nccl-env.sh && python benchmark.py'

# Compare throughput
```

**Expected:** Auto-detected should be slightly faster due to optimal thread count.

## Cleanup

When done testing:

```bash
# Delete test deployment
oc delete statefulset h-kim-test
oc delete service h-kim-test-headless

# Verify actual h-kim is untouched
oc get statefulset h-kim
# Should still exist and be unchanged
```

## Summary

**This test shows:**

✅ All NCCL parameters can be auto-detected
✅ Auto-detection matches hardcoded values (validates correctness)
✅ OMP_NUM_THREADS auto-detection is better (16 vs 8)
✅ Same manifest would adapt to different hardware
✅ No need to hardcode configuration

**Current h-kim deployment:**
- Unchanged
- Still uses simple RDMA detection
- All hardcoded values preserved

**Test deployment:**
- Separate pods (h-kim-test-0, h-kim-test-1)
- Comprehensive auto-detection
- Shows what's possible
- Can be deleted without affecting h-kim

## Next Steps

If auto-detection works well in testing:

1. **Gradually migrate** other deployments
2. **Start with new deployments** (not production h-kim)
3. **Keep as optional** for users who prefer explicit config
4. **Document both approaches** (simple vs comprehensive)

For now, just test and see how it works! 🚀
