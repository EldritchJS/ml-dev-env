# Claude Guidance Documentation

This directory contains operational guides and best practices for managing the H100 GPU cluster.

## Available Guides

### Network and Performance

- **[manual-rate-limiting-mlnx-qos.md](./manual-rate-limiting-mlnx-qos.md)** - How to apply hardware rate limits using mlnx_qos tool
  - Use case: Performance experiments with bandwidth constraints
  - Method: DaemonSet with NVIDIA OFED container image
  - Includes: Step-by-step instructions, troubleshooting, verification

- **[nccl-configuration-h100-cluster.md](./nccl-configuration-h100-cluster.md)** - NCCL settings for H100 cluster
  - Critical settings for 194 GB/s performance
  - DMABUF, CROSS_NIC, and IB_HCA configuration
  - Root cause analysis of common performance issues

- **[rdma-perftest-gpudirect.md](./rdma-perftest-gpudirect.md)** - RDMA performance testing with GPUDirect
  - ib_write_bw and other perftest tools
  - GPU-to-GPU RDMA verification
  - Network bandwidth testing

### Hardware Configuration

- **[mlxconfig-pod-setup.md](./mlxconfig-pod-setup.md)** - Mellanox firmware configuration
  - Using mlxconfig to query/modify NIC settings
  - Running in privileged pods
  - Firmware parameter management

## Quick Links

### Rate Limiting
- Apply 100 Gbps rate limit: See [manual-rate-limiting-mlnx-qos.md](./manual-rate-limiting-mlnx-qos.md#step-by-step-guide)
- Verify rate limits: See [manual-rate-limiting-mlnx-qos.md](./manual-rate-limiting-mlnx-qos.md#step-4-verify-rate-limits-applied)
- Remove rate limits: See [manual-rate-limiting-mlnx-qos.md](./manual-rate-limiting-mlnx-qos.md#removing-rate-limits)

### NCCL Performance
- Critical settings: See [nccl-configuration-h100-cluster.md](./nccl-configuration-h100-cluster.md#quick-reference-critical-nccl-settings)
- Troubleshooting 5x slowdown: See [nccl-configuration-h100-cluster.md](./nccl-configuration-h100-cluster.md#problem-history-the-5x-performance-gap)

### Network Testing
- RDMA bandwidth test: See [rdma-perftest-gpudirect.md](./rdma-perftest-gpudirect.md)
- GPUDirect verification: See [rdma-perftest-gpudirect.md](./rdma-perftest-gpudirect.md)

## Document Updates

These documents are maintained alongside cluster configuration changes. When updating:

1. Add date to "Last Updated" field
2. Document the specific change and why it was needed
3. Update related documents if necessary
4. Test procedures before documenting them

## Related Directories

- `deployments/h-kim/` - Actual deployment manifests and results
- `k8s/machineconfigs/` - OpenShift MachineConfig resources
- `k8s/` - Kubernetes resource definitions
