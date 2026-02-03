# Multi-Node Quick Start

Train on **16 H100 GPUs** (4 nodes × 4 GPUs) in 5 minutes.

## 🚀 5-Minute Setup

```bash
# 1. Build image (if not done)
make build

# 2. Deploy 4-node cluster
make deploy-multi-node

# 3. Wait for pods (2-3 minutes)
oc get pods -n nccl-test -l app=ml-dev-env-multi -w
# Wait until all show: 1/1 Running

# 4. Sync code to all nodes
make sync-multi-node

# 5. Run distributed training
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh"
```

**That's it!** Training runs on 16 H100s with RDMA.

## 📋 What Just Happened?

1. **Deployed 4 pods** (one per node):
   - `ml-dev-env-0` on `moc-r4pcc04u17` (master)
   - `ml-dev-env-1` on `moc-r4pcc04u18`
   - `ml-dev-env-2` on `moc-r4pcc04u23-nairr`
   - `ml-dev-env-3` on `moc-r4pcc04u25-nairr`

2. **Each pod has**:
   - 4 H100 GPUs
   - Access to shared `/workspace` PVC
   - RoCE RDMA networking (mlx5_6,7,10,11)

3. **DeepSpeed launched**:
   - ZeRO-2 optimization
   - FP16 mixed precision
   - NCCL over RDMA for inter-node comm

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
for i in {0..3}; do
  echo "=== Node $i ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv
done

# Check pod status
make status-multi-node
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
make status-multi-node

# Clean up
make clean-multi-node
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

## 📚 Learn More

- **Full guide:** `MULTI-NODE-GUIDE.md`
- **DeepSpeed config:** `workspace/ds_config.json`
- **Example training:** `workspace/train_multi_node.py`

## ✅ Summary

**Deploy:** `make deploy-multi-node`

**Sync:** `make sync-multi-node`

**Train:** `make shell-multi-node` → `./launch_deepspeed.sh`

**Monitor:** `oc logs -f ml-dev-env-0`

You have 16 H100 GPUs ready! 🚀
