# ConnectX-7 PHY_RATE_MASK Firmware Bug

## Overview

ConnectX-7 firmware version **28.37.1014** has a bug where `PHY_RATE_MASK_P1` is enforced even when `PHY_RATE_MASK_OVERRIDE_P1=False(0)`. This causes rate limiting from 400 Gbps down to ~100 Gbps when the mask has an incorrect value.

**Date Discovered:** April 6, 2026  
**Affected Firmware:** 28.37.1014 (likely other 28.37.x versions)  
**Card Model:** ConnectX-7 400G (4-port)

---

## The Bug

### Expected Behavior

When `PHY_RATE_MASK_OVERRIDE_P1=False(0)`:
- NIC should **ignore** `PHY_RATE_MASK_P1` value
- NIC should use auto-negotiation to determine link speed
- Full 400 Gbps per port should be available

### Actual Behavior

When `PHY_RATE_MASK_OVERRIDE_P1=False(0)`:
- NIC **still enforces** `PHY_RATE_MASK_P1` value
- If mask has wrong value, link speed is artificially limited
- Performance degrades to ~100 Gbps (25% of expected)

### Real-World Impact

**Node moc-r4pcc02u25-nairr:**
- NCCL benchmark: ~54 GB/s (should be ~194 GB/s)
- Root cause: `PHY_RATE_MASK_P1 = 41096` (0xA0A8) - wrong bit pattern
- After fix: ~194 GB/s ✓

---

## Detection

### Symptoms

1. **NCCL benchmarks show ~50-60 GB/s** instead of ~194 GB/s (2-node, 8-GPU test)
2. **Link shows 400 Gbps** but actual throughput limited to ~100 Gbps per NIC
3. **All other firmware parameters match working nodes**
4. **No OS-level rate limiting** (TC qdisc, VF config all clean)

### Diagnosis Procedure

To check if a node has this issue:

```bash
# 1. Create MFT pod on suspect node
sed 's/mfttool-node/mfttool-u25r2/g; s/REPLACE_WITH_NODE_NAME/moc-r4pcc02u25-nairr/g' \
  k8s/machineconfigs/mft-tools-template.yaml | kubectl apply -f -

# 2. Enable PHY_RATE_MASK_OVERRIDE temporarily to read the mask value
kubectl exec -n nccl-test mfttool-u25r2 -- mlxconfig -y -d 03:00.0 set PHY_RATE_MASK_OVERRIDE_P1=1

# 3. Read PHY_RATE_MASK_P1 value
kubectl exec -n nccl-test mfttool-u25r2 -- mlxconfig -d 03:00.0 q | grep PHY_RATE_MASK_P1

# 4. Disable override again
kubectl exec -n nccl-test mfttool-u25r2 -- mlxconfig -y -d 03:00.0 set PHY_RATE_MASK_OVERRIDE_P1=0
```

**Good value:** `PHY_RATE_MASK_P1 = 4000` (decimal) = `0xFA0` (hex)  
**Bad value:** `PHY_RATE_MASK_P1 = 41096` (or any other value)

---

## Workaround

### Fix Procedure

Apply the correct PHY_RATE_MASK_P1 value to all 4 NICs on the affected node:

```bash
# Create MFT pod on affected node
NODE="moc-r4pcc02u25-nairr"
POD_NAME="mfttool-u25r2"

sed "s/mfttool-node/${POD_NAME}/g; s/REPLACE_WITH_NODE_NAME/${NODE}/g" \
  k8s/machineconfigs/mft-tools-template.yaml | kubectl apply -f -

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/${POD_NAME} -n nccl-test --timeout=300s

# Apply fix to all 4 devices
for DEV in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
  echo "Setting PHY_RATE_MASK_P1=4000 on $DEV"
  
  # Enable override
  kubectl exec -n nccl-test ${POD_NAME} -- \
    mlxconfig -y -d $DEV set PHY_RATE_MASK_OVERRIDE_P1=1
  
  # Set correct mask value
  kubectl exec -n nccl-test ${POD_NAME} -- \
    mlxconfig -y -d $DEV set PHY_RATE_MASK_P1=4000
  
  # Disable override (NIC will still use the mask value due to bug)
  kubectl exec -n nccl-test ${POD_NAME} -- \
    mlxconfig -y -d $DEV set PHY_RATE_MASK_OVERRIDE_P1=0
done

# Reboot node for changes to take effect
oc debug node/${NODE} -- chroot /host reboot

# Wait for node to come back (~5-10 minutes)
kubectl get nodes -w

# Verify fix with NCCL benchmark (should see ~194 GB/s)
```

### Verification

After reboot, verify the fix:

```bash
# 1. Check firmware applied correctly
kubectl exec -n nccl-test ${POD_NAME} -- mlxconfig -y -d 03:00.0 set PHY_RATE_MASK_OVERRIDE_P1=1
kubectl exec -n nccl-test ${POD_NAME} -- mlxconfig -d 03:00.0 q | grep PHY_RATE_MASK_P1
# Should show: PHY_RATE_MASK_P1 = 4000

kubectl exec -n nccl-test ${POD_NAME} -- mlxconfig -y -d 03:00.0 set PHY_RATE_MASK_OVERRIDE_P1=0

# 2. Run 2-node NCCL benchmark with known-good node
# Expected result: ~194 GB/s for 8000 MB messages
```

---

## Technical Details

### PHY_RATE_MASK_P1 Bit Pattern

The correct value `4000` (0xFA0) sets these bits:

```
Bit positions: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
Binary:         0  0  0  0  1  1  1  1  1  0  1  0  0  0  0  0

Set bits: 11, 10, 9, 8, 7, 5
Values: 2048 + 1024 + 512 + 256 + 128 + 32 = 4000
```

This bit pattern enables the correct combination of speeds/lanes for 400G operation.

### Why Override Doesn't Work

In firmware 28.37.1014, the PHY_RATE_MASK_OVERRIDE_P1 parameter does not function as documented:

- **Documented:** When False(0), mask should be ignored
- **Actual:** Mask is enforced regardless of override setting
- **Workaround:** Set both the mask AND the override correctly

### Nodes Affected in Our Cluster

As of April 6, 2026:
- **moc-r4pcc02u25-nairr** - Fixed with workaround
- Other nodes had correct PHY_RATE_MASK_P1 value from factory

---

## Firmware Upgrade Path

### Current Firmware

All H Kim nodes run: **28.37.1014**

### Newer Versions

This bug is **not publicly documented** by NVIDIA, but related auto-negotiation bugs were fixed in later versions:

- **28.40.1000** - Fixed auto-negotiation 400G_8x linkup issue
- **28.43.2026 LTS** - Long-term support version
- **28.47.1026** - Latest GA release (Feb 2026)
- **28.47.1088 LTS** - Latest LTS

### Upgrade Considerations

**Benefits:**
- May fix PHY_RATE_MASK bug (untested)
- Other bug fixes and improvements
- Newer features

**Risks:**
- Node downtime (reboot required)
- Firmware settings may reset to defaults
- Risk of NIC bricking if update interrupted
- ~20-35 minutes per node, ~5-9 hours for all 15 nodes

**Decision:** As of April 2026, keeping firmware at 28.37.1014 with workaround applied.

---

## Prevention

### For New Nodes

When adding new ConnectX-7 nodes with firmware 28.37.1014:

1. **Check PHY_RATE_MASK_P1 before production use**
2. **Apply workaround if value ≠ 4000**
3. **Verify with NCCL benchmark before declaring node ready**

### Monitoring

Add to node commissioning checklist:
- [ ] Verify PHY_RATE_MASK_P1 = 4000 on all 4 NICs
- [ ] Run 2-node NCCL benchmark with reference node
- [ ] Confirm ~194 GB/s for 8000 MB messages

---

## Related Issues

### Other Firmware Bugs Found

1. **MAX_ACC_OUT_READ=0** (moc-r4pcc04u37-nairr)
   - See: `FIRMWARE-COMPARISON-U09-U37-U25.md`
   - Fix: Set MAX_ACC_OUT_READ=128

2. **RDMA_SELECTIVE_REPEAT_EN=False** (yunshi nodes)
   - See: `connectx7-firmware-reference.md`
   - Fix: Set RDMA_SELECTIVE_REPEAT_EN=1

### Related Documentation

- `mlxconfig-pod-setup.md` - How to deploy MFT tools and query firmware
- `connectx7-firmware-reference.md` - Complete firmware parameter reference
- `nccl-configuration-h100-cluster.md` - NCCL benchmark procedures

---

## References

- NVIDIA ConnectX-7 Firmware Release Notes v28.40.1000
- NVIDIA ConnectX-7 Adapter Cards Firmware v28.43.2026 LTS
- Investigation docs: `RATE-LIMITING-INVESTIGATION-FINDINGS.md`, `FIRMWARE-COMPARISON-U09-U37-U25.md`

---

**Last Updated:** April 6, 2026  
**Status:** Workaround applied and verified
