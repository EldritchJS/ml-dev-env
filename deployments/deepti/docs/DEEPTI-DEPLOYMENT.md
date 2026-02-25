# Deepti Qwen2.5-Omni Deployment Guide

Quick guide for running `deepti.py` on NERC cluster with single node + 4 GPUs.

## Prerequisites

1. OpenShift CLI (`oc`) installed
2. Logged into NERC cluster:
   ```bash
   oc login api.shift.nerc.mghpcc.org
   ```
3. Access to namespace: `coops-767192`

## Quick Start

Deploy deepti.py test with a single command:

```bash
./scripts/deploy-deepti-nerc.sh
```

This script will:
- Create service account `ml-dev-sa` if needed
- Create ConfigMap with `deepti.py`
- Deploy pod with 4x H100 GPUs
- Stream logs in real-time

## What It Does

The deployment:
- Uses single node with **4x NVIDIA H100 GPUs**
- Installs `qwen-omni-utils` package at startup
- Runs the Qwen2.5-Omni test with flash-attention
- Creates a dummy video and tests multimodal inference

## Configuration

**Pod Specs:**
- Name: `deepti-test`
- Namespace: `coops-767192`
- GPUs: 4x H100 (single node)
- Memory: 128Gi request, 256Gi limit
- CPU: 32 cores request, 64 cores limit

**Network Mode:**
- TCP mode (NERC doesn't have RDMA)
- NVLink for intra-node GPU communication

## Monitoring

Check pod status:
```bash
oc get pod deepti-test -n coops-767192
```

View logs:
```bash
oc logs -f deepti-test -n coops-767192
```

Check which node it's running on:
```bash
oc get pod deepti-test -n coops-767192 -o wide
```

Describe pod (for debugging):
```bash
oc describe pod deepti-test -n coops-767192
```

## Cleanup

Delete the test pod:
```bash
oc delete pod deepti-test -n coops-767192
```

Delete ConfigMap:
```bash
oc delete configmap deepti-script -n coops-767192
```

## Troubleshooting

### Pod stuck in Pending

Check events:
```bash
oc describe pod deepti-test -n coops-767192
```

Common causes:
- No GPU nodes available
- Insufficient resources
- Service account permissions

### Pod fails with "ImagePullBackOff"

The container image needs to be built first:
```bash
# Check if image exists
oc get imagestream ml-dev-env -n nccl-test

# If not, build it
oc start-build ml-dev-env -n nccl-test --follow
```

### Import errors for qwen_omni_utils

The pod installs `qwen-omni-utils` at startup. Check logs:
```bash
oc logs deepti-test -n coops-767192 | grep -i "qwen-omni-utils"
```

If it fails to install, you can exec into the pod and install manually:
```bash
oc exec -it deepti-test -n coops-767192 -- bash
pip install qwen-omni-utils -U
```

## Advanced: Modifying deepti.py

1. Edit `deepti.py` locally
2. Redeploy (script will update ConfigMap automatically):
   ```bash
   ./scripts/deploy-deepti-nerc.sh
   ```

## Files

- `k8s/pod-deepti-nerc.yaml` - Pod configuration
- `scripts/deploy-deepti-nerc.sh` - Deployment script
- `deepti.py` - Test script
- `clusters/nerc-production.yaml` - NERC cluster config
