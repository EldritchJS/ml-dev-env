#!/usr/bin/env bash
set -euo pipefail

# Adapted from h-kim.sh for OpenShift h-kim StatefulSet
# This script runs TorchTitan distributed training on OpenShift

# --- CRITICAL: Set unlimited memlock for RDMA ---
ulimit -l unlimited 2>/dev/null || echo "[WARN] Could not set unlimited memlock"

# --- Logging / debugging ---
export LOGLEVEL="${LOGLEVEL:-INFO}"
export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
export PYTHONFAULTHANDLER="${PYTHONFAULTHANDLER:-1}"
export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-0}"

# --- Networking (OpenShift with RDMA/InfiniBand) ---
# Use eth0 for out-of-band communication (RDMA uses net1-4 automatically via NCCL_IB_HCA)
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-eth0}"

# --- NCCL InfiniBand settings ---
# NOTE: NCCL_IB_HCA is auto-detected by the wrapper script in the pod
# Do NOT override it here unless you have a specific reason
# The auto-detection sets it based on allocated SR-IOV devices
# If NCCL_IB_HCA is not set, inherit from environment (set by wrapper)
export NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
# NCCL_IB_HCA is already set by auto-detection wrapper - don't override
export NCCL_IB_GID_INDEX="${NCCL_IB_GID_INDEX:-3}"
export NCCL_NET_GDR_LEVEL="${NCCL_NET_GDR_LEVEL:-5}"

# --- Performance / tuning knobs ---
export NCCL_BUFFSIZE="${NCCL_BUFFSIZE:-2097152}"

# --- Optional: extend LD_LIBRARY_PATH ---
export LD_LIBRARY_PATH="/usr/local/lib/:${LD_LIBRARY_PATH:-}"

# --- Set cache directories (for HuggingFace datasets, models, etc.) ---
export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-/workspace/.cache/huggingface/datasets}"
export TORCH_HOME="${TORCH_HOME:-/workspace/.cache/torch}"
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TORCH_HOME"

# --- TorchTitan repository setup ---
TORCHTITAN_REPO="${TORCHTITAN_REPO:-/workspace/uvm_manual/torchtitan}"

# --- TorchTitan config ---
CONFIG_FILE="${CONFIG_FILE:-${TORCHTITAN_REPO}/torchtitan/models/llama3/train_configs/llama3_70b.toml}"

# --- Distributed parameters ---
# NNODES: total number of pods in the StatefulSet (default: 2)
# NPROC_PER_NODE: GPUs per pod (default: 4 for our h-kim pods)
NNODES="${NNODES:-2}"
NPROC_PER_NODE="${NPROC_PER_NODE:-4}"

# Kubernetes provides HOSTNAME like "h-kim-0"
POD_NAME="${HOSTNAME}"
NODE_RANK="${POD_NAME##*-}"   # Extract "0" or "1" from "h-kim-0"

# Rendezvous: rank0 stable DNS via h-kim-headless service
# MASTER_ADDR should be set by the StatefulSet environment or use the headless service
# The namespace is automatically resolved from the pod's namespace
MASTER_ADDR="${MASTER_ADDR:-h-kim-0.h-kim-headless}"
MASTER_PORT="${MASTER_PORT:-29500}"
RDZV_ENDPOINT="${MASTER_ADDR}:${MASTER_PORT}"

HOOK_DIR="/workspace/uvm_manual/torchtitan/hooks"

# Prepend only if it's not already in PYTHONPATH
case ":${PYTHONPATH-}:" in
  *":$HOOK_DIR:"*) ;;  # already there
  *) export PYTHONPATH="$HOOK_DIR${PYTHONPATH:+:$PYTHONPATH}" ;;
esac

echo "=========================================="
echo "TorchTitan Distributed Training - OpenShift"
echo "=========================================="
echo "[INFO] pod=${POD_NAME}"
echo "[INFO] node_rank=${NODE_RANK}"
echo "[INFO] nnodes=${NNODES}"
echo "[INFO] nproc_per_node=${NPROC_PER_NODE}"
echo "[INFO] total_gpus=$((NNODES * NPROC_PER_NODE))"
echo "[INFO] rdzv_endpoint=${RDZV_ENDPOINT}"
echo "[INFO] config_file=${CONFIG_FILE}"
echo "[INFO] torchtitan_repo=${TORCHTITAN_REPO}"
echo ""
echo "[INFO] RDMA Configuration:"
echo "[INFO]   NCCL_IB_DISABLE=${NCCL_IB_DISABLE}"
echo "[INFO]   NCCL_IB_HCA=${NCCL_IB_HCA:-<not set - auto-detected by wrapper>}"
echo "[INFO]   NCCL_IB_GID_INDEX=${NCCL_IB_GID_INDEX}"
echo "[INFO]   NCCL_NET_GDR_LEVEL=${NCCL_NET_GDR_LEVEL}"
echo "[INFO]   NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}"
echo "[INFO]   Memlock: $(ulimit -l)"
echo "=========================================="
echo ""

# Move to TorchTitan repo
cd "$TORCHTITAN_REPO"

# Use repository code instead of pip-installed package
export PYTHONPATH="${TORCHTITAN_REPO}:${PYTHONPATH:-}"
#export LD_PRELOAD=/workspace/uvm_manual/libuvm_shim.so

#export UVM_RECORD_ITER=3 
#export UVM_OVERRIDE_MALLOC=1 
#export UVM_VERBOSE=1


# Show GPU info
echo "[INFO] Available GPUs:"
python3 -c "import torch; [print(f'  GPU {i}: {torch.cuda.get_device_name(i)}') for i in range(torch.cuda.device_count())]"
echo ""

# --- Run TorchTitan training ---
echo "[INFO] Starting torchrun with RDMA..."
# Use prlimit to ensure child processes inherit unlimited memlock for RDMA
exec prlimit --memlock=unlimited:unlimited \
torchrun \
  --nnodes="${NNODES}" \
  --nproc_per_node="${NPROC_PER_NODE}" \
  --node_rank="${NODE_RANK}" \
  --rdzv_backend=c10d \
  --rdzv_endpoint="${RDZV_ENDPOINT}" \
  --rdzv_id="${JOB_ID:-1}" \
  --max_restarts=0 \
  torchtitan/train.py --job.config_file "${CONFIG_FILE}" "$@"
