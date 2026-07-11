# RDMA Debugging Summary

## ✅ What's Working

**IB Auto-Detection: PERFECT!**
- ✓ Auto-detects IB devices on each pod: `mlx5_6,mlx5_7,mlx5_10,mlx5_11`
- ✓ NCCL loads all devices correctly
- ✓ Works across different nodes with different device names
- ✓ Baked into `deploy-h-kim.sh`

## ❌ Root Cause: Memory Lock Limit

**Critical Issue Found:**
```bash
ulimit -l
8192  # Only 8 MB - RDMA needs GB of locked memory!
```

**Error:**
```
IBV_WC_LOC_PROT_ERR (InfiniBand Work Completion - Local Protection Error)
```

This error occurs because RDMA requires locking large amounts of memory for DMA operations, but the pod is limited to 8 MB.

## 🔍 What Was Tried

### 1. ✗ IPC_LOCK Capability
- Added `IPC_LOCK` capability to pod
- Still couldn't set unlimited memlock
- Limited by OpenShift Security Context Constraints (SCC)

### 2. ✗ SYS_RESOURCE Capability
- Tried `SYS_RESOURCE` capability
- Rejected by all SCCs
- Not allowed in `nccl-scc`

### 3. ✗ SYS_ADMIN Capability
- Added `SYS_ADMIN` (allowed by `nccl-scc`)
- Granted service account permission: `oc adm policy add-scc-to-user nccl-scc -z h-kim-sa`
- Still couldn't set unlimited memlock

### 4. ✗ ulimit / prlimit / Python setrlimit
All methods failed:
```bash
ulimit -l unlimited              # Operation not permitted
prlimit --memlock=unlimited      # Operation not permitted
resource.setrlimit(...)          # not allowed to raise maximum limit
```

## 🔧 Solutions (Requires Cluster Admin)

### Option 1: Modify nccl-scc (Recommended)

Update the existing `nccl-scc` to allow unlimited memlock:

```bash
# As cluster admin
oc edit scc nccl-scc
```

Add under `allowedCapabilities`:
```yaml
allowedCapabilities:
- IPC_LOCK
- SYS_ADMIN
- SYS_RESOURCE  # Add this
```

Or set `allowPrivilegedContainer: true` and use privileged mode.

### Option 2: Create Custom SCC with Memlock

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: nccl-rdma-scc
allowHostDirVolumePlugin: true
allowHostIPC: true
allowHostNetwork: true
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities:
- IPC_LOCK
- SYS_RESOURCE
fsGroup:
  type: RunAsAny
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- hostPath
- persistentVolumeClaim
- projected
- secret
users:
- system:serviceaccount:b-efficient-memory-offloading-765cab:h-kim-sa
```

Apply:
```bash
oc apply -f nccl-rdma-scc.yaml
oc adm policy add-scc-to-user nccl-rdma-scc -z h-kim-sa -n b-efficient-memory-offloading-765cab
```

### Option 3: Use Privileged Mode (Easiest but less secure)

Modify `deploy-h-kim.sh` to use privileged containers:

```yaml
securityContext:
  privileged: true
  capabilities:
    add:
    - IPC_LOCK
```

Then:
```bash
oc adm policy add-scc-to-user privileged -z h-kim-sa -n b-efficient-memory-offloading-765cab
```

### Option 4: Request Platform Team to Increase Default Memlock

Ask cluster admins to increase the default memlock limit cluster-wide or for specific nodes.

## 📊 Diagnostic Output

### IB Devices Detected
```
Device: mlx5_6 - State: PORT_ACTIVE, Link: Ethernet (RoCE)
Device: mlx5_7 - State: PORT_ACTIVE, Link: Ethernet (RoCE)
Device: mlx5_8 - State: PORT_ACTIVE, Link: Ethernet (RoCE)
Device: mlx5_9 - State: PORT_ACTIVE, Link: Ethernet (RoCE)
```

### GID Tables (RoCE v2)
```
mlx5_6: fe80:...:f08e:cbff:fe95:29dc (link-local)
        0000:...:ffff:0a00:6a07     (IPv4-mapped)
mlx5_7: fe80:...:cc4c:f0ff:feef:9f75
        0000:...:ffff:0a00:6907
...
```

### NCCL Settings
```
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11  ✓ Auto-detected
NCCL_IB_GID_INDEX=3                          ✓ Correct for RoCE v2
NCCL_IB_DISABLE=0                            ✓ RDMA enabled
NCCL_NET_GDR_LEVEL=5                         ✓ GPUDirect RDMA enabled
```

### Security Context
```
Capabilities: IPC_LOCK, SYS_ADMIN           ✓
Service Account: h-kim-sa                    ✓
SCC: nccl-scc                                ✓
Memlock Limit: 8192 KB                       ✗ TOO LOW!
```

## 🎯 Next Steps

1. **Contact cluster admins** to modify `nccl-scc` or create custom SCC
2. **OR** Get permission to use privileged mode
3. **Redeploy** pods after SCC changes
4. **Test** with diagnostic script:

```bash
# After SCC fix, verify memlock
oc exec h-kim-0 -- ulimit -l
# Should show: unlimited

# Then run NCCL benchmark
oc exec h-kim-1 -- bash /workspace/run-nccl-bench.sh &
oc exec h-kim-0 -- bash /workspace/run-nccl-bench.sh
```

## 📝 Files Created

- `debug-rdma.sh` - Comprehensive RDMA diagnostic script
- `scripts/deploy-h-kim.sh` - Updated with IB auto-detection + SYS_ADMIN
- `k8s/nccl-ib-autodetect-configmap.yaml` - Auto-detection wrapper
- `RDMA-DEBUG-SUMMARY.md` - This file

## ✅ What's Ready to Use

Once memlock is fixed, everything else is configured correctly:
- ✓ IB auto-detection working
- ✓ NCCL environment configured
- ✓ Security capabilities set
- ✓ Service account granted nccl-scc access
- ✓ SR-IOV RDMA resources allocated

**Only blocker: Memlock limit!**
