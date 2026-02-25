# Yunshi Deployment - Quick Start

Multi-node Time Series Foundation Model (TSFM) training with RDMA/InfiniBand on OpenShift.

## 🚀 Quick Deploy (3 Steps)

### 1. Deploy the StatefulSet

```bash
cd deployments/yunshi
oc apply -f generated/statefulset-yunshi.yaml
```

Wait for pods to start:
```bash
oc get pods -l app=tsfm-ddp -w
```

Expected output:
```
NAME          READY   STATUS    RESTARTS   AGE
tsfm-node-0   1/1     Running   0          2m
tsfm-node-1   1/1     Running   0          2m
```

### 2. Verify Training Started

```bash
# Check logs from both nodes
oc logs tsfm-node-0 --tail=50
oc logs tsfm-node-1 --tail=50
```

Look for:
```
✅ "I am Node Rank: 0" or "I am Node Rank: 1"
✅ "Master Addr: tsfm-node-0.tsfm-headless"
✅ "Starting DDP Training..."
✅ NCCL initialization messages
```

### 3. Monitor Progress

```bash
# Follow training logs
oc logs -f tsfm-node-0

# Check GPU utilization
oc exec tsfm-node-0 -- nvidia-smi
```

---

## 📦 Deployment Variants

### Standard Training (Default)
```bash
oc apply -f generated/statefulset-yunshi.yaml
```
- 2 nodes, 8 GPUs total
- Basic configuration
- Good for testing

### Large Zero-Shot Training
```bash
oc apply -f generated/large_zero_shot_rdma.yaml
```
- Enhanced affinity rules
- Optimized for large-scale zero-shot learning
- Production configuration

### Jupyter Development Environment
```bash
oc apply -f generated/jupyter.yaml
```
- Interactive notebook access
- Development and debugging
- Exploratory analysis

---

## 🔧 Common Tasks

### View Training Logs

```bash
# Node 0 logs
oc logs -f tsfm-node-0

# Node 1 logs
oc logs -f tsfm-node-1

# Last 100 lines from both
oc logs tsfm-node-0 --tail=100
oc logs tsfm-node-1 --tail=100
```

### Check Training Status

```bash
# Pod status
oc get pods -l app=tsfm-ddp

# Detailed pod info
oc describe pod tsfm-node-0

# Check training step
oc logs tsfm-node-0 | grep "Step:"
```

### Access Storage

```bash
# List checkpoints
oc exec tsfm-node-0 -- ls -lh /mnt/tsfm/checkpoints/

# List datasets
oc exec tsfm-node-0 -- ls -lh /mnt/tsfm/data/

# Check storage usage
oc exec tsfm-node-0 -- df -h /mnt/tsfm
```

### Shell into Pods

```bash
# Interactive shell on node 0
oc exec -it tsfm-node-0 -- bash

# Interactive shell on node 1
oc exec -it tsfm-node-1 -- bash

# Run command on node 0
oc exec tsfm-node-0 -- nvidia-smi
```

### Stop Training

```bash
# Delete StatefulSet (keeps data)
oc delete statefulset tsfm-node

# Delete service and StatefulSet
oc delete -f generated/statefulset-yunshi.yaml

# Verify deletion
oc get pods -l app=tsfm-ddp
```

---

## 🧪 Verify RDMA Configuration

### Check InfiniBand Devices

```bash
# List IB devices
oc exec tsfm-node-0 -- ls -la /sys/class/infiniband/

# Check device info
oc exec tsfm-node-0 -- ibv_devices

# Verify all 4 devices
oc exec tsfm-node-0 -- ibstat
```

Expected devices: `mlx5_6`, `mlx5_7`, `mlx5_10`, `mlx5_11`

### Check NCCL Configuration

```bash
# View NCCL environment
oc exec tsfm-node-0 -- env | grep NCCL

# Check NCCL initialization in logs
oc logs tsfm-node-0 | grep NCCL
```

Expected:
```
NCCL_IB_DISABLE=0
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_IB_GID_INDEX=3
NCCL_NET_GDR_LEVEL=5
```

### Verify GPU Access

```bash
# Check GPU visibility
oc exec tsfm-node-0 -- nvidia-smi

# Verify 4 GPUs visible
oc exec tsfm-node-0 -- python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"
```

---

## 📊 Monitor Training

### Training Metrics

```bash
# Watch training progress
oc logs -f tsfm-node-0 | grep -E "Step|Loss|GPU"

# Check learning rate
oc logs tsfm-node-0 | grep "lr:"

# Monitor memory usage
oc exec tsfm-node-0 -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

### System Metrics

```bash
# CPU/Memory usage
oc exec tsfm-node-0 -- top -b -n 1 | head -20

# GPU utilization
oc exec tsfm-node-0 -- nvidia-smi dmon -c 10

# Network usage
oc exec tsfm-node-0 -- ifconfig
```

### Checkpoints

```bash
# List saved checkpoints
oc exec tsfm-node-0 -- ls -lh /mnt/tsfm/checkpoints/

# Check latest checkpoint
oc exec tsfm-node-0 -- ls -lt /mnt/tsfm/checkpoints/ | head

# View checkpoint size
oc exec tsfm-node-0 -- du -sh /mnt/tsfm/checkpoints/*
```

---

## 🔧 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
oc describe pod tsfm-node-0

# Check events
oc get events --sort-by='.lastTimestamp' | grep tsfm

# Common issues:
# - PVC not bound: oc get pvc tsfm
# - Node capacity: oc describe node moc-r4pcc02u15-yunshi
# - GPU quota: check resource limits
```

### Training Not Initializing

```bash
# Check both pods started
oc get pods -l app=tsfm-ddp

# Verify rendezvous
oc exec tsfm-node-0 -- nslookup tsfm-headless
oc exec tsfm-node-1 -- nslookup tsfm-headless

# Check node rank assignment
oc logs tsfm-node-0 | grep "Node Rank"
oc logs tsfm-node-1 | grep "Node Rank"

# Should show:
# Node 0: "I am Node Rank: 0"
# Node 1: "I am Node Rank: 1"
```

### RDMA Not Working

```bash
# Check IB device allocation
oc exec tsfm-node-0 -- env | grep openshift.io/eno

# Verify NCCL sees IB devices
oc logs tsfm-node-0 | grep "Using.*mlx5"

# Check SR-IOV network attachments
oc describe pod tsfm-node-0 | grep -A10 "Networks"
```

### Training Errors

```bash
# Check for CUDA errors
oc logs tsfm-node-0 | grep -i "error\|fail"

# Check for OOM (Out of Memory)
oc logs tsfm-node-0 | grep -i "memory\|oom"

# Verify data paths
oc exec tsfm-node-0 -- ls -la /mnt/tsfm/data/
```

### Slow Training

```bash
# Check GPU utilization
oc exec tsfm-node-0 -- nvidia-smi dmon -c 5

# Should show high GPU utilization (>80%)

# Check NCCL bandwidth
oc logs tsfm-node-0 | grep "busbw"

# Verify RDMA is active
oc exec tsfm-node-0 -- cat /sys/class/infiniband/*/ports/*/state
# Should show: 4: ACTIVE
```

---

## 📝 Configuration

### Model Hyperparameters

Training is configured in the StatefulSet YAML:

```yaml
--context_length 8192
--d_model 1024
--n_head 16
--n_layer 20
--batch_size 64
--lr 3e-4
--precision "bf16"
```

To modify:
1. Edit `generated/statefulset-yunshi.yaml`
2. Find the `torchrun` command args
3. Update desired parameters
4. Reapply: `oc apply -f generated/statefulset-yunshi.yaml`
5. Delete old pods to restart: `oc delete pod tsfm-node-0 tsfm-node-1`

### Data Paths

Datasets are expected at:
```
/mnt/tsfm/data/GiftEval/
/mnt/tsfm/data/GiftPretrain/
/mnt/tsfm/data/kernel_synth_10M/
/mnt/tsfm/data/tsmixup/
/mnt/tsfm/data/tsmixup_v01/
```

Training code:
```
/mnt/tsfm/hybrid_tsfm/pretrain_hybrid.py
```

### Storage

Persistent volume claim: `tsfm`

```bash
# Check PVC
oc get pvc tsfm

# Check capacity
oc describe pvc tsfm

# Monitor usage
oc exec tsfm-node-0 -- df -h /mnt/tsfm
```

---

## 🎯 What You Get

### Hardware
- **2 nodes** (moc-r4pcc02u15-yunshi, moc-r4pcc02u16-yunshi)
- **4 GPUs per node** (8 total)
- **4 InfiniBand HCAs per node** (200 Gbps each)
- **1000Gi memory per node**
- **32 CPUs per node**

### Software
- **PyTorch 25.12** with CUDA support
- **NCCL** with InfiniBand support
- **DistributedDataParallel** (DDP)
- **GPUDirect RDMA** enabled
- **BF16 mixed precision**

### Performance
- **RDMA bandwidth**: 80+ GiB/s
- **GPU-to-GPU communication**: Direct via InfiniBand
- **Multi-node training**: Automatic coordination
- **Checkpointing**: Every 10,000 steps

---

## ⚡ Next Steps

1. **Monitor first training run** to verify everything works
2. **Adjust hyperparameters** based on initial results
3. **Set up TensorBoard** for visualization (if needed)
4. **Configure checkpointing** frequency
5. **Optimize data loading** (`--num_workers`, `--samples_per_read`)

For more details, see [README.md](README.md).

---

## 🆘 Getting Help

**Check logs:**
```bash
oc logs tsfm-node-0 --tail=100
```

**Interactive debugging:**
```bash
oc exec -it tsfm-node-0 -- bash
```

**View full configuration:**
```bash
cat generated/statefulset-yunshi.yaml
```

**Check resource usage:**
```bash
oc describe pod tsfm-node-0 | grep -A10 "Limits\|Requests"
```
