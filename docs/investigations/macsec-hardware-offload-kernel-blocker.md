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

## How to Enable (Once Kernel 6.1+ Is Available)

Once the cluster is on RHEL 10 / kernel 6.1+, the following steps enable MACsec hardware offload between two nodes. This encrypts all L2 traffic on the link — including RDMA/RoCEv2 — at line rate with zero CPU overhead.

### Prerequisites

- Kernel 6.1+ (RHEL 10 ships 6.12)
- ConnectX-7 firmware xx.34.0364+ (both clusters already exceed this)
- DOCA/MLNX_OFED driver with MACsec support (already compiled in on both clusters)

### Per-NIC Setup (Both Ends)

Each NIC pair that communicates needs MACsec configured on both sides with matching keys. Repeat for each NIC (eno5np0–eno8np0 on Barcelona, enp3s0np0/enp195s0np0 on Dublin).

```bash
# 1. Create MACsec device on the physical interface
ip link add link <iface> macsec0 type macsec encrypt on

# 2. Enable hardware offload
ip macsec offload macsec0 mac

# 3. Configure TX security association (SA)
#    Key ID (00) and 128-bit key must match the peer's RX SA
ip macsec add macsec0 tx sa 0 pn 1 on key 00 <128-bit-hex-key>

# 4. Configure RX security association (peer's SCI)
#    SCI = peer's MAC address (no colons) + port 0001
ip macsec add macsec0 rx sci <peer_sci>
ip macsec add macsec0 rx sci <peer_sci> sa 0 pn 1 on key 00 <128-bit-hex-key>

# 5. Assign IP and bring up
ip addr add <ip>/24 dev macsec0
ip link set macsec0 up
```

### Key Management

For testing, use static pre-shared keys (PSK) as shown above. For production, use `wpa_supplicant` with MKA (MACsec Key Agreement, IEEE 802.1X-2010) for automatic key rotation:

```bash
# /etc/wpa_supplicant/wpa_supplicant-macsec.conf
network={
    key_mgmt=NONE
    eapol_flags=0
    macsec_policy=1
    macsec_integ_only=0
    mka_cak=<128-bit-hex-cak>
    mka_ckn=<256-bit-hex-ckn>
    mka_priority=100
}

wpa_supplicant -i <iface> -Dmacsec_linux -c /etc/wpa_supplicant/wpa_supplicant-macsec.conf
```

### Verifying Offload

```bash
# Confirm hardware offload is active
ip macsec show
# Look for: offload: mac

# Verify traffic is encrypted (run on a third node or mirror port)
tcpdump -i <iface> -n ether proto 0x88e5

# Benchmark — should show near line rate (~226 Gbits/sec per NIC)
ib_write_bw -d mlx5_6 -a -F --report_gbits
```

### OpenShift Integration

On OpenShift, MACsec setup would need to be applied via MachineConfig (systemd unit or script at boot) since CoreOS is immutable. The `99-h100-pci-optimization` MachineConfig in the `h100` MachineConfigPool is a pattern to follow — add a similar unit that configures MACsec on all 4 ConnectX-7 NICs at boot.

### NCCL Considerations

No NCCL configuration changes are needed. MACsec is transparent at L2 — RDMA devices bind to the physical NIC, and the NIC encrypts/decrypts frames in hardware before they hit the wire. `NCCL_IB_HCA`, `NCCL_CROSS_NIC`, and all other settings remain the same.

## Workaround (Current Kernel)

Software MACsec (no hardware offload) works on both clusters for TCP traffic only. This uses CPU-based AES-GCM encryption, which adds ~75% throughput overhead (see [encryption-performance-comparison.md](encryption-performance-comparison.md)). It cannot encrypt RDMA traffic because RDMA bypasses the kernel network stack.

## References

- [NVIDIA MACsec Full Offload Documentation](https://networking-docs.nvidia.com/mlnxofedswum/24102180lts/macsec-full-offload)
- [ConnectX-7 Datasheet](https://www.nvidia.com/content/dam/en-zz/Solutions/networking/ethernet-adapters/connectx-7-datasheet-Final.pdf)
- NVIDIA requirement: Kernel 6.1+, firmware xx.34.0364+, ConnectX-7+
