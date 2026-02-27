#!/bin/bash

NODES="u09 u11 u12 u16"
NICS="03:00.0 23:00.0 a3:00.0 c3:00.0"

for node in $NODES; do
  echo ""
  echo "=========================================="
  echo "Applying firmware fixes to moc-r4pcc04${node}-nairr"
  echo "=========================================="
  
  for pci in $NICS; do
    echo ""
    echo "--- Fixing NIC $pci on ${node} ---"
    
    # Apply the three critical settings
    echo "Setting ADVANCED_PCI_SETTINGS=1..."
    oc exec -n nvidia-network-operator mft-diagnostics-${node} -- \
      mlxconfig -y -d $pci set ADVANCED_PCI_SETTINGS=1 2>&1 | grep -E "Applying|configurations|successfully"
    
    echo "Setting PCI_WR_ORDERING=0 (per_mkey)..."
    oc exec -n nvidia-network-operator mft-diagnostics-${node} -- \
      mlxconfig -y -d $pci set PCI_WR_ORDERING=0 2>&1 | grep -E "Applying|configurations|successfully"
    
    echo "Setting MAX_ACC_OUT_READ=128..."
    oc exec -n nvidia-network-operator mft-diagnostics-${node} -- \
      mlxconfig -y -d $pci set MAX_ACC_OUT_READ=128 2>&1 | grep -E "Applying|configurations|successfully"
    
    echo "✓ NIC $pci configured"
  done
  
  echo ""
  echo "✓ All 4 NICs on ${node} configured (changes pending reboot)"
done

echo ""
echo "=========================================="
echo "All firmware changes applied successfully!"
echo "Changes will take effect after node reboots"
echo "=========================================="
