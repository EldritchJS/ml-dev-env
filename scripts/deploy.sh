#!/bin/bash
# Deployment script with configurable namespace

set -e

# Default namespace
NAMESPACE="${NAMESPACE:-nccl-test}"
POD_NAME="ml-dev-env"

echo "=========================================="
echo "ML Development Environment Deployment"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Function to apply YAML with namespace substitution
apply_with_namespace() {
    local file=$1
    echo "Applying $file to namespace $NAMESPACE..."
    cat "$file" | sed "s/namespace: nccl-test/namespace: $NAMESPACE/g" | oc apply -f -
}

# Parse command line arguments
case "${1:-deploy}" in
    build)
        echo "Building container image..."
        apply_with_namespace k8s/imagestream.yaml
        apply_with_namespace k8s/buildconfig.yaml
        echo "Build started. Follow logs with:"
        echo "  oc logs -f bc/$POD_NAME -n $NAMESPACE"
        ;;

    deploy)
        echo "Deploying full environment..."

        # Build
        apply_with_namespace k8s/imagestream.yaml
        apply_with_namespace k8s/buildconfig.yaml

        # Storage
        apply_with_namespace k8s/pvcs.yaml

        # Pod
        apply_with_namespace k8s/pod-multi-gpu.yaml

        # Services
        apply_with_namespace k8s/service.yaml

        echo ""
        echo "Waiting for pod to be ready..."
        oc wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=300s || true

        echo ""
        echo "=========================================="
        echo "Deployment complete!"
        echo "=========================================="
        echo ""
        echo "Get URLs:"
        echo "  VSCode:     https://$(oc get route ml-dev-vscode -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')"
        echo "  Jupyter:    https://$(oc get route ml-dev-jupyter -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')"
        echo "  TensorBoard: https://$(oc get route ml-dev-tensorboard -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')"
        echo ""
        echo "Access shell:"
        echo "  oc rsh $POD_NAME -n $NAMESPACE"
        ;;

    clean)
        echo "Cleaning up resources in namespace $NAMESPACE..."
        read -p "Are you sure? This will delete the pod and optionally PVCs. [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            oc delete pod $POD_NAME -n $NAMESPACE --ignore-not-found=true
            oc delete service $POD_NAME -n $NAMESPACE --ignore-not-found=true
            oc delete route ml-dev-vscode ml-dev-jupyter ml-dev-tensorboard -n $NAMESPACE --ignore-not-found=true

            read -p "Delete PVCs (will delete all data)? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                oc delete pvc ml-dev-workspace ml-datasets -n $NAMESPACE --ignore-not-found=true
            fi

            oc delete bc $POD_NAME -n $NAMESPACE --ignore-not-found=true
            oc delete is $POD_NAME -n $NAMESPACE --ignore-not-found=true

            echo "Cleanup complete!"
        fi
        ;;

    status)
        echo "Status in namespace $NAMESPACE:"
        echo ""
        echo "=== Pod ==="
        oc get pod $POD_NAME -n $NAMESPACE 2>/dev/null || echo "Pod not found"
        echo ""
        echo "=== Builds ==="
        oc get builds -n $NAMESPACE 2>/dev/null | grep $POD_NAME || echo "No builds found"
        echo ""
        echo "=== PVCs ==="
        oc get pvc -n $NAMESPACE 2>/dev/null | grep ml-dev || echo "No PVCs found"
        echo ""
        echo "=== Routes ==="
        oc get routes -n $NAMESPACE 2>/dev/null | grep ml-dev || echo "No routes found"
        ;;

    shell)
        echo "Opening shell in $POD_NAME..."
        oc rsh $POD_NAME -n $NAMESPACE
        ;;

    *)
        echo "Usage: $0 {build|deploy|clean|status|shell}"
        echo ""
        echo "Set namespace with environment variable:"
        echo "  NAMESPACE=my-namespace $0 deploy"
        echo ""
        echo "Or export it:"
        echo "  export NAMESPACE=my-namespace"
        echo "  $0 deploy"
        exit 1
        ;;
esac
