# PyTorch All-Reduce Benchmark - Manual Mode

This directory contains a flexible benchmark setup that allows you to scale pods up/down and run benchmarks on demand.

## Files

- **`pytorch-benchmark-manual.yaml`** - StatefulSet deployment that creates pods and waits for manual benchmark execution
- **`run-benchmark.sh`** - Script to run the all-reduce benchmark on all running pods

## Quick Start

### 1. Deploy the pods

```bash
oc apply -f deployments/h-kim/pytorch-benchmark-manual.yaml
```

This creates 2 pods by default in the `nccl-test` namespace. The pods initialize with:
- 4 H100 GPUs per pod
- 1200Gi memory
- SR-IOV RDMA networking (4 interfaces)
- Optimized NCCL configuration

### 2. Scale to desired number of nodes

```bash
# Scale to 6 nodes (24 GPUs total)
oc scale statefulset pytorch-bench-manual -n nccl-test --replicas=6

# Scale to 4 nodes (16 GPUs total)
oc scale statefulset pytorch-bench-manual -n nccl-test --replicas=4

# Scale to 1 node (4 GPUs total)
oc scale statefulset pytorch-bench-manual -n nccl-test --replicas=1
```

Check pod status:
```bash
oc get pods -n nccl-test -l app=pytorch-bench-manual
```

### 3. Run the benchmark

```bash
./deployments/h-kim/run-benchmark.sh
```

The script automatically:
- Detects the number of running pods
- Launches the benchmark on all pods in parallel
- Waits for completion
- Shows commands to view results

### 4. View results

```bash
# View full results (without NCCL debug logs)
oc logs pytorch-bench-manual-0 -n nccl-test | grep -v 'NCCL INFO' | tail -100

# View just the bandwidth table
oc logs pytorch-bench-manual-0 -n nccl-test | grep -E 'size\(MB\)|^\s+[0-9]+\.[0-9]+'
```

### 5. Clean up

```bash
oc delete -f deployments/h-kim/pytorch-benchmark-manual.yaml
```

## Advanced Usage

### Custom benchmark parameters

```bash
# Run with more iterations (multiplier=2)
MULTIPLIER=2 ./deployments/h-kim/run-benchmark.sh

# Use different namespace
NAMESPACE=my-namespace ./deployments/h-kim/run-benchmark.sh
```

### Manual execution (alternative to script)

If you prefer to run the benchmark manually:

```bash
# Get current number of nodes
NNODES=$(oc get pods -n nccl-test -l app=pytorch-bench-manual --no-headers | wc -l | tr -d ' ')

# Run on all pods
for i in $(seq 0 $((NNODES-1))); do
  oc exec -n nccl-test pytorch-bench-manual-$i -- bash -c \
    "torchrun --nnodes=$NNODES --nproc_per_node=4 --node_rank=$i \
      --master_addr=pytorch-bench-manual-0.pytorch-bench-manual-svc.nccl-test.svc.cluster.local \
      --master_port=29501 --rdzv_backend=c10d \
      --rdzv_endpoint=pytorch-bench-manual-0.pytorch-bench-manual-svc.nccl-test.svc.cluster.local:29501 \
      /benchmark/allreduce-loop.py --multiplier 1" &
done
wait
```

### Interactive mode

Exec into the master pod for interactive testing:

```bash
oc exec -it -n nccl-test pytorch-bench-manual-0 -- bash

# Inside the pod, run:
# torchrun --nnodes=<NUM_NODES> --nproc_per_node=4 --node_rank=0 \
#   --master_addr=$MASTER_ADDR --master_port=$MASTER_PORT \
#   /benchmark/allreduce-loop.py --multiplier 1
```

## Configuration

### Pod Configuration

Each pod is configured with:
- **GPUs:** 4x NVIDIA H100 80GB HBM3
- **Memory:** 1200Gi (request and limit)
- **CPU:** 32 (request), 64 (limit)
- **Network:** SR-IOV RDMA with 4 interfaces (eno5np0, eno6np0, eno7np0, eno8np0)

### NCCL Optimizations

Key NCCL settings applied:
- `NCCL_ALGO=Ring`
- `NCCL_NET_GDR_LEVEL=5` (GPUDirect RDMA)
- `NCCL_MIN_NCHANNELS=8`, `NCCL_MAX_NCHANNELS=16`
- `NCCL_SOCKET_IFNAME=net1,net2,net3,net4`
- `NCCL_IB_GID_INDEX=3`
- `NCCL_DMABUF_ENABLE=1`

### Available Nodes

The StatefulSet can deploy to these -nairr nodes:
- moc-r4pcc04u09-nairr
- moc-r4pcc04u11-nairr
- moc-r4pcc04u12-nairr
- moc-r4pcc04u16-nairr
- moc-r4pcc04u25-nairr
- moc-r4pcc04u36-nairr

## Expected Performance

For 6 nodes (24 GPUs):
- **Peak bandwidth (8GB messages):** ~193 GB/s
- **Large messages (100MB-8GB):** 150-193 GB/s
- **Medium messages (10-100MB):** 19-152 GB/s
- **Small messages (<10MB):** <19 GB/s

## Troubleshooting

### Pods stuck in ContainerCreating
Check if nodes have available resources:
```bash
oc describe pod pytorch-bench-manual-0 -n nccl-test
```

### Benchmark hangs or fails
Check NCCL logs for errors:
```bash
oc logs pytorch-bench-manual-0 -n nccl-test | grep -i error
```

Verify RDMA devices are available:
```bash
oc exec -n nccl-test pytorch-bench-manual-0 -- ls -la /dev/infiniband/
```

### No bandwidth results
Ensure the benchmark completed:
```bash
oc logs pytorch-bench-manual-0 -n nccl-test | tail -50
```

## See Also

- `BENCHMARK-README.md` - Information about automatic benchmark deployments
- `README.md` - Main h-kim deployment documentation
- `pytorch-benchmark-6-nodes.yaml` - Auto-run benchmark (runs on pod startup)
