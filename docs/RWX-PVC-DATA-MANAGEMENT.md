# Managing Data on RWX PVCs

Guide for uploading, downloading, and managing data on ReadWriteMany (RWX) PersistentVolumeClaims.

## Overview

RWX PVCs (ReadWriteMany) allow multiple pods to mount the same storage simultaneously for read and write access. This is ideal for:
- Sharing training datasets across multiple pods
- Multi-node training with shared checkpoints
- Collaborative workflows where multiple users need access

**Example:** The `tsfm` PVC in the `b-ts-data-agent-0a0cee` namespace is a 3TiB RWX volume used by the HybridTSFM training pods.

---

## Method 1: Using a Data Pod (Recommended)

Create a temporary pod to mount the PVC and transfer data.

### Step 1: Create Data Pod

```yaml
# data-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: b-ts-data-agent-0a0cee  # Your namespace
spec:
  restartPolicy: Never
  containers:
  - name: data-container
    image: registry.access.redhat.com/ubi9/ubi:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: tsfm  # Your PVC name
```

Deploy the pod:
```bash
oc apply -f data-pod.yaml
oc wait --for=condition=Ready pod/data-pod -n b-ts-data-agent-0a0cee --timeout=60s
```

### Step 2: Upload Data

**Upload a single file:**
```bash
oc cp /local/path/to/file.tar.gz data-pod:/data/file.tar.gz -n b-ts-data-agent-0a0cee
```

**Upload a directory:**
```bash
oc cp /local/path/to/dataset/ data-pod:/data/datasets/ -n b-ts-data-agent-0a0cee
```

**Upload and extract archive:**
```bash
# Upload tar.gz
oc cp dataset.tar.gz data-pod:/data/ -n b-ts-data-agent-0a0cee

# Extract inside pod
oc exec data-pod -n b-ts-data-agent-0a0cee -- tar -xzf /data/dataset.tar.gz -C /data/
```

### Step 3: Download Data

**Download a file:**
```bash
oc cp data-pod:/data/checkpoints/model.pt /local/path/model.pt -n b-ts-data-agent-0a0cee
```

**Download a directory:**
```bash
oc cp data-pod:/data/logs/ /local/path/logs/ -n b-ts-data-agent-0a0cee
```

### Step 4: Verify and Cleanup

**List contents:**
```bash
oc exec data-pod -n b-ts-data-agent-0a0cee -- ls -lh /data/
```

**Check disk usage:**
```bash
oc exec data-pod -n b-ts-data-agent-0a0cee -- df -h /data
```

**Delete pod when done:**
```bash
oc delete pod data-pod -n b-ts-data-agent-0a0cee
```

---

## Method 2: Using rsync (Faster for Large Transfers)

Rsync is more efficient for large datasets and supports resuming interrupted transfers.

### Step 1: Create rsync Pod

```yaml
# rsync-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: rsync-pod
  namespace: b-ts-data-agent-0a0cee
spec:
  restartPolicy: Never
  containers:
  - name: rsync
    image: quay.io/centos/centos:stream9
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: tsfm
```

```bash
oc apply -f rsync-pod.yaml
oc wait --for=condition=Ready pod/rsync-pod -n b-ts-data-agent-0a0cee --timeout=60s
```

### Step 2: Install rsync in Pod

```bash
oc exec rsync-pod -n b-ts-data-agent-0a0cee -- dnf install -y rsync
```

### Step 3: Upload with rsync

```bash
# Upload directory with progress
oc rsync /local/path/to/dataset/ rsync-pod:/data/dataset/ \
  -n b-ts-data-agent-0a0cee \
  --progress \
  --no-perms

# Upload with compression (slower but uses less bandwidth)
oc rsync /local/path/to/dataset/ rsync-pod:/data/dataset/ \
  -n b-ts-data-agent-0a0cee \
  --compress \
  --progress
```

### Step 4: Download with rsync

```bash
# Download directory
oc rsync rsync-pod:/data/checkpoints/ /local/path/checkpoints/ \
  -n b-ts-data-agent-0a0cee \
  --progress \
  --no-perms
```

**Cleanup:**
```bash
oc delete pod rsync-pod -n b-ts-data-agent-0a0cee
```

---

## Method 3: Direct Access from Training Pods

If you already have training pods running with the PVC mounted, you can use them directly.

**Example with yunshi.yaml deployment:**

```bash
# Check which pods have the PVC mounted
oc get pods -n b-ts-data-agent-0a0cee -l app=tsfm-ddp

# Upload to running pod
oc cp /local/dataset.tar.gz tsfm-node-0:/mnt/tsfm/data/ -n b-ts-data-agent-0a0cee

# Shell into pod to verify
oc exec -it tsfm-node-0 -n b-ts-data-agent-0a0cee -- bash
ls -lh /mnt/tsfm/data/

# Download from running pod
oc cp tsfm-node-0:/mnt/tsfm/checkpoints/step_10000/ /local/checkpoints/ -n b-ts-data-agent-0a0cee
```

**Note:** Training pods mount at `/mnt/tsfm` in the yunshi.yaml configuration.

---

## Method 4: Using S3/Object Storage (For Very Large Datasets)

For datasets > 100GB, use object storage and download directly in pods.

### Step 1: Upload to S3

```bash
# Using AWS CLI (or rclone, s3cmd, etc.)
aws s3 cp dataset.tar.gz s3://your-bucket/datasets/ --region us-east-1
```

### Step 2: Download in Pod

Add download step to your pod startup script:

```yaml
# In yunshi.yaml or similar
args:
  - |
    echo "Downloading dataset from S3..."

    # Install AWS CLI if needed
    pip install awscli

    # Download dataset
    aws s3 cp s3://your-bucket/datasets/dataset.tar.gz /mnt/tsfm/data/ --region us-east-1

    # Extract
    tar -xzf /mnt/tsfm/data/dataset.tar.gz -C /mnt/tsfm/data/

    echo "Dataset ready. Starting training..."
    # ... rest of training script
```

**Alternative: Use rclone for multiple cloud providers:**

```bash
# Install rclone
curl https://rclone.org/install.sh | bash

# Configure (interactive)
rclone config

# Download
rclone copy remote:bucket/dataset /mnt/tsfm/data/ --progress
```

---

## Best Practices

### 1. Use Compression for Network Transfers

```bash
# Compress before upload
tar -czf dataset.tar.gz dataset/
oc cp dataset.tar.gz data-pod:/data/ -n namespace

# Extract in pod
oc exec data-pod -n namespace -- tar -xzf /data/dataset.tar.gz -C /data/
```

### 2. Check Available Space First

```bash
oc exec data-pod -n namespace -- df -h /data

# Expected output for 3TiB PVC:
# Filesystem      Size  Used Avail Use% Mounted on
# ...             3.0T  1.2T  1.8T  40% /data
```

### 3. Set Proper Permissions

RWX PVCs are shared across pods. Ensure files have correct permissions:

```bash
# Make directory writable by all pods
oc exec data-pod -n namespace -- chmod -R 775 /data/shared/

# Set ownership (if needed)
oc exec data-pod -n namespace -- chown -R 1001090000:1001090000 /data/
```

### 4. Organize Data Structure

```
/data/
├── datasets/           # Training data
│   ├── GiftEval/
│   ├── GiftPretrain/
│   └── kernel_synth_10M/
├── checkpoints/        # Model checkpoints
│   └── hybrid_tsfm/
├── logs/              # Training logs
└── code/              # Shared code/scripts
    └── hybrid_tsfm/
```

### 5. Use .gitignore Pattern for Large Files

Create a marker file to track what should be in the PVC:

```bash
# .pvc-contents.txt
datasets/GiftEval/       # 50GB
datasets/GiftPretrain/   # 120GB
datasets/kernel_synth/   # 800GB
checkpoints/            # Generated during training
logs/                   # Generated during training
```

### 6. Cleanup Old Data Regularly

```bash
# Find large files
oc exec data-pod -n namespace -- find /data -type f -size +1G -exec ls -lh {} \;

# Remove old checkpoints (keep last 3)
oc exec data-pod -n namespace -- bash -c '
  cd /data/checkpoints
  ls -t | tail -n +4 | xargs rm -rf
'

# Check space after cleanup
oc exec data-pod -n namespace -- df -h /data
```

---

## Troubleshooting

### "No space left on device"

```bash
# Check usage
oc exec data-pod -n namespace -- df -h /data

# Find what's using space
oc exec data-pod -n namespace -- du -sh /data/* | sort -hr | head -20

# Clean up
oc exec data-pod -n namespace -- rm -rf /data/old-data/
```

### "Permission denied"

```bash
# Check current permissions
oc exec data-pod -n namespace -- ls -la /data/

# Fix permissions
oc exec data-pod -n namespace -- chmod -R 775 /data/problematic-dir/
```

### Slow Transfer Speeds

```bash
# Use rsync instead of cp
oc rsync /local/data/ data-pod:/data/ -n namespace --progress

# Or compress data first
tar -czf data.tar.gz data/
oc cp data.tar.gz data-pod:/data/ -n namespace
```

### Connection Lost During Transfer

```bash
# Use rsync which supports resume
oc rsync /local/data/ rsync-pod:/data/ -n namespace --progress

# Or use screen/tmux for long transfers
screen
oc rsync /local/data/ rsync-pod:/data/ -n namespace --progress
# Ctrl+A, D to detach
# screen -r to reattach
```

---

## Quick Reference

```bash
# Create data pod
oc apply -f data-pod.yaml

# Upload file
oc cp /local/file data-pod:/data/file -n namespace

# Upload directory
oc cp /local/dir/ data-pod:/data/dir/ -n namespace

# Download file
oc cp data-pod:/data/file /local/file -n namespace

# List contents
oc exec data-pod -n namespace -- ls -lh /data/

# Check disk usage
oc exec data-pod -n namespace -- df -h /data

# Shell into pod
oc exec -it data-pod -n namespace -- bash

# Delete pod
oc delete pod data-pod -n namespace
```

---

## Example: Complete Workflow

Upload a dataset for HybridTSFM training:

```bash
# 1. Create data pod
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: data-upload
  namespace: b-ts-data-agent-0a0cee
spec:
  restartPolicy: Never
  containers:
  - name: data
    image: registry.access.redhat.com/ubi9/ubi:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: tsfm-storage
      mountPath: /data
  volumes:
  - name: tsfm-storage
    persistentVolumeClaim:
      claimName: tsfm
EOF

# 2. Wait for pod to start
oc wait --for=condition=Ready pod/data-upload -n b-ts-data-agent-0a0cee --timeout=60s

# 3. Check available space
oc exec data-upload -n b-ts-data-agent-0a0cee -- df -h /data

# 4. Upload compressed dataset
tar -czf kernel_synth.tar.gz kernel_synth_10M/
oc cp kernel_synth.tar.gz data-upload:/data/ -n b-ts-data-agent-0a0cee

# 5. Extract in pod
oc exec data-upload -n b-ts-data-agent-0a0cee -- tar -xzf /data/kernel_synth.tar.gz -C /data/

# 6. Verify
oc exec data-upload -n b-ts-data-agent-0a0cee -- ls -lh /data/kernel_synth_10M/

# 7. Cleanup
oc exec data-upload -n b-ts-data-agent-0a0cee -- rm /data/kernel_synth.tar.gz
oc delete pod data-upload -n b-ts-data-agent-0a0cee

# 8. Start training - data is now available to all pods
oc apply -f yunshi.yaml
```

---

## Related Documentation

- **[yunshi.yaml](../yunshi.yaml)** - TSFM training deployment that uses the tsfm PVC
- **[H-KIM-QUICKSTART.md](../H-KIM-QUICKSTART.md)** - ML environment setup guide
