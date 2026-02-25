#!/usr/bin/env bash
#
# Compare Auto-Detected NCCL Values vs Hardcoded H-Kim Values
#
# This script shows what autodetect finds vs what's hardcoded in h-kim

set -euo pipefail

NAMESPACE="${NAMESPACE:-nccl-test}"
POD_NAME="${POD_NAME:-h-kim-test-0}"

echo "=========================================="
echo "NCCL Auto-Detection Comparison"
echo "=========================================="
echo ""

# Check if test pod exists
if ! oc get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "ERROR: Pod $POD_NAME not found in namespace $NAMESPACE"
    echo ""
    echo "Deploy the test first:"
    echo "  oc apply -f test-h-kim-autodetect.yaml"
    echo ""
    exit 1
fi

# Check if pod is running
POD_STATUS=$(oc get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [[ "$POD_STATUS" != "Running" ]]; then
    echo "ERROR: Pod $POD_NAME is not Running (current status: $POD_STATUS)"
    echo ""
    echo "Wait for pod to be ready:"
    echo "  oc get pod $POD_NAME -n $NAMESPACE -w"
    echo ""
    exit 1
fi

echo "✅ Test pod is running: $POD_NAME"
echo ""

# Get auto-detected values
echo "=========================================="
echo "1. AUTO-DETECTED VALUES"
echo "=========================================="
echo ""
echo "Reading from pod $POD_NAME..."
echo ""

AUTO_VALUES=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- bash -c 'source /shared/nccl-env.sh 2>/dev/null && cat <<EOF
GPUS_PER_NODE=$GPUS_PER_NODE
OMP_NUM_THREADS=$OMP_NUM_THREADS
NCCL_IB_HCA=$NCCL_IB_HCA
NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME
NCCL_IB_GID_INDEX=$NCCL_IB_GID_INDEX
NCCL_NET_GDR_LEVEL=$NCCL_NET_GDR_LEVEL
NCCL_P2P_LEVEL=$NCCL_P2P_LEVEL
NCCL_IB_DISABLE=$NCCL_IB_DISABLE
DETECTED_TRANSPORT=$DETECTED_TRANSPORT
EOF
')

echo "$AUTO_VALUES"
echo ""

# Parse auto-detected values
eval "$AUTO_VALUES"
AUTO_GPUS=$GPUS_PER_NODE
AUTO_OMP=$OMP_NUM_THREADS
AUTO_IB_HCA=$NCCL_IB_HCA
AUTO_SOCKET=$NCCL_SOCKET_IFNAME
AUTO_GID=$NCCL_IB_GID_INDEX
AUTO_GDR=$NCCL_NET_GDR_LEVEL
AUTO_P2P=$NCCL_P2P_LEVEL
AUTO_IB_DISABLE=$NCCL_IB_DISABLE
AUTO_TRANSPORT=$DETECTED_TRANSPORT

# Hardcoded values from h-kim deployment
echo "=========================================="
echo "2. HARDCODED VALUES (from h-kim)"
echo "=========================================="
echo ""

HARDCODED_GPUS="4"
HARDCODED_OMP="8"  # Not explicitly set in h-kim, but would use default
HARDCODED_GID="3"
HARDCODED_GDR="5"
HARDCODED_IB_DISABLE="0"

# Get the actual hardcoded values from h-kim if it's running
if oc get statefulset h-kim -n "$NAMESPACE" &>/dev/null; then
    echo "Reading hardcoded values from h-kim StatefulSet..."
    HARDCODED_GPUS=$(oc get statefulset h-kim -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="GPUS_PER_NODE")].value}' || echo "4")
    HARDCODED_GID=$(oc get statefulset h-kim -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NCCL_IB_GID_INDEX")].value}' || echo "3")
    HARDCODED_GDR=$(oc get statefulset h-kim -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NCCL_NET_GDR_LEVEL")].value}' || echo "5")
    HARDCODED_IB_DISABLE=$(oc get statefulset h-kim -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NCCL_IB_DISABLE")].value}' || echo "0")
    echo ""
else
    echo "h-kim StatefulSet not found, using default hardcoded values"
    echo ""
fi

cat <<EOF
GPUS_PER_NODE=$HARDCODED_GPUS
OMP_NUM_THREADS=$HARDCODED_OMP (default, not explicitly set)
NCCL_IB_HCA=(auto-detected in h-kim via init container)
NCCL_SOCKET_IFNAME=(auto-detected in h-kim via init container)
NCCL_IB_GID_INDEX=$HARDCODED_GID
NCCL_NET_GDR_LEVEL=$HARDCODED_GDR
NCCL_P2P_LEVEL=(not explicitly set, uses NCCL defaults)
NCCL_IB_DISABLE=$HARDCODED_IB_DISABLE
EOF
echo ""

# Get actual IB_HCA and SOCKET_IFNAME from running h-kim if available
if oc get pod h-kim-0 -n "$NAMESPACE" &>/dev/null 2>&1; then
    echo "Reading auto-detected values from h-kim-0..."
    HKIM_IB_HCA=$(oc exec h-kim-0 -n "$NAMESPACE" -- bash -c 'source /shared/nccl-env.sh 2>/dev/null && echo $NCCL_IB_HCA' 2>/dev/null || echo "not available")
    HKIM_SOCKET=$(oc exec h-kim-0 -n "$NAMESPACE" -- bash -c 'source /shared/nccl-env.sh 2>/dev/null && echo $NCCL_SOCKET_IFNAME' 2>/dev/null || echo "not available")
    echo "  NCCL_IB_HCA=$HKIM_IB_HCA"
    echo "  NCCL_SOCKET_IFNAME=$HKIM_SOCKET"
    echo ""
fi

# Comparison
echo "=========================================="
echo "3. COMPARISON"
echo "=========================================="
echo ""

compare_value() {
    local name=$1
    local auto=$2
    local hardcoded=$3
    local status

    if [[ "$auto" == "$hardcoded" ]]; then
        status="✅ MATCH"
    else
        status="⚠️  DIFFERENT"
    fi

    printf "%-25s | %-20s | %-20s | %s\n" "$name" "$auto" "$hardcoded" "$status"
}

printf "%-25s | %-20s | %-20s | %s\n" "Variable" "Auto-Detected" "Hardcoded" "Status"
printf "%-25s-+-%-20s-+-%-20s-+-%s\n" "-------------------------" "--------------------" "--------------------" "-------------"

compare_value "GPUS_PER_NODE" "$AUTO_GPUS" "$HARDCODED_GPUS"
compare_value "OMP_NUM_THREADS" "$AUTO_OMP" "$HARDCODED_OMP"
compare_value "NCCL_IB_GID_INDEX" "$AUTO_GID" "$HARDCODED_GID"
compare_value "NCCL_NET_GDR_LEVEL" "$AUTO_GDR" "$HARDCODED_GDR"
compare_value "NCCL_IB_DISABLE" "$AUTO_IB_DISABLE" "$HARDCODED_IB_DISABLE"

echo ""
echo "IB_HCA and SOCKET_IFNAME:"
if oc get pod h-kim-0 -n "$NAMESPACE" &>/dev/null 2>&1; then
    compare_value "NCCL_IB_HCA" "$AUTO_IB_HCA" "$HKIM_IB_HCA"
    compare_value "NCCL_SOCKET_IFNAME" "$AUTO_SOCKET" "$HKIM_SOCKET"
else
    echo "  (Cannot compare - h-kim-0 not running)"
    echo "  Auto-detected: NCCL_IB_HCA=$AUTO_IB_HCA"
    echo "  Auto-detected: NCCL_SOCKET_IFNAME=$AUTO_SOCKET"
fi

echo ""
echo "NCCL_P2P_LEVEL:"
echo "  Auto-detected: $AUTO_P2P"
echo "  Hardcoded: Not set (uses NCCL defaults)"
echo "  Note: Auto-detection provides explicit value for consistency"

echo ""
echo "=========================================="
echo "4. SUMMARY"
echo "=========================================="
echo ""

# Count matches and differences
MATCHES=0
DIFFS=0

[[ "$AUTO_GPUS" == "$HARDCODED_GPUS" ]] && ((MATCHES++)) || ((DIFFS++))
[[ "$AUTO_GID" == "$HARDCODED_GID" ]] && ((MATCHES++)) || ((DIFFS++))
[[ "$AUTO_GDR" == "$HARDCODED_GDR" ]] && ((MATCHES++)) || ((DIFFS++))
[[ "$AUTO_IB_DISABLE" == "$HARDCODED_IB_DISABLE" ]] && ((MATCHES++)) || ((DIFFS++))

echo "Core NCCL values:"
echo "  ✅ Matches: $MATCHES"
echo "  ⚠️  Differences: $DIFFS"
echo ""

if [[ "$DIFFS" -eq 0 ]]; then
    echo "✅ SUCCESS: Auto-detection matches all hardcoded NCCL values!"
    echo ""
    echo "Key findings:"
    echo "  - NCCL_IB_GID_INDEX: Correctly detected as $AUTO_GID"
    echo "  - NCCL_NET_GDR_LEVEL: Correctly detected as $AUTO_GDR"
    echo "  - NCCL_IB_HCA: Auto-detected as $AUTO_IB_HCA"
    echo "  - NCCL_SOCKET_IFNAME: Auto-detected as $AUTO_SOCKET"
    echo ""
    echo "Differences (improvements):"
    echo "  - OMP_NUM_THREADS: $AUTO_OMP (auto) vs $HARDCODED_OMP (default)"
    echo "    → Auto-detection is better! (optimal CPU allocation)"
    echo "  - NCCL_P2P_LEVEL: $AUTO_P2P (auto) vs not set (hardcoded)"
    echo "    → Auto-detection provides explicit NVLink configuration"
    echo ""
else
    echo "⚠️  WARNING: Some values don't match!"
    echo ""
    echo "This may indicate:"
    echo "  - Hardware doesn't match expectations"
    echo "  - Detection logic needs adjustment"
    echo "  - Hardcoded values may be incorrect"
    echo ""
fi

echo "Transport: $AUTO_TRANSPORT"
echo ""

echo "=========================================="
echo "5. DETAILED DETECTION INFO"
echo "=========================================="
echo ""

echo "From init container logs:"
oc logs "$POD_NAME" -n "$NAMESPACE" -c comprehensive-autodetect | grep "Detection results" -A 10 || echo "(Init container logs not available)"

echo ""
echo "=========================================="
echo "Complete! 🎉"
echo "=========================================="
