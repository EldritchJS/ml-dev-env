# H-Kim RDMA Setup Guide

This guide explains how to deploy h-kim with RDMA/InfiniBand support in any OpenShift namespace.

## Prerequisites

To run h-kim with RDMA, you need:

1. **Cluster with RDMA-capable nodes** (Barcelona cluster with H100 GPUs and ConnectX-7 NICs)
2. **SR-IOV Network Operator** configured with RDMA support
3. **Admin access** to create service accounts and grant SCC permissions

## Quick Start

For namespaces with RDMA already configured:

```bash
./scripts/deploy-h-kim.sh --namespace my-namespace --mode rdma
```

## Complete Setup for New Namespace

### Step 1: Create Service Account

Create a service account with IPC_LOCK capability permission:

```bash
NAMESPACE="your-namespace"

# Create service account
oc create serviceaccount h-kim-sa -n $NAMESPACE

# Grant access to nccl-scc (requires admin or permission from admin)
oc adm policy add-scc-to-user nccl-scc -z h-kim-sa -n $NAMESPACE
```

### Step 2: Create Network Attachment Definitions

Create SR-IOV network attachments for RDMA interfaces:

```bash
NAMESPACE="your-namespace"

# Copy network attachments from default namespace
for iface in eno5np0 eno6np0 eno7np0 eno8np0; do
  oc get network-attachment-definitions ${iface}-network -n default -o yaml | \
    sed "s/namespace: default/namespace: $NAMESPACE/" | \
    sed '/resourceVersion:/d' | \
    sed '/uid:/d' | \
    sed '/creationTimestamp:/d' | \
    sed '/sriovnetwork.openshift.io\/owner-ref:/d' | \
    oc apply -f -
done
```

Verify the network attachments:

```bash
oc get network-attachment-definitions -n $NAMESPACE
```

You should see:
- eno5np0-network
- eno6np0-network
- eno7np0-network
- eno8np0-network

### Step 3: Deploy h-kim with RDMA

```bash
./scripts/deploy-h-kim.sh --namespace $NAMESPACE --mode rdma
```

### Step 4: Verify RDMA Setup

Check that pods have RDMA interfaces:

```bash
oc exec h-kim-0 -n $NAMESPACE -- ip addr show | grep net
```

Expected output:
```
net1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000
net2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000
net3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000
net4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000
```

Check NCCL configuration:

```bash
oc exec h-kim-0 -n $NAMESPACE -- env | grep NCCL
```

Expected settings:
```
NCCL_SOCKET_IFNAME=net1,net2,net3,net4
NCCL_IB_DISABLE=0
NCCL_IB_HCA=mlx5_6,mlx5_7,mlx5_10,mlx5_11
NCCL_IB_GID_INDEX=3
NCCL_NET_GDR_LEVEL=5
```

### Step 5: Run Training

```bash
# Copy training script
oc cp h-kim-openshift.sh h-kim-0:/workspace/ -n $NAMESPACE
oc exec h-kim-0 -n $NAMESPACE -- chmod +x /workspace/h-kim-openshift.sh

# Start training
oc exec h-kim-0 -n $NAMESPACE -- bash -c \
  'MASTER_ADDR=h-kim-0.h-kim-headless.'$NAMESPACE'.svc.cluster.local /workspace/h-kim-openshift.sh'
```

Check for RDMA initialization in logs:

```bash
oc exec h-kim-0 -n $NAMESPACE -- tail -f /workspace/training.log
```

Look for these indicators that RDMA is working:
```
NCCL INFO Bootstrap: Using net1:10.0.103.X<0>
NCCL INFO NET/IB : Using [0]mlx5_6:1/RoCE [1]mlx5_7:1/RoCE [2]mlx5_10:1/RoCE [3]mlx5_11:1/RoCE
NCCL INFO Using network IBext_v11
NCCL INFO DMA-BUF is available on GPU device
```

## Architecture

### Components

1. **Service Account (h-kim-sa)**
   - Grants access to nccl-scc SecurityContextConstraint
   - Enables IPC_LOCK capability required for RDMA memory registration

2. **Network Attachment Definitions**
   - eno5np0-network → mlx5_6 (ConnectX-7 port 0)
   - eno6np0-network → mlx5_7 (ConnectX-7 port 1)
   - eno7np0-network → mlx5_10 (ConnectX-7 port 0 on NIC 2)
   - eno8np0-network → mlx5_11 (ConnectX-7 port 1 on NIC 2)

3. **SR-IOV Resources**
   - openshift.io/eno5np0rdma
   - openshift.io/eno6np0rdma
   - openshift.io/eno7np0rdma
   - openshift.io/eno8np0rdma

### Network Topology

```
Pod (h-kim-0)
├─ eth0 (10.129.x.x)     - K8s pod network (OVN)
├─ net1 (10.0.103.x)     - RDMA interface 1 → mlx5_6
├─ net2 (10.0.104.x)     - RDMA interface 2 → mlx5_7
├─ net3 (10.0.105.x)     - RDMA interface 3 → mlx5_10
└─ net4 (10.0.106.x)     - RDMA interface 4 → mlx5_11

NCCL uses net1-4 for GPU-to-GPU communication via GPUDirect RDMA
```

## Troubleshooting

### Pods Stuck in Pending

**Symptom:** Pods show "Insufficient openshift.io/eno5np0rdma"

**Cause:** Network attachment definitions reference wrong SR-IOV resource names

**Fix:** Ensure network attachments use correct resourceName:
```bash
oc get network-attachment-definitions eno5np0-network -n $NAMESPACE -o yaml | grep resourceName
```

Should show: `k8s.v1.cni.cncf.io/resourceName: openshift.io/eno5np0rdma`

### IPC_LOCK Permission Denied

**Symptom:** Pod creation fails with "capability may not be added: IPC_LOCK"

**Cause:** Service account doesn't have access to nccl-scc

**Fix:** Grant SCC permission:
```bash
oc adm policy add-scc-to-user nccl-scc -z h-kim-sa -n $NAMESPACE
```

### NCCL Bootstrap Error

**Symptom:** "Bootstrap: no socket interface found"

**Cause:** RDMA interfaces (net1-4) don't exist in pod

**Fix:** Verify network attachments are created and referenced correctly:
```bash
# Check attachments exist
oc get network-attachment-definitions -n $NAMESPACE

# Check pod annotations
oc get pod h-kim-0 -n $NAMESPACE -o yaml | grep k8s.v1.cni.cncf.io/networks
```

### TCP Fallback

If RDMA is not available, deploy with TCP mode:

```bash
./scripts/deploy-h-kim.sh --namespace $NAMESPACE --mode tcp
```

TCP mode:
- Uses eth0 instead of net1-4
- Sets NCCL_IB_DISABLE=1
- Lower performance but works on any network

## Performance

RDMA vs TCP performance comparison (8 H100 GPUs, LLaMA 8B training):

| Mode | Bandwidth | Latency | Tokens/sec |
|------|-----------|---------|------------|
| RDMA | ~200 GB/s | <5 μs   | ~12,000    |
| TCP  | ~20 GB/s  | ~100 μs | ~8,000     |

RDMA provides:
- 10x higher bandwidth
- 20x lower latency
- ~50% higher training throughput

## References

- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [GPUDirect RDMA](https://docs.nvidia.com/cuda/gpudirect-rdma/)
- [OpenShift SR-IOV Network Operator](https://docs.openshift.com/container-platform/latest/networking/hardware_networks/about-sriov.html)
