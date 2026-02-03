#!/bin/bash

# Automate port-forwarding and running debug script
# Usage: ./scripts/debug-remote.sh [script_name] [pod_name] [namespace] [port]
#
# Examples:
#   ./scripts/debug-remote.sh
#   ./scripts/debug-remote.sh train.py
#   ./scripts/debug-remote.sh train.py my-pod my-namespace
#   ./scripts/debug-remote.sh train.py my-pod my-namespace 5679

# Configuration with defaults
SCRIPT="${1:-test_debug.py}"
POD_NAME="${2:-${POD_NAME:-ml-dev-env}}"
NAMESPACE="${3:-${NAMESPACE:-nccl-test}}"
DEBUG_PORT="${4:-${DEBUG_PORT:-5678}}"

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    if [ ! -z "$PORT_FORWARD_PID" ]; then
        kill $PORT_FORWARD_PID 2>/dev/null
        echo "✅ Port-forward stopped"
    fi
    exit 0
}

# Trap Ctrl+C
trap cleanup INT TERM

echo "🚀 Remote Debug Automation"
echo "=========================="
echo "Namespace: $NAMESPACE"
echo "Pod:       $POD_NAME"
echo "Script:    /workspace/$SCRIPT"
echo "Port:      $DEBUG_PORT"
echo ""

# Check if pod is running
echo "🔍 Checking pod status..."
if ! oc get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Pod $POD_NAME not found in namespace $NAMESPACE"
    exit 1
fi

POD_STATUS=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Pod is not running (status: $POD_STATUS)"
    exit 1
fi
echo "✅ Pod is running"

# Start port-forward in background
echo ""
echo "🔌 Starting port-forward on port $DEBUG_PORT..."
oc port-forward -n "$NAMESPACE" "$POD_NAME" "$DEBUG_PORT:$DEBUG_PORT" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready
sleep 2

if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
    echo "❌ Port-forward failed to start"
    exit 1
fi
echo "✅ Port-forward ready (PID: $PORT_FORWARD_PID)"

# Run the script on the pod
echo ""
echo "🐍 Running Python script on pod..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Attach your VSCode debugger now!"
echo "   Press F5 and select 'Python: Remote Attach to Cluster'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run the script
oc exec -it "$POD_NAME" -n "$NAMESPACE" -- python "/workspace/$SCRIPT"

# Cleanup
cleanup
