# Node Allocation Plan

**Date:** April 5, 2026
**Status:** Active

---

## H Kim's 15-Node Experiment

### Nodes (14 H100 nodes + 1 yunshi node = 15 total)

**Rack 4:**
- moc-r4pcc04u03-nairr
- moc-r4pcc04u09-nairr
- moc-r4pcc04u11-nairr
- moc-r4pcc04u12-nairr
- moc-r4pcc04u16-nairr
- moc-r4pcc04u25-nairr
- moc-r4pcc04u37-nairr

**Rack 2:**
- moc-r4pcc02u05
- moc-r4pcc02u10-nairr
- moc-r4pcc02u18-nairr
- moc-r4pcc02u25-nairr
- moc-r4pcc02u30-nairr
- moc-r4pcc02u32
- moc-r4pcc02u35
- moc-r4pcc02u16-yunshi

**Configuration:**
- Rate limiting: ENABLED (100 Gbps per NIC)
- Total nodes: 15
- Total GPUs: 60 (4 GPUs per node)

---

## Yunshi's 2-Node Experiments

### Nodes

- moc-r4pcc02u15-yunshi
- moc-r4pcc04u10-nairr

**Configuration:**
- Rate limiting: DISABLED (no rate limits)
- Total nodes: 2
- Total GPUs: 8 (4 GPUs per node)

---

## Node Exclusions

### moc-r4pcc04u10-nairr
- Reserved for Yunshi's 2-node experiments
- Do NOT apply rate limiting
- Do NOT include in H Kim's experiments

### moc-r4pcc02u15-yunshi
- Reserved for Yunshi's 2-node experiments
- Do NOT apply rate limiting
- Active workloads: interactive-jupyter, tsfm-node-0

### moc-r4pcc04u15-jason
- **PROBLEMATIC - EXCLUDED from H Kim's experiments**
- Do NOT use for benchmarking
- Node has issues and should not be included

### moc-r4pcc02u16-yunshi
- Included in H Kim's 15-node experiments
- Will be rate limited
- Active workloads: May have user workloads (do not disturb)

---

## Summary Table

| Node Name | Owner | Experiment Type | Rate Limited | Active Workloads | Notes |
|-----------|-------|-----------------|--------------|------------------|-------|
| moc-r4pcc02u05 | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u10-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u15-yunshi | Yunshi | 2-node | No | interactive-jupyter, tsfm-node-0 | Do not disturb |
| moc-r4pcc02u16-yunshi | H Kim | 15-node | Yes | Possible | Do not disturb |
| moc-r4pcc02u18-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u25-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u30-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u32 | H Kim | 15-node | Yes | None | |
| moc-r4pcc02u35 | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u03-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u09-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u10-nairr | Yunshi | 2-node | No | tsfm-node-1 | Reserved for different project |
| moc-r4pcc04u11-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u12-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u15-jason | EXCLUDED | N/A | N/A | None | **PROBLEMATIC - Do not use** |
| moc-r4pcc04u16-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u25-nairr | H Kim | 15-node | Yes | None | |
| moc-r4pcc04u37-nairr | H Kim | 15-node | Yes | None | |

---

## Rate Limiting Configuration

**H Kim 15-node experiment (100 Gbps rate limit):**
- Applied via mlnx_qos hardware rate limiting
- Target: 100 Gbps per ConnectX-7 NIC
- 4 NICs per node (eno5np0, eno6np0, eno7np0, eno8np0)
- Total nodes with rate limiting: 15
- Expected NCCL performance: ~49 GB/s aggregate per 4 nodes with rate limiting

**Yunshi 2-node experiment (no rate limiting):**
- No rate limits applied
- Full ConnectX-7 400G bandwidth available
- Expected NCCL performance: ~99 GB/s aggregate for 2 nodes without rate limiting

---

**Last Updated:** April 5, 2026
**Change Log:**
- April 5, 2026: Excluded moc-r4pcc04u15-jason (problematic node), reduced H Kim allocation from 16 to 15 nodes
