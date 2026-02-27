# Yunshi RDMA Configuration - VERIFIED WORKING

**Date**: 2026-02-27
**Status**: ✅ OPERATIONAL

## Deployment Status

### Pods Running
- **tsfm-node-0**: Running on `moc-r4pcc02u15-yunshi`
- **tsfm-node-1**: Running on `moc-r4pcc02u16-yunshi`

### RDMA Configuration
✅ SR-IOV VFs with RDMA enabled
✅ `/dev/infiniband` devices accessible (uverbs0-11, rdma_cm)
✅ `/sys/class/infiniband` accessible (mlx5_0-11)
✅ NCCL configured for SR-IOV VF RDMA: **mlx5_6, mlx5_7, mlx5_10, mlx5_11**

## Configuration Changes

### 1. Security Context Constraint (nccl-rdma-scc)

Updated SCC to allow RDMA device access:

```yaml
allowHostDirVolumePlugin: true
allowPrivilegedContainer: true
seLinuxContext:
  type: RunAsAny
allowedCapabilities:
  - IPC_LOCK
  - SYS_RESOURCE
users:
  - system:serviceaccount:b-ts-data-agent-0a0cee:h-kim-sa
volumes:
  - hostPath  # Added for RDMA devices
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
```

### 2. StatefulSet Configuration

Updated `generated/statefulset-yunshi.yaml` with:

#### Security Context
```yaml
securityContext:
  privileged: true  # Required for RDMA device access
  capabilities:
    add:
      - IPC_LOCK      # For pinned memory
      - SYS_RESOURCE  # For ulimit -l unlimited
```

#### NCCL Environment Variables
```yaml
env:
  - name: NCCL_IB_HCA
    value: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"  # SR-IOV VF RDMA devices
  - name: NCCL_SOCKET_IFNAME
    value: "eth0"
  - name: NCCL_IB_GID_INDEX
    value: "3"
  - name: NCCL_NET_GDR_LEVEL
    value: "5"
```

#### Volume Mounts
```yaml
volumeMounts:
  - name: infiniband
    mountPath: /dev/infiniband
  - name: sys-class-infiniband
    mountPath: /sys/class/infiniband
    readOnly: true
```

#### Volumes
```yaml
volumes:
  - name: infiniband
    hostPath:
      path: /dev/infiniband
      type: Directory
  - name: sys-class-infiniband
    hostPath:
      path: /sys/class/infiniband
      type: Directory
```

## Verification

### RDMA Devices Accessible
```bash
$ oc exec tsfm-node-0 -- ls -l /dev/infiniband/uverbs*
crw-rw-rw-. 1 root root 231, 192 Feb 25 23:20 uverbs0
crw-rw-rw-. 1 root root 231, 193 Feb 25 23:20 uverbs1
crw-rw-rw-. 1 root root 231, 202 Feb 25 23:21 uverbs10
crw-rw-rw-. 1 root root 231, 203 Feb 25 23:21 uverbs11
...
```

### NCCL Configuration
```bash
$ oc exec tsfm-node-0 -- env | grep NCCL
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_SOCKET_IFNAME=eth0
NCCL_IB_GID_INDEX=3
NCCL_NET_GDR_LEVEL=5
NCCL_DEBUG=INFO
```

### Training Status
✅ Both nodes loading datasets
✅ Model initialized (283.42M trainable params)
✅ Multi-node DDP training active

## SR-IOV vs Host Networking

### Yunshi Nodes (SR-IOV)
- Uses SR-IOV Virtual Functions (VFs) for network isolation
- RDMA devices: mlx5_6, mlx5_7, mlx5_10, mlx5_11 (VFs)
- Requires hostPath mounts for `/dev/infiniband`
- Uses Multus CNI for multiple network interfaces

### -nairr Nodes (Host Networking)
- Uses `hostNetwork: true` for direct host access
- RDMA devices: mlx5_2, mlx5_3, mlx5_4, mlx5_5 (Physical Functions)
- Simpler configuration, no SR-IOV complexity

## Deployment

To deploy or update the yunshi StatefulSet:

```bash
cd deployments/yunshi
oc apply -f generated/statefulset-yunshi.yaml
```

## Troubleshooting

### If RDMA devices not accessible:
1. Verify SCC allows hostPath: `oc get scc nccl-rdma-scc -o yaml`
2. Check pod security context: `oc get pod tsfm-node-0 -o yaml | grep privileged`
3. Verify SELinux context: `oc get scc nccl-rdma-scc | grep seLinux`

### If NCCL errors occur:
1. Check RDMA device availability: `oc exec tsfm-node-0 -- ls /sys/class/infiniband/`
2. Verify NCCL_IB_HCA matches available devices
3. Check pod logs: `oc logs tsfm-node-0 | grep NCCL`

## Key Differences from Previous Configuration

1. **Removed init container**: No longer auto-detecting RDMA interfaces (static config works better)
2. **Added privileged mode**: Required for hostPath RDMA device access with SELinux
3. **Fixed node affinity**: Moved from initContainers section to spec.affinity
4. **Static NCCL_IB_HCA**: Explicitly set to SR-IOV VF devices instead of auto-detection

## Next Steps

- Monitor training performance and RDMA utilization
- Compare performance with -nairr nodes (host networking)
- Document best practices for SR-IOV RDMA on OpenShift
