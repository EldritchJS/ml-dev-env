# RDMA Perftest Runner

Flexible RDMA performance testing between two nodes with support for:
- GPUDirect (CUDA) or host memory testing
- Configurable NIC selection (4 NICs per node)
- Multiple parallel QP/streams (up to 4)
- Different test types (write, read, send)

## Quick Start

### Available Nodes with RDMA

Only these nodes have SR-IOV RDMA resources configured:
- **moc-r4pcc02u15-yunshi** (AMD EPYC, ConnectX-7)
- **moc-r4pcc02u16-yunshi** (AMD EPYC, ConnectX-7)
- **moc-r4pcc02u17-nairr** (H100, ConnectX-7)
- **moc-r4pcc02u18-nairr** (H100, ConnectX-7)

**Note:** moc-r4pcc02u25-nairr does NOT have RDMA configured and cannot be used.

### Run Tests

```bash
# Basic RDMA test (host memory) - validated at 226 Gb/sec
./scripts/run-rdma-perftest.sh \
  -s moc-r4pcc02u18-nairr \
  -c moc-r4pcc02u17-nairr

# GPUDirect test with GPU 0, NIC 0
./scripts/run-rdma-perftest.sh \
  -s moc-r4pcc02u18-nairr \
  -c moc-r4pcc02u17-nairr \
  --gpudirect \
  --gpu-id 0 \
  --nic-id 0

# GPUDirect test with 4 parallel streams
./scripts/run-rdma-perftest.sh \
  -s moc-r4pcc02u18-nairr \
  -c moc-r4pcc02u17-nairr \
  --gpudirect \
  --gpu-id 1 \
  --nic-id 1 \
  --num-qps 4

# RDMA read test (instead of write)
./scripts/run-rdma-perftest.sh \
  -s moc-r4pcc02u18-nairr \
  -c moc-r4pcc02u17-nairr \
  --test-type read
```

## Script Options

```
-s, --server-node NODE      Server node hostname (required)
-c, --client-node NODE      Client node hostname (required)
-g, --gpudirect             Enable GPUDirect (CUDA) testing
-d, --gpu-id ID             GPU ID to use (0-3, default: 0)
-n, --nic-id ID             NIC ID to use (0-3 for mlx5_6-9, default: 0)
-q, --num-qps NUM           Number of parallel QPs/streams (1-4, default: 1)
-t, --test-type TYPE        Test type: write, read, send (default: write)
-N, --namespace NS          Kubernetes namespace (default: nccl-test)
-h, --help                  Show help message
```

## NIC Mapping

The cluster has 4 ConnectX-7 NICs per node on isolated /24 subnets:

| NIC ID | mlx5 Device | Interface | Subnet | PCI Address |
|--------|-------------|-----------|--------|-------------|
| 0 | mlx5_6 | eno5np0 | 10.0.103.0/24 | 03:00.0 |
| 1 | mlx5_7 | eno6np0 | 10.0.104.0/24 | 23:00.0 |
| 2 | mlx5_8 | eno7np0 | 10.0.105.0/24 | a3:00.0 |
| 3 | mlx5_9 | eno8np0 | 10.0.106.0/24 | c3:00.0 |

**Important:** Subnets are isolated - pods can only communicate on the same subnet (NIC ID).

## GPU Mapping

Each H100 node has 4 GPUs:

| GPU ID | GPU Device |
|--------|------------|
| 0 | /dev/nvidia0 |
| 1 | /dev/nvidia1 |
| 2 | /dev/nvidia2 |
| 3 | /dev/nvidia3 |

For optimal performance with GPUDirect, match GPU and NIC NUMA affinity. See `claude_guidance/gpu-nic-affinity-mapping.md`.

## Available Images

| Image | Base | Size | Use Case |
|-------|------|------|----------|
| `quay.io/jschless/ml-dev-env:minimal-perftest` | Ubuntu 22.04 | ~200MB | Host memory RDMA tests |
| `quay.io/jschless/ml-dev-env:cuda-perftest` | NVIDIA CUDA 12.4.1 runtime | ~2GB | GPUDirect RDMA tests |
| `quay.io/jschless/ml-dev-env:h-kim` | NVIDIA PyTorch 26.01 | ~20GB | Full ML workloads |

The script automatically selects the appropriate image based on `--gpudirect` flag.

## How It Works

1. **Generates pod manifests** from configuration
2. **Deploys server pod** on specified node
3. **Waits for server to be ready**
4. **Deploys client pod** on specified node
5. **Streams client logs** (test results)
6. **Cleans up pods** on exit (via trap)

## Example Output

```
[INFO] === RDMA Perftest Configuration ===
[INFO] Server Node:    moc-r4pcc02u18-nairr
[INFO] Client Node:    moc-r4pcc02u17-nairr
[INFO] GPUDirect:      false
[INFO] NIC ID:         0 (mlx5_6)
[INFO] Test Type:      write (ib_write_bw)
[INFO] Num QPs:        1
[INFO] Namespace:      nccl-test
[INFO] ====================================

...

---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF          Device         : mlx5_6
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : ON
 TX depth        : 128
 CQ Moderation   : 100
 Mtu             : 4096[B]
 Link type       : Ethernet
 GID index       : 3
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0e55 PSN 0xc04a54 RKey 0x041000 VAddr 0x007fc195be4000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:00:103:03
 remote address: LID 0000 QPN 0x0ce1 PSN 0xc04a54 RKey 0x041000 VAddr 0x007f9b58e3d000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:00:103:02
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
 2          5000           0.083333            0.082362            5.147634
 4          5000             0.17               0.16   		   5.124526
...
 8388608    5000             226.27             226.27 		   0.003372
---------------------------------------------------------------------------------------
[SUCCESS] Test completed successfully!
```

**Validated Performance:** ConnectX-7 400G NICs achieve **~226 Gb/sec** RDMA write bandwidth.

## Container Images

The required images are built and available on quay.io:
- `quay.io/jschless/ml-dev-env:cuda-perftest` - CUDA 12.4.1 runtime + perftest (~2GB)
- `quay.io/jschless/ml-dev-env:minimal-perftest` - Ubuntu 22.04 + perftest (~200MB)

The Dockerfile for cuda-perftest is available in `deployments/admin/Dockerfile.cuda-perftest`.

## Troubleshooting

### Pod stuck in Pending

Check if the specified node exists and has available resources:

```bash
kubectl get nodes | grep -E "(u09|u11|u12|u16|u25)"
kubectl describe pod perftest-server -n nccl-test
```

### CUDA errors when using --gpudirect

Verify the node has GPUs and the NVIDIA device plugin is running:

```bash
kubectl get nodes -o json | jq '.items[].status.allocatable | select(.["nvidia.com/gpu"] != null)'
```

### RDMA device not found

Check that the RDMA device operator is running and VFs are created:

```bash
kubectl get pods -n openshift-sriov-network-operator
```

## Related Documentation

- **RDMA Testing Guide:** `claude_guidance/rdma-perftest-gpudirect.md`
- **GPU-NIC Affinity:** `claude_guidance/gpu-nic-affinity-mapping.md`
- **Rate Limiting:** `claude_guidance/manual-rate-limiting-mlnx-qos.md`
