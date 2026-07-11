# 100 Gbps Rate Limit Successfully Applied

## Summary

Successfully applied 100 Gbps rate limits to all four NICs on all 8 H100 nodes using a standalone DaemonSet with NVIDIA OFED container image.

## Solution

Used NVIDIA MOFED (Mellanox OpenFabrics Enterprise Distribution) container image `nvcr.io/nvidia/mellanox/mofed:5.9-0.5.6.0-ubuntu20.04-amd64` which includes the `mlnx_qos` tool.

## Applied Configuration

- **Rate Limit:** 100 Gbps per Traffic Class (TC)
- **NICs per node:** 4 (eno5np0, eno6np0, eno7np0, eno8np0)
- **Traffic Classes:** All 8 TCs configured to 100 Gbps
- **Enforcement:** Hardware-level in NIC firmware (works for RDMA)

## Nodes Configured

All 8 H100 nodes have rate limits applied:

1. moc-r4pcc02u05
2. moc-r4pcc02u32
3. moc-r4pcc02u35
4. moc-r4pcc04u09-nairr
5. moc-r4pcc04u11-nairr
6. moc-r4pcc04u12-nairr
7. moc-r4pcc04u16-nairr
8. moc-r4pcc04u25-nairr

## Verification

Each node shows successful application:

```
tc: 0 ratelimit: 100.0 Gbps, tsa: vendor
tc: 1 ratelimit: 100.0 Gbps, tsa: vendor
tc: 2 ratelimit: 100.0 Gbps, tsa: vendor
tc: 3 ratelimit: 100.0 Gbps, tsa: vendor
tc: 4 ratelimit: 100.0 Gbps, tsa: vendor
tc: 5 ratelimit: 100.0 Gbps, tsa: vendor
tc: 6 ratelimit: 100.0 Gbps, tsa: vendor
tc: 7 ratelimit: 100.0 Gbps, tsa: vendor
```

## Deployment

- **Manifest:** `deployments/h-kim/apply-100g-with-ofed-image.yaml`
- **DaemonSet:** `apply-100g-rate-limit` in `default` namespace
- **Pods:** 8 running (one per H100 node)

## Management

To check status:
```bash
kubectl get pods -n default -l app=apply-100g-rate-limit -o wide
```

To view logs for a specific node:
```bash
kubectl logs -n default apply-100g-rate-limit-<pod-id>
```

To remove rate limits:
```bash
kubectl delete daemonset apply-100g-rate-limit -n default
```

Note: Rate limits persist until NIC reset or system reboot. The DaemonSet keeps running to maintain the configuration.

## Technical Details

- Uses `hostNetwork: true` and `hostPID: true` for direct hardware access
- Requires `privileged: true` security context
- Mounts `/sys` and `/dev` from host for NIC configuration
- mlnx_qos tool communicates directly with ConnectX-7 NICs via DCB protocol
