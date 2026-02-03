# Multi-Node DeepSpeed Training Guide

Train ML models on **4 nodes × 4 GPUs = 16 H100s** using DeepSpeed and RDMA/RoCE networking.

## 🎯 Overview

**Architecture:**
```
ml-dev-env-0  (Node: moc-r4pcc04u17)       - Rank 0-3   (Master)
ml-dev-env-1  (Node: moc-r4pcc04u18)       - Rank 4-7
ml-dev-env-2  (Node: moc-r4pcc04u23-nairr) - Rank 8-11
ml-dev-env-3  (Node: moc-r4pcc04u25-nairr) - Rank 12-15

Total: 16 H100 GPUs with RoCE RDMA interconnect
```

**Key Features:**
- ✅ StatefulSet ensures one pod per node
- ✅ Headless service for pod-to-pod communication
- ✅ DeepSpeed ZeRO-2 optimization
- ✅ NCCL over RDMA (mlx5_6,7,10,11 on net1-4)
- ✅ Shared PVC across all pods
- ✅ Automatic hostfile generation

## 🚀 Quick Start

### Step 1: Build the Image (if not done)

```bash
make build
```

### Step 2: Deploy Multi-Node Environment

```bash
./scripts/deploy-multi-node.sh
```

Or:

```bash
make deploy-multi-node
```

This creates:
- Headless service for pod discovery
- StatefulSet with 4 pods
- Hostfile for DeepSpeed

### Step 3: Wait for All Pods

```bash
# Watch pods come up
oc get pods -n nccl-test -l app=ml-dev-env-multi -w

# Should see:
# ml-dev-env-0   1/1     Running   0          2m
# ml-dev-env-1   1/1     Running   0          2m
# ml-dev-env-2   1/1     Running   0          2m
# ml-dev-env-3   1/1     Running   0          2m
```

### Step 4: Sync Your Code to All Nodes

```bash
./scripts/sync-multi-node.sh
```

This syncs `./workspace/` to all 4 pods.

### Step 5: Run Multi-Node Training

```bash
# Shell into master node (pod-0)
oc exec -it ml-dev-env-0 -n nccl-test -- bash

# Inside pod-0:
cd /workspace
./launch_deepspeed.sh train_multi_node.py
```

Training runs across all 16 GPUs! 🎉

## 📝 Detailed Workflow

### Deploy and Setup

```bash
# 1. Build image (one time)
make build

# 2. Deploy multi-node StatefulSet
make deploy-multi-node

# 3. Check all pods are running
oc get pods -n nccl-test -l app=ml-dev-env-multi

# 4. Check GPU allocation per pod
for i in {0..3}; do
  echo "=== ml-dev-env-$i ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi --query-gpu=name --format=csv,noheader
done
```

### Develop and Sync Code

```bash
# Edit code locally
code workspace/train_multi_node.py

# Sync to all nodes
make sync-multi-node

# Or sync specific directory
./scripts/sync-multi-node.sh ./my-code /workspace
```

### Run Distributed Training

**Option 1: Use launcher script (recommended)**

```bash
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh train_multi_node.py"
```

**Option 2: Manual DeepSpeed command**

```bash
oc exec -it ml-dev-env-0 -n nccl-test -- bash

# Inside pod-0:
deepspeed \
  --hostfile=/workspace/.deepspeed/hostfile \
  --master_addr=ml-dev-env-0.ml-dev-env-headless.nccl-test.svc.cluster.local \
  --master_port=29500 \
  /workspace/train_multi_node.py \
  --deepspeed \
  --deepspeed_config=/workspace/ds_config.json \
  --epochs=10
```

## 🔧 Configuration Files

### 1. DeepSpeed Config (`workspace/ds_config.json`)

```json
{
  "train_batch_size": 128,
  "train_micro_batch_size_per_gpu": 8,
  "gradient_accumulation_steps": 4,

  "fp16": {
    "enabled": true
  },

  "zero_optimization": {
    "stage": 2,
    "offload_optimizer": {
      "device": "none"
    },
    "allgather_partitions": true,
    "overlap_comm": true
  },

  "gradient_clipping": 1.0
}
```

**ZeRO Stages:**
- **Stage 0:** No optimization (baseline)
- **Stage 1:** Optimizer state partitioning
- **Stage 2:** Optimizer + gradient partitioning (recommended for 16 GPUs)
- **Stage 3:** Optimizer + gradient + parameter partitioning (for very large models)

### 2. Hostfile (auto-generated)

Located at `/workspace/.deepspeed/hostfile`:

```
ml-dev-env-0.ml-dev-env-headless.nccl-test.svc.cluster.local slots=4
ml-dev-env-1.ml-dev-env-headless.nccl-test.svc.cluster.local slots=4
ml-dev-env-2.ml-dev-env-headless.nccl-test.svc.cluster.local slots=4
ml-dev-env-3.ml-dev-env-headless.nccl-test.svc.cluster.local slots=4
```

## 🐛 Debugging Multi-Node

### Check Individual Pods

```bash
# Check pod status
oc get pods -n nccl-test -l app=ml-dev-env-multi -o wide

# Check logs for each pod
for i in {0..3}; do
  echo "=== ml-dev-env-$i logs ==="
  oc logs ml-dev-env-$i -n nccl-test --tail=20
done

# Shell into specific pod
oc exec -it ml-dev-env-2 -n nccl-test -- bash
```

### Test Network Connectivity

```bash
# From pod-0, ping other pods
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
for i in {1..3}; do
  echo "Pinging ml-dev-env-$i..."
  ping -c 1 ml-dev-env-$i.ml-dev-env-headless.nccl-test.svc.cluster.local
done
'
```

### Test NCCL Communication

```bash
# Run NCCL test across all nodes
oc exec -it ml-dev-env-0 -n nccl-test -- bash

# Inside pod:
cat > /tmp/test_nccl.py << 'EOF'
import torch
import torch.distributed as dist
import os

dist.init_process_group(backend="nccl")
rank = dist.get_rank()
world_size = dist.get_world_size()

print(f"Rank {rank}/{world_size} initialized")

# All-reduce test
tensor = torch.ones(1000, 1000, device='cuda') * rank
dist.all_reduce(tensor)

expected = sum(range(world_size)) * 1000 * 1000
actual = tensor.sum().item()

if abs(actual - expected) < 1e-5:
    print(f"✅ Rank {rank}: NCCL working! Sum: {actual}")
else:
    print(f"❌ Rank {rank}: NCCL failed. Expected {expected}, got {actual}")

dist.destroy_process_group()
EOF

deepspeed --hostfile=/workspace/.deepspeed/hostfile /tmp/test_nccl.py
```

### Check RDMA/RoCE

```bash
# Check InfiniBand devices on each node
for i in {0..3}; do
  echo "=== ml-dev-env-$i RDMA devices ==="
  oc exec ml-dev-env-$i -n nccl-test -- ibstat | grep -E "CA '|State:|Rate:"
done

# Check NCCL environment
oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL
```

## 📊 Monitoring Training

### Watch Training Logs

```bash
# Follow logs from master (pod-0)
oc logs -f ml-dev-env-0 -n nccl-test

# Follow logs from all pods
for i in {0..3}; do
  oc logs -f ml-dev-env-$i -n nccl-test &
done
# Ctrl+C to stop all
```

### Monitor GPU Usage

```bash
# GPU usage on all pods
for i in {0..3}; do
  echo "=== ml-dev-env-$i GPUs ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv
done
```

### Port-Forward for TensorBoard

```bash
# Port-forward from master pod
oc port-forward ml-dev-env-0 -n nccl-test 6006:6006

# Open http://localhost:6006
```

## 🎓 Example: Custom Training Script

```python
#!/usr/bin/env python3
import os
import torch
import deepspeed
from transformers import AutoModelForCausalLM, AutoTokenizer

def main():
    # DeepSpeed initialization
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--local_rank', type=int, default=0)
    parser = deepspeed.add_config_arguments(parser)
    args = parser.parse_args()

    # Get distributed info
    NODE_RANK = int(os.environ.get('NODE_RANK', 0))
    LOCAL_RANK = int(os.environ.get('LOCAL_RANK', 0))
    WORLD_SIZE = int(os.environ.get('WORLD_SIZE', 16))
    GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK

    # Initialize distributed
    deepspeed.init_distributed()

    if GLOBAL_RANK == 0:
        print(f"Training on {WORLD_SIZE} GPUs across 4 nodes")

    # Load model (example: small GPT-2)
    model = AutoModelForCausalLM.from_pretrained("gpt2")
    
    # Initialize DeepSpeed
    model_engine, optimizer, _, _ = deepspeed.initialize(
        args=args,
        model=model,
        model_parameters=model.parameters()
    )

    # Your training loop here
    for epoch in range(10):
        # ... training code ...
        pass

    if GLOBAL_RANK == 0:
        print("Training complete!")

if __name__ == "__main__":
    main()
```

Save as `workspace/my_training.py`, sync, and run:

```bash
make sync-multi-node
oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh my_training.py"
```

## 🛠️ Makefile Commands

```bash
# Deploy multi-node environment
make deploy-multi-node

# Sync code to all nodes
make sync-multi-node

# Shell into master (pod-0)
make shell-multi-node

# Clean up multi-node deployment
make clean-multi-node

# Check multi-node status
make status-multi-node
```

## 🔍 Troubleshooting

### Issue: Pods stuck in Pending

**Check:**
```bash
oc describe pod ml-dev-env-0 -n nccl-test | tail -20
```

**Common causes:**
- Not enough GPU nodes available
- PVC not bound
- Resource requests too high

**Fix:**
```bash
# Check available GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check PVC status
oc get pvc -n nccl-test

# Reduce replicas temporarily
oc scale statefulset ml-dev-env -n nccl-test --replicas=2
```

### Issue: Training hangs at initialization

**Cause:** Pods can't communicate

**Check:**
```bash
# Test connectivity from pod-0
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
  for i in {1..3}; do
    nc -zv ml-dev-env-$i.ml-dev-env-headless.nccl-test.svc.cluster.local 29500
  done
'
```

**Fix:** Ensure headless service is created:
```bash
oc get svc ml-dev-env-headless -n nccl-test
```

### Issue: NCCL timeout

**Cause:** RDMA/RoCE not working

**Check NCCL environment:**
```bash
oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL_IB
```

**Should show:**
```
NCCL_IB_DISABLE=0
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
```

**Test RDMA devices:**
```bash
oc exec ml-dev-env-0 -n nccl-test -- ibstat
```

### Issue: Out of memory

**Reduce batch size** in `ds_config.json`:
```json
{
  "train_micro_batch_size_per_gpu": 4,  // Was 8
  "gradient_accumulation_steps": 8      // Was 4
}
```

**Or use ZeRO-3** for larger models:
```json
{
  "zero_optimization": {
    "stage": 3,
    "offload_param": {
      "device": "cpu"  // Offload to CPU if needed
    }
  }
}
```

## 📚 Advanced Topics

### Custom Node Selection

Edit `statefulset-multi-node.yaml`:

```yaml
spec:
  template:
    spec:
      # Pin specific pods to specific nodes
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - moc-r4pcc04u17  # Your preferred nodes
                - moc-r4pcc04u18
```

### Different Number of Nodes

Change `replicas` in `statefulset-multi-node.yaml`:

```yaml
spec:
  replicas: 2  # Use only 2 nodes (8 GPUs)
```

Update WORLD_SIZE and hostfile accordingly.

### Mixed Precision Training

Already enabled in `ds_config.json`:

```json
{
  "fp16": {
    "enabled": true,
    "initial_scale_power": 16
  }
}
```

For H100s, consider **BF16** for better precision:

```json
{
  "bf16": {
    "enabled": true
  }
}
```

## 📖 Resources

- **DeepSpeed docs:** https://www.deepspeed.ai/
- **NCCL tuning:** https://docs.nvidia.com/deeplearning/nccl/user-guide/
- **PyTorch DDP:** https://pytorch.org/tutorials/intermediate/ddp_tutorial.html

## ✅ Summary

**Deploy:** `make deploy-multi-node`

**Sync code:** `make sync-multi-node`

**Train:** `oc exec -it ml-dev-env-0 -n nccl-test -- bash -c "cd /workspace && ./launch_deepspeed.sh"`

**Monitor:** `oc logs -f ml-dev-env-0 -n nccl-test`

You now have 16 H100 GPUs ready for distributed training! 🚀
