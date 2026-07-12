#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<USAGE
Usage: $(basename "$0") -c CONFIG -m MANIFEST [-r RUNS] [-l LOG_DIR]

Deploy and run an NCCL benchmark using a config file and manifest.

Options:
  -c, --config FILE      Config file (required). Same file used with generate-nccl-manifest.sh
  -m, --manifest FILE    YAML manifest to apply (required)
  -r, --runs N           Number of benchmark runs (default: 3)
  -l, --log-dir DIR      Log output directory (default: directory containing manifest)
  -h, --help             Show this help

Examples:
  $(basename "$0") -c ../prism/config.conf -m ../prism/manifest.yaml
  $(basename "$0") -c ../prism/config.conf -m ../prism/manifest.yaml -r 5
  $(basename "$0") -c ../my-team/config.conf -m ../my-team/manifest.yaml -l /tmp/logs
USAGE
    exit "${1:-0}"
}

CONFIG_FILE=""
MANIFEST=""
NUM_RUNS=3
LOG_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)    CONFIG_FILE="$2"; shift 2 ;;
        -m|--manifest)  MANIFEST="$2"; shift 2 ;;
        -r|--runs)      NUM_RUNS="$2"; shift 2 ;;
        -l|--log-dir)   LOG_DIR="$2"; shift 2 ;;
        -h|--help)      usage 0 ;;
        *)              echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: config file required (-c)" >&2
    usage 1
fi
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config file not found: $CONFIG_FILE" >&2
    exit 1
fi
if [[ -z "$MANIFEST" ]]; then
    echo "Error: manifest file required (-m)" >&2
    usage 1
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest file not found: $MANIFEST" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Source config
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Apply same defaults as generate-nccl-manifest.sh
: "${GPU_COUNT:=4}"
: "${MASTER_PORT:=29501}"
: "${BENCHMARK_SCRIPT:=$SCRIPT_DIR/allreduce-loop.py}"
BENCHMARK_FILENAME=$(basename "$BENCHMARK_SCRIPT")

# Derive replica count
read -ra NODE_ARRAY <<< "$NODES"
REPLICAS=${#NODE_ARRAY[@]}

# Default log directory to manifest's directory
if [[ -z "$LOG_DIR" ]]; then
    LOG_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
fi
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Step 1: Deploy
# ---------------------------------------------------------------------------
echo "=== Step 1: Deploy ${REPLICAS}-node StatefulSet ==="
oc apply -f "$MANIFEST" -n "$NAMESPACE"

echo ""
echo "Waiting for pods to start..."
sleep 10

# ---------------------------------------------------------------------------
# Step 2: Check pod status
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2: Check pod status ==="
oc get pods -n "$NAMESPACE" -l "app=${DEPLOY_NAME}" -o wide

echo ""
echo "Waiting 30 more seconds for all pods to be Running..."
sleep 30

# ---------------------------------------------------------------------------
# Step 3: Verify all pods are Running
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Verify all ${REPLICAS} pods are Running ==="
READY=$(oc get pods -n "$NAMESPACE" -l "app=${DEPLOY_NAME}" --no-headers | grep -c "1/1.*Running" || true)
echo "Ready pods: $READY / $REPLICAS"

if [[ "$READY" -lt "$REPLICAS" ]]; then
    echo ""
    echo "ERROR: Not all pods are ready. Current status:"
    oc get pods -n "$NAMESPACE" -l "app=${DEPLOY_NAME}"
    echo ""
    echo "Check which nodes they're on:"
    oc get pods -n "$NAMESPACE" -l "app=${DEPLOY_NAME}" \
        -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase'
    exit 1
fi

echo ""
echo "All $REPLICAS pods are Running!"

# ---------------------------------------------------------------------------
# Step 4: Start benchmark
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4: Start benchmark on all ${REPLICAS} pods (${NUM_RUNS} run(s)) ==="

echo "Starting pod-0 (master)..."
oc exec -n "$NAMESPACE" "${DEPLOY_NAME}-0" -- bash -c \
    "torchrun --nproc_per_node=${GPU_COUNT} --nnodes=${REPLICAS} --node_rank=0 \
     --master_addr=${DEPLOY_NAME}-0.${DEPLOY_NAME}-svc \
     --master_port=${MASTER_PORT} /benchmark/${BENCHMARK_FILENAME} -r ${NUM_RUNS}" \
    > "$LOG_DIR/benchmark-pod-0.log" 2>&1 &

sleep 3

for ((i=1; i<REPLICAS; i++)); do
    echo "Starting pod-$i (worker)..."
    oc exec -n "$NAMESPACE" "${DEPLOY_NAME}-${i}" -- bash -c \
        "torchrun --nproc_per_node=${GPU_COUNT} --nnodes=${REPLICAS} --node_rank=${i} \
         --master_addr=${DEPLOY_NAME}-0.${DEPLOY_NAME}-svc \
         --master_port=${MASTER_PORT} /benchmark/${BENCHMARK_FILENAME} -r ${NUM_RUNS}" \
        > "$LOG_DIR/benchmark-pod-${i}.log" 2>&1 &
    sleep 1
done

echo ""
echo "=== Benchmark started! ==="
echo ""
echo "Running $NUM_RUNS time(s)"
echo "Log directory: $LOG_DIR"
echo ""
echo "Monitor with:  tail -f $LOG_DIR/benchmark-pod-0.log"
echo "Check status:  ps aux | grep '${DEPLOY_NAME}' | grep -v grep"
echo ""
EXPECTED_TIME=$((NUM_RUNS * 2))
echo "Results will be in $LOG_DIR/benchmark-pod-0.log (takes ~${EXPECTED_TIME} minutes)"
