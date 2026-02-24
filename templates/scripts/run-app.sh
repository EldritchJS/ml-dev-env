#!/bin/bash
#
# Run application in deployed pods
#
# Usage:
#   ./scripts/run-app.sh              # Run on all pods
#   ./scripts/run-app.sh --node 0     # Run only on pod-0
#   ./scripts/run-app.sh --watch      # Stream logs while running
#

set -e

APP_NAME="{app_name}"
NAMESPACE="{namespace}"
WORKING_DIR="{working_dir}"
ENTRY_POINT="{entry_point}"
ARGUMENTS="{arguments}"

# Parse arguments
WATCH_LOGS=false
SPECIFIC_NODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_LOGS=true
            shift
            ;;
        --node)
            SPECIFIC_NODE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--watch] [--node <N>]"
            exit 1
            ;;
    esac
done

# Build command
CMD="cd $WORKING_DIR && python $ENTRY_POINT $ARGUMENTS"

echo "🚀 Running application: $APP_NAME"
echo "   Working dir: $WORKING_DIR"
echo "   Entry point: $ENTRY_POINT"
if [ -n "$ARGUMENTS" ]; then
    echo "   Arguments: $ARGUMENTS"
fi
echo ""

if [ -n "$SPECIFIC_NODE" ]; then
    # Run on specific pod
    POD_NAME="${APP_NAME}-${SPECIFIC_NODE}"
    echo "Executing on pod: $POD_NAME"

    if [ "$WATCH_LOGS" = true ]; then
        # Stream logs
        oc exec -n $NAMESPACE $POD_NAME -- bash -c "$CMD" 2>&1
    else
        # Run in background
        oc exec -n $NAMESPACE $POD_NAME -- bash -c "nohup bash -c '$CMD' > /workspace/app.log 2>&1 &"
        echo "✓ Application started in background"
        echo "  View logs: ./scripts/logs.sh"
    fi
else
    # Run on all pods
    POD_LIST=$(oc get pods -n $NAMESPACE -l app=${APP_NAME}-multi -o jsonpath='{.items[*].metadata.name}')

    if [ -z "$POD_LIST" ]; then
        echo "❌ No pods found for app: $APP_NAME"
        exit 1
    fi

    for POD in $POD_LIST; do
        echo "Executing on pod: $POD"
        if [ "$WATCH_LOGS" = true ]; then
            oc exec -n $NAMESPACE $POD -- bash -c "$CMD" 2>&1 &
        else
            oc exec -n $NAMESPACE $POD -- bash -c "nohup bash -c '$CMD' > /workspace/app.log 2>&1 &"
        fi
    done

    echo ""
    echo "✓ Application started on all pods"

    if [ "$WATCH_LOGS" = true ]; then
        wait
    else
        echo "  View logs: ./scripts/logs.sh"
    fi
fi

echo ""
echo "Done!"
