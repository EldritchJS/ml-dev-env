# Prism Deployment - BEACON Continued Pre-training

Multi-node distributed training deployment for Barcelona H100 cluster (5 nodes, 20 GPUs).

## Quick Start

**Run 5-node NCCL benchmark:**
```bash
cd deployments/prism
./run-5node-nccl-test.sh
```

Deploys StatefulSet, waits for pods, auto-starts benchmark on all 5 nodes. Results in `benchmark-pod-0.log`.

## Container Images

Two validated images available on quay.io:

### 1. prism-pytorch-25.06 (PyTorch-Only Base)

**Image:** `quay.io/jschless/ml-dev-env:prism-pytorch-25.06`

**What it HAS:**
- PyTorch 2.9.0 + CUDA 13.2
- RDMA/InfiniBand tools (infiniband-diags, ibverbs-utils)
- Validated NCCL performance: ~194 GB/s bus bandwidth (5 nodes, 20 GPUs)

**What it DOESN'T have:**
- NeMo Toolkit
- HuggingFace ecosystem (transformers, datasets, accelerate, etc.)
- DeepSpeed, Lightning
- wandb

**Use for:** NCCL testing, basic PyTorch training, single-node experiments

### 2. prism-nemo-25.04 (Full NeMo Stack)

**Image:** `quay.io/jschless/ml-dev-env:prism-nemo-25.04`

**What it HAS (everything from pytorch-25.06 PLUS):**
- NVIDIA NeMo Toolkit 2.3.2
- HuggingFace Transformers 5.13.0
- HuggingFace Datasets 5.0.0
- HuggingFace Accelerate 1.8.1
- PEFT, TRL 1.8.0
- DeepSpeed 0.19.2
- Lightning 2.4.0
- wandb 0.16.6
- All dependencies from requirements.txt

**Use for:** Multi-node BEACON training, NeMo-based LLM workflows, production training

**See IMAGE-REFERENCE.md for complete details.**

## Barcelona Cluster - 5 H100 Nodes

**Nodes:**
- moc-r4pcc02u17-nairr
- moc-r4pcc02u18-nairr
- moc-r4pcc02u25-nairr
- moc-r4pcc02u15-yunshi
- moc-r4pcc02u16-yunshi

**Per-node hardware:**
- 4x H100 80GB GPUs
- 4x ConnectX-7 400G NICs (eno5np0, eno6np0, eno7np0, eno8np0)
- Isolated /24 subnets: 10.0.103/104/105/106.0/24 (NO inter-subnet routing)

**RDMA devices (SR-IOV pods):**
- mlx5_6, mlx5_7, mlx5_8, mlx5_9 (mapped to net1, net2, net3, net4)

## Critical NCCL Configuration

**MUST HAVE - These are REQUIRED:**

```bash
# GPUDirect DMABUF - no nvidia_peermem kernel module
NCCL_DMABUF_ENABLE=1

# Isolated subnet configuration - NO cross-NIC communication
NCCL_CROSS_NIC=0

# Explicit IB device specification - auto-detect fails in SR-IOV
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_8,mlx5_9
```

**Performance Settings:**

```bash
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=16
NCCL_NET_GDR_LEVEL=5          # GPUDirect RDMA level
NCCL_NET_GDR_READ=1           # Enable GPUDirect read
NCCL_PROTO=Simple
NCCL_ALGO=Ring
```

**InfiniBand Settings:**

```bash
NCCL_IB_GID_INDEX=3           # RoCE v2
NCCL_IB_TC=106                # Traffic class
NCCL_IB_TIMEOUT=23
NCCL_IB_RETRY_CNT=7
NCCL_IB_SL=0
NCCL_IB_AR_THRESHOLD=8192
NCCL_IB_PCI_RELAXED_ORDERING=1
```

**Buffer and Thread Configuration:**

```bash
NCCL_BUFFSIZE=8388608
NCCL_NTHREADS=640
NCCL_LL_THRESHOLD=0
NCCL_TREE_THRESHOLD=0
NCCL_SOCKET_FAMILY=4
NCCL_NSOCKS_PERTHREAD=8
```

**Other Settings:**

```bash
NCCL_NVLS_ENABLE=0            # Disable NVLink Switch (H100 PCIe)
NCCL_NET_SHARED_BUFFERS=1
NCCL_NET_OVERHEAD=0
NCCL_IGNORE_CPU_AFFINITY=1
NCCL_SOCKET_IFNAME=net1,net2,net3,net4
```

**See nccl-test-5node.yaml for complete gold standard configuration.**

## Hardware Optimization Status

**ConnectX-7 Firmware (nvconfig) — all 5 nodes optimized (2026-07-12):**
- ADVANCED_PCI_SETTINGS=True(1)
- MAX_ACC_OUT_READ=128
- PCI_WR_ORDERING=per_mkey(0)
- RDMA_SELECTIVE_REPEAT_EN=True(1)

**PCI Settings (runtime, does not persist across reboots):**
- MaxReadReq=4096 (via `pci_mrr.sh`)
- ATS enabled (via `pci_ats.sh`)

## Validated Performance

**5-node NCCL AllReduce benchmark (IBM bus bandwidth, 8GB messages, 2026-07-11):**

| Image | NCCL Version | Avg GB/s | Max GB/s |
|-------|-------------|----------|----------|
| prism-pytorch-25.06 | 2.27.3 | 194.15 | 194.80 |
| prism-nemo-25.04 | 2.23.4 | 194.15 | 194.95 |

- Configuration: 5 nodes × 4 GPUs = 20 GPUs, 3 runs each
- Matches gold standard ~194 GB/s (bus bandwidth is independent of node count for Ring AllReduce)

## Files

```
deployments/prism/
├── README.md                       # This file
├── IMAGE-REFERENCE.md              # Detailed image documentation
├── NCCL-TESTING.md                 # Complete NCCL testing guide
├── nccl-test-5node.yaml            # 5-node StatefulSet manifest
├── run-5node-nccl-test.sh          # Automated test runner (gold standard)
├── Dockerfile.pytorch-base         # PyTorch-only image build
├── Dockerfile.nemo-base            # NeMo full-stack image build
└── workspace/
    └── requirements.txt            # Python dependencies (for NeMo image)
```

## Running NCCL Benchmarks

### Method 1: Automated Script (Recommended)

```bash
cd deployments/prism
./run-5node-nccl-test.sh          # Default 3 runs
./run-5node-nccl-test.sh 5        # Custom number of runs
```

### Method 2: Manual Execution

See NCCL-TESTING.md for complete manual execution instructions.

## Troubleshooting

### Low NCCL Performance

**Check critical settings:**
```bash
oc logs nccl-benchmark-0 -n nccl-test | grep NCCL_DMABUF
oc logs nccl-benchmark-0 -n nccl-test | grep NCCL_CROSS_NIC
oc logs nccl-benchmark-0 -n nccl-test | grep NCCL_IB_HCA
```

**Common issues:**
- `NCCL_DMABUF_ENABLE` not set → Use DMABUF for GPUDirect
- `NCCL_CROSS_NIC=1` → Should be 0 (isolated subnets)
- `NCCL_IB_HCA` not set → Must specify mlx5_6,7,8,9 explicitly

### Pod Creation Fails

**Missing SecurityContextConstraint:**
```bash
oc adm policy add-scc-to-user nccl-rdma-scc -z default -n nccl-test
```

### Benchmark Hangs

**Not all pods running:**
```bash
oc get pods -n nccl-test -l app=nccl-benchmark
```

All 5 pods must be Running before starting torchrun.

## Related Documentation

- **IMAGE-REFERENCE.md** - Complete image documentation and selection guide
- **NCCL-TESTING.md** - Detailed NCCL testing procedures
- **Gold standard reference:** `/deployments/ops/GOLD-STANDARD-NCCL-BENCHMARK.yaml`
- **NCCL config guide:** `/claude_guidance/nccl-configuration-h100-cluster.md`
