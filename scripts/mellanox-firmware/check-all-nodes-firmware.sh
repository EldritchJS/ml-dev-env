#!/bin/bash

NODES="u09 u11 u12 u16"

for node in $NODES; do
  echo "=== Checking moc-r4pcc04${node}-nairr ==="
  
  # Create MFT pod
  oc get pod mft-diagnostics-$node -n nvidia-network-operator -o json 2>/dev/null | \
    jq ".spec.nodeName = \"moc-r4pcc04${node}-nairr\" | .metadata.name = \"mft-diagnostics-${node}\"" | \
    oc apply -f - 2>/dev/null || echo "Pod mft-diagnostics-$node already exists or failed to create"
  
  sleep 2
done

echo ""
echo "Waiting for pods to be ready..."
sleep 10

for node in $NODES; do
  echo ""
  echo "=== Firmware settings for moc-r4pcc04${node}-nairr ==="
  
  for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do
    echo "--- NIC $pci ---"
    oc exec -n nvidia-network-operator mft-diagnostics-$node -- mlxconfig -d $pci query 2>/dev/null | \
      grep -E "ADVANCED_PCI_SETTINGS|MAX_ACC_OUT_READ|PCI_WR_ORDERING" | \
      grep -v "Name" | head -3
  done
done
