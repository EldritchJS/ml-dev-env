# Prism Deployment - BEACON Continued Pre-training

Multi-node distributed training deployment for Barcelona H100 cluster (5 nodes, 20 GPUs).

## Quick Start

### 1. Generate the benchmark manifest

The benchmark YAML is generated from a config file. The prism config is already set up:

```bash
# Generate the manifest
./deployments/ops/generate-nccl-manifest.sh \
  -c deployments/ops/configs/barcelona-5node-prism.conf \
  -o deployments/prism/nccl-test-5node.yaml
```

### 2. Run the benchmark

```bash
./deployments/ops/run-nccl-job.sh \
  -c deployments/ops/configs/barcelona-5node-prism.conf \
  -m deployments/prism/nccl-test-5node.yaml
```

Deploys the StatefulSet, waits for pods, runs the benchmark (3 runs by default). Results in `deployments/prism/benchmark-pod-0.log`.

For a custom number of runs: add `-r 5`

### 3. Clean up

```bash
oc delete -f deployments/prism/nccl-test-5node.yaml -n <namespace>
```

## How to Change Settings

Edit `deployments/ops/configs/barcelona-5node-prism.conf`, then regenerate:

- **Different image**: Change `IMAGE="quay.io/jschless/ml-dev-env:prism-nemo-25.04"`
- **Different nodes**: Change `NODES="node1 node2 node3"` (replica count is automatic)
- **Different namespace**: Change `NAMESPACE="my-namespace"`
- **Different benchmark script**: Set `BENCHMARK_SCRIPT="/path/to/my-script.py"` (default: IBM AllReduce)
- **NCCL tuning**: Add any `NCCL_*` variable (e.g. `NCCL_ALGO="Tree"`)

Then regenerate:
```bash
./deployments/ops/generate-nccl-manifest.sh \
  -c deployments/ops/configs/barcelona-5node-prism.conf \
  -o deployments/prism/nccl-test-5node.yaml
```

**Setting up a new deployment?** See the [root README](../../README.md#setting-up-a-new-deployment) for step-by-step instructions.

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

## NCCL Configuration

All NCCL parameters are managed by the generator script with gold standard defaults. To see the full list of configurable parameters, check `deployments/ops/configs/example.conf`.

The three critical settings for this cluster are:
- `NCCL_DMABUF_ENABLE=1` — no nvidia_peermem kernel module
- `NCCL_CROSS_NIC=0` — isolated /24 subnets
- `NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_8,mlx5_9` — explicit IB devices for SR-IOV

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
├── nccl-test-5node.yaml            # Generated 5-node manifest
├── run-5node-nccl-test.sh          # Automated test runner
├── Dockerfile.pytorch-base         # PyTorch-only image build
├── Dockerfile.nemo-base            # NeMo full-stack image build
└── workspace/
    └── requirements.txt            # Python dependencies (for NeMo image)

deployments/ops/
├── generate-nccl-manifest.sh       # Manifest generator
├── run-nccl-job.sh                 # Config-driven benchmark runner
├── allreduce-loop.py               # IBM AllReduce benchmark script (default)
└── configs/
    ├── example.conf                # Reference config (all parameters documented)
    └── barcelona-5node-prism.conf  # Prism deployment config
```

## Troubleshooting

### Low NCCL Performance

**Check critical settings:**
```bash
oc logs nccl-benchmark-0 -n <namespace> | grep NCCL_DMABUF
oc logs nccl-benchmark-0 -n <namespace> | grep NCCL_CROSS_NIC
oc logs nccl-benchmark-0 -n <namespace> | grep NCCL_IB_HCA
```

**Common issues:**
- `NCCL_DMABUF_ENABLE` not set → Use DMABUF for GPUDirect
- `NCCL_CROSS_NIC=1` → Should be 0 (isolated subnets)
- `NCCL_IB_HCA` not set → Must specify mlx5_6,7,8,9 explicitly

### Pod Creation Fails

**Missing SecurityContextConstraint:**
```bash
oc adm policy add-scc-to-user nccl-rdma-scc -z <service-account> -n <namespace>
```

### Benchmark Hangs

**Not all pods running:**
```bash
oc get pods -n <namespace> -l app=nccl-benchmark
```

All 5 pods must be Running before starting torchrun.

## Related Documentation

- **IMAGE-REFERENCE.md** — Complete image documentation and selection guide
- **NCCL-TESTING.md** — Manual benchmark execution instructions
- **deployments/ops/configs/example.conf** — All configurable parameters
- **deployments/ops/GOLD-STANDARD-NCCL-BENCHMARK.yaml** — Original gold standard reference
- **claude_guidance/nccl-configuration-h100-cluster.md** — NCCL configuration guide
