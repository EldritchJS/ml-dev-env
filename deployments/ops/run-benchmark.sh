#!/bin/bash
#
# run-benchmark.sh
# Execute N-node NCCL benchmark in parallel across all pods
#
# Usage: ./run-benchmark.sh [NUM_NODES] [GPUS_PER_NODE] [NAMESPACE] [ITERATIONS]
#   NUM_NODES:      Number of nodes (default: 4)
#   GPUS_PER_NODE:  Number of GPUs per node (default: 4)
#   NAMESPACE:      Kubernetes namespace (default: nccl-test)
#   ITERATIONS:     Number of benchmark iterations (default: 3)
#
# Examples:
#   ./run-benchmark.sh                    # 4 nodes, 4 GPUs, nccl-test namespace, 3 iterations
#   ./run-benchmark.sh 8                  # 8 nodes, 4 GPUs, nccl-test namespace, 3 iterations
#   ./run-benchmark.sh 8 4 nccl-test 5    # 8 nodes, 4 GPUs, nccl-test namespace, 5 iterations
#   ./run-benchmark.sh 2 4 my-namespace   # 2 nodes, 4 GPUs, my-namespace, 3 iterations
#

set -e

NUM_NODES="${1:-4}"
GPUS_PER_NODE="${2:-4}"
NAMESPACE="${3:-nccl-test}"
ITERATIONS="${4:-3}"
MASTER_ADDR="nccl-benchmark-0.nccl-benchmark-svc"
MASTER_PORT="29501"

echo "=========================================="
echo "N-Node NCCL Benchmark Execution Script"
echo "=========================================="
echo "Namespace:       $NAMESPACE"
echo "Nodes:           $NUM_NODES"
echo "GPUs per node:   $GPUS_PER_NODE"
echo "Total GPUs:      $((NUM_NODES * GPUS_PER_NODE))"
echo "Iterations:      $ITERATIONS"
echo "Master address:  $MASTER_ADDR"
echo "Master port:     $MASTER_PORT"
echo "=========================================="
echo

# Check if all pods are running
echo "Checking pod status..."
for i in $(seq 0 $((NUM_NODES - 1))); do
  POD_NAME="nccl-benchmark-$i"
  STATUS=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

  if [ "$STATUS" != "Running" ]; then
    echo "ERROR: Pod $POD_NAME is not Running (current status: $STATUS)"
    echo "Please ensure all pods are Running before executing benchmark."
    exit 1
  fi
  echo "  ✓ $POD_NAME: $STATUS"
done

echo
echo "All pods are Running. Starting benchmark..."
echo

# Clean up any previous benchmark results
echo "Cleaning previous results..."
for i in $(seq 0 $((NUM_NODES - 1))); do
  kubectl exec -n $NAMESPACE nccl-benchmark-$i -- bash -c "rm -f /workspace/benchmark-output.log" 2>/dev/null || true
done

echo "Starting torchrun on all nodes in parallel..."
echo

# Start torchrun on all nodes in parallel
pids=()
for rank in $(seq 0 $((NUM_NODES - 1))); do
  POD_NAME="nccl-benchmark-$rank"

  echo "Starting rank $rank on $POD_NAME..."

  kubectl exec -n $NAMESPACE $POD_NAME -- bash -c \
    "torchrun --nnodes=$NUM_NODES --nproc_per_node=$GPUS_PER_NODE --node_rank=$rank \
     --master_addr=$MASTER_ADDR --master_port=$MASTER_PORT \
     /benchmark/allreduce-loop.py -r $ITERATIONS \
     > /workspace/benchmark-output.log 2>&1" &

  pids+=($!)
done

echo
echo "All torchrun processes started. Waiting for completion..."
echo "This may take several minutes depending on iterations."
echo

# Wait for all background processes
failed=0
for i in "${!pids[@]}"; do
  pid=${pids[$i]}
  if wait $pid; then
    echo "  ✓ Rank $i completed successfully"
  else
    echo "  ✗ Rank $i failed (exit code: $?)"
    failed=1
  fi
done

echo
if [ $failed -eq 0 ]; then
  echo "=========================================="
  echo "Benchmark completed successfully!"
  echo "=========================================="
  echo

  # Show results from rank 0 (master)
  echo "Results from nccl-benchmark-0:"
  echo "----------------------------------------"
  kubectl exec -n $NAMESPACE nccl-benchmark-0 -- cat /workspace/benchmark-output.log

  echo
  echo "To view results from other ranks:"
  for i in $(seq 1 $((NUM_NODES - 1))); do
    echo "  kubectl exec -n $NAMESPACE nccl-benchmark-$i -- cat /workspace/benchmark-output.log"
  done
else
  echo "=========================================="
  echo "Benchmark failed on one or more nodes!"
  echo "=========================================="
  echo
  echo "Check logs for errors:"
  for i in $(seq 0 $((NUM_NODES - 1))); do
    echo "  kubectl exec -n $NAMESPACE nccl-benchmark-$i -- cat /workspace/benchmark-output.log"
  done
  exit 1
fi
