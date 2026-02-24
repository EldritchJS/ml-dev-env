#!/bin/bash

# Auto-sync local code changes to the pod
# Usage: ./scripts/sync-code.sh [local_dir] [remote_dir] [pod_name] [namespace]
#
# Examples:
#   ./scripts/sync-code.sh
#   ./scripts/sync-code.sh ./my-code /workspace
#   ./scripts/sync-code.sh ./my-code /workspace my-pod my-namespace

# Configuration with defaults
NAMESPACE="${4:-${NAMESPACE:-nccl-test}}"
POD_NAME="${3:-${POD_NAME:-ml-dev-env}}"
LOCAL_DIR="${1:-${LOCAL_DIR:-./workspace}}"
REMOTE_DIR="${2:-${REMOTE_DIR:-/workspace}}"

echo "🔄 Starting automatic code synchronization..."
echo "Local:  $LOCAL_DIR"
echo "Remote: $POD_NAME:$REMOTE_DIR"
echo ""
echo "Watching for changes... (Ctrl+C to stop)"
echo ""

# Initial sync
echo "📤 Initial sync..."
oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store'

# Watch for changes using fswatch (macOS)
if command -v fswatch >/dev/null 2>&1; then
    fswatch -o "$LOCAL_DIR" | while read -r _; do
        echo "🔄 [$(date +%H:%M:%S)] Changes detected, syncing..."
        oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' 2>&1 | grep -v "^building file list"
        echo "✅ Sync complete"
    done
else
    echo "⚠️  fswatch not installed. Install it for automatic watching:"
    echo "    brew install fswatch"
    echo ""
    echo "For now, running sync every 5 seconds..."
    while true; do
        sleep 5
        echo "🔄 [$(date +%H:%M:%S)] Syncing..."
        oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' 2>&1 | grep -v "^building file list"
    done
fi
