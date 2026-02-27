#!/bin/bash

# Script to check Mellanox ConnectX-7 settings and provide optimization recommendations

NAMESPACE="nccl-test"
POD="pytorch-benchmark-opt-0"

echo "=========================================="
echo "Mellanox ConnectX-7 Configuration Check"
echo "=========================================="
echo ""

# First, re-deploy a pod if needed
if ! oc get pod $POD -n $NAMESPACE &>/dev/null; then
    echo "Pod not found. Deploying..."
    oc apply -f /Users/jschless/taj/cairo/pytorch-benchmark-optimized.yaml
    sleep 20
    echo "Waiting for pod to be ready..."
    oc wait --for=condition=ready pod/$POD -n $NAMESPACE --timeout=120s
    echo ""
fi

echo "=== 1. Firmware Version & Device Info ==="
echo ""
oc exec $POD -n $NAMESPACE -- mst start 2>/dev/null || true
oc exec $POD -n $NAMESPACE -- mst status 2>/dev/null || echo "MST not available - using mlxlink"

# Check firmware version via flint (if available)
oc exec $POD -n $NAMESPACE -- which flint &>/dev/null && \
    oc exec $POD -n $NAMESPACE -- flint -d /dev/mst/mt4129_pciconf0 q 2>/dev/null | grep -E "FW Version|Product Version" || \
    echo "flint not available"

echo ""
echo "=== 2. PCIe Configuration ==="
echo ""
# Check PCIe settings for mlx5_6, mlx5_7, mlx5_10, mlx5_11
for dev in mlx5_6 mlx5_7 mlx5_10 mlx5_11; do
    echo "Device: $dev"
    oc exec $POD -n $NAMESPACE -- sh -c "
        if [ -d /sys/class/infiniband/$dev/device ]; then
            pci_path=\$(readlink -f /sys/class/infiniband/$dev/device)
            echo \"  PCI Address: \$(basename \$pci_path)\"
            echo \"  Max Payload Size: \$(cat \$pci_path/max_read_request_size 2>/dev/null || echo 'N/A')\"
            echo \"  Current Link Speed: \$(cat \$pci_path/current_link_speed 2>/dev/null || echo 'N/A')\"
            echo \"  Current Link Width: \$(cat \$pci_path/current_link_width 2>/dev/null || echo 'N/A')\"
            echo \"  Max Link Speed: \$(cat \$pci_path/max_link_speed 2>/dev/null || echo 'N/A')\"
            echo \"  Max Link Width: \$(cat \$pci_path/max_link_width 2>/dev/null || echo 'N/A')\"
        fi
    "
    echo ""
done

echo "=== 3. Network Interface Settings ==="
echo ""
for iface in net1 net2 net3 net4; do
    echo "Interface: $iface"
    oc exec $POD -n $NAMESPACE -- sh -c "
        if [ -e /sys/class/net/$iface ]; then
            echo \"  Speed: \$(cat /sys/class/net/$iface/speed 2>/dev/null) Mbps\"
            echo \"  MTU: \$(cat /sys/class/net/$iface/mtu)\"
            echo \"  TX Queue Length: \$(cat /sys/class/net/$iface/tx_queue_len)\"
        fi
    " 2>/dev/null || echo "  Interface not found"
    echo ""
done

echo "=== 4. mlx5_core Module Parameters ==="
echo ""
oc exec $POD -n $NAMESPACE -- sh -c "
    if [ -d /sys/module/mlx5_core/parameters ]; then
        echo 'Current mlx5_core parameters:'
        for param in /sys/module/mlx5_core/parameters/*; do
            echo \"  \$(basename \$param): \$(cat \$param 2>/dev/null)\"
        done
    fi
" 2>/dev/null

echo ""
echo "=== 5. RDMA Device Capabilities ==="
echo ""
for dev in mlx5_6 mlx5_7 mlx5_10 mlx5_11; do
    echo "Device: $dev capabilities"
    oc exec $POD -n $NAMESPACE -- ibv_devinfo -d $dev 2>/dev/null | grep -E "max_qp|max_cq|max_mr|max_pd" | head -10
    echo ""
done

echo "=== 6. RoCE/Congestion Control Settings ==="
echo ""
oc exec $POD -n $NAMESPACE -- sh -c "
    for dev in mlx5_6 mlx5_7 mlx5_10 mlx5_11; do
        if [ -d /sys/class/infiniband/\$dev ]; then
            echo \"Device: \$dev\"
            echo \"  RoCE mode: \$(cat /sys/class/infiniband/\$dev/ports/1/gid_attrs/types/* 2>/dev/null | head -1)\"
            # Check for congestion control
            if [ -d /sys/class/infiniband/\$dev/ports/1/hw_counters ]; then
                echo \"  Hardware counters available\"
            fi
        fi
    done
" 2>/dev/null

echo ""
echo "=== 7. mlxlink Status (Link Quality) ==="
echo ""
# Try to get link quality info if mlxlink is available
oc exec $POD -n $NAMESPACE -- which mlxlink &>/dev/null && {
    echo "Checking link quality for active interfaces..."
    for dev in mlx5_6 mlx5_7 mlx5_10 mlx5_11; do
        echo "Device: $dev"
        oc exec $POD -n $NAMESPACE -- mlxlink -d $dev --json 2>/dev/null | grep -E "state|speed|width" | head -5 || echo "  mlxlink query failed"
        echo ""
    done
} || echo "mlxlink not available in container"

echo ""
echo "=========================================="
echo "Check complete!"
echo "=========================================="
