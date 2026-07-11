# IOMMU Analysis - moc-r4pcc04u25-nairr

**Date**: 2026-02-26
**Node**: moc-r4pcc04u25-nairr
**CPU**: AMD EPYC 9754 128-Core Processor

## Summary

**⚠️ IOMMU IS NOT PROPERLY ENABLED** on moc-r4pcc04u25-nairr

## Current Status

### Kernel Parameters
```
iommu=pt
```

### What's Missing
```
amd_iommu=on    ❌ NOT SET
```

### Evidence

1. **Kernel Command Line**: Only has `iommu=pt`
   ```
   BOOT_IMAGE=... iommu=pt
   ```

2. **IOMMU Groups**: **ZERO** IOMMU groups found
   ```bash
   # ls -la /sys/kernel/iommu_groups/
   total 0  # EMPTY - no IOMMU groups
   ```

3. **dmesg Output**: NO AMD IOMMU initialization messages
   - Expected to see: "AMD-Vi: Enabling IOMMU at..."
   - Expected to see: "AMD-Vi: Initialized for Passthrough Mode"
   - **Actual**: No AMD IOMMU messages at all

4. **IOMMU Default**: Passthrough mode attempted, but hardware not activated
   ```
   [6.300216] iommu: Default domain type: Passthrough (set via kernel command line)
   ```

## What This Means

### IOMMU Modes Explained

1. **`iommu=pt`** (Passthrough): IOMMU is enabled but devices can do DMA directly
   - Still provides IOMMU groups
   - Still requires hardware IOMMU to be enabled
   - Lower overhead than full IOMMU virtualization

2. **`amd_iommu=on`**: Actually enables the AMD IOMMU hardware
   - **REQUIRED** for AMD systems
   - Without this, `iommu=pt` does nothing

### Current Configuration Issues

**What's configured**: `iommu=pt` alone
- Tells kernel to use passthrough mode
- But doesn't enable AMD IOMMU hardware
- Result: **No IOMMU functionality at all**

**What should be configured**: `iommu=pt amd_iommu=on`
- Enables AMD IOMMU hardware
- Uses passthrough mode for better performance
- Creates IOMMU groups
- Enables device isolation and protection

## Impact on RDMA Performance

### Current State (No IOMMU)
- Direct DMA access (no protection)
- No device isolation
- **May be faster** due to zero IOMMU overhead
- **Less secure** - devices can access any memory

### With Proper IOMMU (Passthrough Mode)
- IOMMU hardware active but minimal overhead
- Device isolation and memory protection
- IOMMU groups for GPU/NIC topology awareness
- **Slight performance overhead** (~1-3%) but better for:
  - SR-IOV VF assignment
  - GPU Direct RDMA with proper isolation
  - Multi-tenant security

## Recommendation

### For RDMA/GPU Workloads

**Option 1: Keep Current Configuration** (Recommended for maximum performance)
- If this is a dedicated ML/RDMA cluster
- No multi-tenancy requirements
- Performance is critical
- **No changes needed**

**Option 2: Enable IOMMU Properly**
- Add `amd_iommu=on` to kernel parameters
- Expected ~1-3% performance cost
- Better device isolation
- Required for certain SR-IOV scenarios

### How to Enable IOMMU (If Desired)

For OpenShift/RHCOS, use a MachineConfig:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-amd-iommu
spec:
  kernelArguments:
    - iommu=pt
    - amd_iommu=on
```

Apply and reboot:
```bash
oc apply -f iommu-machineconfig.yaml
# Node will automatically reboot to apply
```

### Verification After Enabling

```bash
# Check kernel parameters
cat /proc/cmdline | grep iommu

# Should see AMD IOMMU messages
dmesg | grep AMD-Vi

# Should have IOMMU groups
ls /sys/kernel/iommu_groups/ | wc -l  # Should be > 0
```

## Related Information

### Why This Might Not Matter

Your **194-309 GB/s** RDMA results were achieved **WITHOUT** IOMMU enabled. This suggests:

1. ConnectX-7 NICs working well without IOMMU
2. GPU Direct RDMA functioning properly
3. No device isolation issues in your environment

### Why You Might Want IOMMU Anyway

- Better security/isolation
- Some RDMA features may require it
- GPU passthrough to VMs
- SR-IOV VF assignment to containers

## Comparison with Other Nodes

Should check **moc-r4pcc04u36-nairr** after it reboots to see if it has the same configuration.

## Files

- Full kernel cmdline: checked via `cat /proc/cmdline`
- dmesg output: checked via `dmesg | grep -i iommu`
- IOMMU groups: checked via `ls /sys/kernel/iommu_groups/`
