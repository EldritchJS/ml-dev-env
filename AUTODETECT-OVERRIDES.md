# Auto-Detection with User Overrides

## Overview

The comprehensive auto-detection system allows users to override any auto-detected value when needed. This gives you the best of both worlds:
- **Smart defaults** from auto-detection
- **Full control** when you need it

## How Overrides Work

The auto-detection script uses bash parameter expansion:
```bash
export NCCL_IB_GID_INDEX="${NCCL_IB_GID_INDEX:-3}"
```

This means:
- If `NCCL_IB_GID_INDEX` is already set → **use the user's value**
- If `NCCL_IB_GID_INDEX` is not set → **use auto-detected value (3)**

## Method 1: Override in Pod Spec (Recommended)

Set environment variables directly in your pod manifest:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-pod
spec:
  initContainers:
  - name: autodetect
    image: your-image
    command: ["./scripts/autodetect-full-nccl-config.sh"]
    volumeMounts:
    - name: shared
      mountPath: /shared

  containers:
  - name: training
    image: your-image
    env:
    # Override auto-detected values
    - name: NCCL_IB_GID_INDEX
      value: "1"  # Force GID index 1 instead of auto-detected
    - name: OMP_NUM_THREADS
      value: "8"  # Use 8 threads instead of auto-detected

    # These will use auto-detected values (not overridden)
    # - NCCL_IB_HCA
    # - NCCL_SOCKET_IFNAME
    # - NCCL_NET_GDR_LEVEL
    # etc.

    command:
    - /bin/bash
    - -c
    - |
      source /shared/nccl-env.sh
      echo "NCCL_IB_GID_INDEX=$NCCL_IB_GID_INDEX"  # Will show "1" (overridden)
      echo "NCCL_IB_HCA=$NCCL_IB_HCA"  # Will show auto-detected value
      torchrun --nproc_per_node=$GPUS_PER_NODE train.py

    volumeMounts:
    - name: shared
      mountPath: /shared

  volumes:
  - name: shared
    emptyDir: {}
```

## Method 2: Override at Runtime

Set environment variables before sourcing the auto-detected config:

```bash
#!/bin/bash
# In your pod startup script

# Set overrides BEFORE sourcing auto-detected config
export NCCL_IB_GID_INDEX=1
export OMP_NUM_THREADS=8

# Source auto-detected config
# These values will use user overrides, rest will use auto-detected
source /shared/nccl-env.sh

echo "Using NCCL_IB_GID_INDEX=$NCCL_IB_GID_INDEX"  # Shows 1
echo "Using NCCL_IB_HCA=$NCCL_IB_HCA"  # Shows auto-detected

torchrun --nproc_per_node=$GPUS_PER_NODE train.py
```

## Method 3: Selective Override Script

Create a wrapper script for common override scenarios:

```bash
#!/bin/bash
# override-gid-index.sh
# Override just the GID index, keep everything else auto-detected

export NCCL_IB_GID_INDEX="${1:-3}"  # First arg or default to 3

source /shared/nccl-env.sh

echo "Overridden GID index to: $NCCL_IB_GID_INDEX"
echo "Auto-detected: $NCCL_IB_HCA"
echo "Auto-detected: $NCCL_SOCKET_IFNAME"

exec "$@"
```

Usage:
```bash
# Use GID index 1
./override-gid-index.sh 1 torchrun train.py

# Use GID index 2
./override-gid-index.sh 2 torchrun train.py
```

## Common Override Scenarios

### Scenario 1: Experiment with Different GID Indices

```yaml
env:
- name: NCCL_IB_GID_INDEX
  value: "1"  # Try GID 1 instead of auto-detected 3
```

**When to use**: Testing RDMA connectivity issues or trying different RoCE configurations.

### Scenario 2: Disable GPUDirect RDMA

```yaml
env:
- name: NCCL_NET_GDR_LEVEL
  value: "0"  # Disable GPUDirect, even if auto-detected as available
```

**When to use**: Troubleshooting GPUDirect issues or comparing performance.

### Scenario 3: Force Specific HCAs

```yaml
env:
- name: NCCL_IB_HCA
  value: "mlx5_6,mlx5_7"  # Use only NUMA-local HCAs
```

**When to use**: Testing affinity configurations or isolating specific HCAs.

### Scenario 4: Reduce Thread Count

```yaml
env:
- name: OMP_NUM_THREADS
  value: "4"  # Use fewer threads per GPU
```

**When to use**: Reducing CPU contention in shared environments.

### Scenario 5: Force TCP Instead of RDMA

```yaml
env:
- name: NCCL_IB_DISABLE
  value: "1"  # Disable InfiniBand, use TCP
```

**When to use**: Testing TCP fallback or troubleshooting RDMA issues.

### Scenario 6: Override P2P Level

```yaml
env:
- name: NCCL_P2P_LEVEL
  value: "PIX"  # Force PCIe instead of NVLink
```

**When to use**: Testing PCIe performance or debugging NVLink issues.

## Partial Overrides Example

Mix auto-detected and overridden values:

```yaml
containers:
- name: training
  env:
  # Override these
  - name: NCCL_IB_GID_INDEX
    value: "1"
  - name: NCCL_DEBUG
    value: "INFO"

  # Auto-detect these (not specified)
  # - NCCL_IB_HCA → auto-detected: mlx5_6,mlx5_7,mlx5_10,mlx5_11
  # - NCCL_SOCKET_IFNAME → auto-detected: net1,net2,net3,net4
  # - NCCL_NET_GDR_LEVEL → auto-detected: 5
  # - NCCL_P2P_LEVEL → auto-detected: NVL
  # - GPUS_PER_NODE → auto-detected: 4
  # - OMP_NUM_THREADS → auto-detected: 16

  command:
  - /bin/bash
  - -c
  - source /shared/nccl-env.sh && torchrun train.py
```

## Validation After Override

Always verify your overrides took effect:

```bash
# After sourcing auto-detected config
echo "==================================="
echo "Final NCCL Configuration:"
echo "==================================="
env | grep NCCL_ | sort
echo "==================================="
echo "GPUS_PER_NODE: $GPUS_PER_NODE"
echo "OMP_NUM_THREADS: $OMP_NUM_THREADS"
echo "==================================="
```

## Environment Variable Precedence

**Precedence order** (highest to lowest):

1. **User-set env vars** (in pod spec or before sourcing)
2. **Auto-detected values** (from init container)
3. **Script defaults** (fallbacks in autodetect script)

Example:
```bash
# In pod spec
env:
- name: NCCL_IB_GID_INDEX
  value: "1"  # Priority 1: User override

# Auto-detected (if not overridden)
# NCCL_IB_GID_INDEX=3  # Priority 2: Auto-detected

# Script fallback (if auto-detection fails)
# echo "3"  # Priority 3: Default
```

## Best Practices

### ✅ DO:
- Override when you have specific knowledge about your hardware
- Override for experimentation and debugging
- Override for performance tuning based on benchmarks
- Document why you're overriding (in comments or ConfigMaps)

### ❌ DON'T:
- Override just because you can (trust auto-detection unless you have a reason)
- Hardcode all values (defeats the purpose of auto-detection)
- Override without understanding what the variable does
- Override without validating the results

## Example: Debug RDMA Issues

```yaml
containers:
- name: training
  env:
  # Enable verbose debugging
  - name: NCCL_DEBUG
    value: "INFO"
  - name: NCCL_DEBUG_SUBSYS
    value: "INIT,NET"

  # Try different GID index
  - name: NCCL_IB_GID_INDEX
    value: "1"

  # Everything else auto-detected

  command:
  - /bin/bash
  - -c
  - |
    source /shared/nccl-env.sh

    echo "Testing NCCL with:"
    echo "  GID Index: $NCCL_IB_GID_INDEX (overridden)"
    echo "  HCAs: $NCCL_IB_HCA (auto-detected)"
    echo "  Interfaces: $NCCL_SOCKET_IFNAME (auto-detected)"

    python3 -c "
    import torch.distributed as dist
    dist.init_process_group(backend='nccl')
    print('✅ NCCL initialized successfully!')
    "
```

## Summary

**Auto-detection with overrides gives you:**
- ✅ **Portability**: Works across different hardware by default
- ✅ **Flexibility**: Override when needed for specific use cases
- ✅ **Debuggability**: Test different configurations easily
- ✅ **Best practices**: Auto-detected defaults, manual tuning when beneficial

**Typical workflow:**
1. **Start with 100% auto-detection** (no overrides)
2. **Run benchmarks** to see baseline performance
3. **Override selectively** if you identify bottlenecks
4. **Validate improvements** with benchmarks
5. **Document overrides** so others understand why
