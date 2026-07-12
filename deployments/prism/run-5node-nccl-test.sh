#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR"

# Get number of runs from argument, default to 3
NUM_RUNS=${1:-3}

echo "=== Step 1: Deploy 5-node StatefulSet ==="
cd "$SCRIPT_DIR"
oc apply -f nccl-test-5node.yaml -n nccl-test

echo ""
echo "Waiting for pods to start..."
sleep 10

echo ""
echo "=== Step 2: Check pod status ==="
oc get pods -n nccl-test -l app=nccl-benchmark -o wide

echo ""
echo "Waiting 30 more seconds for all pods to be Running..."
sleep 30

echo ""
echo "=== Step 3: Verify all 5 pods are Running ==="
READY=$(oc get pods -n nccl-test -l app=nccl-benchmark --no-headers | grep -c "1/1.*Running" || true)
echo "Ready pods: $READY / 5"

if [ "$READY" -lt 5 ]; then
  echo ""
  echo "ERROR: Not all pods are ready. Current status:"
  oc get pods -n nccl-test -l app=nccl-benchmark
  echo ""
  echo "Check which nodes they're on:"
  oc get pods -n nccl-test -l app=nccl-benchmark -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase'
  exit 1
fi

echo ""
echo "All 5 pods are Running!"
echo ""
echo "=== Step 4: Start benchmark on all 5 pods (${NUM_RUNS} run(s)) ==="

# Start pod-0 (master)
echo "Starting pod-0 (master)..."
oc exec -n nccl-test nccl-benchmark-0 -- bash -c \
  "torchrun --nproc_per_node=4 --nnodes=5 --node_rank=0 \
   --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
   --master_port=29501 /benchmark/allreduce-loop.py -r $NUM_RUNS" \
  > "$LOG_DIR/benchmark-pod-0.log" 2>&1 &

sleep 3

# Start workers
for i in {1..4}; do
  echo "Starting pod-$i (worker)..."
  oc exec -n nccl-test nccl-benchmark-$i -- bash -c \
    "torchrun --nproc_per_node=4 --nnodes=5 --node_rank=$i \
     --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
     --master_port=29501 /benchmark/allreduce-loop.py -r $NUM_RUNS" \
    > "$LOG_DIR/benchmark-pod-$i.log" 2>&1 &
  sleep 1
done

echo ""
echo "=== Benchmark started! ==="
echo ""
echo "Running $NUM_RUNS time(s)"
echo "Log directory: $LOG_DIR"
echo ""
echo "Monitor with:  tail -f $LOG_DIR/benchmark-pod-0.log"
echo "Check status:  ps aux | grep 'nccl-benchmark' | grep -v grep"
echo ""
EXPECTED_TIME=$((NUM_RUNS * 2))
echo "Results will be in $LOG_DIR/benchmark-pod-0.log (takes ~${EXPECTED_TIME} minutes)"
