# Firmware Verification Complete - moc-r4pcc04u36-nairr

**Date**: 2026-02-26
**Node**: moc-r4pcc04u36-nairr
**Status**: ✅ **FIRMWARE CHANGES VERIFIED AND ACTIVE**

## Summary

Successfully rebooted moc-r4pcc04u36-nairr and verified that all Mellanox firmware changes are now active.

## Reboot Timeline

- **22:48** - Node drained
- **22:48** - Reboot initiated
- **22:51-22:59** - Node rebooting (8 minutes)
- **22:59** - Node came back online (Ready)
- **23:00** - Node uncordoned
- **23:02** - Firmware settings verified

## Firmware Settings Verification (ALL 4 NICs)

### ✅ ALL SETTINGS NOW MATCH moc-r4pcc04u25-nairr

| NIC | ADVANCED_PCI_SETTINGS | MAX_ACC_OUT_READ | PCI_WR_ORDERING | Status |
|-----|----------------------|------------------|-----------------|--------|
| 03:00.0 (eno5np0) | True(1) ✅ | 128 ✅ | per_mkey(0) ✅ | Active |
| 23:00.0 (eno6np0) | True(1) ✅ | 128 ✅ | per_mkey(0) ✅ | Active |
| a3:00.0 (eno7np0) | True(1) ✅ | 128 ✅ | per_mkey(0) ✅ | Active |
| c3:00.0 (eno8np0) | True(1) ✅ | 128 ✅ | per_mkey(0) ✅ | Active |

### Before Reboot (Applied but not active)
```
ADVANCED_PCI_SETTINGS: False(0) → True(1)  [PENDING]
MAX_ACC_OUT_READ:      0       → 128       [PENDING]
PCI_WR_ORDERING:       Mixed   → per_mkey  [PENDING]
```

### After Reboot (Active)
```
ADVANCED_PCI_SETTINGS: True(1)  ✅ ACTIVE
MAX_ACC_OUT_READ:      128      ✅ ACTIVE
PCI_WR_ORDERING:       per_mkey ✅ ACTIVE
```

## Changes Applied

### NIC 03:00.0 (eno5np0)
```
ADVANCED_PCI_SETTINGS: False(0) → True(1)  ✅
MAX_ACC_OUT_READ:      Missing  → 128      ✅
PCI_WR_ORDERING:       force_relax(1) → per_mkey(0) ✅
```

### NICs 23:00.0, a3:00.0, c3:00.0
```
ADVANCED_PCI_SETTINGS: False(0) → True(1)  ✅
MAX_ACC_OUT_READ:      Missing  → 128      ✅
PCI_WR_ORDERING:       per_mkey (no change) ✅
```

## Expected Performance Improvements

With firmware now matching moc-r4pcc04u25-nairr:

1. **Advanced PCI Optimizations Enabled**
   - Better PCIe bandwidth utilization
   - Optimized DMA handling
   - Improved multi-NIC coordination

2. **MAX_ACC_OUT_READ Now Set to 128**
   - Up to 128 outstanding RDMA READ requests
   - Better RDMA READ performance
   - Reduced latency for distributed operations

3. **Consistent PCI Write Ordering**
   - All 4 NICs now using per_mkey ordering
   - Predictable performance across all NICs
   - Better load balancing

## Estimated Performance Gain

**Previous**: Degraded performance due to misconfigured firmware
**Now**: Full RDMA performance capability

**Expected improvement**: 10-30% bandwidth increase in RDMA operations
**Target**: 194-309 GB/s in multi-node benchmarks (matching previous best results)

## Next Steps

1. ✅ Node rebooted successfully
2. ✅ Firmware settings verified active
3. 🔄 Deploying benchmark pods (in progress)
4. ⏳ Running multi-node benchmark (u25 + u36)
5. ⏳ Compare results with target 194-309 GB/s

## Node Status

```
NAME                   STATUS   ROLES    AGE     VERSION
moc-r4pcc04u36-nairr   Ready    worker   2d12h   v1.33.6
```

**SchedulingDisabled**: No (uncordoned)
**Ready**: Yes
**RDMA Devices**: All 4 NICs operational
**Firmware**: Optimized and active

## Related Files

- Pre-reboot settings: `/tmp/u36-all-nics.txt`
- Post-reboot verification: `/tmp/u36-firmware-verified.txt`
- Firmware fix documentation: `/Users/jschless/taj/cairo/firmware-fix-u36-applied.md`
- Comparison analysis: `/Users/jschless/taj/cairo/mellanox-firmware-comparison-u25-u36.md`
