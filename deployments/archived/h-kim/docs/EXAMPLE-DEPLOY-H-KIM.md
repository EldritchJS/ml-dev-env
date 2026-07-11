# Example: Deploy H-Kim with Auto-Detected InfiniBand

## Quick Example

```bash
# Deploy multi-node h-kim with auto-detected IB devices
./scripts/deploy-h-kim.sh \
  --namespace b-efficient-memory-offloading-765cab \
  --mode rdma \
  --type multi

# What happens automatically:
# 1. ConfigMap with IB auto-detection script is deployed
# 2. StatefulSet with 2 pods is created
# 3. Each pod auto-detects its own IB devices at startup
# 4. Training environment is ready with correct NCCL_IB_HCA
```

## Step-by-Step Walkthrough

### 1. Deploy (automatically includes IB auto-detection)

```bash
./scripts/deploy-h-kim.sh \
  --namespace b-efficient-memory-offloading-765cab \
  --mode rdma \
  --type multi
```

Output:
```
[INFO] ==========================================
[INFO] H-Kim Deployment Configuration
[INFO] ==========================================
[INFO] Namespace:        b-efficient-memory-offloading-765cab
[INFO] Network Mode:     rdma
[INFO] Deployment Type:  multi
[INFO] ==========================================

[INFO] Deploying NCCL InfiniBand auto-detection ConfigMap...
configmap/nccl-ib-autodetect created

[INFO] Deploying: Headless Service
service/h-kim-headless created

[INFO] Deploying: Multi-node StatefulSet
statefulset.apps/h-kim created

[SUCCESS] ==========================================
[SUCCESS] Deployment Complete!
[SUCCESS] ==========================================
```

### 2. Watch Pods Come Up

```bash
oc get pods -n b-efficient-memory-offloading-765cab -l app=h-kim-multi -w
```

### 3. Check Auto-Detection Logs

Once pods are running:

```bash
# Check h-kim-0
oc logs h-kim-0 -n b-efficient-memory-offloading-765cab | head -25
```

You should see:
```
=== NCCL InfiniBand Auto-Detection ===
✓ Auto-detected IB devices: mlx5_6,mlx5_7,mlx5_10,mlx5_11
✓ Found 4 working InfiniBand device(s)

=== NCCL Configuration ===
  NCCL_DEBUG=INFO
  NCCL_IB_DISABLE=0
  NCCL_IB_GID_INDEX=3
  NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
  NCCL_IB_TIMEOUT=22
  NCCL_NET_GDR_LEVEL=5
  NCCL_SOCKET_IFNAME=eth0
==========================

==========================================
H-Kim Multi-Node Environment
==========================================
Pod: h-kim-0
Node Rank: 0
World Size: 8
Master: h-kim-0.h-kim-headless.b-efficient-memory-offloading-765cab.svc.cluster.local:29500

Environment ready. Waiting for training job...
```

### 4. Verify NCCL Settings

```bash
# Check in running pod
oc exec h-kim-0 -n b-efficient-memory-offloading-765cab -- env | grep NCCL_IB_HCA

# Output:
# NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
```

### 5. Run Training

```bash
# Copy your training script
oc cp h-kim-openshift.sh h-kim-0:/workspace/ -n b-efficient-memory-offloading-765cab

# Run training
oc exec h-kim-0 -n b-efficient-memory-offloading-765cab -- \
  bash /workspace/h-kim-openshift.sh
```

---

## Different Node Example

If `h-kim-1` is scheduled on a node with different IB device names:

```bash
# Check h-kim-1 logs
oc logs h-kim-1 -n b-efficient-memory-offloading-765cab | head -10

# Might show different devices:
# === NCCL InfiniBand Auto-Detection ===
# ✓ Auto-detected IB devices: mlx5_0,mlx5_1,mlx5_2,mlx5_3
# ✓ Found 4 working InfiniBand device(s)
```

**This is exactly what we want!** Each pod uses its own working IB devices.

---

## Single-Node Example

```bash
./scripts/deploy-h-kim.sh \
  --namespace my-dev-ns \
  --mode rdma \
  --type single

# Wait for pod
oc get pod h-kim-dev -n my-dev-ns -w

# Check logs
oc logs h-kim-dev -n my-dev-ns | head -20

# Access pod
oc exec -it h-kim-dev -n my-dev-ns -- bash
```

---

## TCP Mode (No IB Auto-Detection)

If you use `--mode tcp`, IB is disabled and auto-detection is skipped:

```bash
./scripts/deploy-h-kim.sh \
  --namespace my-ns \
  --mode tcp \
  --type single

# ConfigMap is still deployed, but wrapper sees:
# NCCL_IB_DISABLE=1
# So it skips IB detection and NCCL uses TCP
```

---

## Advanced: Custom Nodes

Deploy to specific nodes:

```bash
./scripts/deploy-h-kim.sh \
  --namespace my-ns \
  --mode rdma \
  --type multi \
  --nodes "node1,node2,node3"
```

Each node will auto-detect its own IB devices!

---

## Comparison: Before vs After

### Before (Hardcoded)

```bash
# If you deployed to nodes with different IB device names:
# ❌ Pods would fail or use wrong devices
# ❌ NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11 (hardcoded)
# ❌ Might include non-working devices
```

### After (Auto-Detected)

```bash
# Pods auto-detect their own devices:
# ✅ Works on any node with any device names
# ✅ Each pod detects: mlx5_X,mlx5_Y,... (whatever is working)
# ✅ Only uses devices with working IB verb interfaces
```

---

## Troubleshooting

### No devices detected

```bash
# Check if ibv_devinfo exists
oc exec h-kim-0 -- which ibv_devinfo

# Check what devices exist
oc exec h-kim-0 -- ls /sys/class/infiniband/

# Run ibv_devinfo manually
oc exec h-kim-0 -- ibv_devinfo -l
```

### Want to see ConfigMap

```bash
# View the auto-detection script
oc get configmap nccl-ib-autodetect -n <namespace> -o yaml
```

### Delete and Redeploy

```bash
# Delete everything
oc delete statefulset h-kim -n <namespace>
oc delete service h-kim-headless -n <namespace>
oc delete configmap nccl-ib-autodetect -n <namespace>
oc delete pvc workspace-h-kim-0 workspace-h-kim-1 -n <namespace>

# Redeploy
./scripts/deploy-h-kim.sh --namespace <namespace> --mode rdma --type multi
```

---

## Summary

**Before:** You run `./scripts/deploy-h-kim.sh --mode rdma`
**After:** You run `./scripts/deploy-h-kim.sh --mode rdma`

**Nothing changes in how you use it!** But now:
- ✅ Auto-detects IB devices on each pod
- ✅ Works across different nodes
- ✅ Only uses working devices
- ✅ Shows detection results in logs
- ✅ More reliable and portable
