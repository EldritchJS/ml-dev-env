#!/bin/bash
# RDMA Debugging Script
# Run this on each pod to diagnose RDMA/InfiniBand issues

echo "========================================"
echo "RDMA/InfiniBand Diagnostic Report"
echo "========================================"
echo "Pod: $HOSTNAME"
echo "Date: $(date)"
echo ""

# 1. Check InfiniBand devices
echo "=== 1. InfiniBand Devices ==="
if command -v ibv_devinfo &> /dev/null; then
    echo "Available IB devices:"
    ibv_devinfo -l
    echo ""

    echo "Detailed device info:"
    for dev in $(ibv_devinfo -l 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'); do
        echo "--- Device: $dev ---"
        ibv_devinfo -d $dev | grep -E "hca_id|node_guid|state|phys_state|link_layer|active_speed|active_width|max_mr_size|Port:"
        echo ""
    done
else
    echo "ERROR: ibv_devinfo not found"
fi
echo ""

# 2. Check device states
echo "=== 2. Port States ==="
if command -v ibstat &> /dev/null; then
    ibstat
else
    echo "ibstat not available, checking via ibv_devinfo"
    for dev in $(ibv_devinfo -l 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'); do
        ibv_devinfo -d $dev | grep -A 20 "port:"
    done
fi
echo ""

# 3. Check RDMA devices in sysfs
echo "=== 3. RDMA Devices in Sysfs ==="
ls -la /sys/class/infiniband/ 2>/dev/null || echo "/sys/class/infiniband/ not accessible"
echo ""

# 4. Check GID tables
echo "=== 4. GID Tables ==="
for dev in /sys/class/infiniband/*; do
    if [ -d "$dev" ]; then
        devname=$(basename $dev)
        echo "Device: $devname"
        for port in $dev/ports/*; do
            if [ -d "$port" ]; then
                portnum=$(basename $port)
                echo "  Port $portnum:"
                if [ -f "$port/gids/0" ]; then
                    for i in {0..15}; do
                        if [ -f "$port/gids/$i" ]; then
                            gid=$(cat "$port/gids/$i" 2>/dev/null)
                            if [ "$gid" != "0000:0000:0000:0000:0000:0000:0000:0000" ]; then
                                echo "    GID[$i]: $gid"
                            fi
                        fi
                    done
                fi
            fi
        done
        echo ""
    fi
done
echo ""

# 5. Check RDMA_CM devices
echo "=== 5. RDMA CM Devices ==="
ls -la /dev/infiniband/ 2>/dev/null || echo "/dev/infiniband/ not accessible"
echo ""

# 6. Check memory limits (important for RDMA)
echo "=== 6. Memory Limits ==="
ulimit -a | grep -E "locked|mem"
echo ""

# 7. Check RDMA resources
echo "=== 7. RDMA Resources ==="
if [ -d /sys/class/infiniband ]; then
    for dev in /sys/class/infiniband/*; do
        devname=$(basename $dev)
        echo "Device: $devname"
        [ -f "$dev/node_type" ] && echo "  Node type: $(cat $dev/node_type)"
        [ -f "$dev/fw_ver" ] && echo "  FW version: $(cat $dev/fw_ver)"
        [ -f "$dev/node_guid" ] && echo "  Node GUID: $(cat $dev/node_guid)"
    done
fi
echo ""

# 8. Network interfaces
echo "=== 8. Network Interfaces ==="
ip a show | grep -E "(^[0-9]:|inet )"
echo ""

# 9. Check NCCL environment
echo "=== 9. NCCL Environment Variables ==="
env | grep ^NCCL_ | sort
echo ""

# 10. Test RDMA verbs
echo "=== 10. RDMA Verbs Test ==="
if command -v ibv_rc_pingpong &> /dev/null; then
    echo "ibv_rc_pingpong available (requires 2 nodes to test)"
else
    echo "ibv_rc_pingpong not available"
fi

if command -v ibv_devices &> /dev/null; then
    echo "Device list via ibv_devices:"
    ibv_devices
fi
echo ""

# 11. Check SR-IOV VFs
echo "=== 11. SR-IOV Virtual Functions ==="
for dev in $(ibv_devinfo -l 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'); do
    echo "Checking $dev for VF info..."
    if [ -L "/sys/class/infiniband/$dev/device" ]; then
        pci_path=$(readlink -f /sys/class/infiniband/$dev/device)
        echo "  PCI path: $pci_path"
        [ -f "$pci_path/physfn/sriov_numvfs" ] && echo "  SR-IOV VF (PF has $(cat $pci_path/physfn/sriov_numvfs) VFs)"
    fi
done
echo ""

# 12. Check for RoCE
echo "=== 12. RoCE Configuration ==="
for dev in /sys/class/infiniband/*/ports/*/gid_attrs/types/*; do
    if [ -f "$dev" ]; then
        echo "$dev: $(cat $dev)"
    fi
done
echo ""

# 13. Check permissions
echo "=== 13. Device Permissions ==="
ls -la /dev/infiniband/* 2>/dev/null | head -20
echo ""

# 14. Security context
echo "=== 14. Container Capabilities ==="
if command -v capsh &> /dev/null; then
    capsh --print | grep Current
else
    echo "capsh not available"
fi
cat /proc/self/status | grep Cap
echo ""

echo "========================================"
echo "Diagnostic Report Complete"
echo "========================================"
