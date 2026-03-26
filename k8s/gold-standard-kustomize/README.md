# Gold Standard NCCL Benchmark - Kustomize Version

This directory contains a Kustomize-based approach to deploying the gold standard NCCL benchmark with different node configurations.

## Structure

```
gold-standard-kustomize/
├── base/              # Base manifest (all common configuration)
│   ├── benchmark.yaml
│   └── kustomization.yaml
└── overlays/          # Cluster-specific configurations
    └── barcelona/     # Barcelona cluster (current)
        ├── 8node/         # All 8 H100 nodes
        ├── 4node-same-rack/  # 4 nodes from rack 4
        └── custom/        # Template for custom node selection
```

For other clusters, create a new directory under `overlays/` (e.g., `overlays/other-cluster/`).

## Quick Start

### Deploy 8-node benchmark
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/8node -n nccl-test
```

### Deploy 4-node same-rack benchmark
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/4node-same-rack -n my-namespace
```

### Deploy custom configuration
```bash
# Edit overlays/barcelona/custom/kustomization.yaml to specify your nodes
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/custom -n my-namespace
```

## Usage Examples

### Example 1: 8-node benchmark (all H100 nodes)
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/8node -n nccl-test

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=nccl-benchmark -n nccl-test --timeout=300s

# Run benchmark on all nodes
kubectl exec -n nccl-test nccl-benchmark-0 -- \
  torchrun --nnodes=8 --nproc_per_node=4 --node_rank=0 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 /benchmark/allreduce-loop.py &

for i in {1..7}; do
  kubectl exec -n nccl-test nccl-benchmark-$i -- \
    torchrun --nnodes=8 --nproc_per_node=4 --node_rank=$i \
    --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
    --master_port=29501 /benchmark/allreduce-loop.py &
done
```

### Example 2: 4-node same-rack benchmark
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/4node-same-rack -n nccl-test

# Run benchmark
kubectl exec -n nccl-test nccl-benchmark-0 -- \
  torchrun --nnodes=4 --nproc_per_node=4 --node_rank=0 \
  --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
  --master_port=29501 /benchmark/allreduce-loop.py &

for i in {1..3}; do
  kubectl exec -n nccl-test nccl-benchmark-$i -- \
    torchrun --nnodes=4 --nproc_per_node=4 --node_rank=$i \
    --master_addr=nccl-benchmark-0.nccl-benchmark-svc \
    --master_port=29501 /benchmark/allreduce-loop.py &
done
```

### Example 3: Custom 2-node benchmark
Create a new overlay or edit `overlays/barcelona/custom/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../../base

replicas:
- name: nccl-benchmark
  count: 2

patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/1/values
      value:
      - moc-r4pcc04u09-nairr
      - moc-r4pcc04u11-nairr
  target:
    kind: StatefulSet
    name: nccl-benchmark
```

Then deploy:
```bash
kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/custom -n my-namespace
```

### Example 4: Custom 6-node benchmark (rack 4 + rack 2)
Create a new overlay directory:

```bash
mkdir -p k8s/gold-standard-kustomize/overlays/barcelona/6node-mixed
cat > k8s/gold-standard-kustomize/overlays/barcelona/6node-mixed/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../../base

replicas:
- name: nccl-benchmark
  count: 6

patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/1/values
      value:
      - moc-r4pcc04u09-nairr
      - moc-r4pcc04u11-nairr
      - moc-r4pcc04u12-nairr
      - moc-r4pcc04u16-nairr
      - moc-r4pcc02u05
      - moc-r4pcc02u32
  target:
    kind: StatefulSet
    name: nccl-benchmark
EOF

kubectl apply -k k8s/gold-standard-kustomize/overlays/barcelona/6node-mixed -n nccl-test
```

## Viewing Generated Manifests

To see what will be applied without actually applying it:

```bash
# View 8-node configuration
kubectl kustomize k8s/gold-standard-kustomize/overlays/barcelona/8node

# View 4-node configuration
kubectl kustomize k8s/gold-standard-kustomize/overlays/barcelona/4node-same-rack
```

## Cleanup

```bash
# Delete deployment
kubectl delete -k k8s/gold-standard-kustomize/overlays/barcelona/8node -n nccl-test

# Or delete by label
kubectl delete statefulset,service,configmap -l app=nccl-benchmark -n nccl-test
```

## Advantages of This Approach

1. **Single source of truth**: Base manifest contains all common configuration
2. **DRY principle**: NCCL settings defined once, reused everywhere
3. **Version controlled**: All configurations are declarative and git-trackable
4. **GitOps ready**: Can be used with ArgoCD, Flux, etc.
5. **Easy validation**: `kubectl kustomize` shows exactly what will be deployed
6. **Native K8s tool**: No external dependencies beyond kubectl

## Creating New Configurations

### For Barcelona Cluster
To create a new configuration for Barcelona:

1. Create a new directory under `overlays/barcelona/`
2. Create a `kustomization.yaml` file
3. Set the replica count and node list
4. Apply with `kubectl apply -k`

See `overlays/barcelona/custom/kustomization.yaml` for a template.

### For Other Clusters
To add support for a different cluster:

1. Create a new directory: `overlays/<cluster-name>/`
2. Copy the barcelona structure as a template:
   ```bash
   cp -r overlays/barcelona overlays/other-cluster
   ```
3. Update node names in the kustomization.yaml files
4. Deploy with the appropriate kubectl context:
   ```bash
   kubectl apply -k overlays/other-cluster/8node --context=other-cluster -n namespace
   ```
