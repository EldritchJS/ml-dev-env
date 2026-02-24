# Multi-Node DeepSpeed Training Guide

Train ML models on **multiple H100 GPUs across nodes** using DeepSpeed with RDMA/RoCE networking or TCP fallback.

> **💡 TIP:** For quickest deployment, see **[MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md)** first.

## 🎯 Overview

This guide covers multi-node distributed training using the **cluster configuration system** for easy deployment.

**Key Features:**

- ✅ Cluster-based deployment (all settings in one file)
- ✅ RDMA mode for high-performance NCCL communication
- ✅ TCP mode for universal compatibility
- ✅ StatefulSet ensures one pod per node
- ✅ Headless service for pod-to-pod DNS
- ✅ DeepSpeed ZeRO-2/3 optimization
- ✅ Shared workspace (when RWX storage available)

## 🚀 Quick Start

### Step 1: Choose Your Cluster

```bash
# List configured clusters
make list-clusters
```

Example clusters:

- **barcelona** - NERC Barcelona cluster (RDMA + per-pod storage)
- **nerc-production** - NERC Production cluster (TCP + RWX storage)

### Step 2: Deploy Multi-Node Environment

**Option A: Use RDMA (High Performance - Barcelona only)**

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

**Option B: Use TCP (Universal Compatibility)**

```bash
# Barcelona with TCP
make deploy-cluster CLUSTER=barcelona MODE=tcp

# NERC Production (TCP only, no RDMA)
make deploy-cluster CLUSTER=nerc-production MODE=tcp
```

### Step 3: Wait for Pods

```bash
# Watch pods come up
oc get pods -n nccl-test -l app=ml-dev-env-multi -w

# Should see (example for 2-node deployment):
# ml-dev-env-0   1/1     Running   0          2m
# ml-dev-env-1   1/1     Running   0          2m
```

### Step 4: Sync Code to All Nodes

```bash
make sync-multi-node
```

### Step 5: Run Training

```bash
# Shell into master node (pod-0)
oc exec -it ml-dev-env-0 -n nccl-test -- bash

# Inside pod-0:
cd /workspace
./launch_deepspeed.sh train_multi_node.py
```

## 📋 Architecture

### With Cluster Configuration System

The cluster config defines:

- **Nodes**: Which GPU nodes to use
- **Storage**: RWX shared storage or per-pod volumes
- **Network**: RDMA devices or TCP interfaces
- **Security**: Privileged SCC if needed for IPC_LOCK
- **Resources**: GPU count, memory, CPU per pod

Example architecture (Barcelona cluster, 2 nodes):

```
ml-dev-env-0  (moc-r4pcc04u25-nairr)  - Rank 0-3   (Master)
ml-dev-env-1  (moc-r4pcc04u23-nairr)  - Rank 4-7

Total: 8 H100 GPUs with RDMA over mlx5_6,7,10,11
```

### Deployment Components

```
┌─────────────────────────────────────────────┐
│  Headless Service (ml-dev-env-headless)    │
│  - DNS: ml-dev-env-0.ml-dev-env-headless   │
│  - DNS: ml-dev-env-1.ml-dev-env-headless   │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
┌───────▼────────┐    ┌────────▼────────┐
│ ml-dev-env-0   │    │ ml-dev-env-1    │
│ (Master)       │    │ (Worker)        │
│ - 4 H100 GPUs  │    │ - 4 H100 GPUs   │
│ - Rank 0-3     │    │ - Rank 4-7      │
│ - /workspace   │◄───►│ - /workspace    │
└────────────────┘    └─────────────────┘
        │                       │
        └───────────┬───────────┘
                    │
        ┌───────────▼───────────┐
        │  Shared PVC (if RWX)  │
        │  or Per-Pod Volumes   │
        └───────────────────────┘
```

## 🌐 Networking Modes

### RDMA Mode (Recommended for Performance)

**Requirements:**

- InfiniBand adapters (mlx5_*)
- RDMA-capable network
- Cluster config with RDMA devices specified

**Features:**

- GPUDirect RDMA for GPU-to-GPU transfers
- Lower latency, higher bandwidth
- NCCL over InfiniBand

**Configuration** (in cluster YAML):

```yaml
network:
  rdma:
    enabled: true
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"  # GPUDirect RDMA
```

**Deploy:**

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

### TCP Mode (Fallback Option)

**Use when:**

- RDMA is unavailable or not configured
- Standard Ethernet networking only
- Troubleshooting RDMA issues

**Features:**

- No special hardware needed
- TCP/IP for inter-node communication
- Slightly lower performance than RDMA

**Configuration** (in cluster YAML):

```yaml
network:
  tcp:
    interface_exclude: "^lo,docker0"
    p2p_level: "NVL"  # NVLink intra-node, TCP inter-node
```

**Deploy:**

```bash
# TCP fallback (works on any cluster)
make deploy-cluster CLUSTER=barcelona MODE=tcp
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

## 💾 Storage Modes

### Shared RWX Storage (Preferred)

**When available:**

- Uses ReadWriteMany PVC
- All pods share `/workspace` and `/datasets`
- Files immediately visible across nodes
- Ideal for collaborative workloads

**Configuration** (in cluster YAML):

```yaml
storage:
  mode: rwx
  class_rwx: nfs-csi
  workspace_size: 100Gi
  datasets_size: 500Gi
```

### Per-Pod Storage (Fallback)

**When RWX unavailable:**

- Each pod gets own volume via volumeClaimTemplates
- Manual file sync required between pods
- Works on any cluster

**Configuration** (in cluster YAML):

```yaml
storage:
  mode: volumeClaimTemplates
  class_rwo: ceph-rbd
  workspace_size: 100Gi
```

## 🔧 Creating Cluster Configurations

### Using a Template

```bash
# 1. Copy template
cp clusters/template.yaml clusters/my-cluster.yaml

# 2. Edit configuration
vim clusters/my-cluster.yaml
```

### Example Configuration

```yaml
cluster:
  name: my-cluster
  api: api.my-cluster.example.com
  namespace: nccl-test

nodes:
  gpu_nodes:
    - gpu-node-1
    - gpu-node-2

storage:
  mode: rwx
  class_rwx: nfs-csi
  workspace_size: 100Gi

network:
  rdma:
    enabled: true
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"

security:
  service_account: ml-dev-sa
  requires_privileged_scc: true
  ipc_lock: true

gpus:
  per_node: 4
  default_nodes: 2
```

### Deploy Custom Cluster

```bash
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

See [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) for complete details.

## 🎓 DeepSpeed Training

### Example Training Script

```python
# workspace/train_multi_node.py
import os
import torch
import deepspeed
from torch.utils.data import DataLoader, Dataset

def main():
    # Parse arguments
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--local_rank', type=int, default=0)
    parser = deepspeed.add_config_arguments(parser)
    args = parser.parse_args()

    # Get distributed info
    NODE_RANK = int(os.environ.get('NODE_RANK', 0))
    LOCAL_RANK = int(os.environ.get('LOCAL_RANK', 0))
    GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK
    WORLD_SIZE = int(os.environ.get('WORLD_SIZE', 8))

    print(f"[Rank {GLOBAL_RANK}] Node {NODE_RANK}, Local Rank {LOCAL_RANK}")

    # Initialize DeepSpeed
    deepspeed.init_distributed()

    # Your model
    model = YourModel()

    # DeepSpeed engine
    model_engine, optimizer, train_loader, _ = deepspeed.initialize(
        args=args,
        model=model,
        model_parameters=model.parameters(),
        training_data=your_dataset
    )

    # Training loop
    for epoch in range(args.epochs):
        for batch in train_loader:
            loss = model_engine(batch)
            model_engine.backward(loss)
            model_engine.step()

        if GLOBAL_RANK == 0:
            print(f"Epoch {epoch} complete")

    if GLOBAL_RANK == 0:
        print("Training done!")

if __name__ == "__main__":
    main()
```

### DeepSpeed Configuration

```json
{
  "train_batch_size": 32,
  "train_micro_batch_size_per_gpu": 4,
  "gradient_accumulation_steps": 2,
  "optimizer": {
    "type": "Adam",
    "params": {
      "lr": 3e-4
    }
  },
  "fp16": {
    "enabled": true
  },
  "zero_optimization": {
    "stage": 2,
    "offload_optimizer": {
      "device": "cpu"
    }
  }
}
```

### Launch Script

```bash
#!/bin/bash
# workspace/launch_deepspeed.sh

SCRIPT=${1:-train_multi_node.py}

deepspeed \
  --num_nodes=$WORLD_SIZE \
  --num_gpus=$GPUS_PER_NODE \
  --master_addr=ml-dev-env-0.ml-dev-env-headless \
  --master_port=29500 \
  --node_rank=$NODE_RANK \
  --hostfile=/workspace/hostfile \
  $SCRIPT \
  --deepspeed_config=/workspace/ds_config.json
```

## 📊 Monitoring

### Check Pod Status

```bash
# Via Make
make status-cluster CLUSTER=barcelona

# Via oc
oc get pods -n nccl-test -l app=ml-dev-env-multi -o wide
```

### Follow Training Logs

```bash
# Master node
oc logs -f ml-dev-env-0 -n nccl-test

# All nodes
for i in 0 1; do
  echo "=== Node $i ==="
  oc logs --tail=20 ml-dev-env-$i -n nccl-test
done
```

### GPU Monitoring

```bash
# Watch GPU usage on all nodes
for i in 0 1; do
  echo "=== Node $i ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi
done
```

### NCCL Performance Testing

```bash
# Test NCCL bandwidth
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
cd /workspace
mpirun -n 8 \
  --allow-run-as-root \
  --hostfile hostfile \
  /usr/local/cuda/bin/nccl-tests/all_reduce_perf -b 8 -e 128M -f 2 -g 1
'
```

## 🔄 Development Workflow

### 1. Edit Code Locally

```bash
# Edit on your local machine
vim workspace/train_multi_node.py
```

### 2. Sync to Pods

```bash
# Sync to all pods
make sync-multi-node

# Or manually
./scripts/sync-multi-node.sh
```

### 3. Run Training

```bash
# Shell into master
make shell-multi-node

# Run training
cd /workspace
./launch_deepspeed.sh train_multi_node.py
```

### 4. Monitor and Iterate

```bash
# Monitor logs
oc logs -f ml-dev-env-0 -n nccl-test

# Make changes, sync again
make sync-multi-node
```

## 🐛 Troubleshooting

### Pods Not Starting

```bash
# Check pod events
oc describe pod ml-dev-env-0 -n nccl-test

# Check StatefulSet status
oc get statefulset ml-dev-env -n nccl-test

# Check node affinity
oc get pods -n nccl-test -o wide
```

### NCCL Initialization Hangs

```bash
# Test NCCL on master
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
python3 -c "
import torch
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\")
print(\"NCCL initialized successfully!\")
"
'

# Check RDMA devices (if using RDMA)
oc exec ml-dev-env-0 -n nccl-test -- ibstat

# Check DNS resolution
oc exec ml-dev-env-0 -n nccl-test -- ping -c 3 ml-dev-env-1.ml-dev-env-headless
```

### Storage Issues

```bash
# Check PVCs
oc get pvc -n nccl-test

# For RWX mode - verify shared storage
oc exec ml-dev-env-0 -n nccl-test -- touch /workspace/test
oc exec ml-dev-env-1 -n nccl-test -- ls -la /workspace/test

# Check storage class
oc get storageclass
```

### Security/Permissions Errors

```bash
# Check ServiceAccount
oc get sa ml-dev-sa -n nccl-test

# Check SCC
oc describe scc privileged | grep -A 10 Users

# Check pod security context
oc get pod ml-dev-env-0 -n nccl-test -o yaml | grep -A 10 securityContext
```

## 🧹 Cleanup

### Remove Deployment

```bash
# Via Make
make clean-cluster CLUSTER=barcelona

# Manual cleanup
oc delete statefulset ml-dev-env -n nccl-test
oc delete service ml-dev-env-headless -n nccl-test
oc delete serviceaccount ml-dev-sa -n nccl-test
```

### Preserve PVCs

PVCs are not deleted by default. To remove them:

```bash
# For RWX storage
oc delete pvc ml-dev-workspace ml-datasets -n nccl-test

# For per-pod storage
oc delete pvc -l app=ml-dev-env-multi -n nccl-test
```

## 📚 Additional Resources

### Documentation

- [MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md) - Quick 5-minute setup
- [MULTI-NODE-TCP-GUIDE.md](MULTI-NODE-TCP-GUIDE.md) - TCP mode details
- [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) - Cluster configuration

### External Resources

- [DeepSpeed Documentation](https://www.deepspeed.ai/)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [PyTorch Distributed Training](https://pytorch.org/tutorials/beginner/dist_overview.html)

## ✅ Summary

**Deploy:**

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

**Sync Code:**

```bash
make sync-multi-node
```

**Run Training:**

```bash
make shell-multi-node
cd /workspace && ./launch_deepspeed.sh
```

**Monitor:**

```bash
oc logs -f ml-dev-env-0 -n nccl-test
```

**Cleanup:**

```bash
make clean-cluster CLUSTER=barcelona
```

Happy distributed training! 🚀
