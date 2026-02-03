#!/bin/bash

# Complete development session: sync + port-forward + debug
# Usage: ./scripts/dev-session.sh [script_name] [local_dir] [remote_dir] [pod_name] [namespace] [port]
#
# Examples:
#   ./scripts/dev-session.sh
#   ./scripts/dev-session.sh train.py
#   ./scripts/dev-session.sh train.py ./my-code /workspace
#   ./scripts/dev-session.sh train.py ./my-code /workspace my-pod my-namespace
#   ./scripts/dev-session.sh train.py ./my-code /workspace my-pod my-namespace 5679
#
# Or use environment variables:
#   export NAMESPACE=my-namespace
#   export POD_NAME=my-pod
#   export LOCAL_DIR=./my-code
#   export REMOTE_DIR=/workspace
#   export DEBUG_PORT=5678
#   ./scripts/dev-session.sh train.py

# Configuration with defaults (args override env vars, env vars override hardcoded defaults)
SCRIPT="${1:-test_debug.py}"
LOCAL_DIR="${2:-${LOCAL_DIR:-./workspace}}"
REMOTE_DIR="${3:-${REMOTE_DIR:-/workspace}}"
POD_NAME="${4:-${POD_NAME:-ml-dev-env}}"
NAMESPACE="${5:-${NAMESPACE:-nccl-test}}"
DEBUG_PORT="${6:-${DEBUG_PORT:-5678}}"

# PIDs for background processes
SYNC_PID=""
PORT_FORWARD_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."

    if [ ! -z "$SYNC_PID" ]; then
        kill $SYNC_PID 2>/dev/null
        echo "✅ Code sync stopped"
    fi

    if [ ! -z "$PORT_FORWARD_PID" ]; then
        kill $PORT_FORWARD_PID 2>/dev/null
        echo "✅ Port-forward stopped"
    fi

    exit 0
}

# Trap Ctrl+C
trap cleanup INT TERM

echo "🚀 ML Development Session"
echo "========================="
echo "Namespace:  $NAMESPACE"
echo "Pod:        $POD_NAME"
echo "Local dir:  $LOCAL_DIR"
echo "Script:     $SCRIPT"
echo ""

# Check if pod is running
echo "🔍 Checking pod status..."
if ! oc get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Pod $POD_NAME not found"
    exit 1
fi

POD_STATUS=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Pod is not running (status: $POD_STATUS)"
    exit 1
fi
echo "✅ Pod is running"

# Initial sync
echo ""
echo "📤 Initial code sync..."
oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' 2>&1 | grep -v "^building file list"
echo "✅ Initial sync complete"

# Start continuous sync in background
echo ""
echo "🔄 Starting continuous code sync..."
if command -v fswatch >/dev/null 2>&1; then
    (
        fswatch -o "$LOCAL_DIR" | while read -r change; do
            echo "🔄 [$(date +%H:%M:%S)] Syncing changes..."
            oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' 2>&1 | grep -v "^building file list"
        done
    ) &
    SYNC_PID=$!
    echo "✅ Auto-sync enabled (using fswatch)"
else
    echo "⚠️  Install fswatch for better performance: brew install fswatch"
    (
        while true; do
            sleep 3
            oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store' 2>&1 | grep -v "^building file list" | grep -v "^$"
        done
    ) &
    SYNC_PID=$!
    echo "✅ Auto-sync enabled (polling every 3 seconds)"
fi

# Start port-forward in background
echo ""
echo "🔌 Starting port-forward on port $DEBUG_PORT..."
oc port-forward -n "$NAMESPACE" "$POD_NAME" "$DEBUG_PORT:$DEBUG_PORT" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 2

if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
    echo "❌ Port-forward failed"
    cleanup
fi
echo "✅ Port-forward ready"

# Instructions
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Development Session Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Code sync:      Active (watching $LOCAL_DIR)"
echo "✅ Port-forward:   localhost:$DEBUG_PORT → pod:$DEBUG_PORT"
echo ""
echo "Next steps:"
echo "  1. Edit code locally in: $LOCAL_DIR"
echo "  2. Changes auto-sync to pod"
echo "  3. Press ENTER to run: $SCRIPT"
echo "  4. Attach VSCode debugger (F5)"
echo ""
echo "Press ENTER to run the script, or Ctrl+C to exit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for user to press enter
read -r

# Run the script
echo ""
echo "🐍 Running: /workspace/$SCRIPT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Attach your VSCode debugger now (F5)!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

oc exec -it "$POD_NAME" -n "$NAMESPACE" -- python "/workspace/$SCRIPT"

echo ""
echo "🏁 Script finished"
echo ""
echo "Code sync and port-forward are still running."
echo "Press Ctrl+C to stop everything, or ENTER to run again"

# Wait for user input
read -r

# Re-run if user pressed enter
exec "$0" "$@"
