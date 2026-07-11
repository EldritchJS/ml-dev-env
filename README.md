# ML Development Environment for MOC H100 Cluster

Operational tooling for the MOC H100 GPU cluster on OpenShift (Barcelona), including NCCL benchmarking, RDMA/GPUDirect testing, network rate limiting, and Mellanox firmware management.

## Cluster Overview

**Barcelona cluster** — 5 GPU nodes, all Rack 2:

| Node | Suffix | GPUs |
|------|--------|------|
| moc-r4pcc02u17-nairr | -nairr | 4x H100 80GB |
| moc-r4pcc02u18-nairr | -nairr | 4x H100 80GB |
| moc-r4pcc02u25-nairr | -nairr | 4x H100 80GB |
| moc-r4pcc02u15-yunshi | -yunshi | 4x H100 80GB |
| moc-r4pcc02u16-yunshi | -yunshi | 4x H100 80GB |

All nodes have ConnectX-7 400G NICs with 4 isolated /24 subnets (10.0.103-106.0/24).

## Quick Start

### Run NCCL Benchmark (5-node)

```bash
# Deploy the benchmark StatefulSet
kubectl apply -f deployments/prism/nccl-test-5node.yaml -n nccl-test

# Wait for all pods, then run the automated benchmark script
./deployments/prism/run-5node-nccl-test.sh
```

See `deployments/prism/README.md` for full details.

### Run RDMA Perftest

```bash
# Basic RDMA test between two nodes
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc02u17-nairr \
  --client-node moc-r4pcc02u18-nairr

# GPUDirect test
./scripts/run-rdma-perftest.sh \
  --server-node moc-r4pcc02u17-nairr \
  --client-node moc-r4pcc02u18-nairr \
  --gpudirect --gpu-id 0 --nic-id 0
```

See `k8s/rdma-perftest/README.md` for all options.

### Apply Rate Limits

```bash
kubectl apply -f deployments/ops/apply-100g-with-ofed-image.yaml
```

See `claude_guidance/manual-rate-limiting-mlnx-qos.md` for details.

### Check Firmware

```bash
sed 's/mfttool-node/mfttool-u17/g; s/REPLACE_WITH_NODE_NAME/moc-r4pcc02u17-nairr/g' \
  k8s/machineconfigs/mft-tools-template.yaml | kubectl apply -f -

kubectl exec -n nccl-test mfttool-u17 -- mlxconfig -d 03:00.0 q
```

See `claude_guidance/mlxconfig-pod-setup.md` for complete procedure.

## NCCL Configuration

Critical environment variables for this cluster:

```bash
NCCL_DMABUF_ENABLE=1                        # Required — no nvidia_peermem module
NCCL_CROSS_NIC=0                            # Required — isolated subnets
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_8,mlx5_9    # Explicit IB device list
```

Full gold standard config: `deployments/ops/GOLD-STANDARD-NCCL-BENCHMARK.yaml`

## Repository Structure

```
ml-dev-env/
├── claude_guidance/              # Operational guides (read these first)
├── deployments/
│   ├── archived/                 # Completed deployments (h-kim, yunshi, deepti)
│   ├── ops/                      # Operational benchmark templates and tools
│   └── prism/                    # Active prism deployment
├── docs/
│   ├── investigations/           # Historical investigation summaries
│   └── rdma/                     # RDMA setup documentation
├── k8s/
│   ├── gold-standard-kustomize/  # Kustomize-based benchmark deployments
│   ├── network-attachments/      # Network attachment definitions
│   ├── rdma-perftest/            # RDMA perftest pod templates
│   └── machineconfigs/           # OpenShift MachineConfig resources
└── scripts/
    ├── run-rdma-perftest.sh      # Automated RDMA testing
    ├── check-hardware-versions.sh
    └── mellanox-firmware/        # Firmware check/apply scripts
```

## Operational Guides

The `claude_guidance/` directory contains step-by-step procedures for common operations:

| Guide | Covers |
|-------|--------|
| `nccl-configuration-h100-cluster.md` | NCCL benchmark execution, gold standard settings |
| `manual-rate-limiting-mlnx-qos.md` | Hardware rate limiting with mlnx_qos |
| `rdma-perftest-gpudirect.md` | RDMA performance testing |
| `mlxconfig-pod-setup.md` | Mellanox firmware inspection with MFT tools |
| `check-iommu-status.md` | IOMMU status verification |
| `gpu-nic-affinity-mapping.md` | GPU-NIC NUMA affinity |

## Performance Baselines

**8-node historical (old cluster):** ~194 GB/s without rate limiting, 49.0 GB/s with 100 Gbps limit

**Current 5-node results:** See `deployments/prism/` for latest benchmark data.

## Container Images

**Validated cluster image:**
```
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env@sha256:8f99384b8277ff732153c58874679fa4d6592104bfa0fe21ca2d5750ee213bed
```

**Reference image:** `quay.io/jschless/ml-dev-env:latest`
