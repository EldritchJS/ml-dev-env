# 4-Node NCCL Benchmark - Gold Standard Configuration

This directory contains templates and scripts for running the gold standard 4-node NCCL benchmark on any H100 cluster.

## Overview

The 4-node benchmark tests NCCL AllReduce performance across 4 nodes with 4 GPUs each (16 GPUs total). This configuration validates:
- Multi-node GPU communication via RDMA
- Network performance and bandwidth
- NCCL collective operation efficiency
- GPUDirect RDMA with DMA-BUF

## Files

- **nccl-benchmark-4node-template.yaml**: StatefulSet and Service definitions
- **run-4node-benchmark.sh**: Parallel execution script for torchrun
- **README-4node-nccl-benchmark.md**: This file

## Prerequisites

1. **Kubernetes cluster** with 4+ H100 nodes (4 GPUs per node)
2. **NVIDIA GPU Operator** installed and functional
3. **Container image** with NCCL, PyTorch, and benchmark code
4. **Network configuration**:
   - SR-IOV network interfaces configured
   - RDMA enabled on ConnectX NICs
   - Proper subnet configuration (isolated /24 subnets for multi-NIC)

## Quick Start

### 1. Modify Node Selection

Edit `nccl-benchmark-4node-template.yaml` and replace the node names in the `nodeAffinity` section:

```yaml
values:
  # MODIFY THESE NODE NAMES - Replace with your target nodes
  - your-node-1
  - your-node-2
  - your-node-3
  - your-node-4
```

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

### 3. Deploy the Benchmark

```bash
kubectl apply -f deployments/ops/nccl-benchmark-4node-template.yaml
```

### 4. Wait for Pods to be Running

```bash
kubectl get pods -n nccl-test -w
```

All 4 pods must show `Running` status before proceeding:
```
NAME               READY   STATUS    RESTARTS   AGE
nccl-benchmark-0   1/1     Running   0          2m
nccl-benchmark-1   1/1     Running   0          2m
nccl-benchmark-2   1/1     Running   0          2m
nccl-benchmark-3   1/1     Running   0          2m
```

### 5. Run the Benchmark

```bash
./deployments/ops/run-4node-benchmark.sh
```

**With custom iteration count:**
```bash
./deployments/ops/run-4node-benchmark.sh 5  # Run 5 iterations instead of default 3
```

### 6. View Results

The script automatically displays results from the master node (rank 0). Results include:
- Bandwidth per message size (GB/s)
- Average across iterations
- NCCL configuration details

## Expected Performance

### Without Rate Limiting

For 4 nodes with ConnectX-7 400G NICs:
- **8GB messages**: ~194 GB/s (typical)
- **Smaller messages**: Lower bandwidth due to latency

### With 100 Gbps Rate Limiting

If hardware rate limiting is applied (100 Gbps per NIC):
- **8GB messages**: ~49 GB/s
- **Efficiency**: Should be >97% of theoretical maximum (50 GB/s)

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

### 8-Node Benchmark

1. Change `replicas: 4` to `replicas: 8` in YAML
2. Add 4 more node names to the `values` list
3. Update `NUM_NODES=8` in the script (or pass different node count)
4. Run: `./run-4node-benchmark.sh` (update script name/copy for 8-node)

### 2-Node Benchmark

1. Change `replicas: 4` to `replicas: 2` in YAML
2. Use only 2 node names in the `values` list
3. Update `NUM_NODES=2` in the script
4. Run benchmark

**Note:** The Ring AllReduce algorithm provides consistent per-GPU bandwidth regardless of node count.

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
   - Symptom: ~10-20 GB/s instead of ~194 GB/s
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
kubectl delete -f deployments/ops/nccl-benchmark-4node-template.yaml
```

### Verify Cleanup

```bash
kubectl get all -n nccl-test
```

Should show no resources (only default ConfigMaps).

## Customization

### Using Different Container Image

Edit the `image:` field in `nccl-benchmark-4node-template.yaml`:

```yaml
image: your-registry/your-image:tag
```

**Requirements for custom image:**
- NVIDIA PyTorch with NCCL support
- Benchmark script at `/benchmark/allreduce-loop.py`
- CUDA and NCCL libraries compatible with H100

### Changing Network Interfaces

**See "Quick Start - Step 2: Verify NCCL_IB_HCA Settings" for detailed instructions.**

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

## Performance Validation

### Baseline Expectations

For 4 nodes × 4 GPUs (16 GPUs total) with ConnectX-7 400G NICs:

| Message Size | Expected Bandwidth | Notes |
|--------------|-------------------|-------|
| 8 GB         | ~194 GB/s         | Ring AllReduce, no rate limiting |
| 4 GB         | ~190 GB/s         | Close to maximum |
| 2 GB         | ~180 GB/s         | Slightly lower |
| 1 GB         | ~165 GB/s         | Latency starts to matter |
| 512 MB       | ~145 GB/s         | More latency impact |

### With 100 Gbps Rate Limiting

| Message Size | Expected Bandwidth | Efficiency |
|--------------|-------------------|------------|
| 8 GB         | ~49.0 GB/s        | 98-99%     |
| 4 GB         | ~48.8 GB/s        | 97-98%     |
| 2 GB         | ~48.5 GB/s        | 97%        |

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
