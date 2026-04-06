#!/bin/bash
#
# run-nccl-rack-grouped.sh
# Execute N-node NCCL benchmark with automatic rack-aware rank assignment
#
# This script automatically discovers pod placement, groups pods by rack,
# and assigns NCCL ranks to minimize cross-rack communication.
#
# Usage: ./run-nccl-rack-grouped.sh [OPTIONS]
#
# Options:
#   -g, --gpus NUM         GPUs per node (default: 4)
#   -n, --namespace NS     Kubernetes namespace (default: nccl-test)
#   -i, --iterations NUM   Benchmark iterations (default: 3)
#   -l, --label LABEL      Pod label selector (default: app=nccl-benchmark)
#   -h, --help             Show this help message
#
# Examples:
#   ./run-nccl-rack-grouped.sh                                 # Use all defaults
#   ./run-nccl-rack-grouped.sh --namespace my-namespace        # Custom namespace
#   ./run-nccl-rack-grouped.sh -i 5                            # 5 iterations
#   ./run-nccl-rack-grouped.sh -n nccl-test -g 4 -i 3         # Specify all
#

set -e

# Default values
GPUS_PER_NODE=4
NAMESPACE="nccl-test"
ITERATIONS=3
LABEL="app=nccl-benchmark"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
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
    -l|--label)
      LABEL="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Rack-aware NCCL benchmark with automatic rank assignment"
      echo ""
      echo "Options:"
      echo "  -g, --gpus NUM         GPUs per node (default: 4)"
      echo "  -n, --namespace NS     Kubernetes namespace (default: nccl-test)"
      echo "  -i, --iterations NUM   Benchmark iterations (default: 3)"
      echo "  -l, --label LABEL      Pod label selector (default: app=nccl-benchmark)"
      echo "  -h, --help             Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                 # Use all defaults"
      echo "  $0 --namespace my-namespace        # Custom namespace"
      echo "  $0 -i 5                            # 5 iterations"
      echo ""
      echo "This script automatically:"
      echo "  1. Discovers all pods and their rack assignments"
      echo "  2. Groups pods by rack for optimal ring topology"
      echo "  3. Assigns NCCL ranks to minimize cross-rack traffic"
      echo "  4. Runs the benchmark with optimal communication pattern"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

MASTER_PORT="29501"

echo "=========================================="
echo "Rack-Aware NCCL Benchmark"
echo "=========================================="
echo "Namespace:       $NAMESPACE"
echo "Label selector:  $LABEL"
echo "GPUs per node:   $GPUS_PER_NODE"
echo "Iterations:      $ITERATIONS"
echo "Master port:     $MASTER_PORT"
echo "=========================================="
echo ""

echo "=== Discovering pod placement ==="
echo ""

# Get all pods with their nodes
rack4_pods=()
rack2_pods=()

while IFS='|' read -r pod node; do
  if [[ $node == *"r4pcc04"* ]]; then
    rack4_pods+=("$pod|$node")
  else
    rack2_pods+=("$pod|$node")
  fi
done < <(kubectl get pods -n ${NAMESPACE} -l ${LABEL} --sort-by=.metadata.name -o json | jq -r '.items[] | "\(.metadata.name)|\(.spec.nodeName)"')

# Count pods
rack4_count=${#rack4_pods[@]}
rack2_count=${#rack2_pods[@]}
total_pods=$((rack4_count + rack2_count))

echo "Found ${total_pods} total pods:"
echo "  RACK-4: ${rack4_count} pods"
echo "  RACK-2: ${rack2_count} pods"
echo ""

if [ "$total_pods" -eq 0 ]; then
  echo "ERROR: No pods found with label '${LABEL}' in namespace '${NAMESPACE}'"
  echo ""
  echo "Check pods with:"
  echo "  kubectl get pods -n ${NAMESPACE} -l ${LABEL}"
  exit 1
fi

# Build rank assignment (rack-4 first, then rack-2)
all_ranked_pods=()
for entry in "${rack4_pods[@]}"; do
  all_ranked_pods+=("$entry")
done
for entry in "${rack2_pods[@]}"; do
  all_ranked_pods+=("$entry")
done

echo "=== Rank Assignment (Rack-Grouped) ==="
echo ""
echo "Rank | Pod                  | Node                           | Rack"
echo "-----+----------------------+--------------------------------+-------"

rank=0
for entry in "${all_ranked_pods[@]}"; do
  IFS='|' read -r pod node <<< "$entry"
  rack_label="RACK-2"
  [[ $node == *"r4pcc04"* ]] && rack_label="RACK-4"
  printf "%-4s | %-20s | %-30s | %s\n" "$rank" "$pod" "$node" "$rack_label"
  ((rank++))
done

echo ""
if [ "$rack4_count" -gt 0 ] && [ "$rack2_count" -gt 0 ]; then
  echo "Cross-rack transitions in ring: 2 out of $((total_pods - 1)) (at rank $((rack4_count - 1))→${rack4_count} and rank $((total_pods - 1))→0)"
else
  echo "Single rack deployment - no cross-rack transitions"
fi
echo ""

# Determine master pod (rank 0)
IFS='|' read -r master_pod master_node <<< "${all_ranked_pods[0]}"
echo "Master: ${master_pod} (rank 0)"
echo "Master address: ${master_pod}.nccl-benchmark-svc"
echo ""

# Check if all pods are running
echo "Checking pod status..."
all_running=true
for entry in "${all_ranked_pods[@]}"; do
  IFS='|' read -r pod node <<< "$entry"
  STATUS=$(kubectl get pod -n $NAMESPACE $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

  if [ "$STATUS" != "Running" ]; then
    echo "  ✗ $pod: $STATUS"
    all_running=false
  else
    echo "  ✓ $pod: Running"
  fi
done

if [ "$all_running" = false ]; then
  echo ""
  echo "ERROR: Not all pods are Running. Please fix pod issues before running benchmark."
  exit 1
fi

echo ""
echo "All pods are Running. Cleaning previous results..."

# Clean up any previous benchmark results
for entry in "${all_ranked_pods[@]}"; do
  IFS='|' read -r pod node <<< "$entry"
  kubectl exec -n $NAMESPACE $pod -- bash -c "rm -f /workspace/benchmark-output.log /tmp/nccl_benchmark_*.log" 2>/dev/null || true
done

echo ""
echo "=========================================="
echo "Starting benchmark on ${total_pods} nodes"
echo "=========================================="
echo ""

# Start all pods with their assigned ranks
pids=()
rank=0
for entry in "${all_ranked_pods[@]}"; do
  IFS='|' read -r pod node <<< "$entry"
  echo "Starting rank ${rank} on ${pod}..."

  kubectl exec -n ${NAMESPACE} ${pod} -- bash -c \
    "torchrun --nnodes=${total_pods} --nproc_per_node=${GPUS_PER_NODE} --node_rank=${rank} \
     --master_addr=${master_pod}.nccl-benchmark-svc --master_port=${MASTER_PORT} \
     /benchmark/allreduce-loop.py -r ${ITERATIONS} \
     > /workspace/benchmark-output.log 2>&1" &

  pids+=($!)
  ((rank++))
done

echo ""
echo "All torchrun processes started. Waiting for completion..."
echo "This may take several minutes depending on iterations."
echo ""

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

echo ""
if [ $failed -eq 0 ]; then
  echo "=========================================="
  echo "Benchmark completed successfully!"
  echo "=========================================="
  echo ""

  # Show results from master pod
  echo "Results from ${master_pod}:"
  echo "----------------------------------------"
  kubectl exec -n ${NAMESPACE} ${master_pod} -- cat /workspace/benchmark-output.log 2>/dev/null || \
    kubectl exec -n ${NAMESPACE} ${master_pod} -- bash -c "cat /tmp/nccl_benchmark_*.log 2>/dev/null | grep '^  ' | tail -20"

  echo ""
  echo "To view results from other ranks:"
  rank=0
  for entry in "${all_ranked_pods[@]}"; do
    IFS='|' read -r pod node <<< "$entry"
    if [ "$rank" -gt 0 ]; then
      echo "  kubectl exec -n ${NAMESPACE} ${pod} -- cat /workspace/benchmark-output.log"
    fi
    ((rank++))
  done
else
  echo "=========================================="
  echo "Benchmark failed on one or more nodes!"
  echo "=========================================="
  echo ""
  echo "Check logs for errors:"
  for entry in "${all_ranked_pods[@]}"; do
    IFS='|' read -r pod node <<< "$entry"
    echo "  kubectl exec -n ${NAMESPACE} ${pod} -- cat /workspace/benchmark-output.log"
  done
  exit 1
fi
