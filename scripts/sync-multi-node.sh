#!/bin/bash

# Sync code to all nodes in multi-node setup
# Usage: ./scripts/sync-multi-node.sh [local_dir] [remote_dir] [namespace]

NAMESPACE="${3:-${NAMESPACE:-nccl-test}}"
LOCAL_DIR="${1:-${LOCAL_DIR:-./workspace}}"
REMOTE_DIR="${2:-${REMOTE_DIR:-/workspace}}"
NUM_NODES=4

echo "🔄 Multi-Node Code Sync"
echo "======================"
echo "Namespace:  $NAMESPACE"
echo "Local dir:  $LOCAL_DIR"
echo "Remote dir: $REMOTE_DIR"
echo "Nodes:      $NUM_NODES"
echo ""

# Check if pods are running
RUNNING_PODS=$(oc get pods -n "$NAMESPACE" -l app=ml-dev-env-multi --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

if [ "$RUNNING_PODS" -eq 0 ]; then
    echo "❌ No running pods found"
    echo "Deploy first: ./scripts/deploy-multi-node.sh"
    exit 1
fi

echo "Found $RUNNING_PODS/$NUM_NODES running pods"
echo ""

# Sync to each pod
for i in $(seq 0 $((NUM_NODES - 1))); do
    POD_NAME="ml-dev-env-$i"

    # Check if pod is running
    POD_STATUS=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

    if [ "$POD_STATUS" != "Running" ]; then
        echo "⏭️  Skipping $POD_NAME (status: $POD_STATUS)"
        continue
    fi

    echo "📤 Syncing to $POD_NAME..."
    if oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.DS_Store' 2>&1 | grep -v "^building file list"; then
        echo "   ✅ $POD_NAME synced"
    else
        echo "   ❌ $POD_NAME sync failed"
    fi
done

echo ""
echo "✅ Multi-node sync complete"
echo ""
echo "Files are now synchronized across all $RUNNING_PODS pods"
