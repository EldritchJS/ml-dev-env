# Mellanox Firmware Configuration with mlxconfig

## Overview

ConnectX-7 NIC firmware settings (nvconfig parameters) can be queried and modified using `mlxconfig`. Since the MOFED driver pods don't include this tool, a dedicated privileged pod is required.

## Creating an mlxconfig Pod

Use the `nic-configuration-operator-daemon` image — it contains `mlxconfig` at `/usr/bin/mlxconfig`.

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mlxconfig-<NODE_SHORT>
  namespace: nccl-test
spec:
  nodeName: <FULL_NODE_NAME>
  hostNetwork: true
  hostPID: true
  containers:
  - name: mlxconfig
    image: nvcr.io/nvidia/mellanox/nic-configuration-operator-daemon@sha256:fe970471827cef38d4270e275d58282d140aeb3b4f19636506b02b1cdd20de2e
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
  restartPolicy: Never
EOF
```

Example for u16-yunshi:
```bash
sed 's/<NODE_SHORT>/u16/g; s/<FULL_NODE_NAME>/moc-r4pcc02u16-yunshi/g'
```

## ConnectX-7 PCI Addresses

All H100 nodes have 4 ConnectX-7 NICs at these PCI addresses:

| NIC | PCI Address | Interface | Subnet |
|-----|-------------|-----------|--------|
| 1 | 03:00.0 | eno5np0 | 10.0.103.0/24 |
| 2 | 23:00.0 | eno6np0 | 10.0.104.0/24 |
| 3 | a3:00.0 | eno7np0 | 10.0.105.0/24 |
| 4 | c3:00.0 | eno8np0 | 10.0.106.0/24 |

## Querying Settings

```bash
# Query all settings on one NIC
oc exec -n nccl-test mlxconfig-<NODE_SHORT> -- mlxconfig -d <PCI_ADDR> q

# Query specific performance-critical settings on all 4 NICs
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  echo "=== $pci ==="
  oc exec -n nccl-test mlxconfig-<NODE_SHORT> -- mlxconfig -d $pci q 2>&1 \
    | grep -iE "ADVANCED_PCI|MAX_ACC_OUT|PCI_WR_ORDER|RDMA_SELECTIVE"
done
```

## Performance-Critical nvconfig Parameters

| Parameter | Optimal Value | Purpose |
|-----------|---------------|---------|
| ADVANCED_PCI_SETTINGS | True(1) | Enables advanced PCI tuning (must be enabled first) |
| MAX_ACC_OUT_READ | 128 | Maximum outstanding PCI read requests (hidden when ADVANCED_PCI_SETTINGS=False) |
| PCI_WR_ORDERING | per_mkey(0) | PCI write ordering mode |
| RDMA_SELECTIVE_REPEAT_EN | True(1) | RDMA selective repeat for reliability |
| ATS_ENABLED | True(1) | PCI Address Translation Services for GPUDirect RDMA |
| ROCE_CONTROL | 2 | RoCE mode control |

**Important:** `MAX_ACC_OUT_READ` is invisible when `ADVANCED_PCI_SETTINGS=False`. However, you do **NOT** need to reboot after enabling `ADVANCED_PCI_SETTINGS` — setting it via mlxconfig immediately makes `MAX_ACC_OUT_READ` available to set in the same session. Set both, then reboot once.

## Modifying Settings

```bash
# Full optimization of a node — set ADVANCED_PCI_SETTINGS first, then MAX_ACC_OUT_READ, ONE reboot:
for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  oc exec -n nccl-test mlxconfig-<NODE_SHORT> -- mlxconfig -d $pci -y set ADVANCED_PCI_SETTINGS=1
  oc exec -n nccl-test mlxconfig-<NODE_SHORT> -- mlxconfig -d $pci -y set MAX_ACC_OUT_READ=128
done
# Then reboot the node ONCE
```

## Reboot Procedure

nvconfig changes are "Next Boot" — they require a node reboot.

```bash
# 1. Cordon the node
oc adm cordon <FULL_NODE_NAME>

# 2. Check for user workloads (ignore DaemonSet pods)
oc get pods --all-namespaces --field-selector spec.nodeName=<FULL_NODE_NAME>

# 3. Reboot
oc debug node/<FULL_NODE_NAME> -- chroot /host systemctl reboot

# 4. Wait for node to come back (can take up to 20 minutes)
oc get node <FULL_NODE_NAME> -w

# 5. Uncordon
oc adm uncordon <FULL_NODE_NAME>

# 6. Verify settings took effect
# Re-create mlxconfig pod (old one died with reboot) and query
```

## Node Firmware Status (as of 2026-07-12)

| Node | ADVANCED_PCI_SETTINGS | MAX_ACC_OUT_READ | PCI_WR_ORDERING | RDMA_SELECTIVE_REPEAT_EN | ATS_ENABLED | ROCE_CONTROL | Status |
|------|----------------------|------------------|-----------------|--------------------------|-------------|--------------|--------|
| u15-yunshi | True(1) | 128 | per_mkey(0) | True(1) | True(1) | 2 | Optimal |
| u16-yunshi | True(1) | 128 | per_mkey(0) | True(1) | True(1) | 2 | Optimal |
| u17-nairr | True(1) | 128 | per_mkey(0) | True(1) | True(1) | 2 | Optimal |
| u18-nairr | True(1) | 128 | per_mkey(0) | True(1) | True(1) | 2 | Optimal |
| u25-nairr | True(1) | 128 | per_mkey(0) | True(1) | True(1) | 2 | Optimal |

All 5 nodes verified optimal as of 2026-07-12. Managed by NicConfigurationTemplate `connectx7-performance` (rawNvConfig only, no operator profiles).

## NVIDIA NIC Configuration Operator

The NIC Configuration Operator (part of NVIDIA Network Operator) manages nvconfig via NicDevice CRs. The **NVIDIA Maintenance Operator** (`maintenance.nvidia.com`) is installed with `maxUnavailable: 0`, meaning it cannot schedule maintenance (cordon/drain/reboot) on any node. This is intentional — the operator is in read-only mode until `maxUnavailable` is raised.

**Current state (2026-07-12):**
- A `NicConfigurationTemplate` (`connectx7-performance`) declares the desired nvconfig for all ConnectX-7 NICs using rawNvConfig only (no operator profiles — profiles caused side effects like CNP_DSCP_P1 drift)
- All 5 nodes: nvconfig matches desired state after MO rollout
- Template manages 6 params: ADVANCED_PCI_SETTINGS, RDMA_SELECTIVE_REPEAT_EN, PCI_WR_ORDERING, ROCE_CONTROL, ATS_ENABLED, plus linkType and numVfs
- MAX_ACC_OUT_READ is not in the template (it is set implicitly when ADVANCED_PCI_SETTINGS=1)
- **Important:** Do NOT use `pciPerformanceOptimized` or `roceOptimized` profiles — they change params beyond what's declared (e.g., CNP_DSCP_P1 from 48→4) and caused a 10 GB/s regression

**To allow the operator to apply changes (one node at a time):**
```bash
oc patch maintenanceoperatorconfig -n nvidia-maintenance-operator default \
  --type merge -p '{"spec":{"maxUnavailable":1}}'
```

**To freeze maintenance again:**
```bash
oc patch maintenanceoperatorconfig -n nvidia-maintenance-operator default \
  --type merge -p '{"spec":{"maxUnavailable":0}}'
```

**Operator inventory:**
```bash
# List all discovered NICs
oc get nicdevices -n nvidia-network-operator

# View details for a specific NIC
oc get nicdevice <name> -n nvidia-network-operator -o yaml

# Check pending maintenance requests
oc get nodemaintenance -A

# Check operator config
oc get maintenanceoperatorconfig -n nvidia-maintenance-operator default -o yaml
```

**Install manifests:** `k8s/maintenance-operator/`

The manual mlxconfig pod procedure above remains available as a fallback.

## Cleanup

```bash
oc delete pod mlxconfig-<NODE_SHORT> -n nccl-test
```

## Last Updated

2026-07-12
