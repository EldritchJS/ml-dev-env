# deployments/h-kim/scripts/lm-train.sh Usage Guide

## Overview

`deployments/h-kim/scripts/lm-train.sh` is configured to run TorchTitan distributed training on h-kim pods with full RDMA/InfiniBand support.

## Recent Updates (2026-02-25)

### ✅ RDMA Integration
- Removed hardcoded `NCCL_IB_HCA` override that conflicted with auto-detection
- Auto-detected InfiniBand devices from wrapper script are now preserved
- Added `ulimit -l unlimited` for RDMA memory registration
- Using `prlimit` to ensure child processes inherit unlimited memlock

### ✅ Network Configuration
- `NCCL_SOCKET_IFNAME` set to `eth0` for out-of-band communication
- RDMA communication uses `net1-net4` automatically via `NCCL_IB_HCA`
- Removed hardcoded namespace from `MASTER_ADDR`

### ✅ RDMA Settings
- `NCCL_IB_DISABLE=0` (RDMA enabled)
- `NCCL_IB_HCA` auto-detected (e.g., `mlx5_6,mlx5_7,mlx5_10,mlx5_11`)
- `NCCL_IB_GID_INDEX=3` (RoCE v2)
- `NCCL_NET_GDR_LEVEL=5` (GPUDirect RDMA enabled)

## Environment Variables

### Required (Auto-configured in h-kim pods)
```bash
HOSTNAME              # Pod name (e.g., h-kim-0)
MASTER_ADDR           # Set by StatefulSet to h-kim-0.h-kim-headless...
MASTER_PORT           # Default: 29500
NCCL_IB_HCA           # Auto-detected by wrapper script
```

### Optional (Can override)
```bash
NNODES                # Default: 2 (number of pods)
NPROC_PER_NODE        # Default: 4 (GPUs per pod)
CONFIG_FILE           # TorchTitan config file path
TORCHTITAN_REPO       # Default: /workspace/uvm_manual/torchtitan
NCCL_DEBUG            # Default: INFO
```

## Usage

### Basic Usage (Default Configuration)
```bash
# On both h-kim pods, the script will run automatically
# Or execute manually:
./deployments/h-kim/scripts/lm-train.sh
```

### With Custom Configuration
```bash
# Use a different TorchTitan config
CONFIG_FILE=/path/to/custom/config.toml ./deployments/h-kim/scripts/lm-train.sh

# Run with different node count
NNODES=4 NPROC_PER_NODE=4 ./deployments/h-kim/scripts/lm-train.sh

# Debug RDMA issues
NCCL_DEBUG=TRACE ./deployments/h-kim/scripts/lm-train.sh
```

### Running from h-kim Deployment

The script is designed to run inside h-kim pods:

```bash
# Copy to pod (if not already there)
oc cp deployments/h-kim/scripts/lm-train.sh <namespace>/h-kim-0:/workspace/

# Execute on both pods simultaneously
oc exec h-kim-0 -n <namespace> -- /workspace/deployments/h-kim/scripts/lm-train.sh &
oc exec h-kim-1 -n <namespace> -- /workspace/deployments/h-kim/scripts/lm-train.sh &
```

## RDMA Configuration Verification

The script will print RDMA configuration on startup:

```
[INFO] RDMA Configuration:
[INFO]   NCCL_IB_DISABLE=0
[INFO]   NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
[INFO]   NCCL_IB_GID_INDEX=3
[INFO]   NCCL_NET_GDR_LEVEL=5
[INFO]   NCCL_SOCKET_IFNAME=eth0
[INFO]   Memlock: unlimited
```

### Expected Values
- ✅ `NCCL_IB_DISABLE=0` - RDMA enabled
- ✅ `NCCL_IB_HCA=mlx5_X,mlx5_Y,...` - 4 auto-detected devices
- ✅ `Memlock: unlimited` - Required for RDMA

### Troubleshooting

**If `NCCL_IB_HCA` is not set:**
- Check pod logs for auto-detection: `oc logs h-kim-0 | grep "Auto-detected"`
- Verify wrapper script is running: `cat /proc/1/environ | tr '\0' '\n' | grep NCCL_IB_HCA`

**If memlock is limited:**
- Check: `oc exec h-kim-0 -- ulimit -l`
- Should show: `unlimited`
- If not, verify privileged pod security context

**If RDMA errors occur:**
- Check IOMMU: `oc debug node/<node> -- chroot /host cat /proc/cmdline | grep iommu=pt`
- Run diagnostic: `./debug-rdma.sh` (copy to pod first)

## Performance Expectations

With RDMA working correctly:
- **NCCL all_reduce:** ~80+ GiB/s (vs ~1 GiB/s with TCP)
- **No errors:** No `IBV_WC_LOC_PROT_ERR` or `IBV_WC_RETRY_EXC_ERR`
- **GPUDirect:** GDRDMA mode active

## File Structure Requirements

The script expects:
```
/workspace/
├── uvm_manual/torchtitan/       # TorchTitan repository
│   ├── torchtitan/train.py      # Training script
│   └── torchtitan/models/llama3/train_configs/
│       └── llama3_70b.toml      # Default config
└── .cache/                      # Cache directories (created automatically)
    ├── huggingface/
    └── torch/
```

## Integration with h-kim Deployment

The `deployments/h-kim/scripts/lm-train.sh` script is designed to work with the h-kim StatefulSet deployment:

1. **Auto-detection:** NCCL_IB_HCA is set by the wrapper script at pod startup
2. **Networking:** Uses headless service for rendezvous
3. **RDMA:** Inherits RDMA configuration from pod environment
4. **Memlock:** Ensured unlimited via `prlimit`

## Example Output

```
==========================================
TorchTitan Distributed Training - OpenShift
==========================================
[INFO] pod=h-kim-0
[INFO] node_rank=0
[INFO] nnodes=2
[INFO] nproc_per_node=4
[INFO] total_gpus=8
[INFO] rdzv_endpoint=h-kim-0.h-kim-headless:29500
[INFO] config_file=.../llama3_70b.toml
[INFO] torchtitan_repo=/workspace/uvm_manual/torchtitan

[INFO] RDMA Configuration:
[INFO]   NCCL_IB_DISABLE=0
[INFO]   NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
[INFO]   NCCL_IB_GID_INDEX=3
[INFO]   NCCL_NET_GDR_LEVEL=5
[INFO]   NCCL_SOCKET_IFNAME=eth0
[INFO]   Memlock: unlimited
==========================================

[INFO] Available GPUs:
  GPU 0: NVIDIA H100 80GB HBM3
  GPU 1: NVIDIA H100 80GB HBM3
  GPU 2: NVIDIA H100 80GB HBM3
  GPU 3: NVIDIA H100 80GB HBM3

[INFO] Starting torchrun with RDMA...
```

## Related Documentation

- **RDMA Setup:** `docs/rdma/RDMA-SETUP-COMPLETE.md`
- **Auto-detection:** `IB-AUTODETECT-FINAL-SUMMARY.md`
- **Troubleshooting:** `docs/rdma/IOMMU-PASSTHROUGH-FIX.md`
- **h-kim Deployment:** `scripts/deploy-h-kim.sh`

## Notes

- The script uses `exec` for the final `torchrun` command, replacing the shell process
- `prlimit --memlock=unlimited:unlimited` ensures child processes inherit unlimited memlock
- NCCL will automatically use the detected InfiniBand devices for inter-node communication
- GPUDirect RDMA will be used for GPU-to-GPU transfers over InfiniBand
