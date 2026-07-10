# Barcelona Cluster - mlx5 Device Mapping

**Last Verified:** 2026-07-10

## CRITICAL: Correct mlx5 Devices

When SR-IOV networks (eno5np0-network through eno8np0-network) are attached to pods on Barcelona H100 nodes, the following **4 mlx5 devices** appear:

```
mlx5_6
mlx5_7
mlx5_8
mlx5_9
```

## Verification Status

**Verified on ALL 5 Barcelona H100 nodes:**
- ✅ moc-r4pcc02u17-nairr
- ✅ moc-r4pcc02u18-nairr
- ✅ moc-r4pcc02u25-nairr
- ✅ moc-r4pcc02u15-yunshi
- ✅ moc-r4pcc02u16-yunshi

**All nodes showed the same 4 devices.** (Note: u16-yunshi listed them in different order but same devices present)

## NCCL Configuration

**Correct setting:**
```yaml
NCCL_IB_HCA: "mlx5_6,mlx5_7,mlx5_8,mlx5_9"
```

**WRONG setting (do NOT use):**
```yaml
# This was in clusters/barcelona.yaml originally - INCORRECT!
NCCL_IB_HCA: "mlx5_6,mlx5_7,mlx5_10,mlx5_11"
```

## What Happens With Wrong Devices

When using the wrong mlx5 device list (`mlx5_10,mlx5_11`), NCCL only detects the first 2 valid devices:
- Only `mlx5_6` and `mlx5_7` are used
- **50% bandwidth loss** (only 2 out of 4 NICs working)
- Example: 94.8 GB/s dropped to 52 GB/s with wrong config

## Network Interface Mapping

When SR-IOV creates 4 network interfaces in the pod:
- **net1** → 10.0.103.0/24 (eno5np0-network)
- **net2** → 10.0.104.0/24 (eno6np0-network)
- **net3** → 10.0.105.0/24 (eno7np0-network)
- **net4** → 10.0.106.0/24 (eno8np0-network)

These map to the 4 ConnectX-7 400G NICs, appearing as mlx5_6, mlx5_7, mlx5_8, mlx5_9.

## How to Verify (If Needed)

Deploy a pod with all 4 SR-IOV networks attached:

```yaml
annotations:
  k8s.v1.cni.cncf.io/networks: nccl-test/eno5np0-network, nccl-test/eno6np0-network, nccl-test/eno7np0-network, nccl-test/eno8np0-network
spec:
  containers:
  - name: check
    resources:
      requests:
        openshift.io/eno5np0rdma: 1
        openshift.io/eno6np0rdma: 1
        openshift.io/eno7np0rdma: 1
        openshift.io/eno8np0rdma: 1
```

Then run: `ibv_devinfo -l`

You should see exactly 4 HCAs: `mlx5_6, mlx5_7, mlx5_8, mlx5_9`

## Notes

- **Do NOT use auto-detect** - manually specify the devices as shown above
- All 5 Barcelona H100 nodes have identical mlx5 numbering
- The host shows 10 mlx5 devices total, but only 4 appear inside SR-IOV pods
- This is different from h-kim cluster which may have different mlx5 numbering
