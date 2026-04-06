#!/bin/bash

# Dynamic rack-aware NCCL benchmark script
# Automatically groups pods by rack for optimal ring topology

NAMESPACE="nccl-test"
LABEL="app=nccl-benchmark"

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
  echo "ERROR: No pods found!"
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
echo "Cross-rack transitions in ring: 2 out of $((total_pods - 1)) (at rank $((rack4_count - 1))→${rack4_count} and rank $((total_pods - 1))→0)"
echo ""

# Determine master pod (rank 0)
IFS='|' read -r master_pod master_node <<< "${all_ranked_pods[0]}"
echo "Master: ${master_pod} (rank 0)"
echo ""

# Start all pods with their assigned ranks
echo "=== Starting benchmark on ${total_pods} nodes ==="
echo ""

rank=0
for entry in "${all_ranked_pods[@]}"; do
  IFS='|' read -r pod node <<< "$entry"
  echo "Starting ${pod} with rank ${rank}..."
  kubectl exec -n ${NAMESPACE} ${pod} -- bash -c "torchrun --nnodes=${total_pods} --nproc_per_node=4 --node_rank=${rank} --master_addr=${master_pod}.nccl-benchmark-svc --master_port=29501 /benchmark/allreduce-loop.py -r 3" &
  ((rank++))
done

echo ""
echo "All benchmark processes started, waiting for completion..."
wait

echo ""
echo "=== Benchmark Complete ==="
echo ""
kubectl exec -n ${NAMESPACE} ${master_pod} -- bash -c "cat /tmp/nccl_benchmark_*.log 2>/dev/null | grep '^  ' | tail -20"
