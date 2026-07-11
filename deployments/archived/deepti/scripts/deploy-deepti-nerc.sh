#!/bin/bash
# Deploy deepti.py test on NERC cluster with single node, 4 GPUs

set -e

NAMESPACE="coops-767192"
POD_NAME="deepti-test"
CONFIGMAP_NAME="deepti-script"
SERVICE_ACCOUNT="ml-dev-sa"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "Deepti Qwen2.5-Omni Deployment (NERC)"
echo -e "==========================================${NC}"
echo ""

# Check if we're logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift${NC}"
    echo "Please run: oc login api.shift.nerc.mghpcc.org"
    exit 1
fi

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Namespace $NAMESPACE not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Current context:${NC}"
oc whoami
oc project "$NAMESPACE"
echo ""

# Create service account if it doesn't exist
if ! oc get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Creating service account: $SERVICE_ACCOUNT${NC}"
    oc create serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE"
    echo -e "${GREEN}✓ Service account created${NC}"
else
    echo -e "${GREEN}✓ Service account exists: $SERVICE_ACCOUNT${NC}"
fi
echo ""

# Note about privileged SCC (optional - only if needed)
echo -e "${YELLOW}Note: If you need privileged access (IPC_LOCK), run:${NC}"
echo "  oc adm policy add-scc-to-user privileged -z $SERVICE_ACCOUNT -n $NAMESPACE"
echo ""

# Check if deepti.py exists
if [ ! -f "deepti.py" ]; then
    echo -e "${RED}Error: deepti.py not found in current directory${NC}"
    exit 1
fi

# Create ConfigMap with deepti.py
echo -e "${YELLOW}Creating ConfigMap with deepti.py...${NC}"
oc create configmap "$CONFIGMAP_NAME" \
    --from-file=deepti.py=deepti.py \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | oc apply -f -
echo -e "${GREEN}✓ ConfigMap created/updated${NC}"
echo ""

# Delete existing pod if it exists
if oc get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Deleting existing pod...${NC}"
    oc delete pod "$POD_NAME" -n "$NAMESPACE" --wait=false
    # Wait for pod to be deleted
    echo -n "Waiting for pod deletion"
    while oc get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; do
        echo -n "."
        sleep 2
    done
    echo ""
    echo -e "${GREEN}✓ Old pod deleted${NC}"
fi
echo ""

# Deploy the pod
echo -e "${YELLOW}Deploying pod...${NC}"
oc apply -f k8s/pod-deepti-nerc.yaml -n "$NAMESPACE"
echo -e "${GREEN}✓ Pod created${NC}"
echo ""

# Wait for pod to be scheduled
echo -e "${YELLOW}Waiting for pod to be scheduled...${NC}"
sleep 3

# Show pod status
echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Status"
echo -e "==========================================${NC}"
oc get pod "$POD_NAME" -n "$NAMESPACE"
echo ""

# Show which node it's running on
NODE=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "pending")
if [ "$NODE" != "pending" ] && [ -n "$NODE" ]; then
    echo -e "${GREEN}Running on node: $NODE${NC}"
    echo ""
fi

# Follow logs
echo -e "${YELLOW}Following pod logs (Ctrl+C to stop):${NC}"
echo -e "${YELLOW}To view logs later, run:${NC}"
echo "  oc logs -f $POD_NAME -n $NAMESPACE"
echo ""

# Wait a moment for container to start
sleep 2

# Tail logs
oc logs -f "$POD_NAME" -n "$NAMESPACE" 2>&1 || {
    echo ""
    echo -e "${YELLOW}Pod not ready yet. Check status with:${NC}"
    echo "  oc get pod $POD_NAME -n $NAMESPACE"
    echo "  oc describe pod $POD_NAME -n $NAMESPACE"
    echo "  oc logs $POD_NAME -n $NAMESPACE"
}
