#!/bin/bash

NODES="moc-r4pcc04u09-nairr moc-r4pcc04u11-nairr moc-r4pcc04u12-nairr moc-r4pcc04u16-nairr moc-r4pcc04u25-nairr moc-r4pcc04u36-nairr"

for node in $NODES; do
    echo "============================================"
    echo "Checking node: $node"
    echo "============================================"

    # Check for InfiniBand devices
    echo "--- InfiniBand Devices (/dev/infiniband) ---"
    kubectl debug node/$node --profile=sysadmin --image=registry.access.redhat.com/ubi9/ubi:latest -- \
        ls -la /host/dev/infiniband/ 2>/dev/null || echo "No /dev/infiniband directory found"

    echo ""
    echo "--- RDMA Devices (/sys/class/infiniband) ---"
    kubectl debug node/$node --profile=sysadmin --image=registry.access.redhat.com/ubi9/ubi:latest -- \
        ls -la /host/sys/class/infiniband/ 2>/dev/null || echo "No RDMA devices in sysfs"

    echo ""
    echo "--- Network Interfaces with RDMA ---"
    kubectl debug node/$node --profile=sysadmin --image=registry.access.redhat.com/ubi9/ubi:latest -- \
        ls /host/sys/class/net/ 2>/dev/null

    echo ""
    echo ""
done
