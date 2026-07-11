# NCCL Benchmark Setup Guide for h-kim Namespace

This guide provides step-by-step instructions for setting up and running 8-node NCCL benchmarks in your namespace.

## Prerequisites

- Access to OpenShift cluster (Barcelona/MOC)
- Your namespace: `b-efficient-memory-offloading-765cab`
- kubectl/oc CLI configured and authenticated
- 8 H100 GPU nodes available

## Complete Setup (One-Time)

Follow these steps in order. You only need to do this once per namespace.

### Step 1: Deploy Network Attachments

**What this does:** Creates 4 SR-IOV network interfaces (one per GPU) with proper IP subnet isolation.

```bash
# Apply network attachments to your namespace
kubectl apply -f network-attachments.yaml -n b-efficient-memory-offloading-765cab
```

**Expected output:**
```
networkattachmentdefinition.k8s.cni.cncf.io/eno5np0-network created
networkattachmentdefinition.k8s.cni.cncf.io/eno6np0-network created
networkattachmentdefinition.k8s.cni.cncf.io/eno7np0-network created
networkattachmentdefinition.k8s.cni.cncf.io/eno8np0-network created
```

**Verify:**
```bash
kubectl get network-attachment-definitions -n b-efficient-memory-offloading-765cab
```

You should see all 4 networks listed.

### Step 2: Configure Service Account Permissions

**What this does:** Grants your service account the security permissions needed for RDMA and GPU access.

```bash
# Add nccl-scc permissions to your service account
oc adm policy add-scc-to-user nccl-scc \
  system:serviceaccount:b-efficient-memory-offloading-765cab:h-kim-sa
```

**Expected output:**
```
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:nccl-scc added: "h-kim-sa"
```

**Verify:**
```bash
oc adm policy who-can use scc nccl-scc | grep h-kim-sa
```

You should see your service account listed.

### Step 3: Deploy NCCL Benchmark

**What this does:** Creates the StatefulSet with 8 pods (one per node), plus the Service and ConfigMap.

```bash
# Deploy the benchmark
kubectl apply -f GOLD-STANDARD-NCCL-BENCHMARK.yaml -n b-efficient-memory-offloading-765cab
```

**Expected output:**
```
service/nccl-benchmark-svc created
configmap/nccl-benchmark-script created
statefulset.apps/nccl-benchmark created
```

**Wait for pods to be ready:**
```bash
kubectl get pods -n b-efficient-memory-offloading-765cab -l app=nccl-benchmark -w
```

Press Ctrl+C when all 8 pods show `1/1 Running`.

## Running the Benchmark

### Option 1: Quick Run (Recommended)

Use the provided run script:

```bash
# Create the run script
cat > run-benchmark.sh << 'EOF'
#!/bin/bash
for i in {0..7}; do
  kubectl exec nccl-benchmark-$i -n b-efficient-memory-offloading-765cab -- \
    torchrun --nnodes=8 --nproc_per_node=4 --node_rank=$i \
    --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
    --master_port=29501 /benchmark/allreduce-loop.py -r 3 &
done
wait
EOF

chmod +x run-benchmark.sh

# Run the benchmark
./run-benchmark.sh
```

**What this does:**
- Runs the benchmark on all 8 nodes simultaneously
- Uses 4 GPUs per node (32 GPUs total)
- Runs 3 iterations for statistical accuracy
- Takes about 5-10 minutes to complete

**Expected results (last line of output):**
```
8000.00    316329.8    316244.1    316400.9    49.00    49.01    48.99
```

This shows **49.00 GB/s** bandwidth - perfect performance with 100 Gbps rate limiting!

### Option 2: Manual Run

If you prefer to run manually:

```bash
# Exec into pod-0
kubectl exec -it nccl-benchmark-0 -n b-efficient-memory-offloading-765cab -- bash

# Inside pod-0, run:
torchrun --nnodes=8 --nproc_per_node=4 --node_rank=0 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 /benchmark/allreduce-loop.py -r 3
```

Then in separate terminals, exec into pods 1-7 and run the same command with `--node_rank=1`, `--node_rank=2`, etc.

**Note:** You must start all 8 torchrun processes within ~30 seconds or they will timeout.

## Scaling Operations

### Scale Down (Stop Using Resources)

When you're done with the benchmark:

```bash
# Scale to zero replicas (stops all pods)
kubectl scale statefulset nccl-benchmark --replicas=0 \
  -n b-efficient-memory-offloading-765cab
```

This frees up GPUs and network resources for other users.

### Scale Up (Resume Testing)

To run the benchmark again later:

```bash
# Scale back to 8 replicas
kubectl scale statefulset nccl-benchmark --replicas=8 \
  -n b-efficient-memory-offloading-765cab

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app=nccl-benchmark \
  -n b-efficient-memory-offloading-765cab --timeout=300s

# Run benchmark
./run-benchmark.sh
```

### Complete Cleanup (Remove Everything)

To completely remove the benchmark:

```bash
# Delete the StatefulSet, Service, and ConfigMap
kubectl delete -f GOLD-STANDARD-NCCL-BENCHMARK.yaml \
  -n b-efficient-memory-offloading-765cab

# Optionally, remove network attachments (usually keep these)
# kubectl delete -f network-attachments.yaml -n b-efficient-memory-offloading-765cab
```

## Troubleshooting

### Pods Stay in Pending State

**Check GPU/RDMA availability:**
```bash
kubectl describe pod nccl-benchmark-0 -n b-efficient-memory-offloading-765cab
```

Look for messages like "Insufficient nvidia.com/gpu" or "Insufficient openshift.io/eno5np0rdma".

**Solution:** Scale down other workloads or wait for resources to become available.

### Benchmark Hangs at "Connected all rings"

This usually means network configuration issues.

**Check network IPs:**
```bash
kubectl exec nccl-benchmark-0 -n b-efficient-memory-offloading-765cab -- \
  ip addr show | grep "inet " | grep "10.0.10[3-6]"
```

You should see 4 different subnets:
```
inet 10.0.103.X/24 ...  # net1
inet 10.0.104.X/24 ...  # net2
inet 10.0.105.X/24 ...  # net3
inet 10.0.106.X/24 ...  # net4
```

**If all IPs are in 10.0.103.0/24:**
```bash
# Reapply network attachments
kubectl apply -f network-attachments.yaml -n b-efficient-memory-offloading-765cab

# Delete and recreate pods
kubectl delete statefulset nccl-benchmark -n b-efficient-memory-offloading-765cab
kubectl apply -f GOLD-STANDARD-NCCL-BENCHMARK.yaml -n b-efficient-memory-offloading-765cab
```

### Port Already in Use Error

Previous benchmark processes are still running.

**Solution:**
```bash
# Kill all torchrun processes
for i in {0..7}; do
  kubectl exec nccl-benchmark-$i -n b-efficient-memory-offloading-765cab -- \
    pkill -9 torchrun || true
done

# Wait 5 seconds and try again
sleep 5
./run-benchmark.sh
```

### Permission Denied Errors

Service account doesn't have nccl-scc permissions.

**Solution:** Re-run Step 2 from setup.

## Understanding the Results

The benchmark tests different message sizes from 0.1 MB to 8000 MB (8 GB).

**Key metrics:**
- `avgbw(GB/sec)`: Average bandwidth across all iterations
- `maxbw(GB/sec)`: Best bandwidth achieved
- `minbw(GB/sec)`: Worst bandwidth achieved

**What to expect:**
- Small messages (< 1 MB): Lower bandwidth (latency-bound)
- Large messages (> 1 GB): **~49 GB/s** (100 Gbps rate-limited)

**Perfect run (8 GB messages):**
```
8000.00    316329.8    316244.1    316400.9    49.00    49.01    48.99
         ↑            ↑            ↑           ↑        ↑        ↑
         avg time    min time     max time   avg BW   max BW   min BW
```

## Files in This Directory

- **`GOLD-STANDARD-NCCL-BENCHMARK.yaml`**: Main benchmark manifest (StatefulSet + Service + ConfigMap)
- **`network-attachments.yaml`**: SR-IOV network definitions (4 NICs with separate subnets)
- **`SETUP-GUIDE.md`**: This file
- **`run-benchmark.sh`**: Script to run benchmark on all 8 nodes simultaneously (create this yourself)

## Quick Reference Commands

```bash
# Deploy everything (one-time setup)
kubectl apply -f network-attachments.yaml -n b-efficient-memory-offloading-765cab
oc adm policy add-scc-to-user nccl-scc system:serviceaccount:b-efficient-memory-offloading-765cab:h-kim-sa
kubectl apply -f GOLD-STANDARD-NCCL-BENCHMARK.yaml -n b-efficient-memory-offloading-765cab

# Check pod status
kubectl get pods -n b-efficient-memory-offloading-765cab -l app=nccl-benchmark

# Run benchmark
./run-benchmark.sh

# Scale down when done
kubectl scale statefulset nccl-benchmark --replicas=0 -n b-efficient-memory-offloading-765cab

# Scale up to resume
kubectl scale statefulset nccl-benchmark --replicas=8 -n b-efficient-memory-offloading-765cab
```

## Getting Help

If you run into issues:

1. Check this guide's Troubleshooting section
2. Verify your setup with the Quick Reference commands
3. Check pod logs: `kubectl logs nccl-benchmark-0 -n b-efficient-memory-offloading-765cab`
4. Contact your cluster administrator

## Important Notes

⚠️ **DO NOT modify the network attachment IP ranges** - they are specifically configured for NCCL performance

⚠️ **Always scale down to 0 replicas** when not actively running benchmarks to free resources

✅ **You can run multiple benchmark iterations** without recreating pods - just run `./run-benchmark.sh` again

✅ **Benchmark is fully automated** - no need to manually configure anything inside pods
