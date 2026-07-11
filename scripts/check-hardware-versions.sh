#!/bin/bash
NODE=$1
echo "========================================="
echo "Hardware/Firmware Check: $NODE"
echo "========================================="

# 1. System Information
echo -e "\n=== System DMI Information ==="
oc debug node/$NODE -- chroot /host dmidecode -t system 2>/dev/null | grep -E "Manufacturer|Product Name|Version|Serial|UUID" | head -10

# 2. BIOS Information
echo -e "\n=== BIOS Information ==="
oc debug node/$NODE -- chroot /host dmidecode -t bios 2>/dev/null | grep -E "Vendor|Version|Release Date|BIOS Revision|Firmware Revision"

# 3. Baseboard Information
echo -e "\n=== Baseboard Information ==="
oc debug node/$NODE -- chroot /host dmidecode -t baseboard 2>/dev/null | grep -E "Manufacturer|Product Name|Version|Serial"

# 4. NIC Information (detailed)
echo -e "\n=== NIC Part Numbers and Revisions ==="
oc debug node/$NODE -- chroot /host bash -c 'for pci in 0000:03:00.0 0000:23:00.0 0000:a3:00.0 0000:c3:00.0; do echo "=== $pci ==="; lspci -vv -s $pci 2>/dev/null | grep -E "Subsystem|Part number|board|Board" | head -5; done' 2>/dev/null

# 5. NIC Firmware Versions
echo -e "\n=== NIC Firmware Versions ==="
oc debug node/$NODE -- chroot /host bash -c 'for pci in 03:00.0 23:00.0 a3:00.0 c3:00.0; do echo "=== $pci ==="; ethtool -i $(ls /sys/bus/pci/devices/0000:$pci/net/ 2>/dev/null | head -1) 2>/dev/null | grep -E "firmware-version|version" || echo "No netdev"; done' 2>/dev/null

# 6. Server Firmware
echo -e "\n=== Server Firmware Versions ==="
oc debug node/$NODE -- chroot /host dmidecode -t 0 2>/dev/null | grep -A5 "BIOS Information"
