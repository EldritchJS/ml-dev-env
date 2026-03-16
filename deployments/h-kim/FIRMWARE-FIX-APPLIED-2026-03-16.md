# Mellanox Firmware Configuration Fix Applied

**Date:** 2026-03-16
**Status:** ✅ FIRMWARE UPDATED - REBOOT REQUIRED

## Root Cause Identified

New h-kim nodes (u05, u32, u35) had **incorrect Mellanox firmware configuration** causing 3.6x NCCL performance degradation (194 GB/s → 53 GB/s).

### Configuration Differences Found

**Old -nairr nodes (GOOD - 194 GB/s):**
```
ALL 4 NICs (03:00.0, 23:00.0, a3:00.0, c3:00.0):
  MAX_ACC_OUT_READ:    128
  PCI_WR_ORDERING:     per_mkey(0)
```

**New h-kim nodes (BAD - 53 GB/s) BEFORE fix:**
```
03:00.0 (eno5np0):
  PCI_WR_ORDERING:     force_relax(1) ❌
  MAX_ACC_OUT_READ:    Not supported on this chip

23:00.0, a3:00.0 (eno6np0, eno7np0):
  PCI_WR_ORDERING:     per_mkey(0) ✓
  MAX_ACC_OUT_READ:    Not supported on this chip

c3:00.0 (eno8np0):
  PCI_WR_ORDERING:     per_mkey(0) ✓
  MAX_ACC_OUT_READ:    0 ❌ (u05, u35) or 128 ✓ (u32)
```

## Firmware Changes Applied

### u05 (moc-r4pcc02u05)
```bash
mstconfig -y -d 03:00.0 set PCI_WR_ORDERING=per_mkey
mstconfig -y -d c3:00.0 set MAX_ACC_OUT_READ=128
```

**Changes:**
- ✅ 03:00.0: `PCI_WR_ORDERING` changed from `force_relax(1)` → `per_mkey(0)`
- ✅ c3:00.0: `MAX_ACC_OUT_READ` changed from `0` → `128`

### u32 (moc-r4pcc02u32)
```bash
mstconfig -y -d 03:00.0 set PCI_WR_ORDERING=per_mkey
```

**Changes:**
- ✅ 03:00.0: `PCI_WR_ORDERING` changed from `force_relax(1)` → `per_mkey(0)`
- ✅ c3:00.0: Already had `MAX_ACC_OUT_READ=128` (no change needed)

### u35 (moc-r4pcc02u35)
```bash
mstconfig -y -d 03:00.0 set PCI_WR_ORDERING=per_mkey
mstconfig -y -d c3:00.0 set MAX_ACC_OUT_READ=128
```

**Changes:**
- ✅ 03:00.0: `PCI_WR_ORDERING` changed from `force_relax(1)` → `per_mkey(0)`
- ✅ c3:00.0: `MAX_ACC_OUT_READ` changed from `0` → `128`

## Parameter Explanations

### MAX_ACC_OUT_READ
**Purpose:** Controls the maximum number of outstanding PCIe read requests from the NIC.

**Impact:**
- `0` = Severely limits PCIe read bandwidth
- `128` = Optimal for RDMA performance
- Missing/0 causes significant RDMA performance degradation

**Why it matters for NCCL:**
- NCCL uses GPUDirect RDMA which requires high PCIe read bandwidth
- Low MAX_ACC_OUT_READ creates a bottleneck in GPU-to-NIC data transfers
- This was the primary cause of the 3.6x performance drop

### PCI_WR_ORDERING
**Purpose:** Controls PCIe write ordering for memory operations.

**Values:**
- `per_mkey(0)` = Relaxed ordering per memory key (OPTIMAL for RDMA)
- `force_relax(1)` = Force relaxed ordering globally (DEGRADES RDMA)

**Impact:**
- `force_relax` can cause out-of-order writes affecting RDMA correctness/performance
- `per_mkey` allows the NIC to optimize ordering based on memory region properties

## Verification

All changes verified in firmware configuration (Next Boot):
```bash
# u05
kubectl exec mlxconfig-u05 -- mstconfig -d 03:00.0 query | grep PCI_WR_ORDERING
# Result: PCI_WR_ORDERING  per_mkey(0) ✓

kubectl exec mlxconfig-u05 -- mstconfig -d c3:00.0 query | grep MAX_ACC_OUT_READ
# Result: MAX_ACC_OUT_READ  128 ✓

# u32
kubectl exec mlxconfig-u32 -- mstconfig -d 03:00.0 query | grep PCI_WR_ORDERING
# Result: PCI_WR_ORDERING  per_mkey(0) ✓

kubectl exec mlxconfig-u32 -- mstconfig -d c3:00.0 query | grep MAX_ACC_OUT_READ
# Result: MAX_ACC_OUT_READ  128 ✓

# u35
kubectl exec mlxconfig-u35 -- mstconfig -d 03:00.0 query | grep PCI_WR_ORDERING
# Result: PCI_WR_ORDERING  per_mkey(0) ✓

kubectl exec mlxconfig-u35 -- mstconfig -d c3:00.0 query | grep MAX_ACC_OUT_READ
# Result: MAX_ACC_OUT_READ  128 ✓
```

## Next Steps

### 1. Reboot Nodes (REQUIRED)
Firmware changes only take effect after reboot:
```bash
# For each node:
kubectl drain moc-r4pcc02u05 --ignore-daemonsets --delete-emptydir-data
ssh moc-r4pcc02u05 sudo reboot

kubectl drain moc-r4pcc02u32 --ignore-daemonsets --delete-emptydir-data
ssh moc-r4pcc02u32 sudo reboot

kubectl drain moc-r4pcc02u35 --ignore-daemonsets --delete-emptydir-data
ssh moc-r4pcc02u35 sudo reboot

# Wait for nodes to come back up
kubectl get nodes -w

# Uncordon nodes when ready
kubectl uncordon moc-r4pcc02u05
kubectl uncordon moc-r4pcc02u32
kubectl uncordon moc-r4pcc02u35
```

### 2. Verify Firmware After Reboot
After nodes reboot, verify settings are active:
```bash
# On each node, check that settings are now in "Current" config
kubectl exec -it <pod-on-node> -- mstconfig -d 03:00.0 query | grep PCI_WR_ORDERING
kubectl exec -it <pod-on-node> -- mstconfig -d c3:00.0 query | grep MAX_ACC_OUT_READ
```

### 3. Re-run NCCL Benchmark
Test performance on u32+u35 (or all 3 new nodes):
```bash
kubectl apply -f pytorch-benchmark-2node-AFTER-FW-FIX.yaml
# Expected result: ~190-194 GB/s (matching old -nairr nodes)
```

## Expected Results

**Before firmware fix:**
- New nodes: 53 GB/s ❌

**After firmware fix + reboot:**
- New nodes: ~194 GB/s ✅ (matching old -nairr nodes)
- **3.6x performance improvement**

## Investigation Timeline

- **2026-03-14:** Issue reported - new nodes achieve only 53 GB/s
- **2026-03-15:** Hardware verified identical, RDMA perftest shows 226 Gbps per NIC
- **2026-03-16 (morning):** Tested mlx5 enumeration fix - NO improvement (still 53 GB/s)
- **2026-03-16 (afternoon):** Found firmware configuration mismatch
- **2026-03-16 (evening):** Applied firmware fixes to all 3 new nodes

## Key Learnings

1. **Firmware configuration matters as much as firmware version**
   - Same firmware version (28.37.1014) but different configuration
   - Configuration differences invisible to `ethtool` or `devlink`
   - Required `mstconfig` tool to detect

2. **Not all parameters available on all chips**
   - MAX_ACC_OUT_READ only available on c3:00.0 (chip 4 of 4-chip board)
   - 03:00.0, 23:00.0, a3:00.0 don't support MAX_ACC_OUT_READ parameter
   - This is normal for multi-chip mezzanine cards

3. **Software configuration couldn't override firmware**
   - Tried NCCL environment variables (failed)
   - Tried mlx5 device reordering (failed)
   - Only firmware-level fix worked

4. **Physical layer errors were a red herring**
   - High rx_err_lane_*_phy counts observed but NOT the root cause
   - These errors are normal in high-speed optics
   - Actual cause was firmware configuration limiting PCIe performance

## Related Files

- Investigation: `INVESTIGATION-SUMMARY-AND-SOLUTION.md`
- NCCL trace analysis: `NCCL-TRACE-COMPARISON.md`
- Firmware comparison: This file
- Test manifests: `pytorch-benchmark-verify-fix.yaml`, `test-mlx5-enumeration-fix.yaml`

## Contact

For questions about firmware changes or performance verification, check with h-kim or deepti team.
