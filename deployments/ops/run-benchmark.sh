#!/bin/bash
#
# run-benchmark.sh
# Execute N-node NCCL benchmark in parallel across all pods
#
# Usage: ./run-benchmark.sh [OPTIONS]
#
# Options:
#   -N, --nodes NUM        Number of nodes (default: 15)
#   -g, --gpus NUM         GPUs per node (default: 4)
#   -n, --namespace NS     Kubernetes namespace (default: nccl-test)
#   -i, --iterations NUM   Benchmark iterations (default: 3)
#   -h, --help             Show this help message
#
# Examples:
#   ./run-benchmark.sh                                    # Use all defaults (15 nodes)
#   ./run-benchmark.sh -N 8                               # 8 nodes, other defaults
#   ./run-benchmark.sh --namespace b-efficient-memory-offloading-765cab
#   ./run-benchmark.sh -N 15 -i 5                         # 15 nodes, 5 iterations
#   ./run-benchmark.sh -n my-namespace -N 4 -g 4 -i 3    # Specify all
#

set -e

# Default values
NUM_NODES=15
GPUS_PER_NODE=4
NAMESPACE="nccl-test"
ITERATIONS=3

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -N|--nodes)
      NUM_NODES="$2"
      shift 2
      ;;
    -g|--gpus)
      GPUS_PER_NODE="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -i|--iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -N, --nodes NUM        Number of nodes (default: 15)"
      echo "  -g, --gpus NUM         GPUs per node (default: 4)"
      echo "  -n, --namespace NS     Kubernetes namespace (default: nccl-test)"
      echo "  -i, --iterations NUM   Benchmark iterations (default: 3)"
      echo "  -h, --help             Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Use all defaults (15 nodes)"
      echo "  $0 -N 8                               # 8 nodes"
      echo "  $0 --namespace my-namespace           # Custom namespace"
      echo "  $0 -N 15 -i 5                         # 15 nodes, 5 iterations"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done
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
