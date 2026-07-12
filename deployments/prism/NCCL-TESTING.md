# NCCL Testing Guide for Prism Deployment

## Overview

This guide explains how to run NCCL performance tests on the Barcelona H100 cluster using all 5 nodes for distributed training validation.

## Barcelona Cluster Nodes

**5 H100 GPU Nodes (4 GPUs each = 20 total GPUs):**
- moc-r4pcc02u17-nairr
- moc-r4pcc02u18-nairr  
- moc-r4pcc02u25-nairr
- moc-r4pcc02u15-yunshi
- moc-r4pcc02u16-yunshi

**Network:** Each node has 4x ConnectX-7 400G NICs with isolated /24 subnets.

## Critical NCCL Environment Variables

### **MUST HAVE - These are REQUIRED:**

```bash
# GPUDirect DMABUF - CRITICAL: This cluster has NO nvidia_peermem kernel module
NCCL_DMABUF_ENABLE=1

# Isolated subnet configuration - CRITICAL: Barcelona has isolated /24 subnets with NO inter-subnet routing
NCCL_CROSS_NIC=0

# IB devices - CRITICAL: Barcelona SR-IOV pods show exactly these 4 devices
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_8,mlx5_9
```

**Why these matter:**
- `NCCL_DMABUF_ENABLE=1`: Without this, GPUDirect RDMA won't work (no nvidia_peermem)
- `NCCL_CROSS_NIC=0`: Subnets are isolated (10.0.103/104/105/106.0/24), no routing between them
- `NCCL_IB_HCA`: Auto-detect breaks - these are the ONLY 4 mlx5 devices visible in SR-IOV pods

### Performance Settings (Recommended):

```bash
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=16
NCCL_NET_GDR_LEVEL=5
NCCL_NET_GDR_READ=1
NCCL_PROTO=Simple
NCCL_ALGO=Ring
```

## Quick Start: Run 5-Node NCCL Test (Recommended)

### Step 0: Generate the Manifest (if needed)

If you've changed the config (image, nodes, namespace, etc.), regenerate the manifest first:

```bash
./deployments/ops/generate-nccl-manifest.sh \
  -c deployments/ops/configs/barcelona-5node-prism.conf \
  -o deployments/prism/nccl-test-5node.yaml
```

### Gold Standard Method - Automated Script

**Use this method** - it deploys the StatefulSet and auto-starts the benchmark on all 5 pods:

```bash
cd deployments/prism
./run-5node-nccl-test.sh
```

The script will:
1. Deploy the 5-pod StatefulSet
2. Wait for all pods to be Running
3. Automatically start torchrun on all 5 pods in parallel
4. Save logs to `benchmark-pod-N.log` files

**Monitor results:**
```bash
tail -f deployments/prism/benchmark-pod-0.log
```

**Custom number of runs:**
```bash
./run-5node-nccl-test.sh 5  # Run 5 iterations instead of default 3
```

---

## Alternative: Manual Execution

If you need to run the benchmark manually on each pod:

### Step 1: Deploy the Test Pods

```bash
# From the prism directory
oc apply -f nccl-test-5node.yaml -n nccl-test
```

This creates a StatefulSet with 5 pods (one per node), each with 4 GPUs.

### Step 2: Wait for All Pods to be Running

```bash
oc get pods -n nccl-test -l app=nccl-benchmark -w
```

Wait until all 5 pods show `1/1 Running`. Press Ctrl+C when ready.

### Step 3: Run the Benchmark Manually

The benchmark must be run **on each pod separately** with a different `--node_rank`:

**On pod-0 (master):**
```bash
oc exec -it nccl-benchmark-0 -n nccl-test -- torchrun \
  --nnodes=5 \
  --nproc_per_node=4 \
  --node_rank=0 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 \
  /benchmark/allreduce-loop.py -r 3
```

**On pod-1:**
```bash
oc exec -it nccl-benchmark-1 -n nccl-test -- torchrun \
  --nnodes=5 \
  --nproc_per_node=4 \
  --node_rank=1 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 \
  /benchmark/allreduce-loop.py -r 3
```

**On pod-2:**
```bash
oc exec -it nccl-benchmark-2 -n nccl-test -- torchrun \
  --nnodes=5 \
  --nproc_per_node=4 \
  --node_rank=2 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 \
  /benchmark/allreduce-loop.py -r 3
```

**On pod-3:**
```bash
oc exec -it nccl-benchmark-3 -n nccl-test -- torchrun \
  --nnodes=5 \
  --nproc_per_node=4 \
  --node_rank=3 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 \
  /benchmark/allreduce-loop.py -r 3
```

**On pod-4:**
```bash
oc exec -it nccl-benchmark-4 -n nccl-test -- torchrun \
  --nnodes=5 \
  --nproc_per_node=4 \
  --node_rank=4 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 \
  /benchmark/allreduce-loop.py -r 3
```

### Step 4: Check Results

The benchmark output appears on **pod-0** stderr. Look for the 8000.00 MB row:

```
 size(MB)   tavg(usec)    tmin(usec)    tmax(usec)  avgbw(GB/sec)  maxbw(GB/sec)  minbw(GB/sec)
 8000.00     ...           ...           ...          ~194.15        ~194.80        ...
```

**Expected performance (5 nodes, 20 GPUs, no rate limiting):**
- Bus bandwidth at 8GB: **~194 GB/s** (matches gold standard)
- Per-GPU: ~12.4 GB/s (bus bandwidth is independent of node count for Ring AllReduce)


## Expected NCCL Output

When working correctly, you should see on pod-0:

```
nccl-benchmark-0:36:36 [0] NCCL INFO Channel 00/16 :    0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19
nccl-benchmark-0:36:36 [0] NCCL INFO Ring 00 : 0[0] -> 1[10000] -> 2[20000] -> 3[30000] -> 4[40000]
...
nccl-benchmark-0:36:36 [0] NCCL INFO Using 256 threads, Min Comp Cap 9, Trees disabled
nccl-benchmark-0:36:36 [0] NCCL INFO comm 0x... rank 0 nranks 20 cudaDev 0 busId 6000 - Init COMPLETE
```

## Troubleshooting

### Issue: Benchmark hangs at "waiting for rank X"

**Cause:** Not all pods are running or not all torchrun commands started.

**Fix:** 
1. Check all 5 pods are Running: `oc get pods -n nccl-test -l app=nccl-benchmark`
2. Ensure you ran all 5 torchrun commands with correct `--node_rank` (0, 1, 2, 3, 4)

### Issue: Low bandwidth (< 190 GB/s bus bandwidth)

**Cause:** Missing critical NCCL environment variables or hardware optimization.

**Fix:** Check the pod logs for NCCL warnings:
```bash
oc logs nccl-benchmark-0 -n nccl-test | grep -i nccl
```

Look for:
- `NCCL_DMABUF_ENABLE` should be `1`
- `NCCL_IB_HCA` should list 4 devices
- No warnings about "falling back to socket"

### Issue: NCCL_IB_HCA shows wrong devices

**Cause:** Using mlx5 device numbers from host instead of pod.

**Fix:** Barcelona pods ALWAYS show `mlx5_6,mlx5_7,mlx5_8,mlx5_9`. Never use auto-detect or host numbers.

## Cleaning Up

```bash
oc delete -f nccl-test-5node.yaml -n nccl-test
```

## References

- Benchmark generator: `deployments/ops/generate-nccl-manifest.sh`
- Config files: `deployments/ops/configs/`
- Gold standard reference: `deployments/ops/GOLD-STANDARD-NCCL-BENCHMARK.yaml`
- NCCL configuration guide: `claude_guidance/nccl-configuration-h100-cluster.md`
