# Multi-Node Quick Start

Train on **multiple H100 GPUs across nodes** in 5 minutes using cluster-based deployment.

## 🚀 5-Minute Setup

> **Note:** The container image should already be built by your administrator.
> If you need to build it yourself, see [BUILD-ON-CLUSTER.md](BUILD-ON-CLUSTER.md).

```bash
# 1. List available clusters
make list-clusters

# 2. Deploy to cluster (e.g., Barcelona with RDMA)
make deploy-cluster CLUSTER=barcelona MODE=rdma

# 3. Wait for pods (2-3 minutes)
oc get pods -n nccl-test -l app=ml-dev-env-multi -w
# Wait until all show: 1/1 Running

# 4. Sync code to all nodes
make sync-multi-node

# 5. Run distributed training
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh"
```

**That's it!** Training runs across multiple H100s.

## 📋 What Just Happened?

The cluster configuration system automatically:

1. **Loaded cluster-specific settings** from `clusters/<name>.yaml`:
   - GPU nodes to use
   - RDMA devices or TCP networking
   - Storage mode (RWX shared or per-pod)
   - Security requirements (privileged SCC if needed)

2. **Deployed multi-node environment**:
   - StatefulSet with one pod per node
   - Each pod gets 4 GPUs (configurable)
   - Headless service for pod-to-pod DNS
   - Shared workspace (if cluster supports RWX)

3. **Configured networking**:
   - RDMA mode: Uses InfiniBand devices for high-speed communication
   - TCP mode: Falls back to Ethernet (works on any cluster)

## 🌍 Available Clusters

Check configured clusters:
```bash
make list-clusters
```

Example clusters:
- **barcelona** - NERC Barcelona cluster with RDMA and per-pod storage

## 📊 Deployment Modes

### RDMA Mode (High Performance - Recommended)
Best for production training with InfiniBand hardware:
```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

**Features**:
- GPUDirect RDMA for optimal GPU-to-GPU communication
- Higher bandwidth, lower latency
- Requires InfiniBand adapters (mlx5_*)

### TCP Mode (Fallback)
Use only if RDMA is unavailable or troubleshooting:
```bash
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

**Features**:
- Standard TCP/IP networking
- No special hardware required
- Slightly lower performance than RDMA

## 🔄 Development Loop

```bash
# Edit code locally
code workspace/train_multi_node.py

# Sync to all nodes
make sync-multi-node

# Run training
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh"

# Monitor
oc logs -f ml-dev-env-0 -n nccl-test
```

## 📊 Monitor Training

```bash
# Follow master logs
oc logs -f ml-dev-env-0 -n nccl-test

# Check GPU usage on all nodes
for i in 0 1; do
  echo "=== Node $i ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv
done

# Check deployment status
make status-cluster CLUSTER=barcelona
```

## 🎓 Run Your Own Model

### 1. Create Training Script

```python
# workspace/my_model.py
import os
import torch
import deepspeed

def main():
    # Parse args
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--local_rank', type=int, default=0)
    parser = deepspeed.add_config_arguments(parser)
    args = parser.parse_args()

    # Get distributed info
    NODE_RANK = int(os.environ.get('NODE_RANK', 0))
    LOCAL_RANK = int(os.environ.get('LOCAL_RANK', 0))
    GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK

    # Initialize DeepSpeed
    deepspeed.init_distributed()

    # Your model here
    model = YourModel()

    # DeepSpeed engine
    model_engine, optimizer, _, _ = deepspeed.initialize(
        args=args,
        model=model,
        model_parameters=model.parameters()
    )

    # Training loop
    for epoch in range(10):
        # Your training code
        pass

    if GLOBAL_RANK == 0:
        print("Training done!")

if __name__ == "__main__":
    main()
```

### 2. Sync and Run

```bash
# Sync
make sync-multi-node

# Run
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh my_model.py"
```

## 🛠️ Useful Commands

```bash
# Shell into master
make shell-multi-node

# Sync code
make sync-multi-node

# Check status
make status-cluster CLUSTER=barcelona

# Clean up
make clean-cluster CLUSTER=barcelona
```

## 🐛 Quick Debug

**Pods not starting?**
```bash
oc describe pod ml-dev-env-0 -n nccl-test | tail -20
```

**Training hangs?**
```bash
# Test NCCL from master
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
python3 -c "
import torch
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\")
print(\"NCCL working!\")
"
'
```

**Code not syncing?**
```bash
# Manual sync
oc rsync ./workspace/ ml-dev-env-0:/workspace/ -n nccl-test
```

## 🔧 Create Your Own Cluster Config

Want to deploy to a new cluster? Copy the template:

```bash
# 1. Copy template
cp clusters/template.yaml clusters/my-cluster.yaml

# 2. Edit configuration
vim clusters/my-cluster.yaml
# Update nodes, storage classes, RDMA devices, etc.

# 3. Deploy
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

See [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) for details.

## 📚 Learn More

- **Cluster Configuration:** [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md)
- **RDMA Details:** [MULTI-NODE-GUIDE.md](MULTI-NODE-GUIDE.md)
- **TCP Mode:** [MULTI-NODE-TCP-GUIDE.md](MULTI-NODE-TCP-GUIDE.md)

## ✅ Summary

**List clusters:** `make list-clusters`

**Deploy:** `make deploy-cluster CLUSTER=barcelona MODE=rdma`

**Sync:** `make sync-multi-node`

**Train:** `make shell-multi-node` → `./launch_deepspeed.sh`

**Monitor:** `oc logs -f ml-dev-env-0`

You have multi-node GPU training ready! 🚀
