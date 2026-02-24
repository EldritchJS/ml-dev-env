# Multi-Node Training: TCP vs RDMA Guide

Train ML models across multiple nodes with **TCP** (universal compatibility) or **RDMA** (high performance) networking.

## 🎯 Overview

The cluster configuration system supports **two networking modes** for multi-node distributed training:

| Mode | Network | Speed | Compatibility | Use Case |
|------|---------|-------|---------------|----------|
| **RDMA** | InfiniBand/RoCE | ⚡ Very Fast | Requires IB hardware | Production, HPC clusters |
| **TCP** | Standard Ethernet | 🐢 Slower | Works anywhere | Development, standard clusters |

## 📊 Performance Comparison

### RDMA/RoCE Mode
- **Bandwidth:** 100-200 Gb/s (InfiniBand)
- **Latency:** < 1 microsecond
- **GPUDirect RDMA:** Direct GPU-to-GPU transfers
- **Best for:** Large-scale training, high communication overhead

### TCP/Ethernet Mode
- **Bandwidth:** 10-100 Gb/s (Ethernet)
- **Latency:** 10-100 microseconds
- **GPU transfers:** Via CPU memory
- **Best for:** Moderate-scale training, testing, compatibility

**Speed difference:** RDMA can be **2-5x faster** for communication-heavy workloads.

## 🚀 Quick Start with Cluster Configs

### Choose Networking Mode

```bash
# List available clusters
make list-clusters

# RDMA Mode (high performance)
make deploy-cluster CLUSTER=barcelona MODE=rdma

# TCP Mode (fallback - if RDMA unavailable)
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

### What the Cluster Config Handles

The cluster configuration automatically sets:

**For TCP Mode:**
- Disables RDMA: `NCCL_IB_DISABLE=1`
- Configures socket interface: `NCCL_SOCKET_IFNAME`
- Uses standard pod networking
- No host network required

**For RDMA Mode:**
- Enables InfiniBand: `NCCL_IB_DISABLE=0`
- Configures RDMA devices: `NCCL_IB_HCA`
- Sets GPUDirect RDMA level: `NCCL_NET_GDR_LEVEL=5`
- Requires host network access

## 🔧 Cluster Configuration

### TCP Mode Configuration

Example cluster config (Barcelona):
```yaml
cluster:
  name: barcelona
  api: barcelona.nerc.mghpcc.org
  namespace: nccl-test

network:
  tcp:
    # Exclude loopback and docker interfaces
    interface_exclude: "^lo,docker0"
    # P2P level: NVLink intra-node, TCP inter-node
    p2p_level: "NVL"
  rdma:
    enabled: false  # RDMA disabled for TCP mode

storage:
  # Use per-pod storage if RWX not available
  mode: volumeClaimTemplates
  class_rwo: ceph-rbd

security:
  # TCP mode typically doesn't need privileged SCC
  requires_privileged_scc: false
  ipc_lock: false
```

Deploy with:
```bash
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

### RDMA Mode Configuration

Example cluster config (Barcelona):
```yaml
cluster:
  name: barcelona
  api: barcelona.nerc.mghpcc.org
  namespace: nccl-test

network:
  rdma:
    enabled: true
    # Active InfiniBand devices (verify with ibstat)
    devices: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"  # GPUDirect RDMA
  tcp:
    interface_exclude: "^lo,docker0"
    p2p_level: "NVL"

storage:
  # Use RWX shared storage when available
  mode: rwx
  class_rwx: nfs-csi

security:
  # RDMA may require privileged SCC for IPC_LOCK
  requires_privileged_scc: true
  ipc_lock: true
```

Deploy with:
```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

## 🌍 When to Use Each Mode

### Use TCP Mode When:
- ✅ Testing on a new cluster
- ✅ Cluster doesn't have InfiniBand hardware
- ✅ Developing/debugging distributed code
- ✅ Standard Ethernet networking is available
- ✅ Communication isn't the bottleneck
- ✅ Privileged access not available

**Example clusters:** Standard cloud VMs, development environments

### Use RDMA Mode When:
- ✅ Production training at scale
- ✅ Cluster has InfiniBand/RoCE adapters
- ✅ Communication-heavy workloads (large models, high gradient sync)
- ✅ Cluster allows host network access
- ✅ Privileged SCC available (for IPC_LOCK)

**Example clusters:** HPC clusters, high-end GPU clusters like NERC

## 📝 Step-by-Step Deployment

### TCP Mode Deployment

```bash
# 1. List clusters
make list-clusters

# 2. Deploy with TCP
make deploy-cluster CLUSTER=barcelona MODE=tcp

# 3. Wait for pods
oc get pods -n nccl-test -l app=ml-dev-env-multi -w

# 4. Sync code
make sync-multi-node

# 5. Run training
make shell-multi-node
cd /workspace && ./launch_deepspeed.sh
```

### RDMA Mode Deployment

```bash
# 1. List clusters
make list-clusters

# 2. Deploy with RDMA
make deploy-cluster CLUSTER=barcelona MODE=rdma

# 3. Wait for pods
oc get pods -n nccl-test -l app=ml-dev-env-multi -w

# 4. Sync code
make sync-multi-node

# 5. Run training
make shell-multi-node
cd /workspace && ./launch_deepspeed.sh
```

## 🔍 Configuration Details

### TCP Mode Environment Variables

Set automatically by cluster config:
```bash
NCCL_DEBUG=INFO
NCCL_IB_DISABLE=1                    # Disable InfiniBand
NCCL_SOCKET_IFNAME=^lo,docker0       # Use primary interface
NCCL_P2P_LEVEL=NVL                   # NVLink intra-node only
```

### RDMA Mode Environment Variables

Set automatically by cluster config:
```bash
NCCL_DEBUG=INFO
NCCL_IB_DISABLE=0                    # Enable InfiniBand
NCCL_IB_HCA=mlx5_2,mlx5_3,mlx5_4,mlx5_5  # Cluster-specific
NCCL_IB_GID_INDEX=3                  # RoCE v2
NCCL_NET_GDR_LEVEL=5                 # GPUDirect RDMA
NCCL_CROSS_NIC=1
NCCL_IB_TIMEOUT=22
NCCL_MIN_NCHANNELS=4
```

## 🔬 Testing and Verification

### Verify TCP Configuration

```bash
# Check NCCL settings
oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL

# Should see:
# NCCL_IB_DISABLE=1
# NCCL_SOCKET_IFNAME=^lo,docker0

# Test NCCL communication
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
python3 -c "
import torch
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\")
print(\"✓ NCCL TCP mode working!\")
"
'
```

### Verify RDMA Configuration

```bash
# Check NCCL settings
oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL

# Should see:
# NCCL_IB_DISABLE=0
# NCCL_IB_HCA=mlx5_2,mlx5_3,mlx5_4,mlx5_5
# NCCL_NET_GDR_LEVEL=5

# Check InfiniBand devices
oc exec ml-dev-env-0 -n nccl-test -- ibstat

# Should show active devices
# State: Active
# Physical state: LinkUp
# Rate: 400 Gb/s (or similar)

# Test NCCL with RDMA
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
python3 -c "
import torch
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\")
print(\"✓ NCCL RDMA mode working!\")
"
'
```

## 🐛 Troubleshooting

### TCP Mode Issues

**Problem:** NCCL hangs during initialization
```bash
# Check network connectivity
oc exec ml-dev-env-0 -n nccl-test -- ping -c 3 ml-dev-env-1.ml-dev-env-headless

# Check NCCL is using TCP
oc logs ml-dev-env-0 -n nccl-test | grep "Using network"
# Should show: Using network Socket
```

**Problem:** Slow communication
```bash
# TCP is inherently slower than RDMA
# Expected for TCP mode
# Consider RDMA if cluster supports it
```

### RDMA Mode Issues

**Problem:** NCCL falls back to TCP
```bash
# Check InfiniBand devices are visible
oc exec ml-dev-env-0 -n nccl-test -- ibstat

# Check host network is enabled
oc get pod ml-dev-env-0 -n nccl-test -o yaml | grep hostNetwork
# Should show: hostNetwork: true

# Check RDMA devices are correct for this cluster
# Update cluster config if needed
vim clusters/my-cluster.yaml
```

**Problem:** IPC_LOCK capability denied
```bash
# Check if privileged SCC is granted
oc get pod ml-dev-env-0 -n nccl-test -o yaml | grep serviceAccount
# Should show: serviceAccountName: ml-dev-sa

# Verify privileged SCC
oc adm policy who-can use scc privileged -n nccl-test

# Grant if needed
oc adm policy add-scc-to-user privileged -z ml-dev-sa -n nccl-test
```

## 📊 Performance Benchmarking

### Run NCCL Tests

**TCP Mode:**
```bash
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
/usr/local/cuda/bin/nccl-tests/all_reduce_perf -b 8 -e 128M -f 2 -g 1
'
```

**RDMA Mode:**
```bash
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
/usr/local/cuda/bin/nccl-tests/all_reduce_perf -b 8 -e 128M -f 2 -g 1
'
```

Compare bandwidth results:
- **TCP:** Typically 10-40 GB/s
- **RDMA:** Typically 50-100 GB/s (with GPUDirect)

## 🔄 Switching Between Modes

### From TCP to RDMA

```bash
# Clean up TCP deployment
make clean-cluster CLUSTER=barcelona

# Deploy with RDMA
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

### From RDMA to TCP

```bash
# Clean up RDMA deployment
make clean-cluster CLUSTER=barcelona

# Deploy with TCP
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

## 🔧 Creating Cluster Configs

### For TCP-Only Cluster

```bash
# Copy template
cp clusters/template.yaml clusters/tcp-cluster.yaml

# Edit configuration
vim clusters/tcp-cluster.yaml
```

```yaml
cluster:
  name: tcp-cluster
  api: api.tcp-cluster.example.com
  namespace: nccl-test

network:
  rdma:
    enabled: false  # Disable RDMA
  tcp:
    interface_exclude: "^lo,docker0"
    p2p_level: "NVL"

storage:
  mode: volumeClaimTemplates  # Fallback storage
  class_rwo: standard

security:
  requires_privileged_scc: false
  ipc_lock: false

gpus:
  per_node: 4
  default_nodes: 2
```

### For RDMA-Capable Cluster

```bash
# Copy template
cp clusters/template.yaml clusters/rdma-cluster.yaml

# Edit configuration
vim clusters/rdma-cluster.yaml
```

```yaml
cluster:
  name: rdma-cluster
  api: api.rdma-cluster.example.com
  namespace: nccl-test

nodes:
  gpu_nodes:
    - ib-node-1
    - ib-node-2

network:
  rdma:
    enabled: true
    # Verify with: ssh node "ibstat"
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"
  tcp:
    interface_exclude: "^lo,docker0"

storage:
  mode: rwx  # Use shared storage if available
  class_rwx: nfs-csi

security:
  requires_privileged_scc: true
  ipc_lock: true

gpus:
  per_node: 4
  default_nodes: 2
```

## 📚 Additional Resources

### Documentation
- [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) - Complete cluster config guide
- [MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md) - Quick deployment
- [MULTI-NODE-GUIDE.md](MULTI-NODE-GUIDE.md) - Detailed multi-node guide

### External Resources
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [DeepSpeed Documentation](https://www.deepspeed.ai/)

## ✅ Summary

**TCP Mode** (Universal):
```bash
make deploy-cluster CLUSTER=barcelona MODE=tcp
```
- Works anywhere
- No special hardware
- Slightly slower

**RDMA Mode** (High Performance):
```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```
- Requires InfiniBand
- 2-5x faster communication
- Best for production

**Create Your Own:**
```bash
cp clusters/template.yaml clusters/my-cluster.yaml
vim clusters/my-cluster.yaml
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

See [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) for complete configuration details.
