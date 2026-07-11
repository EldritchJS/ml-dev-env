# H-Kim File Organization - Migration Guide

All h-kim related files have been organized into `deployments/h-kim/` following the standard project structure.

## What Changed

### File Moves

| Old Location | New Location | Type |
|-------------|--------------|------|
| `k8s/statefulset-h-kim.yaml` | `deployments/h-kim/generated/statefulset-h-kim.yaml` | K8s |
| `k8s/pod-h-kim.yaml` | `deployments/h-kim/generated/pod-h-kim.yaml` | K8s |
| `k8s/job-h-kim-torchtitan.yaml` | `deployments/h-kim/generated/job-h-kim-torchtitan.yaml` | K8s |
| `k8s/imagestream-h-kim.yaml` | `deployments/h-kim/generated/imagestream-h-kim.yaml` | K8s |
| `k8s/buildconfig-h-kim.yaml` | `deployments/h-kim/generated/buildconfig-h-kim.yaml` | K8s |
| `h-kim-openshift.sh` | `deployments/h-kim/scripts/h-kim-openshift.sh` | Script |
| `h-kim.sh` | `deployments/h-kim/scripts/h-kim.sh` | Script |
| `lm-train.sh` | `deployments/h-kim/scripts/lm-train.sh` | Script |
| `lm-train.sh.backup` | `deployments/h-kim/scripts/lm-train.sh.backup` | Backup |
| `debug-rdma.sh` | `deployments/h-kim/scripts/debug-rdma.sh` | Script |
| `check-rdma.sh` | `deployments/h-kim/scripts/check-rdma.sh` | Script |
| `get-ib-devices.sh` | `deployments/h-kim/scripts/get-ib-devices.sh` | Script |
| `H-KIM-QUICKSTART.md` | `deployments/h-kim/docs/H-KIM-QUICKSTART.md` | Docs |
| `H-KIM-TEST-RESULTS.md` | `deployments/h-kim/docs/H-KIM-TEST-RESULTS.md` | Docs |
| `H-KIM-TORCHTITAN-GUIDE.md` | `deployments/h-kim/docs/H-KIM-TORCHTITAN-GUIDE.md` | Docs |
| `DEPLOY-H-KIM-IB-AUTODETECT.md` | `deployments/h-kim/docs/DEPLOY-H-KIM-IB-AUTODETECT.md` | Docs |
| `EXAMPLE-DEPLOY-H-KIM.md` | `deployments/h-kim/docs/EXAMPLE-DEPLOY-H-KIM.md` | Docs |
| `Dockerfile.nccl-autodetect` | `deployments/h-kim/Dockerfile.nccl-autodetect` | Build |
| `nccl_torch_bench.py` | `deployments/h-kim/nccl_torch_bench.py` | Tool |

### New Structure

```
deployments/h-kim/
├── README.md                      # Project overview (NEW)
├── QUICKSTART.md                  # Quick start guide (NEW)
├── MIGRATION.md                   # This file (NEW)
├── Dockerfile.nccl-autodetect     # Container image
├── nccl_torch_bench.py            # RDMA testing tool
├── generated/                     # K8s manifests
│   ├── statefulset-h-kim.yaml
│   ├── pod-h-kim.yaml
│   ├── job-h-kim-torchtitan.yaml
│   ├── imagestream-h-kim.yaml
│   └── buildconfig-h-kim.yaml
├── scripts/                       # All scripts
│   ├── h-kim-openshift.sh
│   ├── h-kim.sh
│   ├── lm-train.sh
│   ├── lm-train.sh.backup
│   ├── get-ib-devices.sh
│   ├── check-rdma.sh
│   └── debug-rdma.sh
├── docs/                          # Documentation
│   ├── H-KIM-QUICKSTART.md
│   ├── H-KIM-TORCHTITAN-GUIDE.md
│   ├── H-KIM-TEST-RESULTS.md
│   ├── DEPLOY-H-KIM-IB-AUTODETECT.md
│   └── EXAMPLE-DEPLOY-H-KIM.md
└── workspace/                     # Training workspace
```

## Impact on Existing Deployments

### ✅ No Breaking Changes

The h-kim pods themselves are **NOT affected** because:

1. **Container paths unchanged**: Files inside the container are at the same paths:
   - `/workspace/lm-train.sh` - Still works
   - `/workspace/check-rdma.sh` - Still works
   - `/workspace/get-ib-devices.sh` - Still works
   - `/workspace/nccl_torch_bench.py` - Still works

2. **Image builds unchanged**: The BuildConfig and ImageStream still reference the same Dockerfile content

3. **Running pods unaffected**: No need to restart or redeploy existing h-kim pods

### 📝 What You Need to Update

#### 1. Deployment Commands

**Old:**
```bash
oc apply -f k8s/statefulset-h-kim.yaml
```

**New:**
```bash
oc apply -f deployments/h-kim/generated/statefulset-h-kim.yaml
```

#### 2. Script References

**Old:**
```bash
./h-kim-openshift.sh
cat lm-train.sh
```

**New:**
```bash
./deployments/h-kim/scripts/h-kim-openshift.sh
cat deployments/h-kim/scripts/lm-train.sh
```

#### 3. Documentation Links

**Old:**
```bash
See H-KIM-QUICKSTART.md
```

**New:**
```bash
See deployments/h-kim/QUICKSTART.md
# or: deployments/h-kim/docs/H-KIM-QUICKSTART.md
```

#### 4. Build Commands

**Old:**
```bash
oc apply -f k8s/buildconfig-h-kim.yaml
oc apply -f k8s/imagestream-h-kim.yaml
```

**New:**
```bash
oc apply -f deployments/h-kim/generated/buildconfig-h-kim.yaml
oc apply -f deployments/h-kim/generated/imagestream-h-kim.yaml
```

## Quick Migration Checklist

- [x] Move all h-kim files to `deployments/h-kim/`
- [x] Create README.md with project overview
- [x] Create QUICKSTART.md with quick start guide
- [x] Create MIGRATION.md (this file)
- [x] Update docs/LM-TRAIN-USAGE.md references
- [ ] Update any custom scripts or automation
- [ ] Update any bookmarks or documentation links
- [ ] Notify team members of new structure

## Rollback (If Needed)

If you need to rollback to the old structure:

```bash
# Copy files back from deployments/h-kim/
cp deployments/h-kim/generated/*.yaml k8s/
cp deployments/h-kim/scripts/*.sh .
cp deployments/h-kim/docs/*.md .
cp deployments/h-kim/Dockerfile.nccl-autodetect .
cp deployments/h-kim/nccl_torch_bench.py .
```

## Benefits of New Structure

1. **Organization**: All h-kim files in one place
2. **Consistency**: Matches deployment wizard structure
3. **Clarity**: Clear separation of generated files, scripts, and docs
4. **Scalability**: Easy to add more deployments following the same pattern
5. **Discoverability**: Everything h-kim related under `deployments/h-kim/`

## Questions?

See:
- [README.md](README.md) - Project overview
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [docs/](docs/) - Detailed documentation

## References Still Working

These paths in the repo root still have h-kim information:
- `docs/LM-TRAIN-USAGE.md` - Updated to reference new paths
- `docs/H-KIM-RDMA-SETUP.md` - General RDMA setup guide
- `docs/rdma/` - RDMA implementation documentation
- `IB_AUTO_DETECTION.md` - InfiniBand auto-detection system

These are general RDMA/infrastructure docs and were intentionally left in place.
