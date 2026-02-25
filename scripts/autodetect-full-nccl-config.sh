#!/usr/bin/env bash
set -euo pipefail

# Comprehensive NCCL and Environment Auto-Detection
#
# This script detects:
# - InfiniBand devices (NCCL_IB_HCA)
# - RDMA network interfaces (NCCL_SOCKET_IFNAME)
# - Number of GPUs (GPUS_PER_NODE)
# - NVLink topology (NCCL_P2P_LEVEL)
# - GPUDirect RDMA support (NCCL_NET_GDR_LEVEL)
# - RoCE GID index (NCCL_IB_GID_INDEX)
# - Optimal OMP threads
# - And more!
#
# Outputs: /shared/nccl-env.sh with all NCCL configuration

OUTPUT_FILE="${OUTPUT_FILE:-/shared/nccl-env.sh}"
VERBOSE="${VERBOSE:-0}"

log() {
    echo "[AUTODETECT] $*" >&2
}

debug() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Detect number of GPUs
detect_gpu_count() {
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

# Detect if NVLink is present
detect_nvlink() {
    if command -v nvidia-smi &>/dev/null; then
        # Check if any GPU has NVLink connections
        if nvidia-smi topo -m 2>/dev/null | grep -q "NV"; then
            echo "NVL"
        else
            echo "PIX"  # PCIe only
        fi
    else
        echo "PIX"
    fi
}

# Detect if GPUDirect RDMA is supported
detect_gpudirect() {
    # Check for nv_peer_mem module (GPUDirect RDMA)
    if lsmod 2>/dev/null | grep -q "nv_peer_mem"; then
        echo "5"  # Full GPUDirect
    elif [[ -d /sys/class/infiniband ]] && command -v nvidia-smi &>/dev/null; then
        # Have both IB and GPUs, assume GPUDirect works
        echo "5"
    else
        echo "0"  # No GPUDirect
    fi
}

# Detect RoCE GID index
detect_gid_index() {
    # Try to find the right GID index for RoCE v2
    local ib_dev

    if command -v ibdev2netdev &>/dev/null; then
        ib_dev=$(ibdev2netdev 2>/dev/null | awk '{print $1}' | head -1)
    elif command -v ibv_devinfo &>/dev/null; then
        ib_dev=$(ibv_devinfo -l 2>/dev/null | head -1)
    fi

    if [[ -n "$ib_dev" ]]; then
        # Check GID table for RoCE v2 (type: RoCEv2)
        for port in 1 2; do
            for gid_idx in 0 1 2 3; do
                if ibv_devinfo -d "$ib_dev" 2>/dev/null | grep -A 20 "port ${port}:" | grep "GID\[${gid_idx}\]" | grep -q "RoCE v2"; then
                    echo "$gid_idx"
                    return 0
                fi
            done
        done
    fi

    # Default to 3 (common for RoCE v2)
    echo "3"
}

# Detect optimal OMP threads
detect_omp_threads() {
    local cpu_count
    local gpu_count

    # Get CPU count
    if command -v nproc &>/dev/null; then
        cpu_count=$(nproc)
    else
        cpu_count=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "32")
    fi

    # Get GPU count
    gpu_count=$(detect_gpu_count)

    if [[ "$gpu_count" -gt 0 ]]; then
        # Allocate CPUs per GPU, typically 4-8 threads per GPU
        local threads_per_gpu=$((cpu_count / gpu_count))

        # Clamp to reasonable range (4-16 threads per GPU)
        if [[ "$threads_per_gpu" -lt 4 ]]; then
            echo "4"
        elif [[ "$threads_per_gpu" -gt 16 ]]; then
            echo "16"
        else
            echo "$threads_per_gpu"
        fi
    else
        # No GPUs, use conservative value
        echo "8"
    fi
}

# Detect InfiniBand devices
detect_ib_devices() {
    if command -v ibv_devinfo &>/dev/null; then
        ibv_devinfo -l 2>/dev/null | grep -v "^$" | tr '\n' ',' | sed 's/,$//' || echo ""
    else
        echo ""
    fi
}

# Detect RDMA network interfaces
detect_rdma_interfaces() {
    local ifaces

    # Method 1: Find netX interfaces (common RDMA naming)
    ifaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^net[0-9]+$' | tr '\n' ',' | sed 's/,$//')

    if [[ -n "$ifaces" ]]; then
        echo "$ifaces"
        return 0
    fi

    # Method 2: Find ibX interfaces
    ifaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^ib[0-9]+$' | tr '\n' ',' | sed 's/,$//')

    if [[ -n "$ifaces" ]]; then
        echo "$ifaces"
        return 0
    fi

    # Method 3: Use ibdev2netdev
    if command -v ibdev2netdev &>/dev/null; then
        ifaces=$(ibdev2netdev 2>/dev/null | awk '{print $5}' | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$ifaces" ]]; then
            echo "$ifaces"
            return 0
        fi
    fi

    # Fallback
    echo "eth0"
}

# Detect if we're in a multi-node setup
detect_multi_node() {
    # Check if WORLD_SIZE or NNODES is set
    if [[ -n "${WORLD_SIZE:-}" ]]; then
        local gpus_per_node=$(detect_gpu_count)
        if [[ "$gpus_per_node" -gt 0 ]]; then
            local num_nodes=$((WORLD_SIZE / gpus_per_node))
            if [[ "$num_nodes" -gt 1 ]]; then
                echo "true"
                return 0
            fi
        fi
    fi

    echo "false"
}

# Detect network transport (RDMA vs TCP)
detect_transport() {
    if [[ -d /sys/class/infiniband ]] && [[ -n "$(detect_ib_devices)" ]]; then
        echo "rdma"
    else
        echo "tcp"
    fi
}

# Main detection
main() {
    log "Starting comprehensive NCCL auto-detection..."

    # Detect hardware capabilities
    GPU_COUNT=$(detect_gpu_count)
    IB_DEVICES=$(detect_ib_devices)
    RDMA_IFACES=$(detect_rdma_interfaces)
    NVLINK_LEVEL=$(detect_nvlink)
    GPUDIRECT_LEVEL=$(detect_gpudirect)
    GID_INDEX=$(detect_gid_index)
    OMP_THREADS=$(detect_omp_threads)
    TRANSPORT=$(detect_transport)

    log "Detection results:"
    log "  GPUs: $GPU_COUNT"
    log "  IB devices: ${IB_DEVICES:-none}"
    log "  RDMA interfaces: $RDMA_IFACES"
    log "  NVLink: $NVLINK_LEVEL"
    log "  GPUDirect: level $GPUDIRECT_LEVEL"
    log "  GID index: $GID_INDEX"
    log "  OMP threads: $OMP_THREADS"
    log "  Transport: $TRANSPORT"

    # Generate NCCL configuration
    cat > "$OUTPUT_FILE" <<EOF
# Auto-detected NCCL Configuration
# Generated by autodetect-full-nccl-config.sh
# $(date)

# ============================================================================
# Hardware Detection
# ============================================================================
export DETECTED_GPU_COUNT="$GPU_COUNT"
export DETECTED_TRANSPORT="$TRANSPORT"

# ============================================================================
# NCCL Network Configuration
# ============================================================================
EOF

    if [[ "$TRANSPORT" == "rdma" ]]; then
        cat >> "$OUTPUT_FILE" <<EOF
# RDMA/InfiniBand configuration
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA="${IB_DEVICES}"
export NCCL_SOCKET_IFNAME="${RDMA_IFACES}"
export NCCL_IB_GID_INDEX="${GID_INDEX}"
export NCCL_NET_GDR_LEVEL="${GPUDIRECT_LEVEL}"
export NCCL_P2P_LEVEL="${NVLINK_LEVEL}"

# RDMA Performance Tuning
export NCCL_IB_TIMEOUT=22
export NCCL_IB_RETRY_CNT=7
EOF
    else
        cat >> "$OUTPUT_FILE" <<EOF
# TCP/Ethernet configuration (no RDMA)
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME="${RDMA_IFACES}"
export NCCL_P2P_LEVEL="${NVLINK_LEVEL}"
EOF
    fi

    cat >> "$OUTPUT_FILE" <<EOF

# ============================================================================
# Performance Tuning
# ============================================================================
export OMP_NUM_THREADS="${OMP_THREADS}"

# ============================================================================
# Multi-GPU Configuration (auto-detected)
# ============================================================================
# Number of GPUs per node (detected)
export GPUS_PER_NODE="${GPU_COUNT}"

# For multi-node training, set WORLD_SIZE externally or calculate:
# WORLD_SIZE = number_of_nodes × GPUS_PER_NODE
# Example: 2 nodes × 4 GPUs = 8
EOF

    if [[ -n "${WORLD_SIZE:-}" ]]; then
        cat >> "$OUTPUT_FILE" <<EOF
export WORLD_SIZE="${WORLD_SIZE}"  # From environment
EOF
    fi

    cat >> "$OUTPUT_FILE" <<EOF

# ============================================================================
# Debugging
# ============================================================================
# Uncomment to enable NCCL debugging:
# export NCCL_DEBUG=INFO
# export NCCL_DEBUG_SUBSYS=INIT,NET

# ============================================================================
# End of auto-detected configuration
# ============================================================================
EOF

    log "Configuration written to $OUTPUT_FILE"

    # Show summary
    if [[ "$VERBOSE" == "1" ]]; then
        log "Configuration summary:"
        cat "$OUTPUT_FILE" >&2
    fi

    log "Auto-detection complete!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
