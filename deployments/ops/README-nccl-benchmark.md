# N-Node NCCL Benchmark - Gold Standard Configuration

This directory contains templates and scripts for running the gold standard NCCL benchmark on any H100 cluster with N nodes.

## Overview

The benchmark tests NCCL AllReduce performance across multiple nodes with 4 GPUs each. This configuration validates:
- Multi-node GPU communication via RDMA
- Network performance and bandwidth
- NCCL collective operation efficiency
- GPUDirect RDMA with DMA-BUF

## Files

- **nccl-benchmark-template.yaml**: Complete benchmark deployment for N nodes
  - **ConfigMap**: Contains the `allreduce-loop.py` benchmark script
  - **StatefulSet**: Deploys N pods with the benchmark environment
  - **Service**: Headless service for pod-to-pod communication
  - The benchmark script is automatically mounted at `/benchmark/allreduce-loop.py` in each pod
- **run-benchmark.sh**: Parallel execution script for torchrun (configurable for N nodes)
- **README-nccl-benchmark.md**: This file

## Prerequisites

1. **Kubernetes cluster** with N H100 nodes (4 GPUs per node, where N ≥ 2)
2. **NVIDIA GPU Operator** installed and functional
3. **Container image** with NCCL, PyTorch, and benchmark code
4. **SR-IOV Network Operator** with network attachments configured:
   - `eno5np0-network` (net1)
   - `eno6np0-network` (net2)
   - `eno7np0-network` (net3)
   - `eno8np0-network` (net4)
5. **Network configuration**:
   - RDMA enabled on ConnectX NICs
   - Isolated /24 subnets for each SR-IOV interface
   - SR-IOV device plugin exposing `openshift.io/eno[5-8]np0rdma` resources

## Quick Start

### 1. Configure Node Count and Selection

Edit `nccl-benchmark-template.yaml`:

**A. Set number of nodes (replicas):**
```yaml
spec:
  replicas: 4  # CHANGE THIS: 2, 4, 8, 16, etc.
```

**B. List target nodes in nodeAffinity:**
```yaml
values:
  # MODIFY THESE NODE NAMES - Must match replicas count
  - your-node-1
  - your-node-2
  - your-node-3
  - your-node-4
  # Add more nodes if replicas > 4
```

**Important:** The number of nodes in the `values` list must equal or exceed the `replicas` count.

**How to find available nodes:**
```bash
kubectl get nodes -l nvidia.com/gpu.product=NVIDIA-H100-80GB-HBM3
```

### 2. Verify NCCL_IB_HCA Settings (IMPORTANT)

Before deploying, verify that the InfiniBand device names match your cluster. The default is `mlx5_6,mlx5_7,mlx5_8,mlx5_9`.

**Check IB devices on your nodes:**
```bash
# Pick one of your target nodes
NODE_NAME="your-node-1"

# Method 1: Using ibdev2netdev (if available)
kubectl debug node/$NODE_NAME --image=nvcr.io/nvidia/mellanox/doca-driver:24.01-0.3.8.0-0-24.01-1.1.4.0-ubuntu22.04-amd64 \
  -- chroot /host ibdev2netdev

# Method 2: Check /sys/class/infiniband
kubectl debug node/$NODE_NAME --image=registry.access.redhat.com/ubi9/ubi:latest \
  -- chroot /host ls -1 /sys/class/infiniband/
```

**Expected output from ibdev2netdev:**
```
mlx5_6 port 1 ==> eno5np0 (Up)
mlx5_7 port 1 ==> eno6np0 (Up)
mlx5_8 port 1 ==> eno7np0 (Up)
mlx5_9 port 1 ==> eno8np0 (Up)
```

**Expected output from ls /sys/class/infiniband:**
```
mlx5_6
mlx5_7
mlx5_8
mlx5_9
```

**If device names are different** (e.g., `mlx5_0,mlx5_1,mlx5_2,mlx5_3`), edit the YAML before deploying:

```yaml
- name: NCCL_IB_HCA
  value: "mlx5_0,mlx5_1,mlx5_2,mlx5_3"  # Update with your device names
```

**Note:** Device names typically follow the pattern `mlx5_X` where X is the device index. On some clusters, the first NICs might be `mlx5_0-3`, while on others they start at higher indices like `mlx5_6-9`. Use **all 4 InfiniBand devices** for optimal performance.

**⚠️ HETEROGENEOUS CLUSTERS:**

If your nodes have **different** mlx5 device assignments (e.g., node-1 uses `mlx5_0-3`, node-2 uses `mlx5_6-9`), **you cannot use a single hardcoded NCCL_IB_HCA value**. See "Advanced Configuration - Auto-Detecting IB Devices" below for solutions.

To check if you have a heterogeneous cluster:
```bash
# Check multiple nodes
for node in node-1 node-2 node-3; do
  echo "=== $node ==="
  kubectl debug node/$node --image=registry.access.redhat.com/ubi9/ubi:latest \
    -- chroot /host ls -1 /sys/class/infiniband/
done
```

If the output shows different device names across nodes, use auto-detection.

### 3. Deploy the Benchmark

```bash
kubectl apply -f deployments/ops/nccl-benchmark-template.yaml
```

### 4. Wait for Pods to be Running

```bash
kubectl get pods -n nccl-test -w
```

All N pods must show `Running` status before proceeding. Example for 4 nodes:
```
NAME               READY   STATUS    RESTARTS   AGE
nccl-benchmark-0   1/1     Running   0          2m
nccl-benchmark-1   1/1     Running   0          2m
nccl-benchmark-2   1/1     Running   0          2m
nccl-benchmark-3   1/1     Running   0          2m
```

### 5. Run the Benchmark

**A. Update script for your node count:**

Edit `run-benchmark.sh` and change:
```bash
NUM_NODES=4  # Change to match your replicas count (2, 8, 16, etc.)
```

**B. Execute the benchmark:**
```bash
./deployments/ops/run-benchmark.sh
```

**With custom iteration count:**
```bash
./deployments/ops/run-benchmark.sh 5  # Run 5 iterations instead of default 3
```

**Note:** The script automatically runs torchrun on all NUM_NODES pods in parallel.

### 6. View Results

The script automatically displays results from the master node (rank 0). Results include:
- Bandwidth per message size (GB/s)
- Average across iterations
- NCCL configuration details

## Expected Performance

### Without Rate Limiting

For ConnectX-7 400G NICs with Ring AllReduce:
- **Per-GPU bandwidth**: ~12.4 GB/s (independent of node count)
- **Total aggregate**: ~49.5 GB/s per node (4 GPUs × 12.4 GB/s)
- **8GB messages**: Optimal performance
- **Smaller messages**: Lower bandwidth due to latency

**Examples by node count:**
- 2 nodes (8 GPUs): ~99 GB/s aggregate
- 4 nodes (16 GPUs): ~198 GB/s aggregate
- 8 nodes (32 GPUs): ~396 GB/s aggregate

**Note:** Ring AllReduce provides constant per-GPU bandwidth regardless of cluster size. Total aggregate bandwidth scales linearly with GPU count.

### With 100 Gbps Rate Limiting

If hardware rate limiting is applied (100 Gbps per NIC):
- **Per-GPU bandwidth**: ~3.06 GB/s
- **Total per node**: ~12.25 GB/s (4 GPUs × 3.06 GB/s)
- **8GB messages**: Best efficiency (>98% of theoretical 12.5 GB/s per node)

**Examples by node count:**
- 2 nodes: ~24.5 GB/s aggregate
- 4 nodes: ~49 GB/s aggregate
- 8 nodes: ~98 GB/s aggregate

## Configuration Details

### Critical NCCL Environment Variables

These are pre-configured in the YAML template. **Do not modify** unless you understand the implications:

```yaml
NCCL_DMABUF_ENABLE: "1"              # Required - GPUDirect RDMA via DMA-BUF
NCCL_CROSS_NIC: "0"                  # Required - isolated subnet config
NCCL_IB_HCA: "mlx5_6,mlx5_7,mlx5_8,mlx5_9"  # Explicit IB device list
```

**Why these settings matter:**
- `NCCL_DMABUF_ENABLE=1`: Enables GPUDirect RDMA without nvidia_peermem kernel module
- `NCCL_CROSS_NIC=0`: Prevents cross-NIC traffic (required for isolated subnets)
- `NCCL_IB_HCA`: Explicitly lists all 4 InfiniBand NICs for use

### Performance Tuning Variables

These optimize NCCL performance and are pre-configured:

```yaml
NCCL_MIN_NCHANNELS: "8"
NCCL_MAX_NCHANNELS: "16"
NCCL_NET_GDR_LEVEL: "5"              # Maximum GPUDirect level
NCCL_NET_GDR_READ: "1"               # Enable GPU-initiated RDMA reads
NCCL_PROTO: "Simple"                 # Simple protocol for large messages
NCCL_ALGO: "Ring"                    # Ring algorithm
```

### Debugging

To enable NCCL debug output, uncomment these lines in the YAML:

```yaml
- name: NCCL_DEBUG
  value: "INFO"
- name: NCCL_DEBUG_SUBSYS
  value: "INIT,NET"
```

## Manual Execution (Alternative to Script)

If you prefer to run torchrun manually instead of using the script:

### Step 1: Start on Pod 0 (Master)

```bash
kubectl exec -n nccl-test nccl-benchmark-0 -- bash -c \
  "torchrun --nnodes=4 --nproc_per_node=4 --node_rank=0 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py -r 3 \
   > /workspace/benchmark-output.log 2>&1" &
```

### Step 2: Start on Pods 1-3 (Workers)

**Pod 1:**
```bash
kubectl exec -n nccl-test nccl-benchmark-1 -- bash -c \
  "torchrun --nnodes=4 --nproc_per_node=4 --node_rank=1 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py -r 3 \
   > /workspace/benchmark-output.log 2>&1" &
```

**Pod 2:**
```bash
kubectl exec -n nccl-test nccl-benchmark-2 -- bash -c \
  "torchrun --nnodes=4 --nproc_per_node=4 --node_rank=2 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py -r 3 \
   > /workspace/benchmark-output.log 2>&1" &
```

**Pod 3:**
```bash
kubectl exec -n nccl-test nccl-benchmark-3 -- bash -c \
  "torchrun --nnodes=4 --nproc_per_node=4 --node_rank=3 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py -r 3 \
   > /workspace/benchmark-output.log 2>&1" &
```

### Step 3: Wait and View Results

```bash
# Wait for all to complete, then view results
kubectl exec -n nccl-test nccl-benchmark-0 -- cat /workspace/benchmark-output.log
```

## Scaling to Different Node Counts

The template works for any number of nodes. Simply adjust the configuration:

### General Process

1. **Set replicas** in YAML to desired node count (2, 8, 16, etc.)
2. **List N node names** in the `values` section (must match replicas)
3. **Update NUM_NODES** in the script to match replicas
4. **Run benchmark**

### Examples

**2-Node (8 GPUs):**
- YAML: `replicas: 2`, list 2 nodes
- Script: `NUM_NODES=2`
- Expected: ~99 GB/s aggregate (no rate limiting)

**8-Node (32 GPUs):**
- YAML: `replicas: 8`, list 8 nodes
- Script: `NUM_NODES=8`
- Expected: ~396 GB/s aggregate (no rate limiting)

**16-Node (64 GPUs):**
- YAML: `replicas: 16`, list 16 nodes
- Script: `NUM_NODES=16`
- Expected: ~792 GB/s aggregate (no rate limiting)

**Note:** The Ring AllReduce algorithm provides consistent per-GPU bandwidth regardless of node count. Total aggregate bandwidth scales linearly.

## Troubleshooting

### Pods Stuck in Pending

**Cause:** Not enough nodes available or node affinity mismatch

**Fix:**
```bash
# Check which nodes have GPUs available
kubectl get nodes -l nvidia.com/gpu.product=NVIDIA-H100-80GB-HBM3

# Check pod events
kubectl describe pod -n nccl-test nccl-benchmark-0
```

### Benchmark Hangs or Times Out

**Cause:** Not all pods are Running when torchrun starts

**Fix:**
```bash
# Verify all pods are Running
kubectl get pods -n nccl-test

# Check NCCL debug logs
kubectl logs -n nccl-test nccl-benchmark-0
```

### Low Bandwidth Results

**Common causes:**

1. **Missing NCCL_DMABUF_ENABLE=1**
   - Symptom: ~10-20 GB/s instead of ~198 GB/s (4-node)
   - Fix: Verify environment variable is set

2. **NCCL_CROSS_NIC=1 (wrong value)**
   - Symptom: Erratic performance or errors
   - Fix: Must be "0" for isolated subnet configuration

3. **Wrong NCCL_IB_HCA**
   - Symptom: Only using 1-2 NICs instead of all 4, or NCCL errors about missing devices
   - Fix: See "Quick Start - Step 2" to verify correct device names for your cluster
   - Check NCCL logs: `kubectl logs -n nccl-test nccl-benchmark-0 | grep "NET/IB"` to see which devices NCCL detected

4. **Rate limiting applied**
   - Symptom: Capped at ~49 GB/s
   - Fix: Check if mlnx_qos rate limiting is active (expected for some tests)

### Pod Fails to Start

**Cause:** Image pull issues or resource constraints

**Fix:**
```bash
# Check pod status and events
kubectl describe pod -n nccl-test nccl-benchmark-0

# Verify image is accessible
kubectl get pods -n nccl-test nccl-benchmark-0 -o jsonpath='{.status.containerStatuses[0].image}'
```

## Cleanup

### Delete Benchmark Resources

```bash
kubectl delete -f deployments/ops/nccl-benchmark-template.yaml
```

This deletes:
- ConfigMap (nccl-benchmark-script)
- StatefulSet (nccl-benchmark)
- Service (nccl-benchmark-svc)
- All associated pods

### Verify Cleanup

```bash
kubectl get all,configmap -n nccl-test
```

Should show no benchmark resources (only default cluster ConfigMaps like `kube-root-ca.crt`).

## Customization

### Using Different Container Image

Edit the `image:` field in `nccl-benchmark-template.yaml`:

```yaml
image: your-registry/your-image:tag
```

**Requirements for custom image:**
- NVIDIA PyTorch with NCCL support
- CUDA and NCCL libraries compatible with H100

**Note:** The benchmark script is provided via ConfigMap, so your image doesn't need to include it. The ConfigMap mounts `/benchmark/allreduce-loop.py` into the container automatically.

### Modifying the Benchmark Script

The benchmark script is defined in the ConfigMap at the top of `nccl-benchmark-template.yaml`. To customize:

1. Edit the `allreduce-loop.py` content in the ConfigMap section
2. Common modifications:
   - Change message sizes (line with `for nMB in [...]`)
   - Adjust iteration counts (`maxiter` calculations)
   - Modify warmup behavior
   - Add custom tensor operations

3. Redeploy with the updated ConfigMap:
   ```bash
   kubectl delete -f deployments/ops/nccl-benchmark-template.yaml
   kubectl apply -f deployments/ops/nccl-benchmark-template.yaml
   ```

**Tip:** The script is from IBM and tests NCCL AllReduce across various message sizes from 0.1 MB to 8 GB.

### Changing Network Interfaces

**InfiniBand Device Names:**

See "Quick Start - Step 2: Verify NCCL_IB_HCA Settings" for detailed instructions.

If your cluster uses different InfiniBand device names than the default `mlx5_6,mlx5_7,mlx5_8,mlx5_9`, you must update `NCCL_IB_HCA` in the YAML:

```yaml
- name: NCCL_IB_HCA
  value: "mlx5_0,mlx5_1,mlx5_2,mlx5_3"  # Your device names
```

To find device names:
```bash
kubectl debug node/your-node --image=registry.access.redhat.com/ubi9/ubi:latest \
  -- chroot /host ls -1 /sys/class/infiniband/
```

**SR-IOV Network Names:**

This template uses SR-IOV network attachments. If your cluster uses different network names, update:

1. **Pod annotations** (spec.template.metadata.annotations):
   ```yaml
   k8s.v1.cni.cncf.io/networks: your-net1,your-net2,your-net3,your-net4
   ```

2. **NCCL_SOCKET_IFNAME** environment variable:
   ```yaml
   - name: NCCL_SOCKET_IFNAME
     value: "your-net1,your-net2,your-net3,your-net4"
   ```

3. **SR-IOV resource requests** (must match your SR-IOV device plugin resource names):
   ```yaml
   resources:
     requests:
       your-cluster.io/rdma-resource-1: 1
       your-cluster.io/rdma-resource-2: 1
       # etc.
   ```

**Note:** This cluster uses OpenShift with `eno5np0-network`, `eno6np0-network`, `eno7np0-network`, `eno8np0-network` network attachments and `openshift.io/eno[5-8]np0rdma` SR-IOV resources.

## Advanced Configuration

### Auto-Detecting IB Devices (Heterogeneous Clusters)

If different nodes have different mlx5 device assignments, use this approach to auto-detect InfiniBand devices at runtime.

**Option 1: Wrapper Script (Recommended)**

Modify the container `command` in the YAML to use a startup script:

```yaml
containers:
- name: nccl-test
  image: your-image:tag
  command: ["/bin/bash", "-c"]
  args:
  - |
    # Auto-detect InfiniBand devices
    IB_DEVICES=$(ls /sys/class/infiniband/ | sort | tr '\n' ',' | sed 's/,$//')
    export NCCL_IB_HCA="$IB_DEVICES"

    echo "Auto-detected NCCL_IB_HCA=$NCCL_IB_HCA"

    # Keep container running for benchmark execution
    sleep infinity
  env:
  # Remove or comment out hardcoded NCCL_IB_HCA
  # - name: NCCL_IB_HCA
  #   value: "mlx5_6,mlx5_7,mlx5_8,mlx5_9"
  - name: NCCL_DMABUF_ENABLE
    value: "1"
  # ... other env vars
```

**Option 2: Init Container**

Add an init container that writes device names to a shared volume:

```yaml
initContainers:
- name: detect-ib-devices
  image: registry.access.redhat.com/ubi9/ubi:latest
  command: ["/bin/bash", "-c"]
  args:
  - |
    IB_DEVICES=$(ls /sys/class/infiniband/ | sort | tr '\n' ',' | sed 's/,$//')
    echo "export NCCL_IB_HCA=\"$IB_DEVICES\"" > /config/nccl-env.sh
    cat /config/nccl-env.sh
  volumeMounts:
  - name: nccl-config
    mountPath: /config

containers:
- name: nccl-test
  image: your-image:tag
  command: ["/bin/bash", "-c"]
  args:
  - |
    source /config/nccl-env.sh
    echo "Using NCCL_IB_HCA=$NCCL_IB_HCA"
    sleep infinity
  volumeMounts:
  - name: nccl-config
    mountPath: /config
  env:
  - name: NCCL_DMABUF_ENABLE
    value: "1"
  # ... other env vars except NCCL_IB_HCA

volumes:
- name: nccl-config
  emptyDir: {}
```

**Option 3: Per-Node ConfigMaps (Complex)**

For very heterogeneous clusters, create separate ConfigMaps per node with specific NCCL_IB_HCA values, then use `envFrom` with node-specific selectors.

**Verification:**

After deploying with auto-detection, verify each pod detected the correct devices:

```bash
# Check detected devices on each pod
for i in {0..3}; do
  echo "=== Pod nccl-benchmark-$i ==="
  kubectl exec -n nccl-test nccl-benchmark-$i -- bash -c 'echo $NCCL_IB_HCA'
  kubectl exec -n nccl-test nccl-benchmark-$i -- ls /sys/class/infiniband/
done
```

All pods should show all 4 InfiniBand devices available on their respective nodes.

## Performance Validation

### Baseline Expectations (Per-GPU Bandwidth)

With ConnectX-7 400G NICs and Ring AllReduce, expect ~12.4 GB/s per GPU regardless of cluster size:

| Message Size | Per-GPU BW | Notes |
|--------------|-----------|-------|
| 8 GB         | ~12.4 GB/s| Optimal for Ring AllReduce |
| 4 GB         | ~12.2 GB/s| Close to maximum |
| 2 GB         | ~11.5 GB/s| Slightly lower |
| 1 GB         | ~10.6 GB/s| Latency starts to matter |
| 512 MB       | ~9.3 GB/s | More latency impact |

### Aggregate Bandwidth by Cluster Size

**Without rate limiting:**

| Node Count | Total GPUs | Aggregate BW (8GB messages) |
|-----------|-----------|---------------------------|
| 2 nodes   | 8 GPUs    | ~99 GB/s                  |
| 4 nodes   | 16 GPUs   | ~198 GB/s                 |
| 8 nodes   | 32 GPUs   | ~396 GB/s                 |
| 16 nodes  | 64 GPUs   | ~792 GB/s                 |

**With 100 Gbps rate limiting (~3.06 GB/s per GPU):**

| Node Count | Total GPUs | Aggregate BW (8GB messages) |
|-----------|-----------|---------------------------|
| 2 nodes   | 8 GPUs    | ~24.5 GB/s                |
| 4 nodes   | 16 GPUs   | ~49 GB/s                  |
| 8 nodes   | 32 GPUs   | ~98 GB/s                  |
| 16 nodes  | 64 GPUs   | ~196 GB/s                 |

If you see significantly lower performance, review the Troubleshooting section.

## References

- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [NCCL Environment Variables](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)
- [GPUDirect RDMA](https://docs.nvidia.com/cuda/gpudirect-rdma/)
- Project guide: `claude_guidance/nccl-configuration-h100-cluster.md`

## Support

For issues specific to this cluster:
1. Check `claude_guidance/` directory for operational guides
2. Review `deployments/h-kim/` for investigation docs
3. Check git history for related changes

For NCCL-specific issues:
- [NVIDIA Developer Forums](https://forums.developer.nvidia.com/)
- NCCL GitHub Issues

---

**Last Updated:** April 3, 2026
