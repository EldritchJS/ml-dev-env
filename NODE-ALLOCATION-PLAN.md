# Node Allocation Plan

**Date:** April 5, 2026
**Status:** Active

---

## H Kim's 16-Node Experiment

### Nodes (16 H100 nodes)

**Rack 4:**
- moc-r4pcc04u03-nairr
- moc-r4pcc04u09-nairr
- moc-r4pcc04u10-nairr
- moc-r4pcc04u11-nairr
- moc-r4pcc04u12-nairr
- moc-r4pcc04u16-nairr
- moc-r4pcc04u25-nairr
- moc-r4pcc04u37-nairr

**Rack 2:**
- moc-r4pcc02u05
- moc-r4pcc02u10-nairr
- moc-r4pcc02u17-nairr
- moc-r4pcc02u18-nairr
- moc-r4pcc02u25-nairr
- moc-r4pcc02u30-nairr
- moc-r4pcc02u32
- moc-r4pcc02u35

**Configuration:**
- Rate limiting: DISABLED (unlimited bandwidth)
- Total nodes: 16
- Total GPUs: 64 (4 GPUs per node)

---

## Yunshi's 2-Node Experiments

### Nodes

**Rack 2:**
- moc-r4pcc02u15-yunshi
- moc-r4pcc02u16-yunshi

**Configuration:**
- Rate limiting: DISABLED (no rate limits)
- Total nodes: 2
- Total GPUs: 8 (4 GPUs per node)

---

## Node Exclusions

### moc-r4pcc02u15-yunshi
- Reserved for Yunshi's 2-node experiments
- Do NOT apply rate limiting
- Active workloads: interactive-jupyter, tsfm-node-0

### moc-r4pcc02u16-yunshi
- Reserved for Yunshi's 2-node experiments
- Do NOT apply rate limiting
- Active workloads: May have user workloads (do not disturb)

### moc-r4pcc04u15-jason
- **PROBLEMATIC - EXCLUDED from all experiments**
- Do NOT use for benchmarking
- Node has issues and should not be included

### moc-r4pcc02u36-nairr
- **NOT YET ALLOCATED** - newly configured but not assigned
- Configured with -nairr firmware settings
- Available for future allocation

---

## Summary Table

| Node Name | Owner | Experiment Type | Rate Limited | Active Workloads | Notes |
|-----------|-------|-----------------|--------------|------------------|-------|
| moc-r4pcc02u05 | H Kim | 16-node | No | None | |
| moc-r4pcc02u10-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc02u15-yunshi | Yunshi | 2-node | No | interactive-jupyter, tsfm-node-0 | Do not disturb |
| moc-r4pcc02u16-yunshi | Yunshi | 2-node | No | Possible | Do not disturb |
| moc-r4pcc02u17-nairr | H Kim | 16-node | No | None | Newly added 2026-04-09 |
| moc-r4pcc02u18-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc02u25-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc02u30-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc02u32 | H Kim | 16-node | No | None | |
| moc-r4pcc02u35 | H Kim | 16-node | No | None | |
| moc-r4pcc02u36-nairr | UNALLOCATED | N/A | No | None | Configured but not yet assigned |
| moc-r4pcc04u03-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u09-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u10-nairr | H Kim | 16-node | No | None | Transferred from Yunshi 2026-04-09 |
| moc-r4pcc04u11-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u12-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u15-jason | EXCLUDED | N/A | N/A | None | **PROBLEMATIC - Do not use** |
| moc-r4pcc04u16-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u25-nairr | H Kim | 16-node | No | None | |
| moc-r4pcc04u37-nairr | H Kim | 16-node | No | None | |

---

## Rate Limiting Configuration

**H Kim 15-node experiment (NO rate limiting):**
- Rate limiting: DISABLED
- All traffic classes set to unlimited (0,0,0,0,0,0,0,0)
- Full ConnectX-7 400G bandwidth available
- 4 NICs per node (eno5np0, eno6np0, eno7np0, eno8np0)
- Expected NCCL performance: ~194 GB/s aggregate for 8 nodes, ~12.4 GB/s per GPU

**Yunshi 2-node experiment (no rate limiting):**
- No rate limits applied
- Full ConnectX-7 400G bandwidth available
- Expected NCCL performance: ~99 GB/s aggregate for 2 nodes without rate limiting

---

**Last Updated:** April 9, 2026
**Change Log:**
- April 9, 2026: Node reallocation - moc-r4pcc02u16-yunshi returned to Yunshi, moc-r4pcc04u10-nairr moved to H Kim, moc-r4pcc02u17-nairr added to H Kim (newly configured). H Kim now has 16 nodes (64 GPUs).
- April 5, 2026 (later): Removed rate limiting from all 15 H Kim nodes (now unlimited bandwidth)
- April 5, 2026: Excluded moc-r4pcc04u15-jason (problematic node), reduced H Kim allocation from 16 to 15 nodes
