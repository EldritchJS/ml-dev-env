# Cluster Discovery Guide

Automatically discover and generate cluster configuration files for new OpenShift/Kubernetes clusters.

## Overview

The `discover-cluster.py` script connects to your cluster and automatically detects:

- ✅ Cluster API endpoint
- ✅ GPU nodes (via nvidia.com/gpu.present label)
- ✅ GPU type and count per node (H100, A100, etc.)
- ✅ RDMA/InfiniBand devices (Mellanox mlx5_* adapters)
- ✅ Storage classes (RWX and RWO)
- ✅ Network configuration (RDMA vs TCP)
- ✅ Security requirements (privileged SCC)

## Quick Start

### Prerequisites

1. **Login to your cluster:**

   ```bash
   oc login https://api.your-cluster.com:6443
   ```

2. **Switch to your namespace:**

   ```bash
   oc project my-ml-namespace
   ```

### Discover Configuration

**Using Makefile (recommended):**

```bash
make discover-cluster NAME=my-cluster
```

**Using script directly:**

```bash
./scripts/discover-cluster.py --name my-cluster
```

### Review and Deploy

```bash
# Review generated configuration
cat clusters/my-cluster.yaml

# Edit if needed
vim clusters/my-cluster.yaml

# Deploy to cluster
make deploy-cluster CLUSTER=my-cluster MODE=tcp
```

## Usage Examples

### Example 1: Basic Discovery

```bash
# Login and switch namespace
oc login https://api.shift.nerc.mghpcc.org:6443
oc project ml-training

# Discover configuration
make discover-cluster NAME=nerc-shift
```

**Output:**

```
🔍 Discovering cluster configuration for: nerc-shift

🔍 Discovering cluster information...
🖥️  Discovering GPU nodes...
   ✓ Found 25 GPU nodes
   ✓ GPU type: NVIDIA H100 80GB HBM3
   ✓ GPUs per node: 4
🔗 Discovering RDMA/InfiniBand configuration...
   Checking node wrk-97 for InfiniBand devices...
   ℹ️  No RDMA/InfiniBand detected - will use TCP
💾 Discovering storage classes...
   ✓ RWX storage available: nfs-csi
   ✓ RWO storage: ocs-external-storagecluster-ceph-rbd
🔒 Discovering security configuration...
   ✓ Privileged SCC: Available

✅ Configuration saved to: clusters/nerc-shift.yaml
```

### Example 2: Custom Namespace

```bash
# Discover with specific namespace
make discover-cluster NAME=prod NAMESPACE=production
```

### Example 3: Custom Output Path

```bash
# Save to custom location
./scripts/discover-cluster.py --name my-cluster --output /tmp/my-config.yaml
```

### Example 4: Dry Run (Preview Only)

```bash
# Print configuration without saving
./scripts/discover-cluster.py --name my-cluster --dry-run
```

## What Gets Discovered

### 1. Cluster Information

```yaml
cluster:
  name: my-cluster
  api: api.shift.nerc.mghpcc.org
  namespace: ml-training
  description: "Auto-discovered configuration for my-cluster"
```

**How it works:**

- API endpoint from `oc whoami --show-server`
- Namespace from current context or `--namespace` flag

### 2. GPU Nodes

```yaml
nodes:
  gpu_nodes:
    - wrk-97
    - wrk-98
    - wrk-99
    # ... up to 10 nodes listed

gpus:
  per_node: 4
  type: "NVIDIA H100 80GB HBM3"
  default_nodes: 2
```

**How it works:**

- Finds nodes with `nvidia.com/gpu.present=true` label
- Reads GPU count from node capacity
- Detects GPU type from node labels or description
- Lists up to 10 nodes in config (more available for deployment)

### 3. RDMA/InfiniBand

```yaml
network:
  rdma:
    enabled: true
    devices: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"
```

**How it works:**

- Checks for RDMA network attachments
- Looks for Mellanox device hints in node labels/annotations
- Falls back to TCP if no RDMA detected

### 4. Storage Classes

```yaml
storage:
  class_rwx: nfs-csi
  class_rwo: ocs-external-storagecluster-ceph-rbd
  workspace_size: 100Gi
  datasets_size: 500Gi
  mode: rwx  # or "volumeClaimTemplates"
```

**How it works:**

- Lists all storage classes
- Identifies RWX classes (nfs, cephfs, rwx in name)
- Identifies RWO classes (rbd, ceph, rwo in name)
- Sets mode to `rwx` if RWX storage available, otherwise `volumeClaimTemplates`

### 5. Security Configuration

```yaml
security:
  service_account: ml-dev-sa
  requires_privileged_scc: false  # true if RDMA enabled
  ipc_lock: false  # true if RDMA enabled
```

**How it works:**

- Checks if privileged SCC exists
- Automatically sets privileged requirements if RDMA detected
- Conservative default (no privileges) for TCP-only clusters

## Troubleshooting

### No GPU Nodes Found

**Issue:**

```
⚠️  No GPU nodes found with label nvidia.com/gpu.present=true
```

**Solution:**
Check node labels:

```bash
# List all nodes
oc get nodes

# Check for GPU labels
oc get nodes -o json | jq '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name'

# Check specific node
oc describe node <node-name> | grep -i gpu
```

If nodes have GPUs but no label, manually add the label:

```bash
oc label node <node-name> nvidia.com/gpu.present=true
```

### RDMA Not Detected

**Issue:**

```
ℹ️  No RDMA/InfiniBand detected - will use TCP
```

**Solution:**
Check for InfiniBand manually:

```bash
# Debug node
oc debug node/<gpu-node>
chroot /host

# Check for Mellanox devices
ibstat
# or
ls /sys/class/infiniband/

# Check for network attachments
oc get network-attachment-definitions -A
```

If RDMA exists but wasn't detected:

1. Edit the generated config file
2. Set `network.rdma.enabled: true`
3. Add correct device names from `ibstat`

### Storage Classes Not Found

**Issue:**

```
⚠️  No storage classes found
```

**Solution:**

```bash
# List storage classes
oc get storageclass

# If none exist, you'll need to work with cluster admin
# to set up storage provisioners
```

### Permission Errors

**Issue:**

```
Error running command: oc get nodes
Error: Forbidden
```

**Solution:**
Ensure you have sufficient permissions:

```bash
# Check current permissions
oc auth can-i list nodes

# If insufficient, request cluster-reader role
# (contact cluster administrator)
```

## Advanced Usage

### Filtering GPU Nodes

If you want to use specific nodes, manually edit the generated config:

```yaml
nodes:
  gpu_nodes:
    - wrk-100  # Only use these specific nodes
    - wrk-101
```

### Custom RDMA Configuration

If auto-detection misses devices, manually configure:

```yaml
network:
  rdma:
    enabled: true
    devices: "mlx5_0,mlx5_1,mlx5_2,mlx5_3"  # Your actual devices
    interfaces: "net1,net2,net3,net4"
```

### Override Storage Mode

Force per-pod storage even if RWX available:

```yaml
storage:
  mode: volumeClaimTemplates  # Force per-pod
```

### Adjust Resource Limits

Customize based on your needs:

```yaml
resources:
  requests:
    memory: 256Gi  # Increase for larger models
    cpu: 64
  limits:
    memory: 512Gi
    cpu: 128
```

## Post-Discovery Checklist

After generating configuration:

- [ ] Review generated config: `cat clusters/<name>.yaml`
- [ ] Verify GPU nodes are correct
- [ ] Confirm RDMA/TCP mode is appropriate
- [ ] Check storage class names are valid
- [ ] Adjust resource limits if needed
- [ ] Update namespace if different
- [ ] Edit notes section with cluster-specific info
- [ ] Test deployment: `make deploy-cluster-dry-run CLUSTER=<name> MODE=<tcp|rdma>`
- [ ] Deploy: `make deploy-cluster CLUSTER=<name> MODE=<tcp|rdma>`

## Reference

### Command Line Options

```
./scripts/discover-cluster.py [OPTIONS]

Options:
  --name NAME          Cluster name (required)
  --namespace NS       Kubernetes namespace (default: current)
  --output FILE        Output file path (default: clusters/<name>.yaml)
  --dry-run           Print to stdout instead of saving
  -h, --help          Show help message
```

### Makefile Targets

```bash
make discover-cluster NAME=<name> [NAMESPACE=<ns>]
make list-clusters
make deploy-cluster CLUSTER=<name> MODE=<tcp|rdma>
```

### Environment Variables

The script uses `oc` commands and inherits your current cluster context:

- Current cluster from `~/.kube/config`
- Current namespace from `oc project`
- Authentication from `oc login`

## Related Documentation

- [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) - Complete cluster configuration reference
- [MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md) - Quick deployment guide
- [MULTI-NODE-TCP-GUIDE.md](MULTI-NODE-TCP-GUIDE.md) - TCP vs RDMA networking

## Examples

### Discover NERC Production

```bash
oc login https://api.shift.nerc.mghpcc.org:6443
oc project coops-767192
make discover-cluster NAME=nerc-prod
cat clusters/nerc-prod.yaml
make deploy-cluster CLUSTER=nerc-prod MODE=tcp
```

### Discover Barcelona

```bash
oc login https://barcelona.nerc.mghpcc.org:6443
oc project nccl-test
make discover-cluster NAME=bcn
cat clusters/bcn.yaml
make deploy-cluster CLUSTER=bcn MODE=rdma
```

### Compare Multiple Clusters

```bash
# Discover multiple clusters
make discover-cluster NAME=cluster-a
make discover-cluster NAME=cluster-b

# Compare
diff clusters/cluster-a.yaml clusters/cluster-b.yaml
```
