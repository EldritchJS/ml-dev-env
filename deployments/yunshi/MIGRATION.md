# Yunshi File Organization - Migration Guide

All yunshi related files have been organized into `deployments/yunshi/` following the standard project structure.

## What Changed

### File Moves

| Old Location | New Location | Type |
|-------------|--------------|------|
| `yunshi.yaml` | `deployments/yunshi/generated/statefulset-yunshi.yaml` | K8s StatefulSet |
| `yunshi/large_zero_shot_rdma.yaml` | `deployments/yunshi/generated/large_zero_shot_rdma.yaml` | K8s StatefulSet |
| `yunshi/jupyter.yaml` | `deployments/yunshi/generated/jupyter.yaml` | K8s Pod |
| `yunshi/` (directory) | Removed (empty) | Directory |

### New Structure

```
deployments/yunshi/
├── README.md                           # Project overview (NEW)
├── QUICKSTART.md                       # Quick start guide (NEW)
├── MIGRATION.md                        # This file (NEW)
├── generated/                          # K8s manifests
│   ├── statefulset-yunshi.yaml        # Main training setup
│   ├── large_zero_shot_rdma.yaml      # Large-scale variant
│   └── jupyter.yaml                    # Jupyter environment
├── scripts/                            # Scripts (empty, for future use)
├── docs/                               # Documentation (empty, for future use)
└── workspace/                          # Training workspace
```

## Impact on Existing Deployments

### ✅ No Breaking Changes

The yunshi pods themselves are **NOT affected** because:

1. **Kubernetes resources unchanged**: The YAML content is identical, only the file location changed
2. **Pod configurations intact**: All environment variables, volumes, and settings remain the same
3. **Running pods unaffected**: No need to restart or redeploy existing yunshi training jobs

### 📝 What You Need to Update

#### 1. Deployment Commands

**Old:**
```bash
oc apply -f yunshi.yaml
oc apply -f yunshi/large_zero_shot_rdma.yaml
oc apply -f yunshi/jupyter.yaml
```

**New:**
```bash
oc apply -f deployments/yunshi/generated/statefulset-yunshi.yaml
oc apply -f deployments/yunshi/generated/large_zero_shot_rdma.yaml
oc apply -f deployments/yunshi/generated/jupyter.yaml
```

#### 2. File References in Scripts

If you have any custom scripts or documentation that reference yunshi files:

**Old:**
```bash
cat yunshi.yaml
vi yunshi/large_zero_shot_rdma.yaml
```

**New:**
```bash
cat deployments/yunshi/generated/statefulset-yunshi.yaml
vi deployments/yunshi/generated/large_zero_shot_rdma.yaml
```

#### 3. Documentation Links

Update any references to yunshi configuration files to point to the new location under `deployments/yunshi/`.

## Quick Migration Checklist

- [x] Move yunshi.yaml to deployments/yunshi/generated/
- [x] Move yunshi/*.yaml to deployments/yunshi/generated/
- [x] Rename yunshi.yaml → statefulset-yunshi.yaml
- [x] Create README.md with project overview
- [x] Create QUICKSTART.md with usage guide
- [x] Create MIGRATION.md (this file)
- [ ] Update any custom scripts that reference old paths
- [ ] Update bookmarks or documentation links
- [ ] Notify team members of new structure

## Rollback (If Needed)

If you need to rollback to the old structure:

```bash
# Copy files back from deployments/yunshi/
cp deployments/yunshi/generated/statefulset-yunshi.yaml yunshi.yaml
mkdir -p yunshi
cp deployments/yunshi/generated/large_zero_shot_rdma.yaml yunshi/
cp deployments/yunshi/generated/jupyter.yaml yunshi/
```

## Benefits of New Structure

1. **Organization**: All yunshi files in one logical location
2. **Consistency**: Matches h-kim deployment structure and deployment wizard pattern
3. **Clarity**: Clear separation of generated files vs. documentation
4. **Discoverability**: Easy to find all yunshi-related resources
5. **Scalability**: Easy to add scripts, docs, and workspace files
6. **Documentation**: Comprehensive guides for new users

## File Descriptions

### Generated Manifests

**statefulset-yunshi.yaml**
- Main TSFM training StatefulSet
- 2 nodes, 8 GPUs total
- Standard configuration for hybrid TSFM pretraining
- Includes RDMA/InfiniBand setup

**large_zero_shot_rdma.yaml**
- Large-scale zero-shot learning variant
- Enhanced pod affinity rules
- Optimized for production zero-shot training
- Same RDMA configuration

**jupyter.yaml**
- Jupyter notebook environment
- Interactive development and debugging
- Access to same storage and datasets

## Deployment Workflow

### Standard Training
```bash
cd deployments/yunshi
oc apply -f generated/statefulset-yunshi.yaml
oc get pods -l app=tsfm-ddp -w
oc logs -f tsfm-node-0
```

### Large Zero-Shot
```bash
cd deployments/yunshi
oc apply -f generated/large_zero_shot_rdma.yaml
oc get pods -l app=tsfm-ddp -w
oc logs -f tsfm-node-0
```

### Jupyter Development
```bash
cd deployments/yunshi
oc apply -f generated/jupyter.yaml
oc port-forward jupyter 8888:8888
```

## Configuration Files Preserved

All configuration in the YAML files remains identical:

- ✅ NCCL environment variables unchanged
- ✅ RDMA/InfiniBand device configuration preserved
- ✅ Storage mounts and PVC references intact
- ✅ Training command and arguments unchanged
- ✅ Resource limits and requests preserved
- ✅ Node affinity and pod placement unchanged

## Training Continuity

**If you have training running:**
- Existing pods continue to work normally
- Checkpoints remain at `/mnt/tsfm/checkpoints/`
- No need to stop or restart training
- File reorganization does not affect running workloads

**To restart training:**
- Delete old StatefulSet: `oc delete statefulset tsfm-node`
- Apply from new location: `oc apply -f deployments/yunshi/generated/statefulset-yunshi.yaml`
- Training will resume from last checkpoint

## Storage and Data

**PVC unchanged:**
```bash
# Still uses the same persistent volume claim
oc get pvc tsfm
```

**Data paths unchanged:**
```
/mnt/tsfm/hybrid_tsfm/         # Code
/mnt/tsfm/data/                # Datasets
/mnt/tsfm/checkpoints/         # Model checkpoints
/mnt/tsfm/logs/                # Training logs
```

## Questions?

See:
- [README.md](README.md) - Full project documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [../../docs/rdma/](../../docs/rdma/) - RDMA setup documentation

## Summary

**Status**: ✅ Migration complete and safe

- File locations updated for better organization
- No changes to pod configurations or deployments
- Running training jobs not affected
- All features and functionality preserved
- Enhanced documentation added

The migration only affects where you find and deploy the files - the actual training setup, RDMA configuration, and resource allocation remain exactly the same.
