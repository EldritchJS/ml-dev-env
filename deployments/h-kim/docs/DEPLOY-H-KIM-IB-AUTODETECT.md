# InfiniBand Auto-Detection in deploy-h-kim.sh

## Changes Made

The `scripts/deploy-h-kim.sh` script now **automatically detects InfiniBand devices** on each pod at runtime instead of using hardcoded device names.

### What Changed

#### Before (hardcoded)
```bash
NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
```

#### After (auto-detected)
```bash
# Deployed as ConfigMap, auto-detects devices using ibv_devinfo -l
# Each pod detects its own working IB devices at startup
NCCL_IB_HCA=""  # Set automatically by wrapper script
```

---

## How It Works

1. **ConfigMap is deployed** containing the auto-detection wrapper script
2. **Pods mount the ConfigMap** at `/scripts/nccl-wrapper.sh`
3. **Container command wraps** your actual command:
   - Old: `command: ["/bin/bash", "-c", "sleep infinity"]`
   - New: `command: ["/bin/bash", "/scripts/nccl-wrapper.sh", "sleep", "infinity"]`
4. **Wrapper runs** `ibv_devinfo -l` to detect working IB devices
5. **Wrapper exports** `NCCL_IB_HCA=mlx5_X,mlx5_Y,...` with detected devices
6. **Wrapper execs** your actual command with NCCL variables already set

---

## Usage (No Changes Required!)

The script works exactly the same as before:

```bash
# Deploy single-node with RDMA (auto-detects IB devices)
./scripts/deploy-h-kim.sh --namespace my-ns --mode rdma --type single

# Deploy multi-node with RDMA (each pod auto-detects its own devices)
./scripts/deploy-h-kim.sh --namespace my-ns --mode rdma --type multi

# Preview what will be deployed
./scripts/deploy-h-kim.sh --namespace my-ns --dry-run
```

---

## Verification

After deployment, check that auto-detection worked:

```bash
# Check pod logs (single-node)
oc logs h-kim-dev -n <namespace> | head -20

# Check pod logs (multi-node)
oc logs h-kim-0 -n <namespace> | head -20

# You should see:
# === NCCL InfiniBand Auto-Detection ===
# ✓ Auto-detected IB devices: mlx5_6,mlx5_7,mlx5_10,mlx5_11
# ✓ Found 4 working InfiniBand device(s)
#
# === NCCL Configuration ===
#   NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
#   NCCL_IB_GID_INDEX=3
#   NCCL_NET_GDR_LEVEL=5
#   ...
```

Check environment in running pod:
```bash
oc exec h-kim-dev -n <namespace> -- env | grep NCCL_IB_HCA
```

---

## Benefits

### 1. **Works Across Different Nodes**
- Old way: All nodes must have `mlx5_6,mlx5_7,mlx5_10,mlx5_11`
- New way: Each pod detects its own devices (might be `mlx5_0,mlx5_1,mlx5_2,mlx5_3` on different nodes)

### 2. **Only Uses Working Devices**
- `ibv_devinfo -l` only lists devices with working InfiniBand verb interfaces
- Filters out virtual functions, disabled ports, etc.
- No more NCCL warnings about invalid devices

### 3. **More Portable**
- Same deployment script works on different clusters
- No need to check device names before deploying
- Future-proof against hardware changes

### 4. **Easier Troubleshooting**
- Auto-detection output appears in pod logs
- Clear indication if IB devices are not found
- Easy to verify what NCCL is actually using

---

## Technical Details

### ConfigMap Content
The script now deploys this ConfigMap before creating pods:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nccl-ib-autodetect
  namespace: <your-namespace>
data:
  nccl-wrapper.sh: |
    #!/bin/bash
    # Auto-detects IB devices using ibv_devinfo
    # Sets NCCL environment variables
    # Executes wrapped command
```

### Pod Modifications

**Volume added:**
```yaml
volumes:
- name: nccl-wrapper
  configMap:
    name: nccl-ib-autodetect
    defaultMode: 0755
```

**VolumeMount added:**
```yaml
volumeMounts:
- name: nccl-wrapper
  mountPath: /scripts
```

**Command wrapped:**
```yaml
# Single-node
command: ["/bin/bash", "/scripts/nccl-wrapper.sh", "sleep", "infinity"]

# Multi-node
command:
- /bin/bash
- /scripts/nccl-wrapper.sh
- bash
- -c
- |
  # Your startup script here
```

**Environment variable removed:**
```yaml
# This line is now commented out (auto-detected instead)
# - name: NCCL_IB_HCA
#   value: "$NCCL_IB_HCA"
```

---

## Backwards Compatibility

- ✅ All existing `--mode rdma` deployments work as before
- ✅ All existing `--mode tcp` deployments work as before
- ✅ No command-line flag changes needed
- ✅ ConfigMap is automatically deployed
- ✅ Existing pods can continue running (update on next deploy)

---

## Troubleshooting

### Problem: No IB devices detected

```bash
# Check if ibverbs tools are in the image
oc exec h-kim-dev -- which ibv_devinfo

# If not found, the image needs ibverbs-utils
# The h-kim image should already have it
```

### Problem: Want to override auto-detection

You can still manually set `NCCL_IB_HCA` as an environment variable in the pod spec if needed:

```yaml
env:
- name: NCCL_IB_HCA
  value: "mlx5_0,mlx5_1"  # Manual override
```

The wrapper will respect existing `NCCL_IB_HCA` values and only set it if not already defined.

### Problem: Want to see what devices exist

```bash
# All devices in sysfs
oc exec h-kim-dev -- ls /sys/class/infiniband/

# Only working devices (what NCCL should use)
oc exec h-kim-dev -- ibv_devinfo -l
```

---

## Files Modified

| File | Changes |
|------|---------|
| `scripts/deploy-h-kim.sh` | - Added ConfigMap deployment<br>- Removed hardcoded NCCL_IB_HCA<br>- Added wrapper volume/mount<br>- Wrapped container commands |

## Files Created

These were created as part of the general IB auto-detection solution:

| File | Purpose |
|------|---------|
| `k8s/nccl-ib-autodetect-configmap.yaml` | Standalone ConfigMap (reference) |
| `scripts/add-ib-autodetect.py` | Tool to add IB detection to any YAML |
| `QUICKSTART-IB-AUTODETECT.md` | General IB auto-detection guide |
| `IB_AUTO_DETECTION.md` | Complete documentation |

---

## Summary

**Before:**
- Hardcoded `NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"`
- Broke if nodes had different device names
- Used all mlx5 devices even if some weren't working

**After:**
- Auto-detects working IB devices using `ibv_devinfo -l`
- Works on any node with any device naming
- Only uses devices with working InfiniBand verb interfaces
- No changes needed to how you run the script!

Just deploy as usual:
```bash
./scripts/deploy-h-kim.sh --namespace my-ns --mode rdma
```
