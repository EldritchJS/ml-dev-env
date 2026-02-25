#!/usr/bin/env bash
#
# Launch wrapper for explicit GPU-to-NIC affinity
#
# This wrapper sets NCCL_IB_HCA per-rank to only include HCAs
# that are local to each GPU's NUMA node.
#
# Usage:
#   torchrun --nproc_per_node=4 launch-with-explicit-affinity.sh train.py [args]
#
# This is more explicit than auto-detection and guarantees local HCA usage.

set -euo pipefail

# Get local rank from torchrun
LOCAL_RANK="${LOCAL_RANK:-${OMPI_COMM_WORLD_LOCAL_RANK:-0}}"

log() {
    echo "[AFFINITY-LAUNCHER] [Rank $LOCAL_RANK] $*" >&2
}

log "Starting with explicit GPU-to-NIC affinity..."

# Determine which GPU this rank will use
# In torchrun, LOCAL_RANK maps directly to GPU ID
GPU_ID=$LOCAL_RANK

log "Assigned to GPU $GPU_ID"

# Detect NUMA node for this GPU
if command -v nvidia-smi &>/dev/null; then
    GPU_NUMA=$(nvidia-smi -i "$GPU_ID" --query-gpu=numa_node --format=csv,noheader 2>/dev/null || echo "-1")
else
    log "WARNING: nvidia-smi not found, using default affinity"
    GPU_NUMA="-1"
fi

log "GPU $GPU_ID is on NUMA node $GPU_NUMA"

# Set NCCL_IB_HCA based on GPU's NUMA node
# This forces NCCL to use only local HCAs
case $GPU_NUMA in
  0)
    # NUMA node 0 - use HCAs local to this node
    export NCCL_IB_HCA="mlx5_6,mlx5_7"
    export NCCL_SOCKET_IFNAME="net1,net2"
    log "Using NUMA 0 HCAs: mlx5_6, mlx5_7"
    ;;

  1)
    # NUMA node 1 - use HCAs local to this node
    export NCCL_IB_HCA="mlx5_10,mlx5_11"
    export NCCL_SOCKET_IFNAME="net3,net4"
    log "Using NUMA 1 HCAs: mlx5_10, mlx5_11"
    ;;

  -1)
    # NUMA detection failed - use all HCAs (fallback)
    export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
    log "WARNING: NUMA unknown, using all HCAs"
    ;;

  *)
    # Other NUMA node - use all HCAs (generic fallback)
    export NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    export NCCL_SOCKET_IFNAME="net1,net2,net3,net4"
    log "NUMA node $GPU_NUMA, using all HCAs"
    ;;
esac

# Also set other NCCL optimizations
export NCCL_NET_GDR_LEVEL=5      # GPUDirect RDMA
export NCCL_IB_DISABLE=0          # Enable InfiniBand
export NCCL_IB_GID_INDEX=3        # RoCE v2
export NCCL_P2P_LEVEL=NVL         # NVLink for intra-node

# Optional: Bind process to same NUMA node as GPU for maximum performance
if command -v numactl &>/dev/null && [[ "$GPU_NUMA" != "-1" ]]; then
    log "Binding process to NUMA node $GPU_NUMA"
    # Note: This requires numactl to be installed in the container
    exec numactl --cpunodebind="$GPU_NUMA" --membind="$GPU_NUMA" python "$@"
else
    log "Starting without NUMA binding"
    exec python "$@"
fi
