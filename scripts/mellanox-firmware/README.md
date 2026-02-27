# Mellanox ConnectX-7 Firmware Optimization for H100 Nodes

This directory contains documentation and scripts for optimizing Mellanox ConnectX-7 400G NIC firmware settings on H100 GPU nodes.

## Problem Solved

H100 nodes were experiencing 10-30% RDMA bandwidth degradation due to suboptimal Mellanox firmware settings. After optimization, nodes achieved **194.87 GB/s** peak bandwidth in multi-node NCCL benchmarks.

## Critical Firmware Parameters

The following firmware settings must be optimized for maximum RDMA performance:

| Parameter | Optimal Value | Impact |
|-----------|--------------|--------|
| `ADVANCED_PCI_SETTINGS` | True(1) | Enables PCIe optimizations, unlocks MAX_ACC_OUT_READ |
| `MAX_ACC_OUT_READ` | 128 | Maximum outstanding RDMA READ requests |
| `PCI_WR_ORDERING` | per_mkey(0) | Consistent PCIe write ordering |

## Quick Start

### 1. Check Current Firmware Settings

```bash
# Create MFT diagnostic pod on target node
oc apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: mft-diagnostics-<node-short-name>
  namespace: nvidia-network-operator
spec:
  nodeName: <full-node-name>
  hostIPC: true
  hostNetwork: true
  hostPID: true
  containers:
  - name: mft-diagnostics
    image: quay.io/jschless/mft-diagnostics:latest
    securityContext:
      privileged: true
    volumeMounts:
    - name: dev
      mountPath: /dev
    - name: sys
      mountPath: /sys
  volumes:
  - name: dev
    hostPath:
      path: /dev
  - name: sys
    hostPath:
      path: /sys
  restartPolicy: Always
EOF

# Check all 4 NICs
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  echo "=== NIC $pci ==="
  oc exec -n nvidia-network-operator mft-diagnostics-<node> -- \
    mlxconfig -d $pci query | grep -E "ADVANCED_PCI|MAX_ACC|PCI_WR"
done
```

### 2. Apply Firmware Fixes

Use the provided script or manually apply:

```bash
# For each NIC
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  oc exec -n nvidia-network-operator mft-diagnostics-<node> -- \
    mlxconfig -y -d $pci set ADVANCED_PCI_SETTINGS=1
  oc exec -n nvidia-network-operator mft-diagnostics-<node> -- \
    mlxconfig -y -d $pci set PCI_WR_ORDERING=0
  oc exec -n nvidia-network-operator mft-diagnostics-<node> -- \
    mlxconfig -y -d $pci set MAX_ACC_OUT_READ=128
done
```

### 3. Reboot Node to Activate

```bash
# Drain node
oc adm drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# Reboot
oc debug node/<node-name> -- chroot /host systemctl reboot

# Wait for node to come back (~5-10 min), then uncordon
oc adm uncordon <node-name>

# Verify settings are active
oc exec -n nvidia-network-operator mft-diagnostics-<node> -- \
  mlxconfig -d 03:00.0 query | grep -E "ADVANCED_PCI|MAX_ACC|PCI_WR"
```

## Files in This Directory

### Documentation
- **firmware-optimization-all-nairr-nodes-2026-02-27.md** - Comprehensive guide covering all nodes
- **mellanox-firmware-comparison-u25-u36.md** - Detailed analysis and impact assessment
- **session-summary-2026-02-26.md** - Full session log of initial optimization work
- **firmware-fix-u36-applied.md** - Example of applying fixes to a single node
- **u36-firmware-verification-complete.md** - Post-reboot verification procedure
- **iommu-analysis-u25.md** - IOMMU investigation (concluded not needed)

### Scripts
- **check-mellanox-settings.sh** - Check firmware settings on nodes
- **apply-firmware-fixes-all.sh** - Apply fixes to multiple nodes
- **check-all-nodes-firmware.sh** - Check all nodes in parallel

## Performance Impact

**Before Optimization:**
- Degraded RDMA bandwidth
- Inconsistent performance across nodes
- 10-30% performance loss

**After Optimization:**
- **194.87 GB/s** peak bandwidth (8× H100 GPUs, 2 nodes)
- Consistent performance across all nodes
- Full utilization of ConnectX-7 400G NICs

## NCCL Configuration Note

When using SR-IOV with ConnectX-7 NICs, **do not hardcode** `NCCL_IB_HCA` device names (e.g., mlx5_6,mlx5_7). Device numbering can differ between nodes.

**Instead**, use `NCCL_SOCKET_IFNAME` to specify network interfaces and let NCCL auto-detect:

```yaml
env:
  - name: NCCL_SOCKET_IFNAME
    value: "net1,net2,net3,net4"
  # Don't set NCCL_IB_HCA - let NCCL auto-detect from socket interfaces
```

## Nodes Already Optimized (as of 2026-02-27)

- ✅ moc-r4pcc04u25-nairr (verified)
- ✅ moc-r4pcc04u36-nairr (verified)
- ✅ moc-r4pcc04u09-nairr (pending reboot verification)
- ✅ moc-r4pcc04u11-nairr (pending reboot verification)
- ✅ moc-r4pcc04u12-nairr (pending reboot verification)
- ✅ moc-r4pcc04u16-nairr (pending reboot verification)

## Related Work

See also:
- **PyTorch benchmarks**: `../../deployments/h-kim/pytorch-benchmark-optimized.yaml`
- **Benchmark results**: `../../deployments/h-kim/benchmark-results-u25-u36-post-firmware-fix.txt`

## References

- Mellanox Firmware Tools (MFT) documentation
- NVIDIA NCCL configuration guide
- ConnectX-7 firmware configuration best practices
