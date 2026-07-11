# Claude Code Instructions for MOC ML Development Environment

This file contains instructions for Claude Code when working with this project.

---

## Project Overview

This repository manages the MOC H100 GPU cluster running on OpenShift (Barcelona), including:
- NCCL benchmarking and performance testing
- Network rate limiting and QoS configuration
- RDMA/GPUDirect testing
- Container image builds for ML workloads

**Primary Working Directory:** `/Users/eldritchjs/github/ml-dev-env`

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

### GPU Nodes (5 total, all Rack 2)

**H100 nodes (-nairr suffix):**
- moc-r4pcc02u17-nairr
- moc-r4pcc02u18-nairr (h100 role label)
- moc-r4pcc02u25-nairr (h100 role label)

**H100 nodes (-yunshi suffix):**
- moc-r4pcc02u15-yunshi
- moc-r4pcc02u16-yunshi

All GPU nodes: 4x H100 80GB HBM3, ConnectX-7 400G NICs

### Other Nodes

**CPU workers:** moc-r4pac08u05-s1-cpu, moc-r4pac08u07-s1-cpu, moc-r4pac08u07-s3-cpu
**Control plane:** moc-r4pac22u33-s1b, moc-r4pac22u35-s3c, moc-r4pac24u37-s3b

**Note:** The cluster previously had 8 H100 nodes (5 in rack 4, 3 in rack 2). Those were removed/relocated. Historical docs in `deployments/archived/` reference the old nodes.

---

## Node Configuration Status

### PCI and Firmware Configuration

**Status: UNKNOWN — needs re-verification on current nodes.**

The previous cluster nodes (rack 4) had PCI optimizations applied (MaxReadReq=4096, ATS enabled) and firmware differences documented. The current nodes (rack 2, `u17/u18/u25-nairr` and `u15/u16-yunshi`) have not been verified for these settings.

To verify, use `claude_guidance/mlxconfig-pod-setup.md` and `claude_guidance/check-iommu-status.md`.

### IOMMU Configuration

Historically disabled at BIOS level on all nodes. Current status unverified on new nodes.

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

**Full configuration:** See `deployments/ops/GOLD-STANDARD-NCCL-BENCHMARK.yaml`

---

## Performance Benchmarks

### Historical 8-Node Results (old cluster)

**Without rate limiting:** ~194 GB/s (8GB messages)
**With 100 Gbps rate limiting:** 49.0 GB/s (99% of theoretical 50 GB/s max)

These results were from the previous 8-node configuration. The current cluster has 5 GPU nodes.

### Current 5-Node Benchmark

**See:** `deployments/prism/` for the current benchmark setup and `deployments/prism/run-5node-nccl-test.sh` for automated execution.

---

## Directory Structure

```
├── claude_guidance/              # Operational guides (READ THESE FIRST)
├── deployments/
│   ├── archived/                 # Completed deployments (h-kim, yunshi, deepti)
│   ├── ops/                      # Operational benchmark templates and tools
│   └── prism/                    # Active prism deployment
├── docs/                         # Documentation
│   ├── investigations/           # Historical investigation summaries
│   └── rdma/                     # RDMA setup documentation
├── k8s/                          # Kubernetes resources
│   ├── gold-standard-kustomize/  # Kustomize-based benchmark deployments
│   ├── network-attachments/      # Network attachment definitions
│   ├── rdma-perftest/            # RDMA perftest pod templates and docs
│   ├── machineconfigs/           # OpenShift MachineConfig resources
│   └── scc-modification-for-memlock.yaml
└── scripts/                      # Automation and utility scripts
    ├── run-rdma-perftest.sh      # Automated RDMA testing
    ├── check-hardware-versions.sh
    └── mellanox-firmware/        # Mellanox firmware check/apply scripts
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
kubectl apply -f deployments/ops/apply-100g-with-ofed-image.yaml
```

**See:** `claude_guidance/manual-rate-limiting-mlnx-qos.md` for details.

### Checking Firmware Parameters

```bash
# Deploy MFT pod (replace node name as needed)
sed 's/mfttool-node/mfttool-u17/g; s/REPLACE_WITH_NODE_NAME/moc-r4pcc02u17-nairr/g' \
  k8s/machineconfigs/mft-tools-template.yaml | kubectl apply -f -

# Query firmware
kubectl exec -n nccl-test mfttool-u17 -- mlxconfig -d 03:00.0 q
```

**See:** `claude_guidance/mlxconfig-pod-setup.md` for complete procedure.

### Running RDMA Perftest

Automated script for flexible RDMA testing between two nodes:

```bash
# Basic RDMA test (host memory)
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc02u17-nairr \
  --client-node moc-r4pcc02u18-nairr

# GPUDirect test with specific GPU and NIC
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc02u17-nairr \
  --client-node moc-r4pcc02u18-nairr \
  --gpudirect --gpu-id 0 --nic-id 0

# Multiple parallel streams
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc02u17-nairr \
  --client-node moc-r4pcc02u18-nairr \
  --gpudirect --gpu-id 1 --nic-id 1 --num-qps 4
```

**See:** `k8s/rdma-perftest/README.md` for all options and troubleshooting.

---

## Best Practices

### Before Making Changes

1. **Check `claude_guidance/` first** - Don't reinvent documented procedures
2. **Read existing deployment files** - Understand current configuration
3. **Test on subset of nodes** - Don't apply to all 5 nodes immediately
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
4. **Document findings** - Create investigation docs in relevant deployment directory

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
- Investigation summaries in relevant deployment directory
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
3. Check `deployments/archived/h-kim/` for similar past work
4. Search git history for related changes

---

**Last Updated:** July 11, 2026
