# H-Kim Image - Quick Start

Minimal PyTorch 26.01 environment with TorchTitan and essential ML packages.

## 🚀 Quick Start (3 Options)

### Option A: Use Deployment Script (Recommended)

Automatically handles namespace, network mode, and configuration:

```bash
# Deploy to any namespace with RDMA
./scripts/deploy-h-kim.sh --namespace my-namespace --mode rdma

# Deploy with TCP fallback
./scripts/deploy-h-kim.sh --namespace my-namespace --mode tcp

# Preview without deploying
./scripts/deploy-h-kim.sh --namespace my-namespace --dry-run
```

See `./scripts/deploy-h-kim.sh --help` for all options.

### Option B: Use Pre-Built Image from Quay

```bash
# Pull the image
podman pull quay.io/jschless/ml-dev-env:h-kim

# Or deploy directly on OpenShift (nccl-test namespace)
oc apply -f k8s/statefulset-h-kim.yaml
```

The image is ~9.2 GB and ready to use.

### Option C: Build from Source (~10-15 minutes)

```bash
# Create ImageStream and BuildConfig
oc apply -f k8s/imagestream-h-kim.yaml
oc apply -f k8s/buildconfig-h-kim.yaml

# Start build and watch logs
oc start-build h-kim -n nccl-test --follow
```

---

### Deploy Pods

**Single-Node (4 GPUs):**
```bash
oc apply -f k8s/pod-h-kim.yaml

# Wait for ready
oc wait --for=condition=Ready pod/h-kim-dev -n nccl-test --timeout=300s
```

**Multi-Node (8+ GPUs):**
```bash
oc apply -f k8s/statefulset-h-kim.yaml

# Wait for all pods
oc get pods -n nccl-test -l app=h-kim-multi -w
```

---

### Test the Setup

```bash
# Shell into pod
oc exec -it h-kim-dev -n nccl-test -- bash
# or for multi-node:
oc exec -it h-kim-0 -n nccl-test -- bash

# Test GPU access
python3 -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"

# Test packages
python3 -c "import transformers, datasets, accelerate; print('✅ All good')"
```

---

## 🏃 Run TorchTitan Training

H-Kim includes a ready-to-use TorchTitan training script:

```bash
# Copy training script to pod
oc cp h-kim-openshift.sh h-kim-0:/workspace/ -n nccl-test
oc exec h-kim-0 -n nccl-test -- chmod +x /workspace/h-kim-openshift.sh

# Run training (single-node, 4 GPUs)
oc exec h-kim-0 -n nccl-test -- /workspace/h-kim-openshift.sh

# Run training (multi-node, 8 GPUs - copy to both pods first)
oc cp h-kim-openshift.sh h-kim-1:/workspace/ -n nccl-test
oc exec h-kim-0 -n nccl-test -- /workspace/h-kim-openshift.sh
```

**What the script does:**
- Auto-clones TorchTitan repository
- Configures NCCL for RDMA/InfiniBand
- Sets up distributed training across all pods
- Uses torchrun for multi-GPU/multi-node training

See [H-KIM-TORCHTITAN-GUIDE.md](H-KIM-TORCHTITAN-GUIDE.md) for detailed training instructions.

---

## 📦 What's Included

- **NVIDIA PyTorch 26.01** (latest stable) + CUDA (from NVIDIA base)
- **TorchTitan** - PyTorch Titan framework
- **Transformers ecosystem**: transformers, tokenizers, datasets, accelerate
- **Configuration**: hydra-core, omegaconf
- **Utilities**: einops, tqdm, rich, tensorboard, wandb
- **RDMA tools**: For multi-node InfiniBand

See [docs/H-KIM-IMAGE.md](docs/H-KIM-IMAGE.md) for full details.

---

## 🔄 Common Commands

```bash
# Build
oc start-build h-kim -n nccl-test --follow

# Deploy single-node
oc apply -f k8s/pod-h-kim.yaml

# Deploy multi-node
oc apply -f k8s/statefulset-h-kim.yaml

# Shell access
oc exec -it h-kim-dev -n nccl-test -- bash          # Single-node
oc exec -it h-kim-0 -n nccl-test -- bash            # Multi-node (master)

# View logs
oc logs h-kim-dev -n nccl-test -f                   # Single-node
oc logs h-kim-0 -n nccl-test -f                     # Multi-node

# Copy files to pod
oc cp ./my-script.py h-kim-dev:/workspace/ -n nccl-test

# Delete
oc delete pod h-kim-dev -n nccl-test                # Single-node
oc delete statefulset h-kim -n nccl-test            # Multi-node
```

---

## 📊 Example Training Script

```python
# test_h_kim.py
import torch
import torch.distributed as dist

def main():
    # Initialize distributed training (for multi-node)
    if 'MASTER_ADDR' in os.environ:
        dist.init_process_group(backend='nccl')
        rank = dist.get_rank()
        world_size = dist.get_world_size()
    else:
        rank = 0
        world_size = 1

    # Setup device
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    print(f"Rank {rank}/{world_size} on device {device}")
    print(f"GPU: {torch.cuda.get_device_name(device)}")

    # Your training code here
    model = YourModel().to(device)

    if world_size > 1:
        model = torch.nn.parallel.DistributedDataParallel(model)

    # Train...

if __name__ == '__main__':
    main()
```

Run it:
```bash
# Single-node
oc exec h-kim-dev -n nccl-test -- python3 /workspace/test_h_kim.py

# Multi-node (from master pod)
oc exec h-kim-0 -n nccl-test -- \
  torchrun \
    --nnodes=2 \
    --nproc_per_node=4 \
    --master_addr=h-kim-0.h-kim-headless.nccl-test.svc.cluster.local \
    --master_port=29500 \
    /workspace/test_h_kim.py
```

---

## 🆚 vs ml-dev-env

| Feature | h-kim | ml-dev-env |
|---------|-------|------------|
| Size | ~8 GB | ~12 GB |
| VSCode | ❌ | ✅ |
| Jupyter | ❌ | ✅ |
| TorchTitan | ✅ | ❌ |
| DeepSpeed | ❌ | ✅ |
| Use case | Minimal training | Full dev environment |

**Choose h-kim** for focused training workloads.
**Choose ml-dev-env** for full development environment.

---

## ⚠️ Running in Different Namespaces

If deploying to a namespace other than `nccl-test`, use the deployment script to automatically configure everything:

```bash
# Automatic configuration for any namespace
./scripts/deploy-h-kim.sh --namespace b-efficient-memory-offloading-765cab --mode rdma
```

**Common Issues:**
- **NCCL Error: "Bootstrap: no socket interface found"**
  - Cause: RDMA interfaces (net1-4) not available
  - Fix: Use `--mode tcp` instead of `--mode rdma`

**Manual deployment to different namespace:**
```bash
# Use TCP mode if RDMA unavailable
NAMESPACE="my-namespace"
sed "s/nccl-test/$NAMESPACE/g" k8s/statefulset-h-kim.yaml | \
  sed 's|image-registry.openshift-image-registry.svc:5000/nccl-test/h-kim:latest|quay.io/jschless/ml-dev-env:h-kim|' | \
  sed 's/NCCL_SOCKET_IFNAME.*net1.*/NCCL_SOCKET_IFNAME: "eth0"/' | \
  sed 's/NCCL_IB_DISABLE.*0.*/NCCL_IB_DISABLE: "1"/' | \
  oc apply -f -
```

---

For detailed documentation, see [docs/H-KIM-IMAGE.md](docs/H-KIM-IMAGE.md)
