#!/usr/bin/env bash
set -euo pipefail

# --- Logging / debugging ---
export LOGLEVEL="${LOGLEVEL:-INFO}"
export NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
export PYTHONFAULTHANDLER="${PYTHONFAULTHANDLER:-1}"
export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-0}"

# --- Networking (Kubernetes pods usually use eth0) ---
# Original SLURM script: NCCL_SOCKET_IFNAME="eth0,en,eth,em,bond"
# On OpenShift, eth0 is typically correct.
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-eth0}"

# --- Performance / tuning knobs copied from the SLURM template ---
export NCCL_BUFFSIZE="${NCCL_BUFFSIZE:-2097152}"
export FI_EFA_SET_CUDA_SYNC_MEMOPS="${FI_EFA_SET_CUDA_SYNC_MEMOPS:-0}"

# These AWS EFA-specific settings usually do NOT apply on OpenShift unless you truly have EFA.
# Keep them unset by default.
# export FI_PROVIDER="efa"
# export LD_LIBRARY_PATH=/opt/amazon/efa/lib:$LD_LIBRARY_PATH

# If you need to tweak these for your cluster, uncomment:
# export NCCL_P2P_DISABLE=1
# export NCCL_IB_DISABLE=1

# --- Optional: extend LD_LIBRARY_PATH like the SLURM script ---
export LD_LIBRARY_PATH="/usr/local/lib/:${LD_LIBRARY_PATH:-}"

# --- TorchTitan config ---
CONFIG_FILE="${CONFIG_FILE:-./torchtitan/models/llama3/train_configs/llama3_8b.toml}"

# --- Distributed parameters (set by your OpenShift YAML) ---
# NNODES: total number of pods/nodes in the job (2)
# NPROC_PER_NODE: processes per node (1 for 1 GPU)
NNODES="${NNODES:-2}"
NPROC_PER_NODE="${NPROC_PER_NODE:-1}"

# Kubernetes provides HOSTNAME like "torchtitan-0"
POD_NAME="${HOSTNAME}"
NODE_RANK="${POD_NAME##*-}"   # "0" or "1" for torchtitan-0/1

# Rendezvous: rank0 stable DNS via headless service
MASTER_ADDR="${MASTER_ADDR:-torchtitan-0.torchtitan}"
MASTER_PORT="${MASTER_PORT:-29500}"
RDZV_ENDPOINT="${MASTER_ADDR}:${MASTER_PORT}"

echo "[INFO] pod=${POD_NAME} node_rank=${NODE_RANK} nnodes=${NNODES} nproc_per_node=${NPROC_PER_NODE}"
echo "[INFO] rdzv_endpoint=${RDZV_ENDPOINT}"
echo "[INFO] CONFIG_FILE=${CONFIG_FILE}"

# Move to TorchTitan repo (adjust if your image layout differs)
if [[ -d /workspace/torchtitan ]]; then
  cd /workspace/torchtitan
elif [[ -d torchtitan ]]; then
  cd torchtitan
else
  echo "[ERROR] Cannot find torchtitan directory. Set WORKDIR or fix image layout."
  exit 1
fi

# --- Run ---
exec torchrun \
  --nnodes="${NNODES}" \
  --nproc_per_node="${NPROC_PER_NODE}" \
  --node_rank="${NODE_RANK}" \
  --rdzv_backend=c10d \
  --rdzv_endpoint="${RDZV_ENDPOINT}" \
  -m torchtitan.train --job.config_file "${CONFIG_FILE}" "$@"

