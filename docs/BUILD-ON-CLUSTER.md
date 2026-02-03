# Building on OpenShift Cluster

> **⚠️ ADMIN/MAINTAINER ONLY**
> This guide is for administrators who need to build or update the container image.
> **Regular users do not need to build** - just use the pre-built image already in the cluster.
> See [QUICKSTART.md](QUICKSTART.md) for regular user deployment.

---

The ML development environment is designed to build **entirely on your OpenShift cluster** - no local Docker/Podman required!

## How It Works

### BuildConfig Architecture

```
┌─────────────────────────────────────────────────┐
│  Your Local Machine                             │
│                                                 │
│  $ make build                                   │
│  $ oc apply -f k8s/buildconfig.yaml             │
│      │                                           │
│      └─────────────────┐                        │
└────────────────────────┼────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────┐
│  OpenShift Cluster                              │
│                                                 │
│  ┌────────────────────────────────────────┐    │
│  │ BuildConfig Controller                 │    │
│  │  - Receives build request              │    │
│  │  - Creates build pod                   │    │
│  └────────────────────────────────────────┘    │
│                  │                              │
│                  ▼                              │
│  ┌────────────────────────────────────────┐    │
│  │ Build Pod (ml-dev-env-1-build)         │    │
│  │                                        │    │
│  │  1. Pull base: nvidia/cuda:12.1.0     │    │
│  │  2. Install apt packages               │    │
│  │  3. Install Python packages            │    │
│  │  4. Compile flash-attn (uses CUDA!)    │    │
│  │  5. Install VSCode server              │    │
│  │  6. Create entrypoint                  │    │
│  │                                        │    │
│  │  Build time: ~15-20 minutes            │    │
│  └────────────────────────────────────────┘    │
│                  │                              │
│                  ▼                              │
│  ┌────────────────────────────────────────┐    │
│  │ Internal Image Registry                │    │
│  │                                        │    │
│  │  image-registry.openshift-image-      │    │
│  │  registry.svc:5000/nccl-test/         │    │
│  │  ml-dev-env:latest                     │    │
│  └────────────────────────────────────────┘    │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Why Build on Cluster?

### ✅ Advantages

1. **No local Docker/Podman needed**
   - Just need `oc` CLI
   - Works from any machine

2. **CUDA compilation works correctly**
   - Build pods can access GPU libraries
   - flash-attn compiles properly with CUDA

3. **Better resources**
   - Cluster nodes have more CPU/RAM
   - Faster than most laptops

4. **Consistent environment**
   - Same architecture as runtime
   - No cross-platform issues (e.g., ARM Mac → x86 cluster)

5. **Integrated with OpenShift**
   - Image automatically available in internal registry
   - No need to push/pull from external registry
   - ImageStream tracks versions

6. **CI/CD ready**
   - Automated builds on config change
   - Webhook triggers available
   - Build history tracked

## Building the Image

### Method 1: Using Makefile (Recommended)

```bash
# Build with default namespace
make build

# Build with custom namespace
NAMESPACE=ml-team make build

# The build runs on cluster automatically
```

### Method 2: Using Deploy Script

```bash
# Build only
./scripts/deploy.sh build

# Or with custom namespace
NAMESPACE=my-namespace ./scripts/deploy.sh build
```

### Method 3: Manual oc Commands

```bash
# Create ImageStream
oc apply -f k8s/imagestream.yaml

# Start build
oc apply -f k8s/buildconfig.yaml

# Or start a new build manually
oc start-build ml-dev-env -n nccl-test
```

## Monitoring the Build

### Follow Build Logs

```bash
# Follow logs in real-time
oc logs -f bc/ml-dev-env -n nccl-test

# Or follow specific build
oc logs -f build/ml-dev-env-1 -n nccl-test
```

### Check Build Status

```bash
# List all builds
oc get builds -n nccl-test

# Get detailed info
oc describe build ml-dev-env-1 -n nccl-test

# Check build pod
oc get pods -n nccl-test | grep build
```

### Build Output

During build, you'll see:

```
Step 1/25: FROM nvcr.io/nvidia/cuda:12.1.0-devel-ubuntu22.04
Step 2/25: ENV DEBIAN_FRONTEND=noninteractive
Step 3/25: RUN apt-get update && apt-get install -y python3.10 ...
Step 4/25: RUN pip install torch==2.1.2 ...
Step 5/25: RUN pip install flash-attn --no-build-isolation
  Compiling CUDA kernels...  [This takes ~5-10 minutes]
Step 6/25: RUN pip install transformers deepspeed ...
...
Step 25/25: CMD ["tail", "-f", "/dev/null"]
Successfully tagged image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:latest
```

## Build Timing

Typical build times on cluster:

| Component | Time |
|-----------|------|
| Base image pull | 2-3 min |
| System packages | 1-2 min |
| PyTorch install | 3-4 min |
| flash-attn compile | 5-10 min |
| Other packages | 3-5 min |
| **Total** | **15-20 min** |

## Customizing Build Resources

If build fails with OOM (out of memory), increase resources by patching the BuildConfig:

```bash
# Patch BuildConfig to add resource limits
oc patch bc/ml-dev-env -n nccl-test -p '
{
  "spec": {
    "resources": {
      "limits": {
        "cpu": "8",
        "memory": "16Gi"
      },
      "requests": {
        "cpu": "4",
        "memory": "8Gi"
      }
    }
  }
}'

# Restart build
oc start-build ml-dev-env -n nccl-test
```

## Build Triggers

### Automatic Rebuild

BuildConfig has `ConfigChange` trigger - rebuilds when config changes:

```yaml
triggers:
  - type: ConfigChange
```

### Manual Rebuild

```bash
# Start new build
oc start-build ml-dev-env -n nccl-test

# Follow logs
oc logs -f bc/ml-dev-env -n nccl-test
```

### Scheduled Rebuilds

Add ImageChange trigger to rebuild when base image updates:

```yaml
triggers:
  - type: ConfigChange
  - type: ImageChange
    imageChange:
      from:
        kind: ImageStreamTag
        name: cuda:12.1.0-devel-ubuntu22.04
```

## Build Cache

OpenShift caches Docker layers to speed up subsequent builds:

```bash
# First build: 15-20 minutes
make build

# Rebuild after small change: 2-5 minutes
# (most layers cached)
make build
```

## Troubleshooting Builds

### Build Fails

```bash
# Check build logs
oc logs build/ml-dev-env-1 -n nccl-test

# Common issues:
# 1. OOM during flash-attn compilation
#    → Increase build resources

# 2. Network timeout pulling packages
#    → Retry build: oc start-build ml-dev-env

# 3. CUDA compilation errors
#    → Check base image CUDA version matches
```

### Build Stuck

```bash
# Check build pod
oc get pod -n nccl-test | grep build

# If stuck, delete and restart
oc delete build ml-dev-env-1 -n nccl-test
oc start-build ml-dev-env -n nccl-test
```

### Build Timeout

Default timeout is 10 minutes. For long builds (flash-attn):

```bash
# Increase timeout
oc patch bc/ml-dev-env -n nccl-test -p '
{
  "spec": {
    "completionDeadlineSeconds": 3600
  }
}'
```

## Image Location

After successful build, image is stored in:

```
image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:latest
```

### Accessing from Pods

Pods reference the image via ImageStream:

```yaml
spec:
  containers:
  - name: ml-dev
    image: image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:latest
```

The pod YAML already uses this format!

### Pulling Locally (Optional)

If you want to pull the image locally:

```bash
# Get registry route
oc get route default-route -n openshift-image-registry

# Login
docker login <registry-route>

# Pull
docker pull <registry-route>/nccl-test/ml-dev-env:latest
```

## Build History

```bash
# List all builds
oc get builds -n nccl-test

# Example output:
# NAME            TYPE     FROM      STATUS     STARTED         DURATION
# ml-dev-env-1    Docker   Binary    Complete   10 minutes ago  15m
# ml-dev-env-2    Docker   Binary    Complete   1 day ago       14m
# ml-dev-env-3    Docker   Binary    Failed     2 days ago      2m

# Get details of specific build
oc describe build ml-dev-env-1 -n nccl-test
```

## Advanced: Multi-Stage Builds

The inline Dockerfile in the BuildConfig uses multi-stage builds for optimization:

```dockerfile
FROM nvcr.io/nvidia/cuda:12.1.0-devel-ubuntu22.04 AS base
# Build stage with all compile tools

# Could add:
FROM base AS runtime
# Runtime stage with only runtime deps
```

Currently single-stage for simplicity, but can be optimized.

## Comparison: Cluster vs Local Build

| Aspect | Cluster Build | Local Build |
|--------|---------------|-------------|
| Requires Docker/Podman | ❌ No | ✅ Yes |
| CUDA compilation | ✅ Works | ⚠️ May fail |
| Build speed | ✅ Fast (cluster resources) | ⚠️ Depends on laptop |
| Cross-platform | ✅ Consistent | ❌ ARM Mac issues |
| CI/CD integration | ✅ Native | ⚠️ Requires setup |
| Image location | ✅ Internal registry | ❌ Must push |
| Network | ✅ Cluster bandwidth | ⚠️ Home internet |

**Verdict**: Cluster build is superior for this use case!

## Quick Reference

```bash
# Build
make build

# Monitor
oc logs -f bc/ml-dev-env -n nccl-test

# Status
oc get builds -n nccl-test

# Rebuild
oc start-build ml-dev-env -n nccl-test

# Increase resources (if build fails with OOM)
oc patch bc/ml-dev-env -n nccl-test -p '{"spec":{"resources":{"limits":{"cpu":"8","memory":"16Gi"}}}}'

# Delete build
oc delete build ml-dev-env-1 -n nccl-test

# Check image
oc get imagestream ml-dev-env -n nccl-test
```

## Summary

✅ **Builds entirely on OpenShift cluster**
✅ **No local Docker/Podman needed**
✅ **Just run `make build`**
✅ **Takes 15-20 minutes**
✅ **Image automatically available in cluster**
✅ **Ready to deploy with `make deploy`**

The cluster build approach is simpler, faster, and more reliable than local builds!
