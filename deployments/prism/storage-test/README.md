# Hybrid Storage Pattern for Multi-Node Training

## Problem

ZeRO-3 distributed training across 5 nodes requires shared access to the dataset and a place to write checkpoints (~166GB per full checkpoint). The Barcelona cluster has no CephFS — only ceph-rbd (block, RWO) and an in-cluster NFS server (`nfs-csi`, RWX).

A single NFS PVC for everything creates a bottleneck: all checkpoint writes from 20 GPUs funnel through one NFS server pod on a CPU node.

## Solution: Split Storage

Use two volume types, each for what it does best:

| Volume | Type | StorageClass | Access Mode | Purpose |
|--------|------|-------------|-------------|---------|
| `prism-data-shared` | NFS | `nfs-csi` | RWX | Dataset (read-heavy, shared across all pods) |
| Per-pod checkpoint PVC | ceph-rbd | `ocs-external-storagecluster-ceph-rbd` | RWO | Checkpoints (write-heavy, per-rank shards) |

### Why This Works

- **Dataset reads** are shared and read-heavy — NFS handles this fine
- **Checkpoint writes** are per-rank with ZeRO-3 — each rank saves its own shard (~33GB for a 166GB checkpoint across 5 nodes), so each pod writes to its own fast block storage PVC independently
- No single-pod bottleneck for the heavy writes

### DeepSpeed/ZeRO-3 Compatibility

ZeRO-3 per-node checkpoint sharding is the default behavior. No code changes needed — just configure different paths:

- `data_dir` / dataset path → `/data` (shared NFS mount)
- `output_dir` / checkpoint path → `/checkpoints` (per-pod RWO mount)

To produce a merged checkpoint for inference or HuggingFace Hub upload, run a single-node job after training.

## Test Results (2026-07-16)

5 pods across 5 H100 nodes, writing 33GB each in parallel:

```
Checkpoint writes (RWO ceph-rbd): 165GB in 275s (~614 MB/s aggregate, ~123 MB/s per pod)
Dataset reads (RWX NFS):          25GB in 15s  (~1.7 GB/s aggregate)
```

Each pod successfully wrote 34GB to its own checkpoint PVC while all pods read from the shared NFS mount simultaneously.

## Pod Spec Example

```yaml
containers:
- name: training
  volumeMounts:
  - name: shared-data
    mountPath: /data
  - name: checkpoint
    mountPath: /checkpoints
volumes:
- name: shared-data
  persistentVolumeClaim:
    claimName: prism-data-shared    # 3TB RWX NFS
volumeClaimTemplates:
- metadata:
    name: checkpoint
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: ocs-external-storagecluster-ceph-rbd
    resources:
      requests:
        storage: 200Gi              # Per-pod checkpoint storage
```

## Files

- `storage-io-test.yaml` — StatefulSet that deploys 5 test pods with the hybrid mount pattern. Uses `volumeClaimTemplates` so checkpoint PVCs are created automatically per pod.
- `checkpoint-pvcs.yaml` — Standalone checkpoint PVCs (alternative to volumeClaimTemplates).
- `run-io-test.sh` — Test script that simulates parallel checkpoint writes and shared dataset reads. Run with `cleanup` argument to tear down.

## Running the Test

```bash
# Deploy
oc apply -f deployments/prism/storage-test/storage-io-test.yaml

# Wait for pods
oc wait --for=condition=Ready pod -l app=storage-io-test -n b-prism --timeout=120s

# Run test
./deployments/prism/storage-test/run-io-test.sh

# Clean up
./deployments/prism/storage-test/run-io-test.sh cleanup
```

## Current PVC State (b-prism)

| PVC | Size | Mode | StorageClass | Status |
|-----|------|------|-------------|--------|
| `prism-data` | 3TB | RWO | ceph-rbd | Fallback (original data, keep until hybrid is validated in production) |
| `prism-data-shared` | 3TB | RWX | nfs-csi | Dataset copy (276GB copied from prism-data) |

## Limitations

- NFS server is a single pod on `moc-r4pac08u07-s3-cpu` — if it goes down, dataset reads fail
- NFS server backing PVC is 3TB ceph-rbd, already 60%+ used by other tenants — monitor capacity
- Checkpoint PVCs are RWO, so a pod can only resume on the same node (StatefulSet handles this)
- Long-term, CephFS would be better for the shared volume but is not available on this external Ceph cluster
