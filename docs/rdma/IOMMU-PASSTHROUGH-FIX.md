# IOMMU Passthrough Configuration for RDMA/GPUDirect

## Problem Summary

RDMA communication is failing with `IBV_WC_LOC_PROT_ERR` (vendor_err=81) errors due to IOMMU being in full translation mode instead of passthrough mode.

**Current State:**
- IOMMU Mode: `Translated (DMA-FQ)`
- RDMA Status: ❌ Failing with memory protection errors
- TCP Mode: ✅ Working (fallback)

**Root Cause:**
IOMMU address translation interferes with:
1. RDMA memory registration for SR-IOV VFs
2. GPUDirect RDMA between GPUs and InfiniBand NICs
3. Direct memory access required for high-speed networking

---

## Solution: Enable IOMMU Passthrough Mode

### What This Does

Setting `iommu=pt` enables IOMMU passthrough mode, which:
- ✅ Keeps IOMMU enabled for device isolation and security
- ✅ Uses passthrough (no address translation) for PCIe devices
- ✅ Allows RDMA memory registration to work correctly
- ✅ Enables GPUDirect RDMA for GPU↔NIC direct transfers
- ✅ Maintains SR-IOV VF security and isolation

### GPU-NIC Topology (from nvidia-smi topo)

Your cluster has GPUs and NICs optimally connected:

```
NUMA Node 0:
  GPU0 ← NODE/PXB → mlx5_6 (net1, 10.0.103.x)
  GPU1 ← PXB/NODE → mlx5_7 (net2, 10.0.104.x)

NUMA Node 1:
  GPU2 ← PXB/NODE → mlx5_10 (net3, 10.0.105.x)
  GPU3 ← NODE/PXB → mlx5_11 (net4, 10.0.106.x)
```

This topology is **designed for GPUDirect RDMA** and requires IOMMU passthrough.

---

## Installation Steps

### Step 1: Apply the MachineConfig

```bash
# Review the configuration
cat 99-worker-iommu-passthrough.yaml

# Apply to cluster (requires cluster-admin privileges)
oc apply -f 99-worker-iommu-passthrough.yaml
```

### Step 2: Monitor Node Updates

The Machine Config Operator will automatically update worker nodes one at a time:

```bash
# Watch MachineConfigPool status
watch oc get mcp

# Monitor node updates
oc get nodes -w

# Check which nodes are updating
oc get nodes -o wide
```

**Expected Output:**
```
NAME       UPDATING   UPDATED   DEGRADED   MACHINECOUNT   READYMACHINECOUNT
worker     True       1         False      N              N-1
```

### Step 3: Wait for Rollout Completion

**⚠️ IMPORTANT**: Each worker node will:
1. Cordon (stop scheduling new pods)
2. Drain (move existing pods)
3. Reboot with new kernel parameters
4. Rejoin the cluster

**Timeline**: ~15-30 minutes per node (depends on workloads)

Monitor until:
```
NAME       UPDATING   UPDATED   DEGRADED   MACHINECOUNT   READYMACHINECOUNT
worker     False      N         False      N              N
```

---

## Verification

### Step 1: Check Kernel Command Line

```bash
# Get a worker node name
NODE=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers | head -1 | awk '{print $1}')

# Verify iommu=pt is present
oc debug node/$NODE -- chroot /host cat /proc/cmdline | grep -o "iommu=pt"
```

**Expected**: `iommu=pt`

### Step 2: Check IOMMU Mode

```bash
# Check IOMMU domain type
oc debug node/$NODE -- chroot /host dmesg | grep -i "iommu.*domain.*type"
```

**Expected**: `iommu: Default domain type: Passthrough` or `Identity`

### Step 3: Verify IOMMU Group Type

```bash
# Check a specific IOMMU group
oc debug node/$NODE -- chroot /host cat /sys/kernel/iommu_groups/103/type
```

**Before**: `DMA-FQ`
**After**: `DMA` or `identity`

### Step 4: Test RDMA Communication

Once nodes are updated, redeploy your pods and test NCCL with RDMA:

```bash
# Delete and recreate pods to get updated nodes
oc delete pod h-kim-0 h-kim-1 -n b-efficient-memory-offloading-765cab
oc wait --for=condition=Ready pod/h-kim-0 pod/h-kim-1 -n b-efficient-memory-offloading-765cab --timeout=5m

# Run RDMA test (auto-detection already configured)
# The existing auto-detection wrapper will use the correct devices
# NCCL should now work without IBV_WC_LOC_PROT_ERR errors
```

---

## Testing NCCL After Fix

### Quick Test Script

Create and run this test once nodes are updated:

```bash
# On h-kim-0 and h-kim-1, run:
cat > /tmp/test-rdma-final.sh << 'EOF'
#!/bin/bash
set -e
eval $(cat /proc/1/environ | tr '\0' '\n' | grep ^NCCL_)
eval $(cat /proc/1/environ | tr '\0' '\n' | grep ^MASTER)

POD_ORDINAL=${HOSTNAME##*-}
export NODE_RANK=$POD_ORDINAL

echo "Testing NCCL with RDMA"
echo "NCCL_IB_HCA: $NCCL_IB_HCA"
echo "Memlock: $(ulimit -l)"

cd /workspace
prlimit --memlock=unlimited:unlimited \
torchrun \
  --nnodes=2 \
  --nproc_per_node=4 \
  --node_rank=$NODE_RANK \
  --master_addr=$MASTER_ADDR \
  --master_port=$MASTER_PORT \
  nccl_torch_bench.py
EOF

chmod +x /tmp/test-rdma-final.sh

# Copy to both pods
oc cp /tmp/test-rdma-final.sh b-efficient-memory-offloading-765cab/h-kim-0:/workspace/
oc cp /tmp/test-rdma-final.sh b-efficient-memory-offloading-765cab/h-kim-1:/workspace/

# Run on both pods simultaneously
oc exec h-kim-0 -n b-efficient-memory-offloading-765cab -- bash /workspace/test-rdma-final.sh &
oc exec h-kim-1 -n b-efficient-memory-offloading-765cab -- bash /workspace/test-rdma-final.sh &
wait
```

### Expected Results

**Before Fix (Current):**
```
[2026-02-25 06:16:39] h-kim-0:1353:1409 [3] ib_plugin.c:2033 NCCL WARN NET/IB: Got completion
from peer 10.128.8.30<55095> with status=IBV_WC_LOC_PROT_ERR(4) opcode=IBV_WC_SEND(0)
reqSize=524288 vendor_err=81 req_type=Send localGid ::ffff:10.0.106.7
remoteGids::ffff:10.0.106.6 hca mlx5_11
```

**After Fix:**
```
NCCL INFO Using network Plugin_v8 RDMA_SHARP
NCCL INFO comm 0x... rank 0 nranks 8 cudaDev 0 busId 6000 - Init COMPLETE
[bench] op=all_reduce world=8 bytes=268435456 iters=50 avg_sec=0.012 approx_alg_BW=36.8 GiB/s
```

Expected bandwidth: **~30-40 GiB/s** (vs 0.98 GiB/s with TCP)

---

## Rollback (If Needed)

If issues occur after applying the change:

```bash
# Delete the MachineConfig
oc delete machineconfig 99-worker-iommu-passthrough

# Nodes will automatically reboot back to original configuration
```

---

## Performance Comparison

### Current State (TCP Mode)
- Bandwidth: ~0.98 GiB/s per all_reduce
- Mode: NCCL_IB_DISABLE=1 (fallback to TCP/IP)
- Status: ✅ Stable but slow

### After IOMMU Passthrough (RDMA Mode)
- Bandwidth: ~30-40 GiB/s per all_reduce (30-40x faster)
- Mode: NCCL with InfiniBand RDMA
- GPUDirect RDMA: Enabled (zero-copy GPU↔GPU via NIC)
- Status: Should be ✅ Stable and fast

---

## Technical Details

### Current IOMMU Configuration
```
Platform: AMD EPYC with AMD-Vi (AMD IOMMU)
IOMMU Groups: Enabled, per-device isolation
Default Domain: Translated (DMA-FQ)
SR-IOV: Enabled with 4 VFs per port
Issue: Translation layer blocking RDMA memory registration
```

### After Passthrough Mode
```
IOMMU Groups: Still enabled (security maintained)
Default Domain: Passthrough/Identity
SR-IOV: Unchanged
RDMA: Direct memory access allowed (no translation)
```

### Why Passthrough is Safe

Passthrough mode **does not disable IOMMU**. It:
- Maintains device isolation via IOMMU groups
- Prevents unauthorized DMA from other devices
- Allows assigned SR-IOV VFs to access container memory directly
- Is the standard configuration for RDMA and GPUDirect workloads

### References

- Mellanox/NVIDIA RDMA Best Practices: Requires `iommu=pt`
- Red Hat OpenShift SR-IOV Documentation: Recommends passthrough for RDMA
- AMD-Vi Documentation: Passthrough mode for high-performance I/O
- GPUDirect RDMA Requirements: IOMMU passthrough mandatory

---

## Summary

**File to Apply**: `99-worker-iommu-passthrough.yaml`

**Impact**: Worker nodes will reboot one at a time (managed rollout)

**Downtime**: Minimal - pods will migrate during rolling update

**Expected Result**: RDMA communication working, 30-40x performance improvement

**Risk**: Low - standard configuration for RDMA/GPUDirect workloads

**Rollback**: Simple - delete the MachineConfig

---

## Questions or Issues?

After applying this fix:
1. Verify kernel cmdline has `iommu=pt`
2. Check IOMMU domain type changed to Passthrough
3. Test NCCL benchmark - should complete without IBV_WC errors
4. Measure bandwidth - should see ~30-40 GiB/s

If RDMA still fails after this fix, check:
- SR-IOV PF trust mode: `ip link show <pf> | grep trust`
- RDMA cgroup controller enabled
- No additional security policies blocking RDMA
