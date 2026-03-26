# SR-IOV Network Attachment Definitions

This directory contains the canonical definitions for SR-IOV network attachments used for NCCL benchmarks.

## Problem This Solves

NetworkAttachmentDefinitions are **namespace-scoped** resources. When creating new namespaces for GPU workloads, these definitions must be manually recreated. Previously, copy-paste errors led to all 4 NICs using the same IP subnet (10.0.103.0/24), causing:

- ✅ 2-node benchmarks to work (8 IPs fit in /24 subnet)
- ❌ 8-node benchmarks to hang (32 IPs caused conflicts)

## Correct Configuration

Each SR-IOV NIC must have its own isolated subnet:

| Network | IPAM Range | Route | Resource Name |
|---------|------------|-------|---------------|
| eno5np0-network | 10.0.103.0/24 | 192.168.77.0/24 | openshift.io/eno5np0rdma |
| eno6np0-network | 10.0.104.0/24 | 192.168.78.0/24 | openshift.io/eno6np0rdma |
| eno7np0-network | 10.0.105.0/24 | 192.168.79.0/24 | openshift.io/eno7np0rdma |
| eno8np0-network | 10.0.106.0/24 | 192.168.80.0/24 | openshift.io/eno8np0rdma |

**Why separate subnets?** NCCL's `NCCL_CROSS_NIC=0` setting requires isolated subnets for optimal multi-NIC performance with H100 GPUs.

## Usage

### Deploy to a New Namespace

```bash
# Deploy network attachments to a specific namespace
kubectl apply -k base/ -n <your-namespace>

# Example:
kubectl apply -k base/ -n b-efficient-memory-offloading-765cab
```

### Validate Existing Configuration

```bash
# Validate network attachments in a namespace
./validate-network-attachments.sh <namespace>

# Example:
./validate-network-attachments.sh b-efficient-memory-offloading-765cab
```

### Expected Output (Valid Configuration)

```
✅ CORRECT: eno5np0-network → 10.0.103.0/24
✅ CORRECT: eno6np0-network → 10.0.104.0/24
✅ CORRECT: eno7np0-network → 10.0.105.0/24
✅ CORRECT: eno8np0-network → 10.0.106.0/24

✅ All network attachments are correctly configured!
```

### Example Output (Invalid Configuration)

```
✅ CORRECT: eno5np0-network → 10.0.103.0/24
❌ MISMATCH: eno6np0-network has range 10.0.103.0/24 (expected: 10.0.104.0/24)
❌ MISMATCH: eno7np0-network has range 10.0.103.0/24 (expected: 10.0.105.0/24)
❌ MISMATCH: eno8np0-network has range 10.0.103.0/24 (expected: 10.0.106.0/24)

❌ Found 3 error(s) in network attachment configuration
```

## Fixing Incorrect Configuration

If validation fails, you can fix it in two ways:

### Option 1: Apply from Template (Recommended)

```bash
kubectl apply -k base/ -n <namespace>
```

### Option 2: Manual Patch

```bash
# Fix eno6np0-network
kubectl patch network-attachment-definition eno6np0-network -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/config", "value": "{\"cniVersion\":\"1.0.0\",\"name\":\"eno6np0-network\",\"type\":\"sriov\",\"mtu\":9000,\"vlan\":0,\"spoofchk\":\"off\",\"trust\":\"on\",\"vlanQoS\":0,\"link_state\":\"enable\",\"logLevel\":\"info\",\"ipam\":{\"type\":\"whereabouts\",\"range\":\"10.0.104.0/24\",\"routes\":[{\"dst\":\"192.168.78.0/24\"}]}}"}]'

# Fix eno7np0-network
kubectl patch network-attachment-definition eno7np0-network -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/config", "value": "{\"cniVersion\":\"1.0.0\",\"name\":\"eno7np0-network\",\"type\":\"sriov\",\"mtu\":9000,\"vlan\":0,\"spoofchk\":\"off\",\"trust\":\"on\",\"vlanQoS\":0,\"link_state\":\"enable\",\"logLevel\":\"info\",\"ipam\":{\"type\":\"whereabouts\",\"range\":\"10.0.105.0/24\",\"routes\":[{\"dst\":\"192.168.79.0/24\"}]}}"}]'

# Fix eno8np0-network
kubectl patch network-attachment-definition eno8np0-network -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/config", "value": "{\"cniVersion\":\"1.0.0\",\"name\":\"eno8np0-network\",\"type\":\"sriov\",\"mtu\":9000,\"vlan\":0,\"spoofchk\":\"off\",\"trust\":\"on\",\"vlanQoS\":0,\"link_state\":\"enable\",\"logLevel\":\"info\",\"ipam\":{\"type\":\"whereabouts\",\"range\":\"10.0.106.0/24\",\"routes\":[{\"dst\":\"192.168.80.0/24\"}]}}"}]'
```

**Important:** After fixing network attachments, you must recreate any running pods to get new IP addresses from the correct subnets.

## Best Practices

1. **Always use this template** when creating network attachments in new namespaces
2. **Run validation script** after deploying to a new namespace
3. **Never manually edit** the IPAM ranges - use the template or patches
4. **Document** any namespace-specific customizations

## Troubleshooting

### Symptom: 8-node NCCL benchmark hangs at "Connected all rings"

**Root Cause:** All 4 NICs using the same subnet causes IP conflicts and routing issues.

**Solution:**
1. Run validation script: `./validate-network-attachments.sh <namespace>`
2. Fix incorrect ranges using template or manual patches
3. Delete and recreate benchmark pods to get new IPs

### Symptom: 2-node benchmark works but 8-node fails

**Root Cause:** Same as above. 2 nodes only need 8 IPs, which fit in a single /24 subnet without visible conflicts. 8 nodes need 32 IPs, exposing the subnet overlap issue.

## History

- **2026-03-26**: Created centralized template after discovering h-kim namespace had incorrect IPAM ranges
- **Root Cause**: Copy-paste error when manually creating network attachments
- **Impact**: 8-node NCCL benchmarks hung after topology discovery
- **Resolution**: Fixed IPAM ranges and created this template to prevent recurrence

## Related Documentation

- [GOLD-STANDARD-NCCL-BENCHMARK.yaml](../../deployments/h-kim/GOLD-STANDARD-NCCL-BENCHMARK.yaml) - NCCL benchmark configuration
- [MOC Barcelona Cluster Documentation](../../README.md) - Overall cluster setup
