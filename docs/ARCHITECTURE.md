# ML Dev Environment - Architecture & Implementation Guide

A comprehensive explanation of how ml-dev-env works, including architecture and OpenShift components.

---

## 🏗️ Overall Architecture

ml-dev-env is a **cluster-based GPU machine learning development environment** for OpenShift that supports both **single-node development** and **multi-node distributed training**. It's designed to run on NVIDIA H100 GPUs with DeepSpeed for distributed training.

---

## 🧩 OpenShift Components Used

### 1. **BuildConfig** (`k8s/buildconfig.yaml`)

- Builds container images directly on the cluster using OpenShift's S2I (Source-to-Image)
- Base image: NVIDIA PyTorch container (`nvcr.io/nvidia/pytorch:25.09-py3`)
- Includes: PyTorch 2.9, CUDA 13.0, Flash Attention 2.7.4, DeepSpeed, RDMA tools
- Creates tagged images: `pytorch-2.9-numpy2`, `pytorch-2.8-numpy1`

### 2. **ImageStream** (`k8s/imagestream.yaml`)

- Tracks container image versions in OpenShift's internal registry
- Location: `image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env`

### 3. **StatefulSet** (Multi-Node)

Two variants based on network mode:

- **`statefulset-multi-node-rdma.yaml`**: RDMA/InfiniBand mode (high performance)
- **`statefulset-multi-node-tcp.yaml`**: TCP/Ethernet mode (universal compatibility)

Key features:

- **Headless Service** (`ml-dev-env-headless`): Provides stable DNS for pod-to-pod communication
  - Pods accessible as: `ml-dev-env-0.ml-dev-env-headless.nccl-test.svc.cluster.local`
- **Pod Anti-Affinity**: Ensures one pod per physical node
- **Parallel Pod Management**: All pods start simultaneously
- **Ordered Naming**: Pods numbered 0, 1, 2, 3... (pod-0 is always the master)

### 4. **Pod** (Single-Node)

- **`pod-multi-gpu.yaml`**: Standalone pod for 4-GPU development
- Used for testing and development before scaling to multi-node

### 5. **PersistentVolumeClaims** (`k8s/pvcs.yaml`)

- **`ml-dev-workspace`**: 100GB for code and models
- **`ml-dev-datasets`**: 500GB for training data

### 6. **Services & Routes** (`k8s/service.yaml`)

- **VSCode Server**: Port 8080
- **Jupyter Notebook**: Port 8888
- **TensorBoard**: Port 6006
- **Debug Port**: Port 5678 (debugpy)
- **Master Port**: 29500 (NCCL communication)

### 7. **Service Accounts & Security**

- **Service Account**: `ml-dev-sa`
- **Privileged SCC**: Required for RDMA mode (IPC_LOCK capability)
- **Capabilities**: IPC_LOCK (for pinning memory for RDMA)

---

## 🎯 Cluster-Based Configuration System

### Configuration Files (`clusters/*.yaml`)

Each cluster has a YAML config defining all infrastructure-specific settings:

```yaml
cluster:
  name: barcelona
  api: barcelona.nerc.mghpcc.org
  namespace: nccl-test

nodes:
  gpu_nodes: [moc-r4pcc04u25-nairr, moc-r4pcc04u23-nairr]

storage:
  mode: volumeClaimTemplates  # Per-pod storage
  class_rwo: ocs-external-storagecluster-ceph-rbd
  workspace_size: 100Gi

network:
  rdma:
    enabled: true
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"

security:
  requires_privileged_scc: true
  ipc_lock: true

gpus:
  per_node: 4
  default_nodes: 2
```

### Deployment Script (`scripts/deploy-cluster.py`)

1. **Loads cluster config** from `clusters/<name>.yaml`
2. **Validates** RDMA availability (auto-falls back to TCP if not supported)
3. **Template substitution**: Replaces placeholders in StatefulSet YAML
   - RDMA device names
   - Network interfaces
   - Node affinity rules
   - Resource limits
   - GPU counts
4. **Generates final manifests** and applies to OpenShift

**Workflow:**

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
  ↓
scripts/deploy-cluster.py barcelona --mode rdma
  ↓
Loads clusters/barcelona.yaml
  ↓
Selects k8s/statefulset-multi-node-rdma.yaml
  ↓
Substitutes cluster-specific values
  ↓
Applies to OpenShift
```

---

## 🌐 Multi-Node Architecture

```
┌─────────────────────────────────────────────────────────┐
│         Headless Service (ml-dev-env-headless)          │
│  Provides stable DNS names for pod-to-pod communication │
└────────────┬───────────────────────────────┬────────────┘
             │                               │
  ┌──────────▼──────────┐       ┌───────────▼────────────┐
  │  ml-dev-env-0       │       │  ml-dev-env-1          │
  │  (Master Node)      │       │  (Worker Node)         │
  │  ┌────────────────┐ │       │  ┌────────────────┐    │
  │  │ 4x H100 GPUs   │ │       │  │ 4x H100 GPUs   │    │
  │  │ Rank 0-3       │ │       │  │ Rank 4-7       │    │
  │  └────────────────┘ │       │  └────────────────┘    │
  │  ┌────────────────┐ │       │  ┌────────────────┐    │
  │  │ DeepSpeed      │ │◄─────►│  │ DeepSpeed      │    │
  │  │ Master         │ │ NCCL  │  │ Worker         │    │
  │  └────────────────┘ │       │  └────────────────┘    │
  │  ┌────────────────┐ │       │  ┌────────────────┐    │
  │  │ VSCode Server  │ │       │  │ (no services)  │    │
  │  │ port 8080      │ │       │  │                │    │
  │  └────────────────┘ │       │  └────────────────┘    │
  └──────────┬──────────┘       └───────────┬────────────┘
             │                               │
             └───────────┬───────────────────┘
                         │
              ┌──────────▼──────────┐
              │  Shared Storage     │
              │  RWX or per-pod PVC │
              │  /workspace         │
              │  /datasets          │
              └─────────────────────┘
```

### Pod Initialization Flow

Each pod runs this startup script (from `statefulset-multi-node-rdma.yaml`):

1. **Calculate Node Rank**: Extract from hostname

   ```bash
   POD_ORDINAL=${HOSTNAME##*-}  # ml-dev-env-0 → 0
   export NODE_RANK=$POD_ORDINAL
   ```

2. **Start VSCode Server** (background)

   ```bash
   code-server --bind-addr 0.0.0.0:8080 --auth none /workspace &
   ```

3. **Generate DeepSpeed Hostfile**

   ```bash
   > /workspace/.deepspeed/hostfile
   for i in $(seq 0 $((NUM_NODES - 1))); do
     echo "ml-dev-env-$i.ml-dev-env-headless... slots=$GPUS_PER_NODE"
   done
   ```

4. **Wait** for user to run training

### NCCL Communication

**RDMA Mode** (InfiniBand):

```
GPU 0 → PCIe → mlx5_6 NIC → InfiniBand → mlx5_6 NIC → PCIe → GPU 4
     (GPUDirect RDMA - direct GPU-to-NIC transfer)
```

Environment variables set:

```bash
NCCL_IB_DISABLE=0                    # Enable InfiniBand
NCCL_IB_HCA=mlx5_2,mlx5_3,mlx5_4,mlx5_5  # Active NICs
NCCL_IB_GID_INDEX=3                  # RoCE v2 GID
NCCL_NET_GDR_LEVEL=5                 # System-level GPUDirect
NCCL_SOCKET_IFNAME=net1,net2,net3,net4  # SR-IOV interfaces
```

**TCP Mode** (Ethernet):

```
GPU 0 → PCIe → System Memory → Ethernet → System Memory → PCIe → GPU 4
     (Slower but works everywhere)
```

---

## 💾 Storage Architecture

### Option 1: ReadWriteMany (RWX) - Shared Storage

```
┌────────────────────────────┐
│  NFS Server (nfs-csi)      │
│  /workspace: 100GB         │
│  /datasets: 500GB          │
└────────┬───────────────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│ Pod 0 │ │ Pod 1 │
│  /ws  │ │  /ws  │  ← Same files!
└───────┘ └───────┘
```

**Pros**: Code synced once, visible to all pods
**Cons**: Requires NFS server, potential performance bottleneck

### Option 2: VolumeClaimTemplates - Per-Pod Storage

```
┌──────────────┐  ┌──────────────┐
│  PVC-pod-0   │  │  PVC-pod-1   │
│  100GB Ceph  │  │  100GB Ceph  │
└──────┬───────┘  └──────┬───────┘
       │                 │
   ┌───▼───┐         ┌───▼───┐
   │ Pod 0 │         │ Pod 1 │
   │  /ws  │         │  /ws  │  ← Separate!
   └───────┘         └───────┘
```

**Pros**: Better performance, no NFS dependency
**Cons**: Must sync code to each pod separately
**Used by**: Barcelona cluster

---

## 🚀 Training Workflow

### 1. Deploy

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

→ Creates StatefulSet with 2 pods (8 GPUs total)

### 2. Sync Code

```bash
make sync-multi-node
```

→ Copies `workspace/` to `/workspace` on all pods

### 3. SSH into Master

```bash
make shell-multi-node  # Opens shell in ml-dev-env-0
```

### 4. Launch Training

```bash
./launch_deepspeed.sh train_multi_node.py
```

What happens:

1. **Validates** running on pod-0 (master)
2. **Checks** hostfile exists
3. **Tests** connectivity to workers (ping)
4. **Waits** for all pods ready
5. **Launches DeepSpeed**:

   ```bash
   deepspeed \
     --hostfile=/workspace/.deepspeed/hostfile \
     --master_addr=ml-dev-env-0.ml-dev-env-headless... \
     --master_port=29500 \
     train_multi_node.py \
     --deepspeed \
     --deepspeed_config=ds_config.json
   ```

DeepSpeed then:

- **SSH** to each worker node listed in hostfile
- **Launches** python processes with appropriate ranks
- **Initializes** NCCL for GPU communication
- **Runs** training with gradient sharding (ZeRO-2/3)

---

## 📦 Container Image Build

### Dockerfile Stages (in BuildConfig)

```dockerfile
FROM nvcr.io/nvidia/pytorch:25.09-py3
  ↓
Install system packages (git, vim, ffmpeg)
  ↓
Install RDMA tools (libibverbs, rdma-core, ibstat)
  ↓
Set NCCL environment variables
  ↓
Install ML libraries:
  - transformers, accelerate, datasets
  - DeepSpeed
  - LLaMAFactory, VideoLLaMA2
  - wandb, tensorboard
  ↓
Install development tools:
  - code-server (VSCode in browser)
  - jupyter
  - debugpy
  ↓
Final image: 12.1 GB
Tagged as: ml-dev-env:pytorch-2.9-numpy2
```

### Build Process

```bash
make build
  ↓
oc apply -f k8s/imagestream.yaml
  ↓
oc apply -f k8s/buildconfig.yaml
  ↓
OpenShift BuildConfig creates build pod
  ↓
Build pod downloads base image
  ↓
Runs Dockerfile instructions
  ↓
Pushes to internal registry:
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:pytorch-2.9-numpy2
  ↓
ImageStream tracks the new image
```

---

## 🔧 Development Workflow

### Automated Session

```bash
make dev-session
```

1. Starts file watcher on `./workspace`
2. Auto-syncs changes to pod via `oc rsync`
3. Port-forwards debug port (5678)
4. Waits for you to run script

### Manual Steps

```bash
make sync-once          # One-time code sync
make shell              # SSH into pod
make port-forward       # Forward debug port
make vscode             # Get VSCode URL
```

---

## 🎛️ Key Design Decisions

### 1. StatefulSet vs Deployment

**Why StatefulSet?**

- **Stable network identities**: Predictable pod names (ml-dev-env-0, ml-dev-env-1, ...)
- **Ordered pod numbering**: Always starts from 0, essential for DeepSpeed master/worker roles
- **Persistent storage**: Each pod gets its own PVC with VolumeClaimTemplates
- **Ordered startup/shutdown**: Can control pod initialization order if needed

### 2. Headless Service

**Why headless?**

- Required for pod-to-pod DNS resolution
- Normal service would load-balance requests across pods
- Headless service returns all pod IPs individually
- Each pod gets stable DNS: `ml-dev-env-{0..N}.ml-dev-env-headless.nccl-test.svc.cluster.local`

### 3. Cluster-based Configuration

**Advantages:**

- Centralized infrastructure settings per cluster
- Avoids manual YAML editing and copy-paste errors
- Version control for cluster-specific differences
- Automatic RDMA fallback to TCP when not supported
- Single command deployment: `make deploy-cluster CLUSTER=barcelona MODE=rdma`

### 4. NVIDIA Base Image

**Benefits:**

- Guaranteed CUDA/PyTorch compatibility (no version conflicts)
- Pre-built Flash Attention (avoids 30-minute compile)
- Tested NCCL integration with CUDA
- Official NVIDIA support and updates
- Includes CUDA toolkit and cuDNN

### 5. Pod-0 as Master

**DeepSpeed convention:**

- Master node coordinates distributed training
- Workers connect to master's IP:port
- VSCode/Jupyter only on master (saves resources on workers)
- Simplified monitoring (logs from one pod)

### 6. Two Storage Modes

**Why support both RWX and per-pod?**

- **RWX (NFS)**: Easier for users, sync once
- **Per-pod (Ceph)**: Better I/O performance, no NFS dependency
- Different clusters have different storage capabilities
- Let cluster config decide based on infrastructure

---

## 🔐 Security Model

### RDMA Mode Requirements

```yaml
securityContext:
  capabilities:
    add:
      - IPC_LOCK  # Required for RDMA memory pinning
```

**Why IPC_LOCK?**

- RDMA requires pinning memory pages to prevent swapping
- GPU memory must be locked for GPUDirect RDMA
- Requires privileged SCC in OpenShift

### Service Account Setup

```bash
# Create service account
oc create serviceaccount ml-dev-sa -n nccl-test

# Grant privileged SCC (for RDMA mode)
oc adm policy add-scc-to-user privileged -z ml-dev-sa -n nccl-test
```

### Pod Security Context

- **RDMA mode**: Privileged (requires SCC)
- **TCP mode**: Non-privileged (works with restricted SCC)
- **Node selectors**: Constrain to GPU nodes
- **Pod anti-affinity**: Prevent co-location

---

## 🌊 Data Flow Example

### Training Step with DeepSpeed ZeRO-2

1. **Forward Pass**

   ```
   Each GPU: Computes forward pass on its batch shard
   GPU 0: batch[0:8]  → activations[0:8]
   GPU 1: batch[8:16] → activations[8:16]
   ```

2. **Backward Pass**

   ```
   Each GPU: Computes gradients locally
   GPU 0: ∂L/∂W[0:8]
   GPU 1: ∂L/∂W[8:16]
   ```

3. **Gradient AllReduce** (via NCCL over InfiniBand)

   ```
   Ring AllReduce:
   GPU 0 ←→ GPU 1 ←→ GPU 2 ←→ ... ←→ GPU 7 ←→ GPU 0
        │         │         │              │
        └─────────┴─────────┴──────────────┘
              InfiniBand network
              (GPUDirect RDMA)

   Result: All GPUs have sum of gradients
   ```

4. **Optimizer Step**

   ```
   Each GPU: Updates its shard of optimizer states
   GPU 0: Updates Adam states for weights[0:N/8]
   GPU 1: Updates Adam states for weights[N/8:2N/8]
   ```

5. **Broadcast Updated Weights** (if needed)

   ```
   Each GPU broadcasts its weight shard to others
   Result: All GPUs have full model weights
   ```

### Network Path (RDMA Mode)

```
┌──────────┐      ┌──────┐      ┌──────────┐      ┌──────┐      ┌──────────┐
│  GPU 0   │─PCIe─│ CPU  │─PCIe─│  mlx5_6  │─IB───│mlx5_6│─PCIe─│  GPU 4   │
│ (Pod 0)  │      │Memory│      │   NIC    │      │ NIC  │      │ (Pod 1)  │
└──────────┘      └──────┘      └──────────┘      └──────┘      └──────────┘
                                       │                              │
                                       └──────────────────────────────┘
                                        GPUDirect RDMA (bypasses CPU)
```

---

## 📊 Performance Characteristics

Based on actual testing (see `infiniband_bandwidth_results.md`):

| Communication Path | Bandwidth | Protocol | Notes |
|-------------------|-----------|----------|-------|
| GPU↔GPU (same node) | 261 GB/s | NVLink | Bidirectional, local only |
| GPU↔GPU (cross-node RDMA) | 14.6 GB/s | GPUDirect RDMA | PCIe 4.0 bottleneck |
| Host↔Host (RDMA) | 28.3 GB/s | InfiniBand | Excellent efficiency |
| GPU↔Host (PCIe) | 28.7 GB/s | PCIe 4.0 x16 | 91% of theoretical |

**Key Insights:**

- NVLink is 18x faster than InfiniBand for GPU-to-GPU
- InfiniBand underutilized due to PCIe 4.0 bottleneck
- NCCL automatically uses NVLink for intra-node, RDMA for inter-node

---

## 🔧 Troubleshooting Flow

### Pod Won't Start

```bash
1. Check pod events
   oc describe pod ml-dev-env-0 -n nccl-test

2. Check if GPU node has capacity
   oc describe node <gpu-node-name> | grep -A 5 "Allocated resources"

3. Check PVC status
   oc get pvc -n nccl-test
   oc describe pvc ml-dev-workspace -n nccl-test

4. Check service account permissions
   oc get sa ml-dev-sa -n nccl-test
   oc describe scc privileged | grep ml-dev-sa
```

### NCCL Hangs

```bash
1. Check DNS resolution
   oc exec ml-dev-env-0 -n nccl-test -- \
     nslookup ml-dev-env-1.ml-dev-env-headless

2. Check network connectivity
   oc exec ml-dev-env-0 -n nccl-test -- \
     ping -c 3 ml-dev-env-1.ml-dev-env-headless

3. Check RDMA devices (RDMA mode)
   oc exec ml-dev-env-0 -n nccl-test -- ibstat
   oc exec ml-dev-env-0 -n nccl-test -- ibv_devinfo

4. Check NCCL environment
   oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL
```

### Training Slow

```bash
1. Check GPU utilization
   oc exec ml-dev-env-0 -n nccl-test -- nvidia-smi

2. Check network mode
   oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL_IB_DISABLE
   # Should be "0" for RDMA, "1" for TCP

3. Check for PCIe errors
   oc exec ml-dev-env-0 -n nccl-test -- nvidia-smi topo -m

4. Profile communication
   # Set NCCL_DEBUG=INFO in StatefulSet, redeploy
   # Look for "Using network" lines in logs
```

---

## 📐 Scaling Considerations

### Horizontal Scaling (More Nodes)

```yaml
# In cluster config
gpus:
  default_nodes: 4  # Change from 2 to 4

# Or override during deploy
make deploy-cluster CLUSTER=barcelona MODE=rdma NODES=8
```

**Considerations:**

- More nodes = more network traffic
- Ensure sufficient InfiniBand ports/switches
- Check node availability
- Update WORLD_SIZE environment variable

### Vertical Scaling (More GPUs per Node)

```yaml
# In cluster config
gpus:
  per_node: 8  # Change from 4 to 8

# Update in StatefulSet
resources:
  requests:
    nvidia.com/gpu: 8  # Match per_node
```

**Considerations:**

- Node must have enough GPUs
- More GPUs = more memory needed
- NVLink topology matters for intra-node

### Storage Scaling

```yaml
# In cluster config
storage:
  workspace_size: 200Gi  # Increase from 100Gi
  datasets_size: 1Ti     # Increase from 500Gi
```

**Watch out for:**

- Storage class quota limits
- NFS server capacity (RWX mode)
- I/O performance with many pods

---

## 🎓 Learning Path

For someone new to this system:

1. **Start with single-node** (`make deploy`)
   - Understand pod, PVC, service basics
   - Test GPU access with `test_multi_gpu.py`
   - Explore VSCode and Jupyter

2. **Learn cluster configs** (`clusters/*.yaml`)
   - Study barcelona cluster config
   - Understand storage modes
   - See how RDMA settings work

3. **Deploy multi-node** (`make deploy-cluster`)
   - Watch StatefulSet create pods
   - Check headless service DNS
   - Observe pod initialization

4. **Run distributed training**
   - Sync code with `make sync-multi-node`
   - Launch DeepSpeed training
   - Monitor with `nvidia-smi` and logs

5. **Debug issues**
   - Practice connectivity tests
   - Check NCCL logs
   - Understand performance metrics

---

This architecture enables seamless scaling from **1 node (4 GPUs)** to **N nodes (4N GPUs)** with minimal configuration changes, while supporting both high-performance RDMA clusters and standard TCP networks.
