# Rack-Aware NCCL Benchmark

This guide explains how to run NCCL benchmarks with optimal rack-aware topology to maximize performance in multi-rack clusters.

## Problem

When running NCCL ring allreduce across multiple racks, **pod placement matters**. Kubernetes default scheduling spreads pods evenly across nodes for high availability, but doesn't consider network topology. This causes pods to be **interleaved between racks**, forcing most ring communication to cross between racks.

### Performance Impact

**Default Kubernetes scheduling (interleaved pods):**
- Cross-rack hops: 78.6% of all ring communications
- Performance: 54-84% of expected bandwidth
- High variance between runs

**Rack-grouped placement (this solution):**
- Cross-rack hops: 14.3% of all ring communications  
- Performance: 100% of expected bandwidth ✓
- Consistent results

## Solution: Dynamic Rack-Aware Rank Assignment

The `run-nccl-rack-grouped.sh` script automatically:
1. Discovers which pods are on which rack
2. Groups pods by rack in the NCCL ring topology
3. Assigns NCCL ranks to minimize cross-rack traffic
4. Runs the benchmark with optimal communication pattern

## Quick Start

### 1. Deploy Pods (Any Template)

Use any existing benchmark template to create pods:

```bash
# Example: 16-node deployment
kubectl apply -f <(sed 's/NAMESPACE_PLACEHOLDER/nccl-test/g' deployments/ops/nccl-benchmark-template.yaml)
```

**Note:** The script works regardless of how Kubernetes schedules the pods. You don't need to control placement.

### 2. Wait for Pods to be Ready

```bash
kubectl wait --for=condition=Ready pod -l app=nccl-benchmark -n nccl-test --timeout=300s
```

### 3. Run Rack-Aware Benchmark

```bash
# From the repo root
./deployments/ops/run-nccl-rack-grouped.sh

# Or from anywhere
bash deployments/ops/run-nccl-rack-grouped.sh
```

That's it! The script handles everything automatically.

## What the Script Does

### Discovery Phase

```
=== Discovering pod placement ===

Found 16 total pods:
  RACK-4: 8 pods
  RACK-2: 8 pods
```

### Rank Assignment

```
=== Rank Assignment (Rack-Grouped) ===

Rank | Pod                  | Node                           | Rack
-----+----------------------+--------------------------------+-------
0    | nccl-benchmark-0     | moc-r4pcc04u37-nairr           | RACK-4
1    | nccl-benchmark-10    | moc-r4pcc04u09-nairr           | RACK-4
...
7    | nccl-benchmark-9     | moc-r4pcc04u10-nairr           | RACK-4
8    | nccl-benchmark-1     | moc-r4pcc02u30-nairr           | RACK-2
...
15   | nccl-benchmark-8     | moc-r4pcc02u10-nairr           | RACK-2

Cross-rack transitions in ring: 2 out of 16 (at rank 7→8 and rank 15→0)
```

**Key point:** All RACK-4 nodes get consecutive ranks (0-6), then all RACK-2 nodes get consecutive ranks (7-14). This creates a ring topology where communication stays within each rack except for 2 transitions.

### Benchmark Execution

The script automatically starts torchrun on each pod with the correct rank assignment, waits for completion, and displays results.

## How It Works

### Ring Allreduce Communication Pattern

NCCL ring allreduce works by having each rank communicate with its neighbors:
- Rank N sends to rank N+1
- Rank N receives from rank N-1

### Why Grouping by Rack Matters

**Default (interleaved) pattern:**
```
Rank 0 (RACK-4) → Rank 1 (RACK-2) ← CROSS-RACK
Rank 1 (RACK-2) → Rank 2 (RACK-4) ← CROSS-RACK
Rank 2 (RACK-4) → Rank 3 (RACK-2) ← CROSS-RACK
...
```
Result: 11 out of 14 transitions cross racks

**Rack-grouped pattern:**
```
Rank 0 (RACK-4) → Rank 1 (RACK-4) ← SAME RACK
Rank 1 (RACK-4) → Rank 2 (RACK-4) ← SAME RACK
...
Rank 6 (RACK-4) → Rank 7 (RACK-2) ← CROSS-RACK
Rank 7 (RACK-2) → Rank 8 (RACK-2) ← SAME RACK
...
```
Result: 2 out of 14 transitions cross racks

## Configuration

The script automatically detects racks based on node naming convention:
- **RACK-4**: Nodes containing `r4pcc04` in the hostname
- **RACK-2**: All other nodes

### Customizing Rack Detection

If your cluster uses different naming, edit the rack detection logic in the script:

```bash
# Around line 16-17
if [[ $node == *"r4pcc04"* ]]; then
  rack4_pods+=("$pod|$node")
else
  rack2_pods+=("$pod|$node")
fi
```

Change the pattern `"r4pcc04"` to match your RACK-4 naming convention.

## Requirements

- Pods deployed with label `app=nccl-benchmark`
- Namespace: `nccl-test` (or edit `NAMESPACE` variable in script)
- `kubectl` access to the cluster
- `jq` installed for JSON parsing

## Expected Results

With proper rack grouping, you should see:
- **6400 MB messages:** ~193-194 GB/s
- **8000 MB messages:** ~194 GB/s

This represents 100% of the theoretical maximum for 4x400G NICs per node with ring allreduce.

## Troubleshooting

### "No pods found" error

The script looks for pods with label `app=nccl-benchmark` in namespace `nccl-test`. Verify:

```bash
kubectl get pods -n nccl-test -l app=nccl-benchmark
```

If using a different namespace, edit the script:
```bash
NAMESPACE="your-namespace-here"
```

### "jq: command not found"

Install jq:
```bash
# macOS
brew install jq

# RHEL/CentOS
sudo yum install jq

# Ubuntu/Debian
sudo apt-get install jq
```

### Poor performance despite rack grouping

Check:
1. **NCCL settings:** Verify `NCCL_DMABUF_ENABLE=1`, `NCCL_CROSS_NIC=0`, `NCCL_IB_HCA` is set correctly
2. **Network health:** Run single-rack tests to verify intra-rack performance is good
3. **Switch configuration:** Contact network team about inter-rack bandwidth, ECMP settings, and QoS

## Comparison Scripts

For comparison, you can still run the default (non-rack-aware) benchmark:

```bash
# Default approach (may show poor cross-rack performance)
./deployments/ops/run-benchmark.sh
```

Run both and compare results to see the impact of rack-aware placement.

## Future Improvements

Consider these production enhancements:

1. **Pod topology spread constraints:** Configure Kubernetes to group pods by rack automatically
2. **Rack labels:** Add `topology.kubernetes.io/rack` labels to nodes
3. **Custom scheduler:** Implement NCCL-aware pod scheduling
4. **Admission controller:** Automatically assign NCCL ranks based on pod placement

For now, this script provides a simple, effective solution that works with any pod placement.

## References

- Original investigation: See commit history for performance analysis
- NCCL ring algorithm: https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/algorithms.html
- Kubernetes topology: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
