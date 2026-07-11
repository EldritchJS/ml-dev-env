#!/bin/bash
# Run this script on your cluster nodes to identify InfiniBand devices for NCCL

echo "=== All devices in /sys/class/infiniband/ ==="
if [ -d /sys/class/infiniband/ ]; then
    ls -1 /sys/class/infiniband/
    echo "Total count: $(ls -1 /sys/class/infiniband/ | wc -l)"
else
    echo "Directory not found"
fi
echo ""

echo "=== Devices detected by ibv_devinfo ==="
if command -v ibv_devinfo &> /dev/null; then
    ibv_devinfo -l
    echo "Total count: $(ibv_devinfo -l | wc -l)"
else
    echo "ibv_devinfo command not found"
    exit 1
fi
echo ""

echo "=== NCCL_IB_HCA value ==="
IB_DEVICES=$(ibv_devinfo -l | tr '\n' ',' | sed 's/,$//')
echo "export NCCL_IB_HCA=$IB_DEVICES"
echo ""

echo "=== Device details from ibv_devinfo ==="
for dev in $(ibv_devinfo -l); do
    echo "--- Device: $dev ---"
    ibv_devinfo -d $dev | grep -E "hca_id|node_guid|sys_image_guid|port:|state:|active"
    echo ""
done

echo "=== Comparison ==="
echo "Devices in sysfs but NOT in ibv_devinfo:"
comm -23 <(ls -1 /sys/class/infiniband/ 2>/dev/null | sort) <(ibv_devinfo -l 2>/dev/null | sort)
