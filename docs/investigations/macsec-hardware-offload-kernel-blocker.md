# MACsec Hardware Offload — Kernel Blocker

**Date:** 2026-07-15
**Clusters tested:** Barcelona, Dublin
**Status:** Blocked — waiting on kernel upgrade

## Summary

ConnectX-7 NICs support MACsec full hardware offload (IEEE 802.1AE), which encrypts/decrypts all L2 frames in the NIC hardware with zero CPU overhead. This would allow encrypted RDMA and NCCL traffic with minimal performance impact. However, hardware offload is not available on the current kernel.

## Findings

### MACsec device creation: Works

```bash
$ ip link add link enp3s0np0 macsec_test type macsec sci 1 encrypt on
# exit code: 0
```

Software MACsec (CPU-based encryption) is fully functional.

### MACsec hardware offload: Fails

```bash
$ ip macsec offload macsec_test mac
RTNETLINK answers: Operation not supported
```

Tested on both clusters:

| Cluster | Kernel | DOCA Version | Offload Result |
|---------|--------|-------------|----------------|
| Barcelona | 5.14.0-570.76.1.el9_6.x86_64 | 26.01-1.0.0 | Operation not supported |
| Dublin | 5.14.0-570.73.1.el9_6.x86_64 | 26.04-0.8.6 | Operation not supported |

### Root Cause

NVIDIA's MACsec full offload documentation requires **kernel 6.1 or higher**. Both clusters run RHEL 9.6 with kernel 5.14. Despite the DOCA driver having MACsec symbols compiled in (confirmed via `/proc/kallsyms`), the kernel's netlink/MACsec subsystem does not support the `ndo_macsec_offload` path in kernel 5.14.

The newer DOCA version (26.04 on Dublin vs 26.01 on Barcelona) makes no difference — the blocker is the kernel, not the driver.

### Driver MACsec support is present

```bash
$ grep -i macsec /proc/kallsyms | head -5
ffffffffc0964b00 t cleanup_macsec_device  [mlx5_ib]
ffffffffc0964b90 t mlx5_macsec_save_roce_gid  [mlx5_ib]
ffffffffc0964c60 t get_macsec_device  [mlx5_ib]
ffffffffc0964d30 t macsec_event  [mlx5_ib]
```

The DOCA `mlx5_ib` module includes MACsec and RoCE-over-MACsec support. The gap is in the kernel's generic MACsec subsystem.

### Firmware is sufficient

ConnectX-7 firmware on both clusters exceeds the minimum requirement (xx.34.0364):

| Cluster | Firmware |
|---------|----------|
| Barcelona | 28.37.1014 |
| Dublin | 28.47.1026 |

## What's Needed

MACsec hardware offload will become available when either:

1. **RHEL 10 / OpenShift 5.x** — RHEL 10 ships kernel 6.12, which has full MACsec offload support
2. **Red Hat backport** — If Red Hat backports `ndo_macsec_offload` into a future RHEL 9.x kernel update (not currently planned as far as we know)

## Workaround

Software MACsec (no hardware offload) works on both clusters. This uses CPU-based AES-GCM encryption, which will add latency and CPU overhead compared to hardware offload. It could be used for functional testing but won't represent production MACsec performance on ConnectX-7.

## References

- [NVIDIA MACsec Full Offload Documentation](https://networking-docs.nvidia.com/mlnxofedswum/24102180lts/macsec-full-offload)
- [ConnectX-7 Datasheet](https://www.nvidia.com/content/dam/en-zz/Solutions/networking/ethernet-adapters/connectx-7-datasheet-Final.pdf)
- NVIDIA requirement: Kernel 6.1+, firmware xx.34.0364+, ConnectX-7+
