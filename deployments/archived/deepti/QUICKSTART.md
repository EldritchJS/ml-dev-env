# Deepti Deployment - Quick Start

Qwen2.5-Omni multimodal model testing and multi-node distributed training on OpenShift NERC production cluster.

> **For general VSCode setup, debugging, and development workflows, see the main documentation:**
> - **[QUICKSTART.md](../../docs/QUICKSTART.md)** - General quickstart guide
> - **[QUICK-DEV-GUIDE.md](../../docs/QUICK-DEV-GUIDE.md)** - Makefile development workflow
> - **[REMOTE-DEBUG-WALKTHROUGH.md](../../docs/REMOTE-DEBUG-WALKTHROUGH.md)** - VSCode debugging tutorial
> - **[VSCODE-DEBUG-GUIDE.md](../../docs/VSCODE-DEBUG-GUIDE.md)** - Complete debugging guide

## 🚀 Quick Deploy (2 Steps)

### 1. Deploy Test Pod

**NERC Production Cluster:**
```bash
cd deployments/deepti
oc apply -f generated/pod-deepti-nerc.yaml
```

### 2. Monitor Test Execution

```bash
# Watch pod start
oc get pod deepti-test -w

# View test logs
oc logs -f deepti-test
```

Expected output:
```
✅ ffmpeg works
✅ Model + processor loaded
✅ Multimodal generation successful
```

---

## 📦 Deployment Options

### Using Deploy Script

**NERC (automated):**
```bash
./scripts/deploy-deepti-nerc.sh
```

### Different PyTorch Versions

**PyTorch 2.9:**
```bash
oc apply -f generated/pod-deepti-nerc-pytorch29.yaml
```

**Latest stable:**
```bash
oc apply -f generated/pod-deepti-nerc.yaml
```

---

## 🔧 Common Tasks

### View Test Results

```bash
# Live log following
oc logs -f deepti-test

# Last 50 lines
oc logs deepti-test --tail=50

# Search for errors
oc logs deepti-test | grep -i error
```

### Check Pod Status

```bash
# Pod info
oc get pod deepti-test

# Detailed status
oc describe pod deepti-test

# Check GPU allocation
oc describe pod deepti-test | grep -A5 "Limits\|Requests"
```

### Access Pod Shell

```bash
# Interactive shell
oc exec -it deepti-test -- bash

# Check GPUs
oc exec deepti-test -- nvidia-smi

# Verify PyTorch
oc exec deepti-test -- python -c "import torch; print(f'PyTorch {torch.__version__}, GPUs: {torch.cuda.device_count()}')"
```

### Run Tests Manually

```bash
# Shell into pod
oc exec -it deepti-test -- bash

# Run full test
cd /workspace
python deepti.py

# Run simple test
python deepti-simple.py
```

---

## 🔗 Multi-Node Distributed Training

### Quick Setup for 2-Node Training

**1. Create headless service:**
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: deepti-train-svc
spec:
  clusterIP: None
  selector:
    app: deepti-train
  ports:
  - port: 29500
    name: nccl
EOF
```

**2. Deploy master node (rank 0):**
```bash
# Modify pod-deepti-nerc.yaml:
# - name: deepti-train-0
# - hostname: deepti-train-0
# - subdomain: deepti-train-svc
# - labels: app: deepti-train
# - command: run torchrun with --node_rank=0

oc apply -f deepti-train-0.yaml
```

**3. Deploy worker node (rank 1):**
```bash
# Similar to master but with --node_rank=1
oc apply -f deepti-train-1.yaml
```

**4. Monitor training:**
```bash
# Watch logs from master
oc logs -f deepti-train-0

# Watch logs from worker
oc logs -f deepti-train-1
```

### NCCL Environment Variables

Set these in your pod spec for multi-node training:

```yaml
env:
- name: NCCL_DEBUG
  value: "INFO"
- name: NCCL_IB_DISABLE
  value: "1"              # No RDMA on NERC
- name: NCCL_SOCKET_IFNAME
  value: "eth0"           # TCP networking
- name: NCCL_P2P_LEVEL
  value: "NVL"
- name: NCCL_NET_GDR_LEVEL
  value: "0"
```

### Training Command Example

```bash
# Inside pod, run:
torchrun \
  --nnodes=2 \
  --nproc_per_node=4 \
  --node_rank=0 \
  --master_addr=deepti-train-0.deepti-train-svc \
  --master_port=29500 \
  train.py
```

---

## 🧪 Test Scripts

### deepti.py - Full Multimodal Test

Complete test pipeline:
1. Creates dummy video with ffmpeg
2. Loads Qwen2.5-Omni-7B
3. Enables Flash Attention 2
4. Processes video + text prompt
5. Generates multimodal response

**Run manually:**
```bash
oc exec -it deepti-test -- python /workspace/deepti.py
```

### deepti-simple.py - Quick Validation

Simplified test for rapid iteration.

**Run manually:**
```bash
oc exec -it deepti-test -- python /workspace/deepti-simple.py
```

---

## 🔍 Verify Configuration

### Check GPU Access

```bash
# GPU count
oc exec deepti-test -- nvidia-smi --list-gpus

# GPU utilization
oc exec deepti-test -- nvidia-smi

# CUDA version
oc exec deepti-test -- nvcc --version
```

Expected: 4 GPUs visible per node

### Verify Flash Attention

```bash
# Check installation
oc exec deepti-test -- python -c "import flash_attn; print(f'Flash Attention {flash_attn.__version__}')"

# Test compatibility
oc exec deepti-test -- python -c "import torch; print(f'CUDA: {torch.version.cuda}, PyTorch: {torch.__version__}')"
```

### Verify NCCL Configuration

```bash
# Check NCCL environment
oc exec deepti-test -- env | grep NCCL

# Expected:
# NCCL_DEBUG=INFO
# NCCL_IB_DISABLE=1
# NCCL_SOCKET_IFNAME=eth0
```

---

## 🛠️ Development Workflow

For developing and debugging on this deployment:

### Quick Start

```bash
# Configure environment for deepti deployment
export NAMESPACE=mllm-interpretation-and-failure-investigation-c8fa7f  # or your namespace
export POD_NAME=deepti-debug  # or deepti-test
export LOCAL_DIR=./workspace
export REMOTE_DIR=/workspace

# Start automated dev session
make dev-session
```

This gives you:
- Auto-sync of code changes
- Port-forwarding for VSCode debugging
- Live debugging on cluster GPUs

### VSCode Debugging

1. **Start dev session:** `make dev-session`
2. **Set breakpoints** in `workspace/deepti.py` or your test scripts
3. **Press F5** in VSCode to attach debugger
4. **Debug controls:**
   - **F10** - Step over
   - **F11** - Step into
   - **F5** - Continue
   - **Shift+F5** - Stop

**See [QUICK-DEV-GUIDE.md](../../docs/QUICK-DEV-GUIDE.md) for complete workflow details**

---

## 📊 Monitor Performance

### GPU Utilization

```bash
# Real-time monitoring
oc exec deepti-test -- nvidia-smi dmon -c 10

# GPU memory usage
oc exec deepti-test -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# All GPU stats
oc exec deepti-test -- nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv
```

### Multi-Node Training Metrics

```bash
# Monitor NCCL communication
oc logs -f deepti-train-0 | grep "NCCL INFO"

# Check training throughput
oc logs deepti-train-0 | grep -i "samples/sec\|iter/sec"

# Watch GPU utilization across nodes
for pod in deepti-train-0 deepti-train-1; do
  echo "=== $pod ==="
  oc exec $pod -- nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader
done
```

---

## 🔧 Troubleshooting

### Pod Pending or Not Starting

```bash
# Check pod events
oc describe pod deepti-test | grep -A10 Events

# Common issues:
# - Insufficient GPU nodes
# - Image pull errors
# - Resource quota exceeded

# Check node capacity
oc describe nodes | grep -A5 "Allocated resources"
```

### Model Loading Errors

```bash
# Check logs for errors
oc logs deepti-test | grep -i "error\|fail"

# Verify internet connectivity (for HuggingFace download)
oc exec deepti-test -- curl -I https://huggingface.co

# Check disk space
oc exec deepti-test -- df -h

# Clear model cache if needed
oc exec deepti-test -- rm -rf ~/.cache/huggingface/
```

### CUDA/GPU Issues

```bash
# Verify CUDA is available
oc exec deepti-test -- python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Check GPU count
oc exec deepti-test -- python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"

# Test GPU computation
oc exec deepti-test -- python -c "import torch; x = torch.randn(1000, 1000).cuda(); print('GPU works!')"
```

### Multi-Node Training Issues

```bash
# Check network connectivity between pods
oc exec deepti-train-0 -- ping -c 3 deepti-train-1.deepti-train-svc

# Verify NCCL settings on all nodes
for pod in deepti-train-0 deepti-train-1; do
  echo "=== $pod ==="
  oc exec $pod -- env | grep NCCL
done

# Check for NCCL errors
oc logs deepti-train-0 | grep -i "nccl error"

# Common issues:
# - NCCL_IB_DISABLE not set (tries to use RDMA)
# - Wrong master_addr hostname
# - Network policy blocking pod communication
# - Port conflict on master_port
```

### Slow Training Performance

```bash
# Check if all GPUs are utilized
oc exec deepti-train-0 -- nvidia-smi

# Monitor inter-node communication
oc logs deepti-train-0 | grep "NCCL INFO.*Send\|Recv"

# Tune NCCL for better TCP performance:
# Add to pod env:
# NCCL_SOCKET_NTHREADS=8
# NCCL_NSOCKS_PERTHREAD=8
```

### Out of Memory (OOM)

```bash
# Check GPU memory
oc exec deepti-test -- nvidia-smi

# If OOM:
# - Reduce batch size
# - Use BF16 instead of FP32
# - Enable Flash Attention
# - Use device_map="auto" for model sharding
# - For multi-node: use gradient accumulation
```

---

## 🎯 What You Get

### Hardware (per pod)
- **4 GPUs** (NVIDIA H100 80GB HBM3)
- **128-256Gi memory**
- **32-64 CPU cores**
- **TCP networking** for multi-node

### Software
- **PyTorch** 2.8 or 2.9 with NCCL
- **CUDA** 11.6+
- **Flash Attention 2** (optional, recommended)
- **Transformers** library
- **ffmpeg** for video processing

### Model
- **Qwen2.5-Omni-7B** (7 billion parameters)
- **Multimodal**: Text + Video/Audio
- **Optimized**: Flash Attention 2
- **Precision**: BF16 mixed precision

### Cluster
- **NERC Production**: Standard Ethernet networking
- **Multi-node capable**: NCCL over TCP
- **Scalable**: 2+ nodes for distributed training

---

## 📝 Configuration

### Cluster: NERC Production

**Network:**
- Standard Ethernet (TCP/IP)
- NCCL communication over TCP sockets
- No RDMA required

**Best for:**
- Multi-node distributed training
- Production workloads
- Large-scale model training

### PyTorch Version Selection

Choose based on your needs:
- **pytorch28**: Stable, well-tested
- **pytorch29**: Latest features
- **Default**: Current stable release

### Resource Limits

Default configuration per pod:
```yaml
resources:
  requests:
    nvidia.com/gpu: 4
    memory: 128Gi
    cpu: 32
  limits:
    nvidia.com/gpu: 4
    memory: 256Gi
    cpu: 64
```

Adjust in YAML if needed for your workload.

---

## ⚡ Next Steps

1. **Run initial test** to verify setup works
2. **Try multi-node training** with 2+ nodes
3. **Modify test scripts** in workspace/ for your use case
4. **Try different models** from HuggingFace
5. **Optimize NCCL settings** for your network
6. **Use VSCode debugging** for development (see main docs)

For more details, see [README.md](README.md) and main documentation.

---

## 📚 Additional Documentation

### Main Documentation (General Workflows)
- **[QUICKSTART.md](../../docs/QUICKSTART.md)** - General quickstart
- **[QUICK-DEV-GUIDE.md](../../docs/QUICK-DEV-GUIDE.md)** - Development workflow
- **[REMOTE-DEBUG-WALKTHROUGH.md](../../docs/REMOTE-DEBUG-WALKTHROUGH.md)** - Debugging tutorial
- **[VSCODE-DEBUG-GUIDE.md](../../docs/VSCODE-DEBUG-GUIDE.md)** - Debugging reference

### Deployment-Specific
- **[README.md](README.md)** - Deepti deployment overview
- **[MIGRATION.md](MIGRATION.md)** - Migration from old structure

### External Resources
- **[PyTorch Distributed Training](https://pytorch.org/tutorials/beginner/dist_overview.html)** - Official guide
- **[NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/)** - NVIDIA NCCL docs
- **[PyTorch DDP Tutorial](https://pytorch.org/docs/stable/notes/ddp.html)** - DDP best practices

---

## 🆘 Getting Help

**Quick diagnostics:**
```bash
# Full pod status
oc describe pod deepti-test

# Recent logs
oc logs deepti-test --tail=100

# GPU check
oc exec deepti-test -- nvidia-smi

# Python environment
oc exec deepti-test -- pip list | grep -E "torch|transformers|flash"

# NCCL environment
oc exec deepti-test -- env | grep NCCL
```

**Common commands:**
```bash
# Restart test
oc delete pod deepti-test
oc apply -f generated/pod-deepti-nerc.yaml

# Access pod
oc exec -it deepti-test -- bash

# Copy files to pod
oc cp local-file.py deepti-test:/workspace/

# Copy results from pod
oc cp deepti-test:/workspace/output.txt ./output.txt
```

**Multi-node training commands:**
```bash
# Delete all training pods
oc delete pod -l app=deepti-train

# Check service connectivity
oc get svc deepti-train-svc
oc get endpoints deepti-train-svc

# Test pod-to-pod communication
oc exec deepti-train-0 -- ping deepti-train-1.deepti-train-svc
```

---

Happy training! 🚀

For data management, file downloads, and PVC workflows, see the main [QUICKSTART.md](../../docs/QUICKSTART.md).
