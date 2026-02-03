#!/bin/bash

# Deploy multi-node StatefulSet for distributed training (TCP/Ethernet - NO RDMA)
# Usage: ./scripts/deploy-multi-node-tcp.sh [namespace]

NAMESPACE="${1:-${NAMESPACE:-nccl-test}}"

echo "🚀 Deploying Multi-Node ML Environment (TCP Mode)"
echo "======================================"
echo "Namespace: $NAMESPACE"
echo "Nodes:     2 (default, adjust in YAML)"
echo "GPUs:      8 (4 per node, default)"
echo "Network:   TCP/Ethernet (NO RDMA required)"
echo ""

# Check if PVCs exist
echo "📦 Checking PVCs..."
if ! oc get pvc ml-dev-workspace -n "$NAMESPACE" &>/dev/null; then
    echo "⚠️  PVC ml-dev-workspace not found. Creating..."
    oc apply -f k8s/pvcs.yaml -n "$NAMESPACE"
    echo "Waiting for PVCs to be bound..."
    sleep 5
fi

# Check image exists
echo "🔍 Checking container image..."
if ! oc get is ml-dev-env -n "$NAMESPACE" &>/dev/null; then
    echo "❌ ImageStream ml-dev-env not found"
    echo "Please build the image first: make build"
    exit 1
fi

IMAGE_TAG=$(oc get is ml-dev-env -n "$NAMESPACE" -o jsonpath='{.status.tags[0].items[0].dockerImageReference}' 2>/dev/null)
if [ -z "$IMAGE_TAG" ]; then
    echo "❌ No image found in ImageStream"
    echo "Please build the image first: make build"
    exit 1
fi
echo "✅ Using image: $IMAGE_TAG"

# Deploy StatefulSet (TCP variant)
echo ""
echo "🚢 Deploying StatefulSet (TCP/Ethernet mode)..."
cat k8s/statefulset-multi-node-tcp.yaml | sed "s|namespace: nccl-test|namespace: $NAMESPACE|g" | oc apply -f -

echo ""
echo "⏳ Waiting for pods to be created..."
sleep 5

# Watch pod status
echo ""
echo "📊 Pod Status:"
oc get pods -n "$NAMESPACE" -l app=ml-dev-env-multi -o wide

echo ""
echo "======================================"
echo "Deployment initiated!"
echo ""
echo "⚠️  NOTE: This uses TCP/Ethernet networking (NO RDMA)"
echo "   - Works on any nodes (no InfiniBand required)"
echo "   - Slower than RDMA but more compatible"
echo "   - For RDMA mode, use: make deploy-multi-node"
echo ""
echo "Monitor progress:"
echo "  oc get pods -n $NAMESPACE -l app=ml-dev-env-multi -w"
echo ""
echo "Check logs:"
echo "  oc logs ml-dev-env-0 -n $NAMESPACE"
echo ""
echo "Once all pods are Running (1/1), you can:"
echo "  1. Shell into master: oc exec -it ml-dev-env-0 -n $NAMESPACE -- bash"
echo "  2. Start training: ./workspace/launch_deepspeed.sh"
echo ""
echo "See docs/MULTI-NODE-GUIDE.md for details"
echo "======================================"
