# Prism Container Images Reference

## Available Images

### 1. prism-pytorch-25.06 (PyTorch-Only)

**Registry:** `quay.io/jschless/ml-dev-env:prism-pytorch-25.06`

**Base:** NVIDIA PyTorch 25.06 Container (`nvcr.io/nvidia/pytorch:25.06-py3`)

**Build Status:** ✅ Validated (Build #8, tested 2026-07-10)

**Performance:** ~194 GB/s bus bandwidth (5-node NCCL benchmark with 20 GPUs)

#### What This Image HAS:

**Core ML Stack:**
- ✅ **PyTorch 2.9.0** with full CUDA 13.2 support
- ✅ **torchvision 0.22.0**
- ✅ **torchaudio 2.11.0**
- ✅ **Python 3.12**

**GPU/CUDA:**
- ✅ **CUDA 13.2** (full toolkit)
- ✅ **cuDNN 9.x**
- ✅ **NCCL 2.x** (GPUDirect RDMA enabled)
- ✅ All NVIDIA GPU libraries

**RDMA/Networking:**
- ✅ **infiniband-diags** (ibstat, ibv_devinfo)
- ✅ **ibverbs-utils**
- ✅ **libibverbs-dev**
- ✅ **rdma-core**
- ✅ Unlimited memlock configured

**Standard Libraries:**
- ✅ NumPy, SciPy (included in PyTorch base)
- ✅ All standard NVIDIA PyTorch 25.06 packages

#### What This Image DOES NOT Have:

**You must `pip install` these at runtime:**
- ❌ **NVIDIA NeMo Toolkit**
- ❌ **HuggingFace Transformers**
- ❌ **HuggingFace Datasets**
- ❌ **HuggingFace Accelerate**
- ❌ **HuggingFace Tokenizers**
- ❌ **HuggingFace Hub**
- ❌ **safetensors**
- ❌ **sentencepiece**
- ❌ **PEFT** (Parameter-Efficient Fine-Tuning)
- ❌ **TRL** (Transformer Reinforcement Learning)
- ❌ **DeepSpeed**
- ❌ **Lightning / PyTorch Lightning**
- ❌ **scikit-learn**
- ❌ **wandb** (Weights & Biases)
- ❌ **evaluate**

#### When to Use This Image:

**Use for:**
- ✅ NCCL performance testing and validation
- ✅ Basic PyTorch distributed training without NeMo
- ✅ Testing RDMA/InfiniBand connectivity
- ✅ Scenarios where you want control over package versions

**Don't use for:**
- ❌ Multi-node NeMo training (pip installing NeMo on 5 nodes is wasteful)
- ❌ Production BEACON training workflows (use prism-nemo image when available)

#### Runtime Package Installation:

For single-node experimentation, you can install packages at runtime:

```bash
pip install transformers datasets accelerate tokenizers huggingface_hub \
    safetensors sentencepiece peft trl evaluate scikit-learn wandb \
    deepspeed lightning nemo_toolkit[all]
```

**Note:** For multi-node (5-pod) deployments, installing packages on each pod separately is inefficient. Use a pre-built image with all dependencies instead.

#### Validation Results:

**Test:** 5-node NCCL AllReduce benchmark (Barcelona cluster, IBM bus bandwidth)
- **Date:** 2026-07-11
- **Configuration:** 5 nodes × 4 GPUs = 20 GPUs total
- **Message size:** 8GB, 3 runs
- **Bus bandwidth:** ~194.15 avg, ~194.80 max GB/s
- **NCCL Config:** Gold standard (DMABUF_ENABLE=1, CROSS_NIC=0, IB_HCA=mlx5_6,7,8,9)

**Build Information:**
- **Build ID:** prism-image-build-8
- **Duration:** 18m9s
- **Committed:** 2026-07-10

---

### 2. prism-nemo-25.04 (Full NeMo Stack)

**Registry:** `quay.io/jschless/ml-dev-env:prism-nemo-25.04`

**OpenShift Registry:** `image-registry.openshift-image-registry.svc:5000/nccl-test/prism@sha256:314a4644aa664bc43cb1a47e86eda5c4fdf9ae6ac4e9337a57b17e793738da07`

**Base:** NVIDIA NeMo 25.04.02 Container (`nvcr.io/nvidia/nemo:25.04.02`)

**Build Status:** ✅ Complete (Build #16, completed 2026-07-10)

#### What This Image HAS:

**Everything in prism-pytorch-25.06 PLUS:**
- ✅ **NVIDIA NeMo Toolkit 2.3.2**
- ✅ **HuggingFace Transformers 5.13.0**
- ✅ **HuggingFace Datasets 5.0.0**
- ✅ **HuggingFace Accelerate 1.8.1**
- ✅ **HuggingFace ecosystem** (tokenizers 0.22.2, hub 1.23.0, safetensors 0.8.0, sentencepiece 0.2.0)
- ✅ **PEFT** (Parameter-Efficient Fine-Tuning)
- ✅ **TRL 1.8.0** (Transformer Reinforcement Learning)
- ✅ **DeepSpeed 0.19.2**
- ✅ **Lightning 2.4.0 / PyTorch Lightning 2.5.2**
- ✅ **scikit-learn**
- ✅ **wandb 0.16.6**
- ✅ **evaluate**
- ✅ All requirements from `requirements.txt`

**Known Dependency Conflicts (Warnings Only):**
- transformers 5.13.0 incompatible with nemo-toolkit requirement (<4.48.0), sentence-transformers, tensorrt-llm
- pyarrow 25.0.0 incompatible with cudf, pylibcudf (<20.0.0)
- numba 0.61.0 incompatible with cudf, cugraph, cuml, dask-cuda (<0.61.0)

These are pip warnings, not errors - packages install and should function normally.

#### What This Image DOES NOT Have:

- ❌ **kernels>=0.12.0** (MXFP4 support) - skipped due to 4+ hour build time for tensorstore dependency
- ❌ **JAX/Flax** - not included in requirements.txt
- ❌ **Ray/Horovod** - alternative distributed frameworks not included

If you need these packages, install at runtime or build a custom image.

#### When to Use This Image:

**Use for:**
- ✅ Multi-node BEACON continued pre-training
- ✅ NeMo-based LLM training workflows
- ✅ Production distributed training (all dependencies pre-installed)
- ✅ Any workflow requiring the full HuggingFace + NeMo stack

**Available:** ✅ Build complete, pushed to quay.io

---

## Quick Reference Table

| Feature | prism-pytorch-25.06 | prism-nemo-25.04 |
|---------|---------------------|------------------|
| PyTorch 2.9 + CUDA | ✅ | ✅ |
| RDMA/InfiniBand | ✅ | ✅ |
| NCCL Validated | ✅ (~194 GB/s) | ✅ (~194 GB/s) |
| NeMo Toolkit | ❌ | ✅ |
| HuggingFace | ❌ | ✅ |
| DeepSpeed | ❌ | ✅ |
| Lightning | ❌ | ✅ |
| wandb | ❌ | ✅ |
| Build Time | 18 min | ~26-30 min |
| Use Case | Testing, experiments | Production training |

---

## Image Selection Guide

**Choose `prism-pytorch-25.06` if:**
- Testing NCCL performance
- Running basic PyTorch distributed training
- Experimenting on a single node
- You want to control exact package versions

**Choose `prism-nemo-25.04` if:**
- Running BEACON continued pre-training
- Using NeMo Toolkit
- Multi-node training (5 pods)
- Production workflows needing all dependencies pre-installed

---

## Usage Examples

### Pull the Image

```bash
# PyTorch-only
podman pull quay.io/jschless/ml-dev-env:prism-pytorch-25.06

# NeMo (when available)
podman pull quay.io/jschless/ml-dev-env:prism-nemo-25.04
```

### Use in Kubernetes

```yaml
containers:
- name: training
  image: quay.io/jschless/ml-dev-env:prism-pytorch-25.06
  # or
  # image: quay.io/jschless/ml-dev-env:prism-nemo-25.04
```

### Verify Image Contents

```bash
# Check PyTorch version
podman run --rm quay.io/jschless/ml-dev-env:prism-pytorch-25.06 \
  python -c "import torch; print(torch.__version__)"

# Check CUDA availability
podman run --rm --gpus all quay.io/jschless/ml-dev-env:prism-pytorch-25.06 \
  python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# List installed packages
podman run --rm quay.io/jschless/ml-dev-env:prism-pytorch-25.06 \
  pip list | grep -E "torch|transformers|nemo"
```

---

## Build History

| Build | Image Tag | Status | Duration | Date |
|-------|-----------|--------|----------|------|
| #8 | prism-pytorch-25.06 | ✅ Success | 18m9s | 2026-07-10 |
| #16 | prism-nemo-25.04 | ✅ Success | 34m11s | 2026-07-10 |

---

## Related Documentation

- **NCCL Testing:** [NCCL-TESTING.md](./NCCL-TESTING.md)
- **5-Node Test Manifest:** [nccl-test-5node.yaml](./nccl-test-5node.yaml)
- **NCCL Configuration:** [../../claude_guidance/nccl-configuration-h100-cluster.md](../../claude_guidance/nccl-configuration-h100-cluster.md)
