# Encryption Performance Comparison: Software MACsec vs IPsec

**Date:** 2026-07-16
**Cluster:** Dublin (host-192-168-100-153)
**Status:** Complete

## Summary

Compared CPU-based encryption methods for TCP traffic on ConnectX-7 NICs. Neither method can encrypt RDMA/RoCEv2 traffic — RDMA bypasses the kernel network stack entirely. Hardware offload (MACsec or IPsec packet offload) is required for RDMA encryption, and both are blocked on kernel 5.14.

## Results

| Test | Throughput | vs Baseline | Retransmits |
|------|-----------|-------------|-------------|
| Baseline (no encryption) | 26.1 Gbits/sec | — | 0 |
| Software MACsec (AES-GCM-128) | 6.42 Gbits/sec | -75% | 0 |
| Software IPsec (AES-GCM-128) | 5.23 Gbits/sec | -80% | 1,214 |

**Software MACsec is the better option** — 23% faster than software IPsec with zero retransmits.

## Test Setup

- Single H100 node, NIC-to-NIC via veth pair between two network namespaces
- DOCA 26.04-0.8.6, kernel 5.14.0-570.73.1.el9_6, ConnectX-7 firmware 28.47.1026
- iperf3, 10-second runs, MTU 9000
- MACsec: `ip link add ... type macsec encrypt on`, GCM-AES-128
- IPsec: `ip xfrm state add ... aead rfc4106(gcm(aes))`, transport mode, software (no offload)

## What Can Encrypt RDMA?

| Method | TCP | RDMA | Available? |
|--------|-----|------|-----------|
| Software MACsec | Yes | **No** | Yes |
| Software IPsec | Yes | **No** | Yes |
| IPsec crypto offload | Yes | **No** (kernel still frames packets) | Yes — verified on Dublin |
| IPsec packet offload | Yes | **Yes** | **No** — kernel 5.14 returns "Invalid argument", dmesg: "TECH PREVIEW" |
| MACsec HW offload | Yes | **Yes** | **No** — kernel 5.14 returns "Operation not supported" |

### IPsec Offload Details

The kernel has the right config options:

```
CONFIG_XFRM_OFFLOAD=y
CONFIG_INET_ESP_OFFLOAD=m
CONFIG_MLX5_EN_IPSEC=y
```

DOCA mlx5_core has 289 IPsec symbols compiled in, and `CRYPTO_POLICY=UNRESTRICTED` is set in firmware. However:

- `ethtool -k enp3s0np0 | grep esp` → `esp-hw-offload: off [fixed]`
- `offload crypto dev ...` works (NIC handles AES-GCM, kernel handles ESP framing) — but kernel still frames packets, so RDMA bypasses it
- `offload packet dev ...` fails with "Invalid argument" — full packet offload not available
- `dmesg` shows "TECH PREVIEW: IPsec packet offload may not be fully supported"

NVIDIA documents that RoCEv2 encryption requires `packet` offload specifically: "enables the use of IPsec over RoCE packets, which are outside the network stack and cannot be used without full hardware offload."

## Conclusions

1. **For TCP/NFS traffic:** Software MACsec is the best available option — 6.4 Gbits/sec with clean delivery (no retransmits). Acceptable for dataset reads over NFS where the bottleneck is typically storage, not network.

2. **For RDMA/NCCL traffic:** No encryption is possible on kernel 5.14. Both hardware offload paths (MACsec and IPsec packet offload) require kernel 6.1+ (RHEL 10).

3. **When RHEL 10 arrives:** MACsec hardware offload is the better choice — zero CPU overhead, L2 encryption covers everything on the wire transparently. IPsec packet offload is the alternative if MACsec isn't available.

## Related

- [MACsec Hardware Offload Kernel Blocker](macsec-hardware-offload-kernel-blocker.md)
- [NVIDIA IPsec Packet Offload Documentation](https://docs.nvidia.com/doca/sdk/ipsec-packet-offload/index.html)
- [NVIDIA IPsec Full Offload Documentation](https://docs.nvidia.com/networking/display/mlnxofedv24010331/ipsec+full+offload)
