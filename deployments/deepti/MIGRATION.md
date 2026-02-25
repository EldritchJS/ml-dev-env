# Deepti File Organization - Migration Guide

All deepti related files have been organized into `deployments/deepti/` following the standard project structure.

## What Changed

### File Moves

| Old Location | New Location | Type |
|-------------|--------------|------|
| `k8s/pod-deepti-barcelona.yaml` | `deployments/deepti/generated/pod-deepti-barcelona.yaml` | K8s Pod |
| `k8s/pod-deepti-barcelona-pytorch28.yaml` | `deployments/deepti/generated/pod-deepti-barcelona-pytorch28.yaml` | K8s Pod |
| `k8s/pod-deepti-barcelona-pytorch29.yaml` | `deployments/deepti/generated/pod-deepti-barcelona-pytorch29.yaml` | K8s Pod |
| `k8s/pod-deepti-nerc.yaml` | `deployments/deepti/generated/pod-deepti-nerc.yaml` | K8s Pod |
| `k8s/pod-deepti-nerc-pytorch29.yaml` | `deployments/deepti/generated/pod-deepti-nerc-pytorch29.yaml` | K8s Pod |
| `k8s/pod-deepti-nerc-pytorch29-test.yaml` | `deployments/deepti/generated/pod-deepti-nerc-pytorch29-test.yaml` | K8s Pod |
| `k8s/pod-debug-deepti-nerc.yaml` | `deployments/deepti/generated/pod-debug-deepti-nerc.yaml` | K8s Pod |
| `scripts/deploy-deepti-barcelona.sh` | `deployments/deepti/scripts/deploy-deepti-barcelona.sh` | Script |
| `scripts/deploy-deepti-nerc.sh` | `deployments/deepti/scripts/deploy-deepti-nerc.sh` | Script |
| `deepti.py` | `deployments/deepti/workspace/deepti.py` | Test script |
| `deepti-simple.py` | `deployments/deepti/workspace/deepti-simple.py` | Test script |
| `deepti-test.txt` | `deployments/deepti/workspace/deepti-test.txt` | Test output |

### New Structure

```
deployments/deepti/
├── README.md                           # Project overview (NEW)
├── QUICKSTART.md                       # Quick start guide (NEW)
├── MIGRATION.md                        # This file (NEW)
├── generated/                          # K8s manifests
│   ├── pod-deepti-barcelona.yaml
│   ├── pod-deepti-barcelona-pytorch28.yaml
│   ├── pod-deepti-barcelona-pytorch29.yaml
│   ├── pod-deepti-nerc.yaml
│   ├── pod-deepti-nerc-pytorch29.yaml
│   ├── pod-deepti-nerc-pytorch29-test.yaml
│   └── pod-debug-deepti-nerc.yaml
├── scripts/                            # Deployment scripts
│   ├── deploy-deepti-barcelona.sh
│   └── deploy-deepti-nerc.sh
├── docs/                               # Documentation (empty, for future use)
└── workspace/                          # Test scripts and outputs
    ├── deepti.py
    ├── deepti-simple.py
    └── deepti-test.txt
```

## Impact on Existing Deployments

### ✅ No Breaking Changes

The deepti pods themselves are **NOT affected** because:

1. **Kubernetes resources unchanged**: The YAML content is identical, only the file location changed
2. **Pod configurations intact**: All environment variables, resources, and settings remain the same
3. **Test scripts preserved**: Scripts moved to workspace/ but content unchanged
4. **Running pods unaffected**: No need to restart or redeploy existing deepti test pods

### 📝 What You Need to Update

#### 1. Deployment Commands

**Old:**
```bash
oc apply -f k8s/pod-deepti-barcelona.yaml
oc apply -f k8s/pod-deepti-nerc.yaml
```

**New:**
```bash
oc apply -f deployments/deepti/generated/pod-deepti-barcelona.yaml
oc apply -f deployments/deepti/generated/pod-deepti-nerc.yaml
```

#### 2. Script References

**Old:**
```bash
./scripts/deploy-deepti-barcelona.sh
./scripts/deploy-deepti-nerc.sh
```

**New:**
```bash
./deployments/deepti/scripts/deploy-deepti-barcelona.sh
./deployments/deepti/scripts/deploy-deepti-nerc.sh
```

#### 3. Test Script Paths

**Old:**
```bash
cat deepti.py
python deepti-simple.py
```

**New:**
```bash
cat deployments/deepti/workspace/deepti.py
python deployments/deepti/workspace/deepti-simple.py
```

#### 4. Documentation Links

Update any references to deepti configuration files to point to the new location under `deployments/deepti/`.

## Quick Migration Checklist

- [x] Move all pod YAML files to deployments/deepti/generated/
- [x] Move deploy scripts to deployments/deepti/scripts/
- [x] Move test scripts to deployments/deepti/workspace/
- [x] Create README.md with project overview
- [x] Create QUICKSTART.md with usage guide
- [x] Create MIGRATION.md (this file)
- [ ] Update any custom scripts that reference old paths
- [ ] Update bookmarks or documentation links
- [ ] Notify team members of new structure

## Rollback (If Needed)

If you need to rollback to the old structure:

```bash
# Copy pod files back
cp deployments/deepti/generated/*.yaml k8s/

# Copy scripts back
cp deployments/deepti/scripts/*.sh scripts/

# Copy test scripts back
cp deployments/deepti/workspace/deepti*.py .
cp deployments/deepti/workspace/deepti-test.txt .
```

## Benefits of New Structure

1. **Organization**: All deepti files in one logical location
2. **Consistency**: Matches h-kim and yunshi deployment structures
3. **Clarity**: Clear separation of generated files, scripts, and workspace
4. **Discoverability**: Easy to find all deepti-related resources
5. **Scalability**: Easy to add docs, additional scripts, and test data
6. **Documentation**: Comprehensive guides for new users

## File Descriptions

### Generated Manifests

**pod-deepti-barcelona.yaml**
- Main test pod for Barcelona cluster
- RDMA/InfiniBand enabled
- Latest stable configuration
- Recommended for Barcelona

**pod-deepti-barcelona-pytorch{28,29}.yaml**
- Specific PyTorch version variants
- Use for version-specific testing

**pod-deepti-nerc.yaml**
- Main test pod for NERC cluster
- Standard GPU networking
- Latest stable configuration
- Recommended for NERC

**pod-deepti-nerc-pytorch29{,-test}.yaml**
- PyTorch 2.9 specific variants
- Test variant for experimental features

**pod-debug-deepti-nerc.yaml**
- Debug pod with enhanced logging
- For troubleshooting issues

### Scripts

**deploy-deepti-barcelona.sh**
- Automated deployment to Barcelona cluster
- Handles namespace and image selection
- Validates prerequisites

**deploy-deepti-nerc.sh**
- Automated deployment to NERC cluster
- Handles namespace and image selection
- Validates prerequisites

### Workspace

**deepti.py**
- Full multimodal test script
- Creates dummy video
- Loads Qwen2.5-Omni-7B
- Tests video understanding

**deepti-simple.py**
- Simplified validation test
- Quick iteration testing

**deepti-test.txt**
- Sample test output
- Reference for expected results

## Deployment Workflow

### Barcelona Cluster
```bash
cd deployments/deepti

# Using manifest
oc apply -f generated/pod-deepti-barcelona.yaml

# Using script
./scripts/deploy-deepti-barcelona.sh

# Monitor
oc logs -f deepti-test
```

### NERC Cluster
```bash
cd deployments/deepti

# Using manifest
oc apply -f generated/pod-deepti-nerc.yaml

# Using script
./scripts/deploy-deepti-nerc.sh

# Monitor
oc logs -f deepti-test
```

## Configuration Files Preserved

All configuration in the YAML files remains identical:

- ✅ GPU resource requests unchanged (4 GPUs)
- ✅ NCCL environment variables preserved (Barcelona)
- ✅ Memory/CPU limits intact
- ✅ Container images unchanged
- ✅ Service account references preserved
- ✅ Node selectors unchanged

## Test Continuity

**If you have tests running:**
- Existing pods continue to work normally
- No need to stop or restart tests
- File reorganization does not affect running workloads

**To run new tests:**
- Delete old pod: `oc delete pod deepti-test`
- Apply from new location: `oc apply -f deployments/deepti/generated/pod-deepti-barcelona.yaml`
- Tests run with same configuration

## Questions?

See:
- [README.md](README.md) - Full project documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [../../docs/rdma/](../../docs/rdma/) - RDMA setup documentation (for Barcelona)

## Summary

**Status**: ✅ Migration complete and safe

- File locations updated for better organization
- No changes to pod configurations or deployments
- Running test pods not affected
- All features and functionality preserved
- Enhanced documentation added

The migration only affects where you find and deploy the files - the actual test setup, model configuration, and resource allocation remain exactly the same.

## Comparison with Other Deployments

### Deepti vs H-Kim/Yunshi

| Feature | Deepti | H-Kim | Yunshi |
|---------|--------|-------|--------|
| **Type** | Single-node test | Multi-node training | Multi-node training |
| **Purpose** | Model validation | General ML training | Time series training |
| **Pods** | 1 pod | 2 pods (StatefulSet) | 2 pods (StatefulSet) |
| **GPUs** | 4 GPUs | 8 GPUs (2x4) | 8 GPUs (2x4) |
| **Networking** | Standard/RDMA | RDMA (required) | RDMA (required) |
| **Duration** | Short (test run) | Long (training) | Long (training) |
| **Restart Policy** | Never | Always | Always |

All three follow the same directory structure for consistency!
