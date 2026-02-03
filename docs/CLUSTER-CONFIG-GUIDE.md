# Cluster Configuration Guide

## Overview

The cluster configuration system provides a centralized way to manage cluster-specific settings. Instead of manually editing multiple YAML files for each cluster, you define all settings in a single configuration file per cluster.

## Benefits

- **Centralized Configuration**: All cluster settings in one YAML file
- **Easy Deployment**: Single command to deploy to any cluster
- **Version Control**: Track cluster configurations in git
- **Consistency**: Ensures correct settings for each cluster
- **Portability**: Easy to add new clusters or share configurations

## Quick Start

### 1. List Available Clusters

```bash
make list-clusters
```

### 2. Deploy to a Cluster

```bash
# Deploy with RDMA
make deploy-cluster CLUSTER=cairo MODE=rdma

# Deploy with TCP (fallback)
make deploy-cluster CLUSTER=barcelona MODE=tcp

# Dry run (preview generated configs)
make deploy-cluster-dry-run CLUSTER=cairo MODE=rdma
```

### 3. Check Status

```bash
make status-cluster CLUSTER=cairo
```

### 4. Clean Up

```bash
make clean-cluster CLUSTER=cairo
```

## Available Clusters

### Cairo
**Location**: NERC Cairo cluster (api.cairo.test.nerc.mghpcc.org)

**Configuration Highlights**:
- **Storage**: RWX via NFS (nfs-csi)
- **RDMA Devices**: mlx5_2, mlx5_3, mlx5_4, mlx5_5 (400 Gb/s)
- **Security**: Requires privileged SCC for IPC_LOCK
- **Nodes**: moc-r4pcc02u15, moc-r4pcc02u16
- **GPUs**: 4x H100 per node

**Setup Required**:
```bash
# Service account with privileged SCC
oc create serviceaccount ml-dev-sa -n nccl-test
oc adm policy add-scc-to-user privileged -z ml-dev-sa -n nccl-test

# Create RWX PVCs (auto-created by deploy script)
# Verify NFS server is running
oc get pods -n nfs
```

**Deploy**:
```bash
make deploy-cluster CLUSTER=cairo MODE=rdma
```

### Barcelona
**Location**: NERC Barcelona cluster (barcelona.nerc.mghpcc.org)

**Configuration Highlights**:
- **Storage**: Per-pod storage (volumeClaimTemplates) - no RWX available
- **RDMA Devices**: mlx5_6, mlx5_7, mlx5_10, mlx5_11
- **Security**: No privileged SCC required, no IPC_LOCK
- **Nodes**: moc-r4pcc04u25-nairr, moc-r4pcc04u23-nairr
- **GPUs**: 4x H100 per node

**Setup Required**:
```bash
# Service account (no privileged SCC)
oc create serviceaccount ml-dev-sa -n nccl-test
```

**Deploy**:
```bash
make deploy-cluster CLUSTER=barcelona MODE=tcp
```

## Creating a New Cluster Configuration

### Step 1: Copy Template

```bash
cp clusters/template.yaml clusters/my-cluster.yaml
```

### Step 2: Gather Cluster Information

You'll need to know:

1. **Cluster API endpoint**: `oc cluster-info`
2. **GPU nodes**: `oc get nodes -l nvidia.com/gpu.present=true`
3. **Storage classes**: `oc get storageclass`
4. **RDMA devices** (if using RDMA): SSH to a GPU node and run `ibstat`
5. **Network interfaces**: `ip addr` on a GPU node
6. **Security requirements**: Check if privileged SCC is available

### Step 3: Edit Configuration

Open `clusters/my-cluster.yaml` and customize:

```yaml
cluster:
  name: my-cluster  # Used for generated file names
  api: api.my-cluster.example.com
  namespace: nccl-test

nodes:
  gpu_nodes:
    - gpu-node-1
    - gpu-node-2

storage:
  # IMPORTANT: Check if RWX storage is available
  mode: rwx  # Or "volumeClaimTemplates" if no RWX
  class_rwx: nfs-csi  # Your RWX storage class
  class_rwo: ceph-rbd  # Your RWO storage class

network:
  rdma:
    enabled: true
    # Run 'ibstat' on GPU node to find active devices
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"

security:
  # Check if privileged SCC is available
  requires_privileged_scc: true
  ipc_lock: true

gpus:
  per_node: 4  # GPUs per node
  default_nodes: 2  # Default number of nodes
```

### Step 4: Test Configuration

```bash
# Dry run to verify generated configs
make deploy-cluster-dry-run CLUSTER=my-cluster MODE=rdma

# Check generated files
ls -l /tmp/my-cluster-*
cat /tmp/my-cluster-statefulset-rdma.yaml
```

### Step 5: Deploy

```bash
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

## Configuration Reference

### Cluster Section

```yaml
cluster:
  name: cairo                          # Cluster identifier
  api: api.cairo.test.nerc.mghpcc.org # Cluster API endpoint
  namespace: nccl-test                 # Deployment namespace
  description: "Brief description"     # Documentation
```

### Nodes Section

```yaml
nodes:
  gpu_nodes:  # Specific nodes to use (or empty for auto-select)
    - node-1
    - node-2
```

**Finding GPU nodes**:
```bash
oc get nodes -l nvidia.com/gpu.present=true
```

### Storage Section

```yaml
storage:
  class_rwx: nfs-csi           # ReadWriteMany storage class
  class_rwo: ceph-rbd           # ReadWriteOnce storage class
  workspace_size: 100Gi         # Workspace PVC size
  datasets_size: 500Gi          # Datasets PVC size
  mode: rwx                     # "rwx" or "volumeClaimTemplates"
```

**Storage Modes**:
- **`rwx`**: Shared storage across all pods (requires NFS or CephFS)
  - ✅ Files visible across all pods
  - ✅ Ideal for collaborative workloads
  - ❌ Requires RWX-capable storage class
- **`volumeClaimTemplates`**: Per-pod storage
  - ✅ Works on any cluster
  - ✅ Each pod gets isolated storage
  - ❌ No file sharing between pods

**Finding storage classes**:
```bash
oc get storageclass
```

### Network Section

```yaml
network:
  rdma:
    enabled: true
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"  # Mellanox devices
    interfaces: "net1,net2,net3,net4"        # Network interfaces
    gid_index: "3"                            # RoCE v2
    gdr_level: "5"                            # GPUDirect RDMA
    cross_nic: "1"
    ib_timeout: "22"
    min_nchannels: "4"
  tcp:
    interface_exclude: "^lo,docker0"  # Exclude loopback/docker
    p2p_level: "NVL"                   # NVLink intra-node
```

**Finding RDMA devices**:
```bash
# SSH to a GPU node
ibstat
# Look for "State: Active" devices
# Note the device names (e.g., mlx5_2)
```

### Security Section

```yaml
security:
  service_account: ml-dev-sa       # ServiceAccount name
  requires_privileged_scc: true    # Privileged SCC required?
  ipc_lock: true                    # Enable IPC_LOCK capability?
```

**IPC_LOCK and Privileged SCC**:
- **IPC_LOCK**: Required for shared memory operations in distributed training
- **Privileged SCC**: Required to grant IPC_LOCK capability in OpenShift
- Check with cluster admin if privileged SCC is available

### GPUs Section

```yaml
gpus:
  per_node: 4                         # GPUs per node
  type: "NVIDIA H100 80GB HBM3"      # GPU type (informational)
  default_nodes: 2                    # Default number of nodes
```

### Resources Section

```yaml
resources:
  requests:
    memory: 128Gi
    cpu: 32
  limits:
    memory: 256Gi
    cpu: 64
```

### NCCL Section

```yaml
nccl:
  debug: "INFO"  # "INFO", "WARN", or "TRACE"
```

### Notes Section

```yaml
notes: |
  Multi-line notes about the cluster.
  Setup instructions, known issues, etc.
```

## Deployment Script

The `scripts/deploy-cluster.py` script:

1. Loads cluster configuration from `clusters/<name>.yaml`
2. Reads base templates (`k8s/statefulset-multi-node-*.yaml`)
3. Replaces values with cluster-specific settings
4. Generates:
   - ServiceAccount YAML (if required)
   - PVCs YAML (if using RWX storage)
   - StatefulSet YAML (with cluster-specific values)
5. Applies configurations to cluster (unless `--dry-run`)

**Usage**:
```bash
python3 scripts/deploy-cluster.py <cluster-name> [--mode tcp|rdma] [--dry-run] [--output-dir /tmp]
```

**Examples**:
```bash
# Deploy Cairo with RDMA
python3 scripts/deploy-cluster.py cairo --mode rdma

# Dry run for Barcelona with TCP
python3 scripts/deploy-cluster.py barcelona --mode tcp --dry-run

# Generate configs to custom directory
python3 scripts/deploy-cluster.py cairo --mode rdma --dry-run --output-dir ./configs
```

## Makefile Integration

The Makefile provides convenient targets:

```bash
# List clusters
make list-clusters

# Deploy
make deploy-cluster CLUSTER=cairo MODE=rdma
make deploy-cluster CLUSTER=barcelona MODE=tcp

# Dry run
make deploy-cluster-dry-run CLUSTER=cairo MODE=rdma

# Status
make status-cluster CLUSTER=cairo

# Clean up
make clean-cluster CLUSTER=cairo
```

## Troubleshooting

### Error: Cluster configuration not found

```bash
Error: Cluster configuration not found: clusters/my-cluster.yaml
Available clusters:
  - barcelona
  - cairo
  - template
```

**Solution**: Check spelling or create the configuration file.

### Storage Class Not Found

```bash
# Check available storage classes
oc get storageclass

# Update cluster config with correct class names
```

### RDMA Devices Not Available

```bash
# Check InfiniBand status on GPU node
oc debug node/<gpu-node>
chroot /host
ibstat

# Look for "State: Active" devices
# Update cluster config with active device names
```

### Privileged SCC Denied

```bash
# Check if privileged SCC is available
oc get scc privileged

# Request cluster admin to grant access
# Or set requires_privileged_scc: false and ipc_lock: false
```

## Best Practices

1. **Version Control**: Commit cluster configs to git
2. **Documentation**: Use the `notes` field for setup instructions
3. **Testing**: Always do a dry run first
4. **Validation**: Verify generated configs before applying
5. **Security**: Only use privileged SCC when necessary
6. **Storage**: Prefer RWX storage when available for better collaboration

## Examples

See the following files for complete examples:
- `clusters/cairo.yaml` - RWX storage, RDMA, privileged SCC
- `clusters/barcelona.yaml` - Per-pod storage, no privileged SCC
- `clusters/template.yaml` - Fully documented template

## Related Documentation

- [Multi-Node Quickstart](MULTI-NODE-QUICKSTART.md) - Multi-node deployment guide
- [Multi-Node TCP Guide](MULTI-NODE-TCP-GUIDE.md) - TCP/Ethernet mode
- [Cairo Cluster Results](CAIRO_CLUSTER_RWX_RESULTS.md) - Cairo test results
