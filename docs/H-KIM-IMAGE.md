# H-Kim Image - Build & Usage Guide

A minimal PyTorch environment based on NVIDIA PyTorch 2.9 with a focused package set for distributed training.

---

## 📦 Included Packages

### Base

- **NVIDIA PyTorch 26.01** (latest stable, from NVIDIA base image)
- **CUDA** (latest from NVIDIA base image)
- **NCCL** with GPUDirect RDMA support

### Python Packages

- `torchtitan` - PyTorch Titan training framework
- `transformers` - Hugging Face Transformers
- `tokenizers` - Fast tokenizers
- `datasets` - Hugging Face Datasets
- `accelerate` - Easy distributed training
- `safetensors` - Safe tensor serialization
- `hydra-core` - Configuration management
- `omegaconf` - Hierarchical configuration
- `pyyaml` - YAML parser
- `einops` - Tensor operations
- `tqdm` - Progress bars
- `rich` - Terminal formatting
- `tensorboard` - Training visualization
- `fsspec` - File system abstraction
- `wandb` - Experiment tracking

### System Tools

- Git, vim, wget, curl
- RDMA/InfiniBand tools (libibverbs, rdma-core, ibstat)
- PCI utilities, numactl

---

## 🔨 Building the Image

### 1. Create ImageStream and BuildConfig

```bash
# From the ml-dev-env directory
oc apply -f k8s/imagestream-h-kim.yaml
oc apply -f k8s/buildconfig-h-kim.yaml
```

### 2. Start the Build

```bash
# Start build and follow logs
oc start-build h-kim -n nccl-test --follow

# Or check build status
oc get builds -n nccl-test | grep h-kim
```

Build will take approximately **10-15 minutes**.

### 3. Verify Image

```bash
# Check ImageStream
oc get imagestream h-kim -n nccl-test

# Get image details
oc describe imagestream h-kim -n nccl-test
```

The image will be available at:

```
image-registry.openshift-image-registry.svc:5000/nccl-test/h-kim:latest
```

---

## 🚀 Using the Image

### Option 1: Single-Node Pod

Create a pod using the h-kim image:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: h-kim-dev
  namespace: nccl-test
spec:
  restartPolicy: Always

  nodeSelector:
    nvidia.com/gpu.present: "true"

  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule

  containers:
  - name: h-kim
    image: image-registry.openshift-image-registry.svc:5000/nccl-test/h-kim:latest
    imagePullPolicy: Always

    resources:
      requests:
        nvidia.com/gpu: 4
        memory: 128Gi
        cpu: 32
      limits:
        nvidia.com/gpu: 4
        memory: 256Gi
        cpu: 64

    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: "all"

    volumeMounts:
    - name: workspace
      mountPath: /workspace
    - name: dshm
      mountPath: /dev/shm

    command: ["/bin/bash", "-c", "sleep infinity"]

  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: ml-dev-workspace
  - name: dshm
    emptyDir:
      medium: Memory
      sizeLimit: 32Gi
```

Save as `k8s/pod-h-kim.yaml` and deploy:

```bash
oc apply -f k8s/pod-h-kim.yaml

# Wait for pod to be ready
oc wait --for=condition=Ready pod/h-kim-dev -n nccl-test --timeout=300s

# Shell into pod
oc exec -it h-kim-dev -n nccl-test -- bash
```

### Option 2: Multi-Node StatefulSet

For distributed training across multiple nodes, create a StatefulSet:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: h-kim-headless
  namespace: nccl-test
spec:
  clusterIP: None
  selector:
    app: h-kim-multi
  ports:
  - port: 29500
    name: master
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: h-kim
  namespace: nccl-test
spec:
  serviceName: h-kim-headless
  replicas: 2
  podManagementPolicy: Parallel

  selector:
    matchLabels:
      app: h-kim-multi

  template:
    metadata:
      labels:
        app: h-kim-multi

    spec:
      restartPolicy: Always

      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - h-kim-multi
            topologyKey: kubernetes.io/hostname

      nodeSelector:
        nvidia.com/gpu.present: "true"

      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule

      containers:
      - name: h-kim
        image: image-registry.openshift-image-registry.svc:5000/nccl-test/h-kim:latest
        imagePullPolicy: Always

        resources:
          requests:
            nvidia.com/gpu: 4
            memory: 128Gi
            cpu: 32
          limits:
            nvidia.com/gpu: 4
            memory: 256Gi
            cpu: 64

        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"

        # NCCL configuration
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_IB_DISABLE
          value: "0"
        - name: NCCL_IB_HCA
          value: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"
        - name: NCCL_IB_GID_INDEX
          value: "3"
        - name: NCCL_NET_GDR_LEVEL
          value: "5"
        - name: NCCL_SOCKET_IFNAME
          value: "net1,net2,net3,net4"

        # DeepSpeed/distributed settings
        - name: MASTER_ADDR
          value: "h-kim-0.h-kim-headless.nccl-test.svc.cluster.local"
        - name: MASTER_PORT
          value: "29500"
        - name: WORLD_SIZE
          value: "8"
        - name: GPUS_PER_NODE
          value: "4"

        volumeMounts:
        - name: workspace
          mountPath: /workspace
        - name: dshm
          mountPath: /dev/shm

        command:
        - /bin/bash
        - -c
        - |
          POD_ORDINAL=${HOSTNAME##*-}
          export NODE_RANK=$POD_ORDINAL
          echo "Node: $HOSTNAME, Rank: $NODE_RANK"
          sleep infinity

      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ml-dev-workspace
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 32Gi
```

Save as `k8s/statefulset-h-kim.yaml` and deploy:

```bash
oc apply -f k8s/statefulset-h-kim.yaml

# Wait for pods
oc get pods -n nccl-test -l app=h-kim-multi -w

# Shell into master node
oc exec -it h-kim-0 -n nccl-test -- bash
```

---

## 🧪 Testing the Image

### Test GPU Access

```bash
oc exec h-kim-dev -n nccl-test -- python3 -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
print(f'GPU count: {torch.cuda.device_count()}')
for i in range(torch.cuda.device_count()):
    print(f'  GPU {i}: {torch.cuda.get_device_name(i)}')
"
```

### Test Packages

```bash
oc exec h-kim-dev -n nccl-test -- python3 -c "
import transformers
import datasets
import accelerate
import hydra
import einops
import wandb
print('✅ All packages imported successfully')
print(f'Transformers: {transformers.__version__}')
print(f'Datasets: {datasets.__version__}')
print(f'Accelerate: {accelerate.__version__}')
"
```

### Test NCCL (Multi-Node)

```bash
oc exec h-kim-0 -n nccl-test -- python3 -c "
import torch
import torch.distributed as dist

dist.init_process_group(
    backend='nccl',
    init_method='env://',
)

print(f'Rank: {dist.get_rank()}')
print(f'World size: {dist.get_world_size()}')
print('✅ NCCL initialized successfully')

dist.destroy_process_group()
"
```

---

## 🔄 Rebuilding the Image

If you need to rebuild (e.g., to update packages):

```bash
# Delete old build
oc delete build -l buildconfig=h-kim -n nccl-test

# Start new build
oc start-build h-kim -n nccl-test --follow

# Restart pods to use new image
oc delete pod h-kim-dev -n nccl-test  # Single-node
# or
oc rollout restart statefulset h-kim -n nccl-test  # Multi-node
```

---

## 📝 Differences from ml-dev-env

The h-kim image is **minimal** compared to ml-dev-env:

| Feature | ml-dev-env | h-kim |
|---------|------------|-------|
| **Size** | ~12 GB | ~8 GB (estimated) |
| **VSCode Server** | ✅ Included | ❌ Not included |
| **Jupyter** | ✅ Included | ❌ Not included |
| **DeepSpeed** | ✅ Included | ❌ Not included |
| **Flash Attention** | ✅ Pre-built | ❌ Not included |
| **LLaMAFactory** | ✅ Included | ❌ Not included |
| **Core ML packages** | ✅ Many | ✅ Focused set |
| **RDMA tools** | ✅ Included | ✅ Included |
| **PyTorch/CUDA** | ✅ 2.9/13.0 | ✅ 2.9/13.0 (same) |

**Use h-kim when:**

- You need a minimal training environment
- You're using TorchTitan for training
- You don't need VSCode/Jupyter in the container
- You want faster image builds and smaller size

**Use ml-dev-env when:**

- You need full development environment
- You want VSCode/Jupyter integrated
- You're using DeepSpeed or Flash Attention
- You want all-in-one solution

---

## 🗑️ Cleanup

```bash
# Delete single-node pod
oc delete pod h-kim-dev -n nccl-test

# Delete multi-node StatefulSet
oc delete statefulset h-kim -n nccl-test
oc delete service h-kim-headless -n nccl-test

# Delete image (if needed)
oc delete imagestream h-kim -n nccl-test
oc delete buildconfig h-kim -n nccl-test
```

---

## 🔗 Related Documentation

- [ml-dev-env Architecture](ARCHITECTURE.md) - Understanding the full ml-dev-env system
- [Multi-Node Guide](MULTI-NODE-GUIDE.md) - Distributed training setup
- [Build on Cluster](BUILD-ON-CLUSTER.md) - Container build process

---

**Quick Start:**

```bash
# 1. Build image
oc apply -f k8s/imagestream-h-kim.yaml
oc apply -f k8s/buildconfig-h-kim.yaml
oc start-build h-kim -n nccl-test --follow

# 2. Deploy single-node pod
oc apply -f k8s/pod-h-kim.yaml

# 3. Test
oc exec -it h-kim-dev -n nccl-test -- python3 -c "import torch; print(torch.cuda.device_count())"
```
