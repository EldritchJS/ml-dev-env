# Running TorchTitan on OpenShift with H-Kim Image

This guide shows how to run TorchTitan distributed training using the h-kim image on OpenShift.

## Overview

The `h-kim-openshift.sh` script is an adapted version of h-kim's original training script that works with our OpenShift cluster setup. It:

- Automatically clones the TorchTitan repository if needed
- Configures NCCL for RDMA/InfiniBand networking
- Sets up distributed training across multiple pods
- Uses the h-kim-headless service for stable DNS resolution

## Quick Start

### Option 1: Use Existing h-kim StatefulSet

The h-kim StatefulSet is already running with 2 pods (8 GPUs total). To run TorchTitan training:

**1. Copy the training script to the pods:**

```bash
oc cp h-kim-openshift.sh h-kim-0:/workspace/ -n nccl-test
oc cp h-kim-openshift.sh h-kim-1:/workspace/ -n nccl-test
```

**2. Make it executable:**

```bash
oc exec h-kim-0 -n nccl-test -- chmod +x /workspace/h-kim-openshift.sh
oc exec h-kim-1 -n nccl-test -- chmod +x /workspace/h-kim-openshift.sh
```

**3. Run training (from master pod h-kim-0):**

```bash
# Start training across all pods
oc exec h-kim-0 -n nccl-test -- /workspace/h-kim-openshift.sh

# Or with custom config
oc exec h-kim-0 -n nccl-test -- bash -c "CONFIG_FILE=/workspace/torchtitan/train_configs/llama3_8b.toml /workspace/h-kim-openshift.sh"
```

The script will:

- Clone TorchTitan repo to `/workspace/torchtitan` (first run only)
- Detect it's running on h-kim-0 (node rank 0)
- Connect to h-kim-1 via the headless service
- Launch training across 2 nodes × 4 GPUs = 8 total GPUs

### Option 2: Dedicated Training Job

Create a dedicated Kubernetes Job for training (see `k8s/job-h-kim-torchtitan.yaml`):

```bash
oc apply -f k8s/job-h-kim-torchtitan.yaml

# Monitor training
oc logs -f h-kim-0 -n nccl-test

# Check all pods
oc get pods -n nccl-test -l app=h-kim-torchtitan
```

## Configuration

### Environment Variables

You can customize the training by setting environment variables:

```bash
# Number of nodes (pods)
export NNODES=2

# GPUs per node
export NPROC_PER_NODE=4

# TorchTitan config file
export CONFIG_FILE=/workspace/torchtitan/train_configs/llama3_8b.toml

# NCCL debug level
export NCCL_DEBUG=INFO

# Master address (usually h-kim-0)
export MASTER_ADDR=h-kim-0.h-kim-headless.nccl-test.svc.cluster.local
export MASTER_PORT=29500
```

### Available TorchTitan Configs

After the TorchTitan repo is cloned, configs are in `/workspace/torchtitan/train_configs/`:

- `llama3_8b.toml` - Llama 3 8B model
- `llama3_70b.toml` - Llama 3 70B model
- `debug_model.toml` - Small debug model for testing

You can also create custom configs based on these templates.

## Testing the Setup

**1. Test basic connectivity:**

```bash
# From h-kim-0, check if h-kim-1 is reachable
oc exec h-kim-0 -n nccl-test -- python3 -c "
import socket
print(f'h-kim-1 IP: {socket.gethostbyname(\"h-kim-1.h-kim-headless.nccl-test.svc.cluster.local\")}')
"
```

**2. Test GPU access on all pods:**

```bash
oc exec h-kim-0 -n nccl-test -- nvidia-smi --query-gpu=index,name --format=csv,noheader
oc exec h-kim-1 -n nccl-test -- nvidia-smi --query-gpu=index,name --format=csv,noheader
```

**3. Test TorchTitan installation:**

```bash
oc exec h-kim-0 -n nccl-test -- python3 -c "import torchtitan; print('TorchTitan OK')"
```

**4. Run a quick test (single GPU):**

```bash
# Create a test script
oc exec h-kim-0 -n nccl-test -- bash -c 'cat > /workspace/test_torch.py << EOF
import torch
import torch.distributed as dist

print(f"PyTorch: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")

# Test simple tensor operation
if torch.cuda.is_available():
    x = torch.randn(1000, 1000).cuda()
    y = x @ x.T
    print(f"GPU test passed: {y.shape}")
EOF
'

# Run it
oc exec h-kim-0 -n nccl-test -- python3 /workspace/test_torch.py
```

## Troubleshooting

### Common Issues

**1. "Cannot find torchtitan directory"**

The script will automatically clone the repo on first run. If it fails:

```bash
oc exec h-kim-0 -n nccl-test -- git clone https://github.com/pytorch/torchtitan.git /workspace/torchtitan
```

**2. NCCL timeout or connection issues**

Check that both pods are running and can communicate:

```bash
oc get pods -n nccl-test -l app=h-kim-multi
oc exec h-kim-0 -n nccl-test -- ping -c 3 h-kim-1.h-kim-headless.nccl-test.svc.cluster.local
```

**3. Out of memory errors**

Adjust the model config or batch size in the .toml file, or reduce `NPROC_PER_NODE`:

```bash
export NPROC_PER_NODE=2  # Use 2 GPUs instead of 4
```

**4. Check NCCL settings**

```bash
oc exec h-kim-0 -n nccl-test -- env | grep NCCL
```

### Viewing Logs

```bash
# Follow logs from master pod
oc logs -f h-kim-0 -n nccl-test

# View logs from both pods
oc logs h-kim-0 -n nccl-test --tail=50
oc logs h-kim-1 -n nccl-test --tail=50

# Get recent events
oc get events -n nccl-test --sort-by='.lastTimestamp' | tail -20
```

## Performance Notes

- **8 H100 GPUs (2 nodes × 4):** Ideal for training Llama 3 8B with good throughput
- **RDMA/InfiniBand enabled:** Low-latency communication between nodes
- **NVLink within nodes:** Fast GPU-to-GPU communication on the same node
- **Shared storage:** Each pod has its own 100Gi volume for checkpoints

## Next Steps

1. **Custom datasets:** Mount your dataset via PVC or copy to `/workspace`
2. **Checkpointing:** Configure checkpoint directory in .toml file (e.g., `/workspace/checkpoints`)
3. **Monitoring:** Add Prometheus/Grafana for training metrics
4. **Scaling:** Increase `replicas` in StatefulSet for more GPUs

## References

- [TorchTitan GitHub](https://github.com/pytorch/torchtitan)
- [H-Kim Image Documentation](docs/H-KIM-IMAGE.md)
- [Multi-Node Training Guide](docs/MULTI-NODE-GUIDE.md)
