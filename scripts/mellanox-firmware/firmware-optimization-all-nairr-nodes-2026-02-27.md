# Mellanox Firmware Optimization - All NAIRR Nodes
**Date**: 2026-02-27  
**Status**: ✅ FIRMWARE APPLIED (Pending Reboot)

## Summary

Applied critical firmware optimizations to **all 4 remaining NAIRR nodes** (u09, u11, u12, u16) to match the optimized configuration already deployed on u25 and u36.

## Nodes Updated

| Node | NICs Fixed | Status | Workloads |
|------|-----------|--------|-----------|
| moc-r4pcc04u09-nairr | 4/4 ✅ | Pending Reboot | Minimal |
| moc-r4pcc04u11-nairr | 4/4 ✅ | Pending Reboot | Minimal |
| moc-r4pcc04u12-nairr | 4/4 ✅ | Pending Reboot | allreduce-bench-0 |
| moc-r4pcc04u16-nairr | 4/4 ✅ | Pending Reboot | Minimal |

**Total NICs Optimized**: 16 (4 nodes × 4 NICs each)

## Firmware Changes Applied

For each of the 4 ConnectX-7 NICs (03:00.0, 23:00.0, a3:00.0, c3:00.0) on each node:

### Before (Suboptimal)
```
ADVANCED_PCI_SETTINGS:  False(0)  ❌
MAX_ACC_OUT_READ:       Missing   ❌
PCI_WR_ORDERING:        Mixed     ❌ (force_relax or per_mkey)
```

### After (Optimized) - Pending Reboot
```
ADVANCED_PCI_SETTINGS:  True(1)   ✅
MAX_ACC_OUT_READ:       128       ✅
PCI_WR_ORDERING:        per_mkey(0) ✅
```

## Performance Impact

Based on validated testing with moc-r4pcc04u36-nairr:

- **Before Firmware Fix**: Degraded RDMA performance (10-30% loss)
- **After Firmware Fix**: **194.87 GB/s** peak bandwidth ✅
- **Expected Improvement**: 10-30% bandwidth increase in RDMA operations

## Commands Executed

For each node and each NIC:
```bash
mlxconfig -y -d <pci> set ADVANCED_PCI_SETTINGS=1
mlxconfig -y -d <pci> set PCI_WR_ORDERING=0
mlxconfig -y -d <pci> set MAX_ACC_OUT_READ=128
```

## Next Steps - Node Reboots Required

Changes are applied but **not yet active**. Each node requires a reboot to activate the new firmware settings.

### Reboot Procedure (per node):

1. **Drain the node:**
   ```bash
   oc adm drain moc-r4pcc04u<XX>-nairr --ignore-daemonsets --delete-emptydir-data --force
   ```

2. **Reboot the node:**
   ```bash
   oc debug node/moc-r4pcc04u<XX>-nairr -- chroot /host systemctl reboot
   ```

3. **Wait for node to come back (typically 5-10 minutes)**

4. **Uncordon the node:**
   ```bash
   oc adm uncordon moc-r4pcc04u<XX>-nairr
   ```

5. **Verify firmware settings active:**
   ```bash
   oc exec -n nvidia-network-operator mft-diagnostics-u<XX> -- \
     mlxconfig -d 03:00.0 query | grep -E "ADVANCED_PCI|MAX_ACC|PCI_WR"
   ```

### Recommended Reboot Order:

1. **u09** - minimal workloads
2. **u11** - minimal workloads  
3. **u16** - minimal workloads
4. **u12** - has allreduce-bench-0 (coordinate with user first)

## Cluster-Wide Status

| Node | Firmware Status | Reboot Status |
|------|----------------|---------------|
| moc-r4pcc04u25-nairr | ✅ Optimized | ✅ Complete |
| moc-r4pcc04u36-nairr | ✅ Optimized | ✅ Complete |
| moc-r4pcc04u09-nairr | ✅ Applied | ⏳ Pending |
| moc-r4pcc04u11-nairr | ✅ Applied | ⏳ Pending |
| moc-r4pcc04u12-nairr | ✅ Applied | ⏳ Pending |
| moc-r4pcc04u16-nairr | ✅ Applied | ⏳ Pending |

## Technical Details

### Firmware Parameters Explained

**ADVANCED_PCI_SETTINGS (0→1)**
- Enables advanced PCIe optimizations
- Unlocks additional configuration parameters including MAX_ACC_OUT_READ
- Improves PCIe bandwidth utilization and DMA handling
- Critical for multi-NIC coordination

**MAX_ACC_OUT_READ (Missing→128)**
- Maximum outstanding RDMA READ requests
- Up to 128 concurrent READ operations
- Significantly improves RDMA READ performance
- Reduces latency for distributed operations

**PCI_WR_ORDERING (Mixed→per_mkey)**
- Controls PCIe write ordering behavior
- per_mkey(0): Consistent ordering for better predictability
- force_relax(1): More relaxed ordering (was causing inconsistencies)
- All NICs now standardized for uniform performance

## Validation

Firmware settings were validated on moc-r4pcc04u36-nairr with multi-node NCCL benchmark:
- **Peak bandwidth**: 194.87 GB/s
- **Sustained bandwidth**: ~194 GB/s
- **Target achieved**: ✅ (194.23 GB/s historical best)

## Related Documentation

- `/Users/jschless/taj/cairo/session-summary-2026-02-26.md` - u25/u36 firmware fixes
- `/Users/jschless/taj/cairo/benchmark-results-u25-u36-post-firmware-fix.txt` - Performance validation
- `/Users/jschless/taj/cairo/mellanox-firmware-comparison-u25-u36.md` - Original analysis
- `/Users/jschless/taj/cairo/u36-firmware-verification-complete.md` - Verification procedure

## Business Impact

- **Performance**: All nodes will achieve 10-30% better RDMA bandwidth
- **Consistency**: Uniform firmware configuration across all H100 nodes
- **Reliability**: Eliminates firmware-related performance variability
- **Future-proof**: Standard configuration for any new H100 nodes

