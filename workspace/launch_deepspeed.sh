#!/bin/bash

# DeepSpeed Multi-Node Launcher
# Run this on pod-0 (master node)

set -e

echo "=========================================="
echo "DeepSpeed Multi-Node Launcher"
echo "=========================================="

# Configuration
SCRIPT="${1:-train_multi_node.py}"
DS_CONFIG="${2:-ds_config.json}"
HOSTFILE="${3:-/workspace/.deepspeed/hostfile}"

# Verify we're on the master node
POD_ORDINAL=${HOSTNAME##*-}
if [ "$POD_ORDINAL" != "0" ]; then
    echo "❌ This script should be run on ml-dev-env-0 (master node)"
    echo "Current pod: $HOSTNAME"
    exit 1
fi

echo "✅ Running on master node: $HOSTNAME"
echo ""

# Check if hostfile exists
if [ ! -f "$HOSTFILE" ]; then
    echo "❌ Hostfile not found: $HOSTFILE"
    exit 1
fi

echo "Hostfile:"
cat "$HOSTFILE"
echo ""

# Check if training script exists
if [ ! -f "/workspace/$SCRIPT" ]; then
    echo "❌ Training script not found: /workspace/$SCRIPT"
    exit 1
fi

# Check if DeepSpeed config exists
if [ ! -f "/workspace/$DS_CONFIG" ]; then
    echo "❌ DeepSpeed config not found: /workspace/$DS_CONFIG"
    exit 1
fi

echo "Configuration:"
echo "  Script:        $SCRIPT"
echo "  DS Config:     $DS_CONFIG"
echo "  Hostfile:      $HOSTFILE"
echo ""

# Verify connectivity to worker nodes
echo "Testing connectivity to worker nodes..."
for i in {1..3}; do
    NODE="ml-dev-env-$i.ml-dev-env-headless.nccl-test.svc.cluster.local"
    if ping -c 1 -W 2 "$NODE" &>/dev/null; then
        echo "  ✅ $NODE reachable"
    else
        echo "  ⚠️  $NODE not reachable (may not be ready yet)"
    fi
done
echo ""

# Wait for all pods to be ready
echo "Waiting for all pods to be ready..."
for i in {0..3}; do
    POD="ml-dev-env-$i"
    echo -n "  Waiting for $POD... "

    # Check if pod exists and is ready
    for retry in {1..30}; do
        if oc get pod "$POD" -n nccl-test &>/dev/null 2>&1; then
            STATUS=$(oc get pod "$POD" -n nccl-test -o jsonpath='{.status.phase}')
            if [ "$STATUS" = "Running" ]; then
                echo "✅ Ready"
                break
            fi
        fi

        if [ $retry -eq 30 ]; then
            echo "⚠️  Timeout (proceeding anyway)"
            break
        fi
        sleep 2
    done
done
echo ""

echo "=========================================="
echo "Starting DeepSpeed Training"
echo "=========================================="
echo "  Nodes:     4"
echo "  GPUs:      16 (4 per node)"
echo "  Script:    $SCRIPT"
echo "  Config:    $DS_CONFIG"
echo ""
echo "Launching..."
echo ""

# Launch DeepSpeed training
deepspeed \
    --hostfile="$HOSTFILE" \
    --master_addr="ml-dev-env-0.ml-dev-env-headless.nccl-test.svc.cluster.local" \
    --master_port=29500 \
    "/workspace/$SCRIPT" \
    --deepspeed \
    --deepspeed_config="/workspace/$DS_CONFIG" \
    "${@:4}"  # Pass any additional arguments

echo ""
echo "=========================================="
echo "DeepSpeed Training Completed"
echo "=========================================="
