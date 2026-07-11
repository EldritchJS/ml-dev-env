# IOMMU Configuration Performance Comparison

## Test Configuration
- **Nodes Tested**: 2 nodes, 4 GPUs per node (8 GPUs total)
- **GPU Model**: H100
- **Network**: InfiniBand with RDMA (GPUDirect)
- **Framework**: PyTorch with NCCL backend

## Configurations Compared

### IOMMU Passthrough (iommu=pt)
- **Nodes**: moc-r4pcc04u17, moc-r4pcc04u18
- **IOMMU Mode**: Passthrough via kernel parameter
- **Kernel Setting**: `iommu=pt`
- **Status**: Default domain type = Passthrough

### IOMMU Completely Disabled
- **Nodes**: moc-r4pcc04u12-nairr, moc-r4pcc04u16-nairr
- **IOMMU Mode**: Disabled in BIOS
- **IOMMU Groups**: 0
- **Status**: No IOMMU functionality

---

## Performance Results

### 1. NCCL All-Reduce Bandwidth Test

| Message Size | Passthrough (GB/s) | Disabled (GB/s) | Difference |
|-------------|-------------------|-----------------|------------|
| 1 MB        | 5.91              | 5.90            | +0.2%      |
| 4 MB        | 23.25             | 23.17           | +0.3%      |
| 16 MB       | 75.92             | 75.71           | +0.3%      |
| 64 MB       | 89.23             | 88.90           | +0.4%      |
| 256 MB      | 92.44             | 91.98           | +0.5%      |
| 512 MB      | 93.04             | 92.26           | +0.8%      |
| 1024 MB     | 93.08             | 92.30           | +0.8%      |
| 2048 MB     | 93.13             | 92.37           | +0.8%      |

**Peak Bandwidth**:
- Passthrough: 93.13 GB/s
- Disabled: 92.37 GB/s
- **Difference: +0.8% (essentially identical)**

**Conclusion**: NCCL communication performance is virtually identical between passthrough and disabled modes.

---

### 2. TorchTitan LLM Training Performance

| Metric          | Passthrough     | Disabled        | Difference  |
|-----------------|-----------------|-----------------|-------------|
| **Average TPS** | **169,093**     | **158,852**     | **+6.4%**   |
| Min TPS         | 4,587           | 5,179           | -11.4%      |
| Max TPS         | 205,821         | 191,883         | +7.3%       |
| Sample Count    | 80              | 80              | -           |

**TPS = Tokens Per Second**

**Conclusion**: Training throughput is ~6.4% higher with IOMMU passthrough compared to completely disabled.

---

## Summary

| Test Type            | Winner          | Performance Gain |
|---------------------|-----------------|------------------|
| NCCL Bandwidth      | Tie             | < 1%             |
| Training Throughput | **Passthrough** | **+6.4%**        |

## Key Findings

1. **NCCL Communication**: Both configurations deliver nearly identical bandwidth for GPU-to-GPU communication over InfiniBand RDMA.

2. **Training Performance**: IOMMU passthrough mode shows measurably better training throughput (+6.4% TPS) compared to IOMMU completely disabled.

3. **Recommendation**: **IOMMU Passthrough (iommu=pt)** provides the best overall performance:
   - Maintains full IOMMU protection for other system components
   - Allows GPUDirect RDMA without translation overhead
   - Delivers superior training performance
   - More flexible than completely disabling IOMMU in BIOS

## Technical Notes

- The superior training performance with passthrough may be due to:
  - Better memory access patterns with IOMMU page tables in passthrough mode
  - Potential PCIe optimization differences
  - More efficient DMA operations with IOMMU hardware assist

- Both configurations successfully eliminate IO_PAGE_FAULT errors that occur when IOMMU is fully enabled (translated mode)

- IOMMU passthrough is the recommended configuration for GPU compute nodes requiring RDMA
