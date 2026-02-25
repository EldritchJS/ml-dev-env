# RDMA Setup - Complete Implementation

## Overview

This directory contains the complete RDMA/InfiniBand setup for multi-node H100 GPU training with automatic device detection and IOMMU passthrough configuration.

## Files

### Configuration Files

- **`/k8s/nccl-ib-autodetect-configmap.yaml`**
  - ConfigMap with wrapper script for automatic SR-IOV device detection
  - Sets `NCCL_IB_HCA` dynamically per pod based on allocated devices
  - Configures unlimited memlock for RDMA
  - Already integrated into `scripts/deploy-h-kim.sh`

- **`/k8s/machineconfigs/99-worker-iommu-passthrough.yaml`**
  - MachineConfig to enable IOMMU passthrough mode (`iommu=pt`)
  - Required for RDMA and GPUDirect RDMA to work
  - Applied to all worker nodes via OpenShift Machine Config Operator

### Documentation

- **`IOMMU-PASSTHROUGH-FIX.md`**
  - Complete technical documentation
  - Problem analysis and solution details
  - Installation and verification procedures
  - Performance benchmarks and testing guide

- **`ADMIN-QUICK-START.md`**
  - Quick reference for cluster administrators
  - One-command deployment instructions
  - Verification commands
  - Monitoring and troubleshooting

- **`RDMA-SETUP-COMPLETE.md`** (this file)
  - Overview and file index

## Implementation Status

### ✅ Completed

1. **Auto-Detection System**
   - Detects SR-IOV allocated InfiniBand devices per pod
   - Works across different nodes with different device names
   - Fallback detection if environment variables not available

2. **IOMMU Passthrough**
   - Applied to all 13 worker nodes
   - Changed from Translation mode (DMA-FQ) to Passthrough (identity)
   - Required for RDMA memory registration

3. **Integration**
   - Baked into `scripts/deploy-h-kim.sh`
   - No manual configuration required
   - Portable across clusters

4. **Verification**
   - Tested on H100 nodes
   - RDMA working with 83+ GiB/s bandwidth
   - Zero RDMA errors (IBV_WC_LOC_PROT_ERR fixed)

## Performance Results

| Mode | Bandwidth | vs TCP |
|------|-----------|--------|
| TCP (fallback) | 0.98 GiB/s | 1x |
| RDMA (working) | 83.33 GiB/s | **85x faster** |

## Quick Start

### For Users

Deploy h-kim with RDMA (auto-detection already integrated):

```bash
./scripts/deploy-h-kim.sh \
  --namespace my-namespace \
  --mode rdma \
  --type multi
```

### For Administrators

Enable IOMMU passthrough (one-time cluster setup):

```bash
oc apply -f k8s/machineconfigs/99-worker-iommu-passthrough.yaml
```

Monitor rollout:
```bash
watch oc get mcp worker
```

## Architecture

### Auto-Detection Flow

1. Pod starts with wrapper script (`/scripts/nccl-wrapper.sh`)
2. Script extracts allocated devices from SR-IOV env vars
3. Sets `NCCL_IB_HCA` to detected devices (e.g., `mlx5_6,mlx5_7,mlx5_10,mlx5_11`)
4. Sets unlimited memlock for RDMA
5. Executes main container command

### IOMMU Passthrough

**Before:**
- IOMMU Mode: Translation (DMA-FQ)
- RDMA: Blocked with memory protection errors
- Performance: TCP fallback at 0.98 GiB/s

**After:**
- IOMMU Mode: Passthrough (identity)
- RDMA: Working with GPUDirect
- Performance: 83+ GiB/s (85x faster)

## Verification

### Check Auto-Detection

```bash
oc logs <pod-name> | grep "Auto-detected"
# Should show: ✓ Auto-detected allocated SR-IOV devices: mlx5_X,mlx5_Y,...
```

### Check IOMMU

```bash
oc debug node/<node-name> -- chroot /host cat /proc/cmdline | grep iommu=pt
# Should show: iommu=pt

oc debug node/<node-name> -- chroot /host dmesg | grep "Default domain type"
# Should show: Passthrough
```

### Test RDMA

```bash
# The nccl_torch_bench.py is available in all h-kim pods
# Run it to verify RDMA performance
```

## Troubleshooting

See `IOMMU-PASSTHROUGH-FIX.md` for detailed troubleshooting guide.

Common checks:
- Verify IOMMU passthrough is applied to nodes
- Check unlimited memlock: `oc exec <pod> -- ulimit -l` → should show "unlimited"
- Verify devices detected: Check pod logs for "Auto-detected allocated SR-IOV devices"
- Test connectivity: `oc exec <pod> -- ibstat mlx5_X` → should show "PORT_ACTIVE"

## Related Documentation

- `/docs/H-KIM-RDMA-SETUP.md` - Original RDMA setup guide
- `/docs/MULTI-NODE-GUIDE.md` - Multi-node training guide
- `/IB-AUTODETECT-FINAL-SUMMARY.md` - Auto-detection implementation summary (root dir)
- `/RDMA-DEBUG-SUMMARY.md` - RDMA debugging findings (root dir)

## History

- **2026-02-25**: IOMMU passthrough implemented, RDMA fully working
- **2026-02-25**: Auto-detection system integrated into deploy-h-kim.sh
- **2026-02-24**: Initial auto-detection implementation
- **Earlier**: Manual RDMA configuration

## Status

🎉 **Production Ready** - RDMA working with 85x performance improvement over TCP
