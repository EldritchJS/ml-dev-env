# Manual Network Rate Limiting with mlnx_qos

**Date Created:** March 25, 2026
**Last Updated:** March 25, 2026
**Cluster:** 8x H100-80GB nodes with ConnectX-7 400G NICs
**Purpose:** Apply hardware-enforced rate limits for network performance experiments

---

## Quick Reference

Apply 100 Gbps rate limit to all NICs on all H100 nodes:

```bash
kubectl apply -f deployments/h-kim/apply-100g-with-ofed-image.yaml
```

Verify rate limits are applied:

```bash
kubectl logs -n default -l app=apply-100g-rate-limit | grep "ratelimit: 100"
```

Remove rate limits:

```bash
kubectl delete daemonset apply-100g-rate-limit -n default
```

**Note:** Rate limits persist in hardware until NIC reset or reboot.

---

## Background

### Use Case

Network rate limiting is needed for:
- **Performance experiments:** Testing application behavior under bandwidth constraints
- **Multi-tenancy:** Ensuring fair resource allocation between workloads
- **Benchmarking:** Comparing performance at different network speeds
- **Cost analysis:** Understanding bandwidth vs. cost tradeoffs

### Hardware Capabilities

ConnectX-7 NICs support hardware-enforced rate limiting via:
- **DCB (Data Center Bridging):** IEEE 802.1Qaz standard
- **Traffic Classes (TCs):** 8 independent priority queues per interface
- **Per-TC rate limiting:** Enforced in NIC firmware, no CPU overhead
- **RDMA compatibility:** Works with GPUDirect RDMA traffic

### Why Hardware Rate Limiting?

- **Zero CPU overhead:** Enforcement happens in NIC firmware
- **Works with RDMA:** Software iptables/tc rules don't affect RDMA
- **Precise control:** Hardware enforcement is exact and consistent
- **Low latency:** No additional latency vs. software rate limiting

---

## Solution: DaemonSet with NVIDIA OFED Image

### Why This Approach?

We use a **standalone pod with mlnx_qos tool** instead of MachineConfig because:

1. **No host installation required:** mlnx_qos tool is in the container
2. **Easily reversible:** Delete DaemonSet to stop applying rate limits
3. **No node reboots:** Applied immediately without MachineConfig rollout
4. **Consistent across nodes:** Same container image on all nodes

### Key Components

1. **NVIDIA OFED Image:** `nvcr.io/nvidia/mellanox/mofed:5.9-0.5.6.0-ubuntu20.04-amd64`
   - Contains `mlnx_qos` tool pre-installed
   - Has necessary libraries and dependencies
   - Runs on standard container runtime

2. **mlnx_qos Tool:** Mellanox QoS configuration utility
   - Configures DCB Traffic Classes
   - Sets per-TC rate limits via netlink
   - Reads/writes NIC firmware configuration

3. **DaemonSet Pattern:** Runs one pod per H100 node
   - Uses `hostNetwork: true` for direct NIC access
   - Requires `privileged: true` security context
   - Mounts `/sys` and `/dev` for hardware access

---

## Step-by-Step Guide

### Step 1: Review the DaemonSet Manifest

File: `deployments/h-kim/apply-100g-with-ofed-image.yaml`

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: apply-100g-rate-limit
  namespace: default
spec:
  selector:
    matchLabels:
      app: apply-100g-rate-limit
  template:
    metadata:
      labels:
        app: apply-100g-rate-limit
    spec:
      hostNetwork: true
      hostPID: true
      nodeSelector:
        node-role.kubernetes.io/h100: ""
      tolerations:
      - operator: Exists
      containers:
      - name: mlnx-qos
        image: nvcr.io/nvidia/mellanox/mofed:5.9-0.5.6.0-ubuntu20.04-amd64
        command: ["/bin/bash", "-c"]
        args:
        - |
          set -ex

          RATE="100,100,100,100,100,100,100,100"

          for iface in eno5np0 eno6np0 eno7np0 eno8np0; do
            echo "Setting $iface to 100 Gbps per TC..."

            if mlnx_qos -i $iface --ratelimit=$RATE 2>&1; then
              echo "✓ $iface: Rate limit applied successfully"
              mlnx_qos -i $iface 2>&1 | grep -E "tc:|ratelimit" | head -8
            else
              echo "✗ $iface: Failed to apply rate limit"
            fi
          done

          sleep infinity

        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName

        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
            - SYS_ADMIN

        volumeMounts:
        - name: sys
          mountPath: /sys
        - name: dev
          mountPath: /dev

      volumes:
      - name: sys
        hostPath:
          path: /sys
          type: Directory
      - name: dev
        hostPath:
          path: /dev
          type: Directory
```

### Step 2: Apply the DaemonSet

```bash
kubectl apply -f deployments/h-kim/apply-100g-with-ofed-image.yaml
```

Expected output:
```
daemonset.apps/apply-100g-rate-limit created
```

### Step 3: Wait for Pods to Start

```bash
kubectl get pods -n default -l app=apply-100g-rate-limit -o wide
```

Wait until all 8 pods show `Running` status (one per H100 node).

### Step 4: Verify Rate Limits Applied

Check logs from one pod:

```bash
POD=$(kubectl get pods -n default -l app=apply-100g-rate-limit -o name | head -1)
kubectl logs -n default $POD
```

Expected output for each interface:
```
Setting eno5np0 to 100 Gbps per TC...
tc: 0 ratelimit: 100.0 Gbps, tsa: vendor
tc: 1 ratelimit: 100.0 Gbps, tsa: vendor
tc: 2 ratelimit: 100.0 Gbps, tsa: vendor
tc: 3 ratelimit: 100.0 Gbps, tsa: vendor
tc: 4 ratelimit: 100.0 Gbps, tsa: vendor
tc: 5 ratelimit: 100.0 Gbps, tsa: vendor
tc: 6 ratelimit: 100.0 Gbps, tsa: vendor
tc: 7 ratelimit: 100.0 Gbps, tsa: vendor
✓ eno5np0: Rate limit applied successfully
```

Check all pods:

```bash
kubectl logs -n default -l app=apply-100g-rate-limit | grep "✓"
```

Should show 32 success messages (4 NICs × 8 nodes).

### Step 5: Run Benchmark to Verify

Run NCCL benchmark to confirm rate limiting is active:

```bash
kubectl apply -f k8s/machineconfigs/gold-standard-8node.yaml
kubectl exec -n nccl-test nccl-benchmark-0 -- bash -c \
  "torchrun --nnodes=8 --nproc_per_node=4 --node_rank=0 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py"
```

**Expected results:**
- **Without rate limit:** ~194 GB/s (baseline)
- **With 100 Gbps rate limit:** ~39 GB/s (confirming rate limit active)

---

## Understanding mlnx_qos Rate Limiting

### Traffic Classes (TCs)

Each NIC has 8 Traffic Classes (TCs) numbered 0-7:
- Independent priority queues
- Each TC can have its own rate limit
- Network traffic is mapped to TCs via priority (PCP/DSCP)

### Rate Limit Format

```bash
mlnx_qos -i <interface> --ratelimit=<tc0>,<tc1>,<tc2>,<tc3>,<tc4>,<tc5>,<tc6>,<tc7>
```

- Values in **Gbps** (not Mbps or Kbps)
- `0` means unlimited
- For uniform limiting, set all TCs to the same value

### Examples

**100 Gbps uniform rate limit:**
```bash
mlnx_qos -i eno5np0 --ratelimit=100,100,100,100,100,100,100,100
```

**Different rates per TC:**
```bash
mlnx_qos -i eno5np0 --ratelimit=200,100,100,50,50,25,25,10
```

**Remove all rate limits (unlimited):**
```bash
mlnx_qos -i eno5np0 --ratelimit=0,0,0,0,0,0,0,0
```

### View Current Configuration

```bash
mlnx_qos -i eno5np0
```

Shows:
- DCBX mode
- Priority trust state
- PFC configuration
- Buffer allocation
- **TC rate limits** ← What we care about

---

## Customizing Rate Limits

### Different Rate Limit Values

To apply a different rate (e.g., 50 Gbps):

1. Edit the manifest:
   ```yaml
   RATE="50,50,50,50,50,50,50,50"  # Change from 100 to 50
   ```

2. Reapply:
   ```bash
   kubectl delete daemonset apply-100g-rate-limit -n default
   kubectl apply -f deployments/h-kim/apply-100g-with-ofed-image.yaml
   ```

### Different NICs

To apply to different network interfaces:

1. Edit the manifest:
   ```bash
   for iface in eth0 eth1; do  # Change interface names
   ```

2. Reapply the DaemonSet

### Selective Node Application

To apply only to specific nodes:

1. Add node name restrictions to nodeSelector:
   ```yaml
   nodeSelector:
     node-role.kubernetes.io/h100: ""
     kubernetes.io/hostname: moc-r4pcc04u09-nairr  # Add this
   ```

2. Or use node labels for more flexible selection

---

## Removing Rate Limits

### Method 1: Delete the DaemonSet

```bash
kubectl delete daemonset apply-100g-rate-limit -n default
```

**IMPORTANT:** This only stops the pods. The rate limits **persist in hardware**.

### Method 2: Reset Rate Limits to Unlimited

Create a new DaemonSet that sets rate limits to 0:

```yaml
RATE="0,0,0,0,0,0,0,0"  # 0 = unlimited
```

Or manually on each node:

```bash
oc debug node/<node-name>
chroot /host
for iface in eno5np0 eno6np0 eno7np0 eno8np0; do
  mlnx_qos -i $iface --ratelimit=0,0,0,0,0,0,0,0
done
```

### Method 3: Reboot Nodes

NIC configuration resets to defaults on reboot:

```bash
oc debug node/<node-name>
chroot /host
systemctl reboot
```

---

## Troubleshooting

### Pods Not Starting

**Symptom:** Pods stuck in `ContainerCreating`

**Cause:** Image pull issues

**Solution:**
```bash
kubectl describe pod -n default <pod-name>
```

Check ImagePullBackOff or ErrImagePull errors.

### mlnx_qos Command Not Found

**Symptom:** `mlnx_qos: command not found`

**Cause:** Wrong container image

**Solution:** Ensure using NVIDIA OFED image:
```yaml
image: nvcr.io/nvidia/mellanox/mofed:5.9-0.5.6.0-ubuntu20.04-amd64
```

### Rate Limits Not Applied

**Symptom:** Logs show success but `mlnx_qos -i eno5np0` shows no rate limit

**Possible causes:**
1. **DCB not enabled on switch:** Check switch configuration
2. **DCBX mode conflict:** May need to set to "OS controlled"
3. **Firmware version:** Some older firmware doesn't support rate limiting

**Debug:**
```bash
kubectl exec -n default <pod-name> -- mlnx_qos -i eno5np0
```

Look for:
```
DCBX mode: OS controlled  ← Should be "OS controlled"
tc: 0 ratelimit: 100.0 Gbps, tsa: vendor  ← Should show your rate
```

### Permission Denied

**Symptom:** `Operation not permitted` errors

**Cause:** Insufficient privileges

**Solution:** Ensure DaemonSet has:
```yaml
securityContext:
  privileged: true
  capabilities:
    add:
    - NET_ADMIN
    - SYS_ADMIN
hostNetwork: true
```

---

## Verification Checklist

Before running experiments, verify:

- [ ] DaemonSet is running (8 pods for 8 nodes)
- [ ] All pods show `Running` status
- [ ] Pod logs show "✓" for all 4 NICs × 8 nodes = 32 success messages
- [ ] `mlnx_qos` output confirms rate limits are set
- [ ] NCCL benchmark shows reduced performance (confirms rate limiting active)
- [ ] Rate limit value matches your experiment requirements

---

## Performance Impact Reference

Based on testing with 8 H100 nodes (32 GPUs):

| Rate Limit | NCCL AllReduce Bandwidth | % of Baseline |
|------------|---------------------------|---------------|
| Unlimited  | 194 GB/s                  | 100%          |
| 100 Gbps   | 39 GB/s                   | 20%           |
| 50 Gbps    | ~20 GB/s (estimated)      | 10%           |
| 25 Gbps    | ~10 GB/s (estimated)      | 5%            |

**Note:** Actual performance depends on:
- Message size
- Number of nodes
- NCCL algorithm
- Network topology
- Application communication pattern

---

## Related Documentation

- `deployments/h-kim/RATE-LIMIT-APPLIED.md` - Deployment summary
- `deployments/h-kim/RATE-LIMIT-VERIFICATION.md` - Benchmark results
- `deployments/h-kim/apply-100g-with-ofed-image.yaml` - DaemonSet manifest
- `claude_guidance/nccl-configuration-h100-cluster.md` - NCCL settings

---

## Technical Notes

### Why 8 Traffic Classes?

IEEE 802.1Qaz DCB standard defines 8 priority levels (0-7). Each priority maps to a Traffic Class. NCCL typically uses TC 0 for data traffic, but setting all 8 ensures all traffic is rate-limited regardless of priority marking.

### Why Set All TCs to the Same Rate?

For uniform rate limiting, all TCs must have the same limit. If TCs have different rates, traffic could be reclassified to use higher-rate TCs, bypassing the limit.

### Hardware vs. Software Rate Limiting

**Hardware (mlnx_qos):**
- ✓ Works with RDMA
- ✓ Zero CPU overhead
- ✓ Exact enforcement
- ✗ Requires compatible NIC
- ✗ Needs privileged access

**Software (tc/iptables):**
- ✓ Works on any NIC
- ✓ Standard Linux tools
- ✗ Doesn't affect RDMA
- ✗ CPU overhead
- ✗ Less precise

For RDMA workloads (GPUDirect, NCCL), **hardware rate limiting is required**.

### Persistence Behavior

Rate limits are **persistent in NIC firmware** until:
1. Explicitly changed by mlnx_qos
2. NIC reset (via firmware update or power cycle)
3. System reboot (NICs reinitialize)

Deleting the DaemonSet does NOT remove the rate limits - they remain active in hardware.

---

## Future Improvements

Potential enhancements for this solution:

1. **Automated cleanup:** Add a "remove rate limit" job that runs on DaemonSet deletion
2. **ConfigMap-driven rates:** Make rate values configurable via ConfigMap
3. **Status checking:** Add init container to verify current rate limits before applying
4. **Gradual rollout:** Use DaemonSet update strategy to apply limits node-by-node
5. **Metrics collection:** Export rate limit status as Prometheus metrics
6. **Per-application limits:** Use network namespaces or VFs for per-pod rate limiting

---

## Questions or Issues?

If you encounter problems:

1. Check pod logs: `kubectl logs -n default <pod-name>`
2. Verify NIC firmware supports DCB: `mlnx_qos -i eno5np0 --help`
3. Check switch DCB configuration (may need assistance from network team)
4. Review this guide's troubleshooting section
5. Compare against working deployment in `deployments/h-kim/`

For questions about NCCL performance with rate limiting, see `RATE-LIMIT-VERIFICATION.md`.
