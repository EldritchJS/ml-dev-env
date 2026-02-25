#!/usr/bin/env bash
set -euo pipefail

# GPU-to-NIC Affinity Detection for Optimal RDMA Performance
#
# This script detects the physical topology of GPUs and NICs to optimize
# NCCL configuration for minimal PCIe hops and best RDMA performance.
#
# Key concepts:
# - GPUs and NICs are connected via PCIe to specific CPU sockets/NUMA nodes
# - Using "local" NICs (same NUMA node as GPU) minimizes latency
# - NCCL can use this info to optimize communication patterns
#
# Outputs:
# - /shared/nccl-env.sh: NCCL environment variables
# - /shared/gpu-nic-affinity.json: Detailed affinity mapping (optional)
# - /shared/gpu-nic-affinity.txt: Human-readable affinity info

OUTPUT_DIR="${OUTPUT_DIR:-/shared}"
VERBOSE="${VERBOSE:-0}"

log() {
    echo "[GPU-NIC-AFFINITY] $*" >&2
}

debug() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Detect NUMA node for a GPU
get_gpu_numa_node() {
    local gpu_id=$1

    # Try nvidia-smi first (most reliable)
    if command -v nvidia-smi &>/dev/null; then
        local numa_node
        numa_node=$(nvidia-smi -i "$gpu_id" --query-gpu=numa_node --format=csv,noheader 2>/dev/null || echo "")
        if [[ -n "$numa_node" && "$numa_node" != "N/A" ]]; then
            echo "$numa_node"
            return 0
        fi
    fi

    # Fallback: parse from /sys
    local gpu_pci
    gpu_pci=$(nvidia-smi -i "$gpu_id" --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/^0000://')
    if [[ -n "$gpu_pci" ]]; then
        local numa_file="/sys/bus/pci/devices/0000:${gpu_pci}/numa_node"
        if [[ -f "$numa_file" ]]; then
            cat "$numa_file"
            return 0
        fi
    fi

    # Unknown
    echo "-1"
}

# Detect NUMA node for a network interface
get_nic_numa_node() {
    local interface=$1

    # Check sysfs
    local numa_file="/sys/class/net/${interface}/device/numa_node"
    if [[ -f "$numa_file" ]]; then
        cat "$numa_file"
    else
        echo "-1"
    fi
}

# Map InfiniBand device to network interface
ib_device_to_netdev() {
    local ib_dev=$1

    # Use ibdev2netdev if available
    if command -v ibdev2netdev &>/dev/null; then
        ibdev2netdev | grep "^${ib_dev}" | awk '{print $5}' | head -1
    else
        # Fallback: check sysfs
        for port in /sys/class/infiniband/"${ib_dev}"/device/net/*; do
            if [[ -d "$port" ]]; then
                basename "$port"
                return 0
            fi
        done
    fi
}

# Get InfiniBand device for a network interface
netdev_to_ib_device() {
    local netdev=$1

    if command -v ibdev2netdev &>/dev/null; then
        ibdev2netdev | grep "port.*===> ${netdev}" | awk '{print $1}' | head -1
    else
        # Check sysfs - find IB device that has this netdev
        for ib_dev_path in /sys/class/infiniband/*; do
            if [[ -d "$ib_dev_path" ]]; then
                local ib_dev
                ib_dev=$(basename "$ib_dev_path")
                for net_path in "${ib_dev_path}"/device/net/*; do
                    if [[ -d "$net_path" ]] && [[ "$(basename "$net_path")" == "$netdev" ]]; then
                        echo "$ib_dev"
                        return 0
                    fi
                done
            fi
        done
    fi
}

# Parse nvidia-smi topo -m output to get GPU-to-NIC affinity hints
parse_nvidia_topo() {
    if ! command -v nvidia-smi &>/dev/null; then
        return 1
    fi

    # nvidia-smi topo -m shows affinity between GPUs and devices
    # Look for lines with "mlx" or "IB" to identify InfiniBand devices
    nvidia-smi topo -m 2>/dev/null || true
}

# Build GPU-to-NIC affinity map
build_affinity_map() {
    local -A gpu_numa_map
    local -A nic_numa_map
    local -A nic_to_ib_map

    log "Detecting GPU-to-NIC affinity..."

    # Get GPU count
    local gpu_count
    if command -v nvidia-smi &>/dev/null; then
        gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    else
        gpu_count=0
    fi

    debug "Detected $gpu_count GPUs"

    # Map GPUs to NUMA nodes
    for ((i=0; i<gpu_count; i++)); do
        local numa_node
        numa_node=$(get_gpu_numa_node "$i")
        gpu_numa_map[$i]=$numa_node
        debug "GPU $i -> NUMA node $numa_node"
    done

    # Detect RDMA interfaces
    local rdma_ifaces=()

    # Method 1: Find netdevs with InfiniBand devices
    if command -v ibdev2netdev &>/dev/null; then
        while IFS= read -r line; do
            local netdev
            netdev=$(echo "$line" | awk '{print $5}')
            if [[ -n "$netdev" && "$netdev" != "---" ]]; then
                rdma_ifaces+=("$netdev")
            fi
        done < <(ibdev2netdev 2>/dev/null || true)
    fi

    # Method 2: Look for net[0-9]+ interfaces (common RDMA naming)
    if [[ ${#rdma_ifaces[@]} -eq 0 ]]; then
        while IFS= read -r iface; do
            rdma_ifaces+=("$iface")
        done < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^net[0-9]+$' || true)
    fi

    # Method 3: Check for ib[0-9]+ interfaces
    if [[ ${#rdma_ifaces[@]} -eq 0 ]]; then
        while IFS= read -r iface; do
            rdma_ifaces+=("$iface")
        done < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^ib[0-9]+$' || true)
    fi

    debug "Detected ${#rdma_ifaces[@]} RDMA interfaces: ${rdma_ifaces[*]}"

    # Map NICs to NUMA nodes and IB devices
    for nic in "${rdma_ifaces[@]}"; do
        local numa_node
        numa_node=$(get_nic_numa_node "$nic")
        nic_numa_map[$nic]=$numa_node

        local ib_dev
        ib_dev=$(netdev_to_ib_device "$nic")
        if [[ -n "$ib_dev" ]]; then
            nic_to_ib_map[$nic]=$ib_dev
            debug "NIC $nic -> NUMA node $numa_node, IB device $ib_dev"
        else
            debug "NIC $nic -> NUMA node $numa_node, IB device unknown"
        fi
    done

    # Export for use by caller
    echo "GPU_COUNT=$gpu_count"
    for i in "${!gpu_numa_map[@]}"; do
        echo "GPU_NUMA_$i=${gpu_numa_map[$i]}"
    done
    for nic in "${!nic_numa_map[@]}"; do
        echo "NIC_NUMA_$nic=${nic_numa_map[$nic]}"
    done
    for nic in "${!nic_to_ib_map[@]}"; do
        echo "NIC_IB_$nic=${nic_to_ib_map[$nic]}"
    done
    echo "RDMA_IFACES=${rdma_ifaces[*]}"
}

# Generate NCCL configuration based on affinity
generate_nccl_config() {
    local affinity_data=$1

    # Source the affinity data
    eval "$affinity_data"

    log "Generating NCCL configuration..."

    # Collect all IB devices and RDMA interfaces
    local -a ib_devices
    local -a rdma_interfaces

    for nic in $RDMA_IFACES; do
        local ib_var="NIC_IB_$nic"
        local ib_dev="${!ib_var:-}"
        if [[ -n "$ib_dev" ]]; then
            ib_devices+=("$ib_dev")
        fi
        rdma_interfaces+=("$nic")
    done

    # Remove duplicates and join
    local ib_hca
    ib_hca=$(printf '%s\n' "${ib_devices[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')

    local socket_ifname
    socket_ifname=$(printf '%s\n' "${rdma_interfaces[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')

    # Write NCCL environment variables
    cat > "${OUTPUT_DIR}/nccl-env.sh" <<EOF
# NCCL configuration with GPU-to-NIC affinity awareness
# Generated by detect-gpu-nic-affinity.sh

# InfiniBand HCAs detected in topology
export NCCL_IB_HCA="${ib_hca}"

# RDMA network interfaces (for socket fallback)
export NCCL_SOCKET_IFNAME="${socket_ifname}"

# GPUDirect RDMA optimizations
export NCCL_NET_GDR_LEVEL=5

# Enable IB/RDMA
export NCCL_IB_DISABLE=0

# GID index for RoCE (typically 3 for RoCE v2)
export NCCL_IB_GID_INDEX=3

# Prefer NVLink for intra-node, RDMA for inter-node
export NCCL_P2P_LEVEL=NVL

# Enable topology detection
export NCCL_TOPO_FILE=/shared/nccl-topology.xml
EOF

    log "NCCL configuration written to ${OUTPUT_DIR}/nccl-env.sh"
    log "  NCCL_IB_HCA=$ib_hca"
    log "  NCCL_SOCKET_IFNAME=$socket_ifname"
}

# Generate human-readable affinity report
generate_affinity_report() {
    local affinity_data=$1

    eval "$affinity_data"

    cat > "${OUTPUT_DIR}/gpu-nic-affinity.txt" <<EOF
GPU-to-NIC Affinity Report
==========================

System Configuration:
- GPUs detected: ${GPU_COUNT:-0}
- RDMA interfaces: ${RDMA_IFACES:-none}

GPU Topology:
EOF

    for ((i=0; i<${GPU_COUNT:-0}; i++)); do
        local numa_var="GPU_NUMA_$i"
        local numa_node="${!numa_var:-unknown}"
        echo "  GPU $i: NUMA node $numa_node" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    done

    echo "" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "NIC Topology:" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"

    for nic in $RDMA_IFACES; do
        local numa_var="NIC_NUMA_$nic"
        local ib_var="NIC_IB_$nic"
        local numa_node="${!numa_var:-unknown}"
        local ib_dev="${!ib_var:-unknown}"
        echo "  $nic: NUMA node $numa_node, IB device $ib_dev" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    done

    echo "" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "Affinity Recommendations:" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"

    # For each GPU, suggest local NICs
    for ((i=0; i<${GPU_COUNT:-0}; i++)); do
        local gpu_numa_var="GPU_NUMA_$i"
        local gpu_numa="${!gpu_numa_var:-}"

        if [[ -z "$gpu_numa" || "$gpu_numa" == "-1" ]]; then
            echo "  GPU $i: NUMA node unknown, using all NICs" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
            continue
        fi

        local local_nics=()
        for nic in $RDMA_IFACES; do
            local nic_numa_var="NIC_NUMA_$nic"
            local nic_numa="${!nic_numa_var:-}"
            if [[ "$nic_numa" == "$gpu_numa" ]]; then
                local_nics+=("$nic")
            fi
        done

        if [[ ${#local_nics[@]} -gt 0 ]]; then
            echo "  GPU $i (NUMA $gpu_numa): Prefer NICs ${local_nics[*]}" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
        else
            echo "  GPU $i (NUMA $gpu_numa): No local NICs found, using all" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
        fi
    done

    echo "" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "For optimal performance:" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "1. Ensure processes are bound to the same NUMA node as their GPU" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "2. NCCL will automatically use the configuration from nccl-env.sh" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"
    echo "3. For manual tuning, see per-GPU NIC preferences above" >> "${OUTPUT_DIR}/gpu-nic-affinity.txt"

    log "Affinity report written to ${OUTPUT_DIR}/gpu-nic-affinity.txt"
}

# Generate NCCL topology XML (advanced)
generate_nccl_topology() {
    local affinity_data=$1

    eval "$affinity_data"

    # This is a placeholder for advanced NCCL topology file generation
    # NCCL can use an XML file to explicitly define the system topology
    # For now, we rely on NCCL's auto-detection with environment hints

    cat > "${OUTPUT_DIR}/nccl-topology.xml" <<EOF
<?xml version="1.0"?>
<!-- NCCL Topology File -->
<!-- Auto-generated by detect-gpu-nic-affinity.sh -->
<!-- NCCL will auto-detect if this file is not perfect -->
<system version="1">
  <cpu numaid="0" affinity="0xffffffff" arch="x86_64" vendor="GenuineIntel">
    <!-- Topology details would go here -->
    <!-- For now, relying on NCCL auto-detection -->
  </cpu>
</system>
EOF

    debug "Topology XML placeholder written to ${OUTPUT_DIR}/nccl-topology.xml"
}

# Main execution
main() {
    log "Starting GPU-to-NIC affinity detection..."

    mkdir -p "$OUTPUT_DIR"

    # Build affinity map
    affinity_data=$(build_affinity_map)

    # Generate outputs
    generate_nccl_config "$affinity_data"
    generate_affinity_report "$affinity_data"
    generate_nccl_topology "$affinity_data"

    log "Affinity detection complete!"
    log ""
    log "To use this configuration in your training:"
    log "  source ${OUTPUT_DIR}/nccl-env.sh"
    log ""
    log "For detailed affinity information:"
    log "  cat ${OUTPUT_DIR}/gpu-nic-affinity.txt"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
