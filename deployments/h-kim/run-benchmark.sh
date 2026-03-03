#!/bin/bash
set -e

# Run PyTorch all-reduce benchmark on pytorch-bench-manual pods

NAMESPACE="${NAMESPACE:-nccl-test}"
APP_LABEL="${APP_LABEL:-pytorch-bench-manual}"
SERVICE_NAME="${SERVICE_NAME:-pytorch-bench-manual-0.pytorch-bench-manual-svc.nccl-test.svc.cluster.local}"
MASTER_PORT="${MASTER_PORT:-29501}"
MULTIPLIER="${MULTIPLIER:-1}"

echo "=========================================="
echo "PyTorch All-Reduce Benchmark Runner"
echo "=========================================="
echo ""

# Get number of running pods
echo "Checking for running pods..."
NNODES=$(oc get pods -n "$NAMESPACE" -l "app=$APP_LABEL" --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')

if [ "$NNODES" -eq 0 ]; then
  echo "ERROR: No running pods found with label app=$APP_LABEL in namespace $NAMESPACE"
  echo ""
  echo "Deploy pods first with:"
  echo "  oc apply -f deployments/h-kim/pytorch-benchmark-manual.yaml"
  exit 1
fi

echo "Found $NNODES running pods"
echo "Namespace: $NAMESPACE"
echo "Master: $SERVICE_NAME:$MASTER_PORT"
echo ""

echo "Starting benchmark on all $NNODES nodes..."
echo ""

# Run benchmark on all pods in parallel
for i in $(seq 0 $((NNODES-1))); do
  POD_NAME="pytorch-bench-manual-$i"
  echo "Starting on pod $i ($POD_NAME)..."

  oc exec -n "$NAMESPACE" "$POD_NAME" -- bash -c \
    "torchrun --nnodes=$NNODES --nproc_per_node=4 --node_rank=$i \
      --master_addr=$SERVICE_NAME \
      --master_port=$MASTER_PORT \
      --rdzv_backend=c10d \
      --rdzv_endpoint=$SERVICE_NAME:$MASTER_PORT \
      /benchmark/allreduce-loop.py --multiplier $MULTIPLIER" &
done

echo ""
echo "Waiting for all benchmarks to complete..."
wait

echo ""
echo "=========================================="
echo "Benchmark Complete!"
echo "=========================================="
echo ""
echo "View results with:"
echo "  oc logs pytorch-bench-manual-0 -n $NAMESPACE | grep -v 'NCCL INFO' | tail -100"
echo ""
echo "Or to see just the bandwidth table:"
echo "  oc logs pytorch-bench-manual-0 -n $NAMESPACE | grep -E 'size\\(MB\\)|^\\s+[0-9]+\\.[0-9]+'"
echo ""
