# Deepti Deployment - Quick Start

Qwen2.5-Omni multimodal model testing on OpenShift with GPU acceleration.

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

### Delete Test Pod

```bash
# Delete pod
oc delete pod deepti-test

# Verify deletion
oc get pod deepti-test
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

### Check Model Loading

```bash
# Model cache location
oc exec deepti-test -- ls -lh ~/.cache/huggingface/hub/

# Available disk space
oc exec deepti-test -- df -h /

# Memory usage
oc exec deepti-test -- free -h
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

### System Resources

```bash
# CPU/Memory
oc exec deepti-test -- top -b -n 1 | head -20

# Disk usage
oc exec deepti-test -- df -h

# Process list
oc exec deepti-test -- ps aux | grep python
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

### Flash Attention Not Working

```bash
# Check if installed
oc exec deepti-test -- pip show flash-attn

# GPU architecture check (needs Ampere or newer)
oc exec deepti-test -- nvidia-smi --query-gpu=compute_cap --format=csv

# Ampere (A100) = 8.0
# Hopper (H100) = 9.0
# Flash Attention 2 requires >= 8.0
```

### ffmpeg Errors

```bash
# Check ffmpeg installation
oc exec deepti-test -- ffmpeg -version

# Test video creation
oc exec deepti-test -- ffmpeg -f lavfi -i testsrc=size=224x224:rate=5 -t 2 -pix_fmt yuv420p /tmp/test.mp4

# Verify video created
oc exec deepti-test -- ls -lh /tmp/test.mp4
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
5. **Scale to multi-node** if needed (see h-kim/yunshi deployments)

For more details, see [README.md](README.md).

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
