# Claude Code Instructions for NAIRR ML Development Environment

This file contains instructions for Claude Code when working with this project.

---

## Project Overview

This repository manages the NAIRR H100 GPU cluster running on OpenShift, including:
- NCCL benchmarking and performance testing
- Network rate limiting and QoS configuration
- RDMA/GPUDirect testing
- Container image builds for ML workloads

**Primary Working Directory:** `/Users/jschless/nairr/deepti/ml-dev-env`

---

## Claude Guidance Documentation System

**CRITICAL:** This project has operational guides in `claude_guidance/` directory. When the user mentions specific keywords, **you MUST read the corresponding guide first** before taking action.

### Keyword → Guide Mapping

| User Says | Read This Guide First | What It Contains |
|-----------|----------------------|------------------|
| "rate limit", "mlnx_qos", "bandwidth limit" | `claude_guidance/manual-rate-limiting-mlnx-qos.md` | Hardware rate limiting with DaemonSet, mlnx_qos tool usage |
| "gold standard", "nccl benchmark", "run benchmark" | `claude_guidance/nccl-configuration-h100-cluster.md` | Proper NCCL benchmark execution, critical settings |
| "rdma test", "perftest", "ib_write_bw", "gpudirect" | `claude_guidance/rdma-perftest-gpudirect.md` | RDMA performance testing procedures |
| "firmware", "mlxconfig", "mft tools", "nic settings" | `claude_guidance/mlxconfig-pod-setup.md` | Mellanox firmware inspection using MFT tools |
| "check iommu", "iommu status", "verify iommu" | `claude_guidance/check-iommu-status.md` | Checking IOMMU status in OS (not just dmesg) |
| "gpu affinity", "nic affinity", "numa", "topology manager" | `claude_guidance/gpu-nic-affinity-mapping.md` | GPU-NIC NUMA affinity enforcement and optimization |

**Required Action:** Read the guide, follow documented procedures, use exact commands from guides. Do not improvise methods that are already documented.

---

## Cluster Node Types

### H100 GPU Nodes (8 total)

**Rack 4 (-nairr suffix):**
- moc-r4pcc04u09-nairr
- moc-r4pcc04u11-nairr
- moc-r4pcc04u12-nairr
- moc-r4pcc04u16-nairr
- moc-r4pcc04u25-nairr

**Rack 2 (other):**
- moc-r4pcc02u05
- moc-r4pcc02u32
- moc-r4pcc02u35

### AMD EPYC Nodes (-yunshi suffix)

**Rack 2 (yunshi users):**
- moc-r4pcc02u15-yunshi
- moc-r4pcc02u16-yunshi

**Hardware:** AMD EPYC 9754 128-Core Processor, ConnectX-7 400G NICs

---

## Node Configuration Status

### PCI Configuration Scripts

Two scripts apply PCI optimizations: `pci_mrr.sh` (MaxReadReq) and `pci_ats.sh` (ATS enable).

**Status as of 2026-04-01:**
- ✅ **Applied on -nairr nodes:** MaxReadReq=4096, ATS=0x8000
- ❌ **NOT applied on yunshi nodes:** MaxReadReq=512, ATS=0x0000

### IOMMU Configuration

**All nodes** (both -nairr and yunshi):
- IOMMU is **disabled at BIOS level**
- No IVRS ACPI table present
- Empty `/sys/kernel/iommu_groups/`
- Using SWIOTLB (software bounce buffer)

**To verify IOMMU status:** Use `claude_guidance/check-iommu-status.md` procedures, not just dmesg.

### Firmware Differences (ConnectX-7)

| Parameter | yunshi | -nairr | Impact |
|-----------|--------|--------|--------|
| RDMA_SELECTIVE_REPEAT_EN | False(0) | True(1) | RDMA reliability |
| PCI_WR_ORDERING | force_relax(1) | per_mkey(0) | PCI write ordering |
| All other parameters | Identical | Identical | - |

---

## Network Configuration

### ConnectX-7 NICs (4 per H100 node)

**PCI Device Mapping:**
- eno5np0 = 03:00.0
- eno6np0 = 23:00.0
- eno7np0 = a3:00.0
- eno8np0 = c3:00.0

**Network Subnets (Isolated /24 subnets):**
- net1 (eno5np0): 10.0.103.0/24
- net2 (eno6np0): 10.0.104.0/24
- net3 (eno7np0): 10.0.105.0/24
- net4 (eno8np0): 10.0.106.0/24

**CRITICAL:** Subnets are isolated with NO inter-subnet routing. This is why `NCCL_CROSS_NIC=0` is required.

### Driver Stack

- **Inbox kernel driver:** mlx5_core (RHEL 9.6 kernel 5.14.0-570.76.1.el9_6.x86_64)
- **DOCA overlay:** doca3.3.0-26.01-1.0.0.0-0 (managed by NVIDIA Network Operator)
- **Firmware versions:**
  - ConnectX-6 Lx: 26.38.1002
  - ConnectX-7: 28.37.1014

---

## Container Images

### Validated Images

**Cluster-built image (validated 2026-04-01):**
```
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env@sha256:8f99384b8277ff732153c58874679fa4d6592104bfa0fe21ca2d5750ee213bed
```
- Base: NVIDIA PyTorch 25.06
- Performance: 49.0 GB/s with 100 Gbps rate limit (identical to reference image)

**Reference image:**
```
quay.io/jschless/ml-dev-env:latest
```

Both images achieve identical benchmark performance.

---

## NCCL Configuration

### Critical Environment Variables (Gold Standard)

**MUST HAVE:**
```bash
NCCL_DMABUF_ENABLE=1           # Required - no nvidia_peermem kernel module
NCCL_CROSS_NIC=0               # Required - isolated subnet configuration
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_8,mlx5_9  # Explicit IB device specification
```

**Performance Settings:**
```bash
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=16
NCCL_NET_GDR_LEVEL=5
NCCL_NET_GDR_READ=1
NCCL_PROTO=Simple
NCCL_ALGO=Ring
```

**Full configuration:** See `deployments/h-kim/GOLD-STANDARD-NCCL-BENCHMARK.yaml`

---

## Performance Benchmarks

### 8-Node Gold Standard Results

**Without rate limiting:**
- 8GB messages: ~194 GB/s
- Baseline performance for comparison

**With 100 Gbps rate limiting:**
- 8GB messages: 49.0 GB/s
- 99% efficiency of theoretical 50 GB/s maximum

**Benchmark command:**
```bash
# Run on pod-0, then on pods 1-7 separately with different --node_rank
torchrun --nnodes=8 --nproc_per_node=4 --node_rank=0 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 /benchmark/allreduce-loop.py -r 3
```

**See:** `claude_guidance/nccl-configuration-h100-cluster.md` for proper execution procedure.

---

## Directory Structure

```
├── claude_guidance/              # Operational guides (READ THESE FIRST)
│   ├── README.md
│   ├── check-iommu-status.md
│   ├── manual-rate-limiting-mlnx-qos.md
│   ├── mlxconfig-pod-setup.md
│   ├── nccl-configuration-h100-cluster.md
│   └── rdma-perftest-gpudirect.md
├── deployments/
│   ├── admin/                    # Admin tools and container images
│   └── h-kim/                    # Deployment manifests and investigation docs
├── k8s/                          # Kubernetes resources
│   ├── gold-standard-kustomize/  # Kustomize-based benchmark deployments
│   ├── rdma-perftest/            # RDMA perftest pod templates and docs
│   └── machineconfigs/           # OpenShift MachineConfig resources
├── scripts/                      # Automation scripts
│   └── run-rdma-perftest.sh      # Automated RDMA testing script
├── pci_ats.sh                    # PCI ATS enable script
└── pci_mrr.sh                    # PCI MaxReadReq optimization script
```

---

## Common Operations

### Deploying Gold Standard Benchmark

**Method 1: Manual YAML (Recommended for testing):**
```bash
kubectl apply -f /tmp/gold-standard-nvidia-25-06.yaml -n nccl-test
# Wait for all 8 pods to be Running
# Exec into each pod and run torchrun with appropriate --node_rank
```

**Method 2: Kustomize (Production):**
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/8node/
```

**See:** `claude_guidance/nccl-configuration-h100-cluster.md` for complete instructions.

### Applying Rate Limits

```bash
kubectl apply -f deployments/h-kim/apply-100g-with-ofed-image.yaml
```

**See:** `claude_guidance/manual-rate-limiting-mlnx-qos.md` for details.

### Checking Firmware Parameters

```bash
# Deploy MFT pod
sed 's/mfttool-node/mfttool-u09/g; s/REPLACE_WITH_NODE_NAME/moc-r4pcc04u09-nairr/g' \
  k8s/machineconfigs/mft-tools-template.yaml | kubectl apply -f -

# Query firmware
kubectl exec -n nccl-test mfttool-u09 -- mlxconfig -d 03:00.0 q
```

**See:** `claude_guidance/mlxconfig-pod-setup.md` for complete procedure.

### Running RDMA Perftest

Automated script for flexible RDMA testing between two nodes:

```bash
# Basic RDMA test (host memory)
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc04u09-nairr \
  --client-node moc-r4pcc04u11-nairr

# GPUDirect test with specific GPU and NIC
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc04u09-nairr \
  --client-node moc-r4pcc04u11-nairr \
  --gpudirect --gpu-id 0 --nic-id 0

# Multiple parallel streams
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc04u09-nairr \
  --client-node moc-r4pcc04u11-nairr \
  --gpudirect --gpu-id 1 --nic-id 1 --num-qps 4
```

**See:** `k8s/rdma-perftest/README.md` for all options and troubleshooting.

---

## Best Practices

### Before Making Changes

1. **Check `claude_guidance/` first** - Don't reinvent documented procedures
2. **Read existing deployment files** - Understand current configuration
3. **Test on subset of nodes** - Don't apply to all 8 nodes immediately
4. **Document changes** - Update relevant guides in `claude_guidance/`

### When Running Benchmarks

1. **Use gold standard configuration** - Don't modify NCCL settings without reason
2. **Run multiple iterations** - Use `-r 3` or higher for consistent results
3. **Check all pods are Running** - Benchmark will hang if any pod is not ready
4. **Save results** - Copy output to `/tmp/` or document location for comparison

### When Investigating Issues

1. **Check recent changes** - Review git log and deployment history
2. **Compare against working baseline** - Use gold standard results as reference
3. **Check one variable at a time** - Don't change multiple settings simultaneously
4. **Document findings** - Create investigation docs in `deployments/h-kim/`

---

## OpenShift Commands

### Node Debugging

```bash
# Access node filesystem
oc debug node/<node-name> -- chroot /host bash

# Check PCI settings
oc debug node/<node-name> -- chroot /host lspci -vvv -s 03:00.0 | grep MaxReadReq

# Check IOMMU status
oc debug node/<node-name> -- chroot /host ls -la /sys/kernel/iommu_groups/
```

### Pod Management

```bash
# Watch pod status
kubectl get pods -n nccl-test -w

# Check pod logs
kubectl logs -n nccl-test nccl-benchmark-0

# Exec into pod
kubectl exec -it -n nccl-test nccl-benchmark-0 -- bash
```

---

## Troubleshooting

### NCCL Benchmark Hangs

**Symptoms:** Benchmark starts but doesn't complete, pods show "waiting for rank X"

**Common causes:**
1. Not all pods are Running
2. Wrong `--nnodes` count
3. Missing `--node_rank` on some pods
4. Network connectivity issues

**See:** `claude_guidance/nccl-configuration-h100-cluster.md#troubleshooting`

### Low NCCL Performance

**Symptoms:** Benchmark completes but shows <100 GB/s (without rate limiting)

**Common causes:**
1. `NCCL_DMABUF_ENABLE` not set to 1
2. `NCCL_IB_HCA` not set correctly
3. `NCCL_CROSS_NIC=1` (should be 0)
4. Rate limiting still applied from previous test

**See:** `claude_guidance/nccl-configuration-h100-cluster.md#root-cause-analysis`

### Rate Limits Not Applied

**Symptoms:** `mlnx_qos` shows success but performance unchanged

**Common causes:**
1. DaemonSet pod not privileged
2. Missing `hostNetwork: true`
3. DCBX mode conflict
4. Switch configuration issue

**See:** `claude_guidance/manual-rate-limiting-mlnx-qos.md#troubleshooting`

---

## Git Workflow

**DO NOT commit:**
- Temporary test files in `/tmp/`
- Pod logs
- Personal experiments in `deployments/<user>/`

**DO commit:**
- New guides in `claude_guidance/`
- Validated configurations in `k8s/`
- Investigation summaries in `deployments/h-kim/` (after cleanup)
- Script improvements

**Commit message format:**
```
<area>: <brief description>

<detailed explanation if needed>
```

Examples:
- `nccl: Add 4-node benchmark for rack-04 nodes`
- `docs: Add IOMMU verification guide`
- `network: Apply 100 Gbps rate limit to all H100 nodes`

---

## Questions or Issues?

1. Check `claude_guidance/README.md` for guide overview
2. Review relevant guide for the operation you're attempting
3. Check `deployments/h-kim/` for similar past work
4. Search git history for related changes

---

**Last Updated:** April 1, 2026
