# Deepti Deployment - Quick Start

Qwen2.5-Omni multimodal model testing on OpenShift with GPU acceleration.

> **For general VSCode setup, debugging, and development workflows, see the main documentation:**
> - **[QUICKSTART.md](../../docs/QUICKSTART.md)** - General quickstart guide
> - **[QUICK-DEV-GUIDE.md](../../docs/QUICK-DEV-GUIDE.md)** - Makefile development workflow
> - **[REMOTE-DEBUG-WALKTHROUGH.md](../../docs/REMOTE-DEBUG-WALKTHROUGH.md)** - VSCode debugging tutorial
> - **[VSCODE-DEBUG-GUIDE.md](../../docs/VSCODE-DEBUG-GUIDE.md)** - Complete debugging guide

## 🚀 Quick Deploy (2 Steps)

### 1. Deploy Test Pod

**Barcelona Cluster (with RDMA):**
```bash
cd deployments/deepti
oc apply -f generated/pod-deepti-barcelona.yaml
```

**NERC Cluster:**
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

### Using Deploy Scripts

**Barcelona (automated):**
```bash
./scripts/deploy-deepti-barcelona.sh
```

**NERC (automated):**
```bash
./scripts/deploy-deepti-nerc.sh
```

### Different PyTorch Versions

**PyTorch 2.8:**
```bash
oc apply -f generated/pod-deepti-barcelona-pytorch28.yaml
```

**PyTorch 2.9:**
```bash
oc apply -f generated/pod-deepti-barcelona-pytorch29.yaml
```

**Latest stable:**
```bash
oc apply -f generated/pod-deepti-barcelona.yaml
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

Expected: 4 GPUs visible

### Verify Flash Attention

```bash
# Check installation
oc exec deepti-test -- python -c "import flash_attn; print(f'Flash Attention {flash_attn.__version__}')"

# Test compatibility
oc exec deepti-test -- python -c "import torch; print(f'CUDA: {torch.version.cuda}, PyTorch: {torch.__version__}')"
```

### RDMA Verification (Barcelona Only)

```bash
# InfiniBand devices
oc exec deepti-test -- ls -la /sys/class/infiniband/

# NCCL configuration
oc exec deepti-test -- env | grep NCCL

# Expected devices: mlx5_6, mlx5_7, mlx5_10, mlx5_11
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

### Out of Memory (OOM)

```bash
# Check GPU memory
oc exec deepti-test -- nvidia-smi

# If OOM:
# - Reduce batch size (if applicable)
# - Use BF16 instead of FP32
# - Enable Flash Attention
# - Use device_map="auto" for model sharding
```

---

## 🎯 What You Get

### Hardware (per pod)
- **4 GPUs** (NVIDIA A100 or H100)
- **128-256Gi memory**
- **32-64 CPU cores**

### Software
- **PyTorch** 2.8 or 2.9
- **CUDA** 11.6+
- **Flash Attention 2** (optional, recommended)
- **Transformers** library
- **ffmpeg** for video processing

### Model
- **Qwen2.5-Omni-7B** (7 billion parameters)
- **Multimodal**: Text + Video/Audio
- **Optimized**: Flash Attention 2
- **Precision**: BF16 mixed precision

### Cluster Support
- **Barcelona**: RDMA enabled (80+ GiB/s)
- **NERC**: Standard networking

---

## 📝 Configuration

### Cluster Selection

**Barcelona (RDMA):**
- High-performance RDMA networking
- 4x InfiniBand HCAs
- Best for distributed workloads
- Uses `pod-deepti-barcelona.yaml`

**NERC (Standard):**
- Standard GPU networking
- Good for testing
- No RDMA requirements
- Uses `pod-deepti-nerc.yaml`

### PyTorch Version Selection

Choose based on your needs:
- **pytorch28**: Stable, well-tested
- **pytorch29**: Latest features
- **Default**: Current stable release

### Resource Limits

Default configuration:
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
2. **Modify test scripts** in workspace/ for your use case
3. **Try different models** from HuggingFace
4. **Optimize configuration** for your workload
5. **Use VSCode debugging** for development (see main docs)

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
```

**Common commands:**
```bash
# Restart test
oc delete pod deepti-test
oc apply -f generated/pod-deepti-barcelona.yaml

# Access pod
oc exec -it deepti-test -- bash

# Copy files to pod
oc cp local-file.py deepti-test:/workspace/

# Copy results from pod
oc cp deepti-test:/workspace/output.txt ./output.txt
```

---

Happy testing! 🚀

For data management, file downloads, and PVC workflows, see the main [QUICKSTART.md](../../docs/QUICKSTART.md).
