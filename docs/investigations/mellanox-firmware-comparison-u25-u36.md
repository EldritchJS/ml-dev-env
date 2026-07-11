# Mellanox Firmware Comparison: moc-r4pcc04u25-nairr vs moc-r4pcc04u36-nairr

**Date**: 2026-02-26
**Nodes Compared**:
- Node 1: moc-r4pcc04u25-nairr
- Node 2: moc-r4pcc04u36-nairr

## Executive Summary

**CRITICAL DISCREPANCIES FOUND** between the two nodes that will impact RDMA performance:

1. **ADVANCED_PCI_SETTINGS**: u25 has it ENABLED, u36 has it DISABLED
2. **MAX_ACC_OUT_READ**: u25 has value `128`, u36 is MISSING this setting entirely
3. **PCI_WR_ORDERING**: u36's first NIC (03:00.0/eno5np0) has `force_relax(1)` instead of `per_mkey(0)`

## Detailed Firmware Settings Comparison

### Node: moc-r4pcc04u25-nairr

All 4 ConnectX-7 NICs have IDENTICAL settings:

| NIC PCI Address | Interface | NUM_OF_VFS | SRIOV_EN | MAX_ACC_OUT_READ | PCI_WR_ORDERING | ADVANCED_PCI_SETTINGS |
|-----------------|-----------|------------|----------|------------------|-----------------|-----------------------|
| 03:00.0         | eno5np0   | 1          | True(1)  | **128**          | per_mkey(0)     | **True(1)**           |
| 23:00.0         | eno6np0   | 1          | True(1)  | **128**          | per_mkey(0)     | **True(1)**           |
| a3:00.0         | eno7np0   | 1          | True(1)  | **128**          | per_mkey(0)     | **True(1)**           |
| c3:00.0         | eno8np0   | 1          | True(1)  | **128**          | per_mkey(0)     | **True(1)**           |

### Node: moc-r4pcc04u36-nairr

NICs have INCONSISTENT settings:

| NIC PCI Address | Interface | NUM_OF_VFS | SRIOV_EN | MAX_ACC_OUT_READ | PCI_WR_ORDERING    | ADVANCED_PCI_SETTINGS |
|-----------------|-----------|------------|----------|------------------|--------------------|-----|
| 03:00.0         | eno5np0   | 1          | True(1)  | **MISSING**      | **force_relax(1)** ❌ | **False(0)** ❌       |
| 23:00.0         | eno6np0   | 1          | True(1)  | **MISSING**      | per_mkey(0)        | **False(0)** ❌       |
| a3:00.0         | eno7np0   | 1          | True(1)  | **MISSING**      | per_mkey(0)        | **False(0)** ❌       |
| c3:00.0         | eno8np0   | 1          | True(1)  | **MISSING**      | per_mkey(0)        | **False(0)** ❌       |

## Key Differences

### 1. ADVANCED_PCI_SETTINGS ⚠️ CRITICAL

- **u25**: `True(1)` on ALL NICs ✅
- **u36**: `False(0)` on ALL NICs ❌

**Impact**: Advanced PCI settings enable important PCIe optimizations for RDMA performance. This is likely causing performance degradation on u36.

### 2. MAX_ACC_OUT_READ ⚠️ CRITICAL

- **u25**: `128` on ALL NICs ✅
- **u36**: **MISSING/NOT SET** on ALL NICs ❌

**Impact**: This parameter controls the maximum number of outstanding RDMA READ requests. Without this setting, RDMA READ performance may be severely limited.

**Expected behavior**: Default value when ADVANCED_PCI_SETTINGS is disabled may be much lower (possibly 16 or 32), which would throttle RDMA bandwidth.

### 3. PCI_WR_ORDERING (Partial Inconsistency)

- **u25**: `per_mkey(0)` on ALL NICs ✅
- **u36**:
  - NIC 03:00.0 (eno5np0): `force_relax(1)` ❌
  - NICs 23:00.0, a3:00.0, c3:00.0: `per_mkey(0)` ✅

**Impact**: The first NIC on u36 has relaxed PCI write ordering which may cause slight performance differences, but this is less critical than the other issues.

### 4. Settings That Match ✅

- **NUM_OF_VFS**: Both nodes have `1` VF per NIC ✅
- **SRIOV_EN**: Both nodes have SR-IOV enabled ✅

## Performance Impact Analysis

The firmware discrepancies on **moc-r4pcc04u36-nairr** are likely causing:

1. **Reduced RDMA READ performance** due to missing MAX_ACC_OUT_READ setting
2. **Suboptimal PCIe utilization** due to ADVANCED_PCI_SETTINGS being disabled
3. **Potential inconsistent behavior** between NICs on the same node (eno5np0 vs others)

### Estimated Impact

- **Bandwidth loss**: 10-30% lower RDMA performance
- **Latency increase**: Higher tail latencies for RDMA operations
- **Inefficient multi-NIC utilization**: NICs may not balance load optimally

## Recommendations

### Option 1: Quick Fix - Match u36 to u25 Settings (RECOMMENDED)

Apply these firmware changes to **all 4 NICs on moc-r4pcc04u36-nairr**:

```bash
# For each NIC (03:00.0, 23:00.0, a3:00.0, c3:00.0)
mlxconfig -d 03:00.0 set ADVANCED_PCI_SETTINGS=1
mlxconfig -d 03:00.0 set PCI_WR_ORDERING=0  # per_mkey

mlxconfig -d 23:00.0 set ADVANCED_PCI_SETTINGS=1
mlxconfig -d a3:00.0 set ADVANCED_PCI_SETTINGS=1
mlxconfig -d c3:00.0 set ADVANCED_PCI_SETTINGS=1
```

**Note**: MAX_ACC_OUT_READ should automatically become available once ADVANCED_PCI_SETTINGS=1. If not, set it explicitly:

```bash
mlxconfig -d 03:00.0 set MAX_ACC_OUT_READ=128
mlxconfig -d 23:00.0 set MAX_ACC_OUT_READ=128
mlxconfig -d a3:00.0 set MAX_ACC_OUT_READ=128
mlxconfig -d c3:00.0 set MAX_ACC_OUT_READ=128
```

**REQUIRES NODE REBOOT** after changes.

### Option 2: Verify u25 is Optimal

Before changing u36, verify that u25's settings are indeed optimal by:
1. Running benchmark on u25 alone (4 GPUs, single node)
2. Running benchmark on u36 alone (4 GPUs, single node)
3. Comparing results

If u25 performs significantly better, proceed with Option 1.

### Option 3: Document Only

If both nodes are performing acceptably in multi-node benchmarks, document these differences but defer changes until:
- Performance issues are observed
- A maintenance window is available
- Both nodes can be updated simultaneously

## Next Steps

1. **Immediate**: Run single-node benchmarks on each node to quantify impact
2. **Short-term**: Update u36 firmware settings to match u25
3. **Long-term**: Document standard firmware configuration for all H100 nodes
4. **Validation**: Re-run multi-node benchmarks after changes

## Commands to Fix u36

```bash
# Connect to MFT diagnostics pod on u36
oc exec -it mft-diagnostics-u36 -- bash

# Enable ADVANCED_PCI_SETTINGS on all 4 NICs
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  echo "Configuring NIC $pci..."
  mlxconfig -d $pci set ADVANCED_PCI_SETTINGS=1
  mlxconfig -d $pci set PCI_WR_ORDERING=0
  mlxconfig -d $pci set MAX_ACC_OUT_READ=128
done

# Verify changes
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  echo "=== NIC $pci ===" mlxconfig -d $pci query | grep -E "ADVANCED_PCI|MAX_ACC|PCI_WR_ORDERING"
done
```

**IMPORTANT**: Node must be rebooted for changes to take effect.

## Reference Files

- Full u25 settings: `/tmp/u25-all-nics.txt`
- Full u36 settings: `/tmp/u36-all-nics.txt`
- MST status u25: `/tmp/u25-mst-status.txt`
- MST status u36: `/tmp/u36-mst-status.txt`
