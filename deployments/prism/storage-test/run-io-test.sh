#!/bin/bash
#
# Test split storage pattern: shared NFS for dataset reads + per-pod RWO for checkpoint writes.
# Simulates ZeRO-3 checkpoint I/O: each pod writes ~33GB to its own RWO PVC
# while reading from the shared NFS mount.
#
# Usage:
#   # 1. Create the StatefulSet (PVCs are created automatically via volumeClaimTemplates)
#   oc apply -f storage-io-test.yaml
#
#   # 2. Wait for all pods
#   oc wait --for=condition=Ready pod -l app=storage-io-test -n b-prism --timeout=120s
#
#   # 3. Run this script
#   ./run-io-test.sh
#
#   # 4. Clean up
#   ./run-io-test.sh cleanup

set -euo pipefail

NAMESPACE="b-prism"
LABEL="app=storage-io-test"
WRITE_SIZE_GB=33
BLOCK_SIZE="1M"
READ_TEST_FILE="/data/read-test-file"
READ_SIZE_GB=5

if [[ "${1:-}" == "cleanup" ]]; then
    echo "=== Cleaning up ==="
    oc delete statefulset storage-io-test -n "$NAMESPACE" --ignore-not-found
    for i in 0 1 2 3 4; do
        oc delete pvc "checkpoint-storage-io-test-${i}" -n "$NAMESPACE" --ignore-not-found
    done
    echo "Done. prism-data-shared PVC preserved."
    exit 0
fi

PODS=$(oc get pods -n "$NAMESPACE" -l "$LABEL" -o jsonpath='{.items[*].metadata.name}')
POD_COUNT=$(echo "$PODS" | wc -w | tr -d ' ')

if [[ "$POD_COUNT" -ne 5 ]]; then
    echo "ERROR: Expected 5 pods, found $POD_COUNT. Are all pods Running?"
    exit 1
fi

echo "=== Storage I/O Test ==="
echo "Pods: $PODS"
echo "Write test: ${WRITE_SIZE_GB}GB per pod to /checkpoints (RWO ceph-rbd)"
echo "Read test: ${READ_SIZE_GB}GB from /data (RWX NFS)"
echo ""

# --- Phase 1: Seed a test file on shared NFS from pod-0 ---
FIRST_POD=$(echo "$PODS" | awk '{print $1}')
echo "=== Phase 1: Seeding ${READ_SIZE_GB}GB test file on shared NFS ==="
oc exec -n "$NAMESPACE" "$FIRST_POD" -- bash -c \
    "dd if=/dev/urandom of=${READ_TEST_FILE} bs=${BLOCK_SIZE} count=$((READ_SIZE_GB * 1024)) status=progress 2>&1"
echo ""

# --- Phase 2: Parallel checkpoint writes (simulates ZeRO-3 per-rank save) ---
echo "=== Phase 2: Parallel ${WRITE_SIZE_GB}GB writes to per-pod RWO PVCs ==="
for POD in $PODS; do
    echo "Starting write on $POD..."
    oc exec -n "$NAMESPACE" "$POD" -- bash -c \
        "dd if=/dev/urandom of=/checkpoints/checkpoint.bin bs=${BLOCK_SIZE} count=$((WRITE_SIZE_GB * 1024)) status=none 2>&1 && echo DONE" &
done

echo "Waiting for all writes to complete..."
WRITE_START=$(date +%s)
wait
WRITE_END=$(date +%s)
WRITE_ELAPSED=$((WRITE_END - WRITE_START))
TOTAL_WRITTEN=$((WRITE_SIZE_GB * POD_COUNT))
echo "All writes complete: ${TOTAL_WRITTEN}GB total in ${WRITE_ELAPSED}s (~$((TOTAL_WRITTEN * 1024 / WRITE_ELAPSED)) MB/s aggregate)"
echo ""

# --- Phase 3: Parallel reads from shared NFS (simulates dataset loading) ---
echo "=== Phase 3: Parallel ${READ_SIZE_GB}GB reads from shared NFS ==="
for POD in $PODS; do
    echo "Starting read on $POD..."
    oc exec -n "$NAMESPACE" "$POD" -- bash -c \
        "dd if=${READ_TEST_FILE} of=/dev/null bs=${BLOCK_SIZE} status=none 2>&1 && echo DONE" &
done

echo "Waiting for all reads to complete..."
READ_START=$(date +%s)
wait
READ_END=$(date +%s)
READ_ELAPSED=$((READ_END - READ_START))
TOTAL_READ=$((READ_SIZE_GB * POD_COUNT))
echo "All reads complete: ${TOTAL_READ}GB total in ${READ_ELAPSED}s (~$((TOTAL_READ * 1024 / READ_ELAPSED)) MB/s aggregate)"
echo ""

# --- Phase 4: Report per-pod PVC usage ---
echo "=== Phase 4: Per-pod checkpoint PVC usage ==="
for POD in $PODS; do
    echo -n "$POD: "
    oc exec -n "$NAMESPACE" "$POD" -- du -sh /checkpoints
done
echo ""

# --- Phase 5: Shared NFS usage ---
echo "=== Phase 5: Shared NFS usage ==="
oc exec -n "$NAMESPACE" "$FIRST_POD" -- du -sh /data
echo ""

echo "=== Test Complete ==="
echo "Summary:"
echo "  Checkpoint writes (RWO ceph-rbd): ${TOTAL_WRITTEN}GB in ${WRITE_ELAPSED}s"
echo "  Dataset reads (RWX NFS):          ${TOTAL_READ}GB in ${READ_ELAPSED}s"
