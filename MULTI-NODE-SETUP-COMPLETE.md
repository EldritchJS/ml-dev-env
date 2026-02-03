# ✅ Multi-Node DeepSpeed Setup Complete!

You now have a complete multi-node distributed training environment for 16 H100 GPUs.

## 📦 What Was Created

### 1. Multi-Node Configuration Files

**`statefulset-multi-node.yaml`**
- StatefulSet with 4 replicas (one pod per node)
- Headless service for pod-to-pod communication
- Anti-affinity rules to spread pods across nodes
- NCCL environment for RDMA (mlx5_6,7,10,11)
- Shared PVC across all pods
- Auto-generated hostfile

### 2. DeepSpeed Configuration

**`workspace/ds_config.json`**
- ZeRO-2 optimization for model parallelism
- FP16 mixed precision training
- Gradient clipping and accumulation
- Optimized for 16 GPUs

### 3. Training Scripts

**`workspace/train_multi_node.py`**
- Example multi-node training script
- Automatic rank calculation
- NCCL communication test
- Works with DeepSpeed launcher

**`workspace/launch_deepspeed.sh`**
- DeepSpeed launcher for multi-node
- Hostfile-based pod discovery
- Connectivity verification
- Error handling

### 4. Deployment & Management Scripts

**`scripts/deploy-multi-node.sh`**
- Deploy 4-node StatefulSet
- Create headless service
- Verify prerequisites

**`scripts/sync-multi-node.sh`**
- Sync code to all 4 nodes simultaneously
- Exclude unnecessary files
- Show sync status per node

### 5. Makefile Commands

```bash
make deploy-multi-node   # Deploy 4-node cluster
make sync-multi-node     # Sync code to all nodes
make shell-multi-node    # Shell into master (pod-0)
make status-multi-node   # Show deployment status
make clean-multi-node    # Remove multi-node deployment
```

### 6. Documentation

**`MULTI-NODE-QUICKSTART.md`**
- 5-minute quick start guide
- Common commands
- Quick debugging tips

**`MULTI-NODE-GUIDE.md`**
- Complete multi-node guide
- Architecture overview
- Detailed troubleshooting
- Advanced topics

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  ml-dev-env-headless Service                │
│             (Pod discovery and communication)               │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
┌─────────▼────────┐ ┌────────▼───────┐ ┌────────▼───────┐ ┌────────────────┐
│  ml-dev-env-0    │ │ ml-dev-env-1   │ │ ml-dev-env-2   │ │ ml-dev-env-3   │
│  (Master)        │ │                │ │                │ │                │
│ ┌──────────────┐ │ │ ┌────────────┐ │ │ ┌────────────┐ │ │ ┌────────────┐ │
│ │ Rank 0-3     │ │ │ │ Rank 4-7   │ │ │ │ Rank 8-11  │ │ │ │ Rank 12-15 │ │
│ │ 4x H100 GPUs │ │ │ │ 4x H100    │ │ │ │ 4x H100    │ │ │ │ 4x H100    │ │
│ └──────────────┘ │ │ └────────────┘ │ │ └────────────┘ │ │ └────────────┘ │
│                  │ │                │ │                │ │                │
│ Node:            │ │ Node:          │ │ Node:          │ │ Node:          │
│ moc-r4pcc04u17   │ │ moc-r4pcc04u18 │ │ moc-r4pcc04u23 │ │ moc-r4pcc04u25 │
└──────────────────┘ └────────────────┘ └────────────────┘ └────────────────┘
          │                   │                   │                   │
          └───────────────────┴───────────────────┴───────────────────┘
                         RoCE RDMA Network
                  (mlx5_6,7,10,11 on net1-4)
                    NCCL All-Reduce/Broadcast
```

## 🚀 Quick Start

### 1. Deploy (First Time)

```bash
make deploy-multi-node
```

Wait for all pods:
```bash
oc get pods -n nccl-test -l app=ml-dev-env-multi -w
```

### 2. Sync Code

```bash
make sync-multi-node
```

### 3. Run Training

```bash
# Shell into master
make shell-multi-node

# Inside pod-0:
cd /workspace
./launch_deepspeed.sh train_multi_node.py
```

### 4. Monitor

```bash
oc logs -f ml-dev-env-0 -n nccl-test
```

## 🎓 Run Your Own Model

### Create Training Script

```python
# workspace/my_training.py
import os
import torch
import deepspeed

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--local_rank', type=int, default=0)
    parser = deepspeed.add_config_arguments(parser)
    args = parser.parse_args()

    # Get rank info
    NODE_RANK = int(os.environ['NODE_RANK'])
    LOCAL_RANK = int(os.environ['LOCAL_RANK'])
    GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK

    # Initialize
    deepspeed.init_distributed()

    # Your model
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

if __name__ == "__main__":
    main()
```

### Deploy

```bash
# Edit locally
code workspace/my_training.py

# Sync to all nodes
make sync-multi-node

# Run on 16 GPUs
make shell-multi-node
# Then: cd /workspace && ./launch_deepspeed.sh my_training.py
```

## 📊 Key Features

### Automatic Rank Calculation
```python
NODE_RANK = int(os.environ['NODE_RANK'])    # 0-3 (from pod ordinal)
LOCAL_RANK = int(os.environ['LOCAL_RANK'])  # 0-3 (from DeepSpeed)
GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK    # 0-15 (unique across all GPUs)
```

### Shared Storage
All pods mount the same `/workspace` PVC:
- Code is shared across all nodes
- Checkpoints saved once, accessible by all
- Single source of truth for data

### RDMA Networking
```bash
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_SOCKET_IFNAME=net1,net2,net3,net4
NCCL_IB_DISABLE=0
NCCL_NET_GDR_LEVEL=5
```

### DeepSpeed ZeRO
```json
{
  "zero_optimization": {
    "stage": 2,  // Can use stage 3 for larger models
    "offload_optimizer": {"device": "none"},
    "overlap_comm": true
  }
}
```

## 🔍 Comparison: Single vs Multi-Node

| Feature | Single-Node | Multi-Node |
|---------|-------------|------------|
| **GPUs** | 4 H100s | 16 H100s (4 nodes) |
| **Deploy** | `make deploy` | `make deploy-multi-node` |
| **Pod count** | 1 | 4 (StatefulSet) |
| **Sync** | `make sync-code` | `make sync-multi-node` |
| **Shell** | `make shell` | `make shell-multi-node` |
| **Best for** | Development, debugging | Large model training |
| **Network** | N/A (single node) | NCCL over RDMA |
| **Launcher** | Direct Python | DeepSpeed launcher |

## 📚 Documentation

- **Quick start:** [MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md)
- **Full guide:** [MULTI-NODE-GUIDE.md](MULTI-NODE-GUIDE.md)
- **DeepSpeed config:** [workspace/ds_config.json](workspace/ds_config.json)
- **Example training:** [workspace/train_multi_node.py](workspace/train_multi_node.py)

## 🛠️ Troubleshooting Quick Reference

**Pods not starting:**
```bash
oc describe pod ml-dev-env-0 -n nccl-test | tail -20
```

**Check connectivity:**
```bash
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
for i in {1..3}; do ping -c 1 ml-dev-env-$i.ml-dev-env-headless.nccl-test.svc.cluster.local; done
'
```

**Test NCCL:**
```bash
make shell-multi-node
# Then run the example training script
```

**Sync issues:**
```bash
# Manual sync to specific pod
oc rsync ./workspace/ ml-dev-env-0:/workspace/ -n nccl-test
```

## ✅ What's Next?

1. **Deploy your first multi-node job:**
   ```bash
   make deploy-multi-node
   make sync-multi-node
   make shell-multi-node
   # ./launch_deepspeed.sh train_multi_node.py
   ```

2. **Adapt the example for your model:**
   - Edit `workspace/train_multi_node.py`
   - Modify `workspace/ds_config.json` for your batch size
   - Sync and run!

3. **Monitor and optimize:**
   - Watch GPU utilization across nodes
   - Tune batch size and ZeRO stage
   - Profile with TensorBoard

## 🎉 Summary

You now have:
- ✅ 16 H100 GPUs ready for distributed training
- ✅ DeepSpeed with ZeRO-2 optimization
- ✅ NCCL over RDMA for fast inter-node communication
- ✅ Automatic hostfile generation
- ✅ Code sync to all nodes
- ✅ Complete documentation and examples

**Start training on 16 GPUs right now:**
```bash
make deploy-multi-node && make sync-multi-node && make shell-multi-node
```

Happy training! 🚀
