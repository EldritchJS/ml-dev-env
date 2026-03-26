#!/bin/bash
#
# Validate SR-IOV network attachment definitions in a namespace
#
# Usage: ./validate-network-attachments.sh <namespace>
#

set -e

NAMESPACE=${1:-default}

echo "Validating SR-IOV network attachments in namespace: $NAMESPACE"
echo ""

EXPECTED_RANGES=(
  "eno5np0-network:10.0.103.0/24"
  "eno6np0-network:10.0.104.0/24"
  "eno7np0-network:10.0.105.0/24"
  "eno8np0-network:10.0.106.0/24"
)

ERRORS=0

for entry in "${EXPECTED_RANGES[@]}"; do
  IFS=':' read -r net expected_range <<< "$entry"

  if ! kubectl get network-attachment-definition "$net" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ MISSING: $net not found in namespace $NAMESPACE"
    ((ERRORS++))
    continue
  fi

  actual_range=$(kubectl get network-attachment-definition "$net" -n "$NAMESPACE" -o json | \
    jq -r '.spec.config | fromjson | .ipam.range')

  if [ "$actual_range" != "$expected_range" ]; then
    echo "❌ MISMATCH: $net has range $actual_range (expected: $expected_range)"
    ((ERRORS++))
  else
    echo "✅ CORRECT: $net → $expected_range"
  fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "✅ All network attachments are correctly configured!"
  exit 0
else
  echo "❌ Found $ERRORS error(s) in network attachment configuration"
  exit 1
fi
