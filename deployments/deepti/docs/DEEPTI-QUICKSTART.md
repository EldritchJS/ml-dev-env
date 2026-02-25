# Deepti Group - Qwen2.5-Omni Testing Quick Start Guide

Welcome! This guide will help you run and debug the Qwen2.5-Omni multimodal model on the NERC Production cluster.

## Your Environment

- **Cluster:** NERC Production (shift.nerc.mghpcc.org)
- **Namespace:** `mllm-interpretation-and-failure-investigation-c8fa7f`
- **GPUs:** 4x NVIDIA H100 80GB HBM3 per pod
- **Image:** `quay.io/jschless/ml-dev-env:pytorch-2.9-numpy2` (12.1 GB)
  - PyTorch 2.9 with Flash-Attention 2.7.4.post1
  - NumPy 2.2.6 (fully tested and compatible)
  - All necessary ML libraries pre-installed

## Prerequisites

1. **Cluster Access:** You need to be logged into the NERC Production cluster
   ```bash
   oc login https://api.shift.nerc.mghpcc.org:6443
   oc project mllm-interpretation-and-failure-investigation-c8fa7f
   ```

2. **VSCode (for debugging):** Install Visual Studio Code with the Python extension
   - Download: https://code.visualstudio.com/
   - Install Python extension from Extensions marketplace

## Quick Start - Running the Test

### Option 1: Run the Test Once (Simplest)

This runs the Qwen2.5-Omni test and exits when complete:

```bash
# From the ml-dev-env directory
oc create configmap deepti-script --from-file=deepti.py=./deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f

oc apply -f k8s/pod-deepti-nerc.yaml
```

**Monitor the test:**
```bash
# Watch pod status
oc get pod deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f

# View logs
oc logs -f deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**Expected output:** The test loads the Qwen2.5-Omni model and generates a description of a test video pattern. Should complete in 2-3 minutes.

**Cleanup:**
```bash
oc delete pod deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f
```

---

## Remote Debugging with VSCode

Want to step through the code, inspect variables, or modify behavior? Use remote debugging!

### Step 1: Create Debug Pod

This creates a pod that runs deepti.py with debugpy and waits for VSCode to connect:

```bash
# Create the debug pod
oc apply -f k8s/pod-debug-deepti-nerc.yaml

# Wait for it to start (usually 30-60 seconds)
oc get pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f

# Check that debugpy is ready
oc logs deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
# Should show: "Starting debugpy server on port 5678..."
```

### Step 2: Start Port Forwarding

In a **new terminal window**, run:

```bash
oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
```

Keep this running! This connects your local machine to the debug port on the cluster.

### Step 3: Open Project in VSCode

```bash
cd /path/to/ml-dev-env
code .
```

The project already has the debugging configuration in `.vscode/launch.json`.

### Step 4: Set Breakpoints

1. Open `deepti.py` in VSCode
2. Click in the left margin (gutter) next to line numbers to set breakpoints

**Useful breakpoint locations:**
- **Line 70:** Right before model loads - inspect configuration
- **Line 77:** After model loads - check GPU memory usage
- **Line 128:** Before model.generate() - inspect inputs
- **Line 144:** After generation - inspect model outputs

### Step 5: Connect Debugger

1. Click the **Run and Debug** icon (or press `Cmd+Shift+D` / `Ctrl+Shift+D`)
2. From the dropdown at top, select: **"Debug Deepti (Remote - NERC Production)"**
3. Click the green **Start Debugging** button (or press `F5`)

**VSCode will connect to the pod and start running the code!**

When it hits a breakpoint, execution pauses. You can:

### Debugging Controls

- **F10** - Step Over (execute current line, stay at current level)
- **F11** - Step Into (enter function calls)
- **Shift+F11** - Step Out (exit current function)
- **F5** - Continue (run until next breakpoint)
- **Shift+F5** - Stop Debugging

### Debug Console

At the bottom, the **Debug Console** lets you run Python commands **while the code is paused**:

```python
# Check GPU memory usage
>>> import torch
>>> torch.cuda.memory_allocated(0) / 1024**3  # GB on GPU 0

# Inspect variables
>>> input_ids.shape
>>> type(model)

# Check all GPUs
>>> for i in range(4):
...     print(f"GPU {i}: {torch.cuda.memory_allocated(i) / 1024**3:.2f} GB")

# Modify variables (for testing)
>>> max_new_tokens = 50  # Change generation length
```

### What to Debug

**Model Loading (Line 70-77):**
- Inspect `MODEL_NAME`
- Check GPU placement: `next(model.parameters()).device`
- Monitor memory: `torch.cuda.memory_allocated(0)`

**Input Processing (Line 118-126):**
- Check `messages` structure
- Inspect `text` content after processing
- View `input_ids` shape

**Model Generation (Line 128):**
- Step into `model.generate()` to see how flash-attention is used
- Monitor GPU memory during generation
- Modify generation parameters

**Output Processing (Line 144-148):**
- Inspect `output_ids`
- Check decoded `response`

### Step 6: Cleanup When Done

Stop debugging in VSCode (`Shift+F5`), then:

```bash
# Stop port forwarding (Ctrl+C in the terminal running it)

# Delete debug pod
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
```

---

## Troubleshooting

### Pod Won't Start

**Check quota:**
```bash
oc describe quota -n mllm-interpretation-and-failure-investigation-c8fa7f
```

The namespace has limits:
- CPU: 32 cores
- Memory: 60 GB
- GPUs: 10

If quota exceeded, delete other pods first:
```bash
oc get pods -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete pod <pod-name> -n mllm-interpretation-and-failure-investigation-c8fa7f
```

### Debugger Won't Connect

1. **Check pod is running:**
   ```bash
   oc get pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

2. **Check debugpy is listening:**
   ```bash
   oc logs deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```
   Should show: "Starting debugpy server on port 5678..."

3. **Check port forwarding is running:**
   ```bash
   nc -zv localhost 5678
   ```
   Should show: "Connection to localhost port 5678 succeeded!"

4. **Restart port forwarding if needed:**
   ```bash
   # Kill existing port forward
   pkill -f "port-forward deepti-debug"

   # Start new one
   oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

### Code Changes Not Showing

#### Option 1: Automated Sync with Makefile (Recommended)

For faster iteration, use the Makefile to automatically sync code changes:

**Setup (one-time):**
```bash
# Configure for Deepti project
export NAMESPACE=mllm-interpretation-and-failure-investigation-c8fa7f
export POD_NAME=deepti-debug
export LOCAL_DIR=.
export REMOTE_DIR=/workspace
export DEBUG_PORT=5678

# Or create a .env file for persistence
cat > .env.deepti <<EOF
NAMESPACE=mllm-interpretation-and-failure-investigation-c8fa7f
POD_NAME=deepti-debug
LOCAL_DIR=.
REMOTE_DIR=/workspace
DEBUG_PORT=5678
EOF

# Load it
source .env.deepti
```

**Sync code once:**
```bash
# One-time sync of current code
make sync-once
```

**Auto-sync on file changes:**
```bash
# Watch for changes and auto-sync (runs continuously)
make sync-code
```

This watches your local files and automatically syncs changes to the pod every 2 seconds. Leave it running in a separate terminal while you code!

**Full dev session (sync + port-forward):**
```bash
# Start everything in one command
make dev-session
```

This will:
1. Sync code to the pod
2. Start port forwarding on port 5678
3. Keep watching for file changes

**Port forwarding only:**
```bash
# Just port-forward (if already synced)
make port-forward
```

**Quick reference:**
```bash
# Terminal 1: Start auto-sync
source .env.deepti
make sync-code

# Terminal 2: Port-forward for debugging
source .env.deepti
make port-forward

# Then connect VSCode debugger (F5)
```

#### Option 2: Manual ConfigMap Update

If you prefer the ConfigMap approach:

```bash
# 1. Edit deepti.py locally

# 2. Update ConfigMap
oc delete configmap deepti-script -n mllm-interpretation-and-failure-investigation-c8fa7f
oc create configmap deepti-script --from-file=deepti.py=./deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f

# 3. Restart pod
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
oc apply -f k8s/pod-debug-deepti-nerc.yaml

# 4. Restart port forwarding
oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**Comparison:**

| Feature | Makefile Sync | ConfigMap |
|---------|--------------|-----------|
| Speed | Fast (2 sec sync) | Slow (requires pod restart) |
| Auto-sync | ✅ Yes | ❌ No |
| Setup | One-time env vars | None |
| Downtime | None | Pod restart required |
| Best for | Active development | One-off tests |

### Out of Memory

If the pod runs out of memory, you can reduce GPU usage:

Edit the pod YAML to request fewer GPUs:
```yaml
resources:
  requests:
    nvidia.com/gpu: 2  # Use 2 instead of 4
```

Also update `CUDA_VISIBLE_DEVICES` to match:
```yaml
env:
- name: CUDA_VISIBLE_DEVICES
  value: "0,1"  # Match GPU count
```

---

## What's in the Code (deepti.py)

The test script does the following:

1. **Creates a test video** using ffmpeg (224x224, color bars pattern)
2. **Loads Qwen2.5-Omni model** (7B parameters)
   - Uses Flash-Attention 2 for optimized inference
   - Loads across 4 GPUs with `device_map="auto"`
3. **Prepares input** with the test video
4. **Generates description** using the model
5. **Prints output** - should describe the test pattern

**Expected runtime:** 2-3 minutes total
- Model download (first time only): ~1 minute
- Model loading: ~30 seconds
- Inference: ~30 seconds

---

## Managing Data with Shared Storage

For working with your own videos or sharing datasets across multiple test runs, you can use a shared PersistentVolumeClaim (PVC).

### When You Need Shared Storage

- Testing with your own video files
- Sharing datasets across multiple pods
- Storing model checkpoints for fine-tuning
- Managing large video collections

### Creating a Data Pod

Create a temporary pod to upload/download data:

```bash
# Create data-pod.yaml
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: deepti-data
  namespace: mllm-interpretation-and-failure-investigation-c8fa7f
spec:
  restartPolicy: Never
  containers:
  - name: data
    image: registry.access.redhat.com/ubi9/ubi:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: shared-data
      mountPath: /data
  volumes:
  - name: shared-data
    persistentVolumeClaim:
      claimName: deepti-videos  # Your PVC name
EOF

# Wait for pod to start
oc wait --for=condition=Ready pod/deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f --timeout=60s
```

### Upload Your Videos

**Single video:**
```bash
oc cp /local/path/video.mp4 deepti-data:/data/videos/ -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**Multiple videos (directory):**
```bash
oc cp /local/videos/ deepti-data:/data/videos/ -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**Large dataset (compressed):**
```bash
# Compress locally
tar -czf videos.tar.gz videos/

# Upload
oc cp videos.tar.gz deepti-data:/data/ -n mllm-interpretation-and-failure-investigation-c8fa7f

# Extract in pod
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  tar -xzf /data/videos.tar.gz -C /data/
```

### Download Data from URLs

Download datasets or videos directly from the internet to the PVC (faster than downloading locally then uploading):

**Using wget:**
```bash
# Download single file
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  wget -P /data/videos/ https://example.com/video.mp4

# Download with progress and resume support
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  wget -c --progress=bar:force https://example.com/large-dataset.tar.gz -O /data/dataset.tar.gz
```

**Using curl:**
```bash
# Download file
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  curl -L -o /data/videos/video.mp4 https://example.com/video.mp4

# Download with progress bar
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  curl -# -L -o /data/dataset.tar.gz https://example.com/dataset.tar.gz
```

**Using Python (for complex downloads):**
```bash
# Install Python packages if needed
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  pip install requests tqdm

# Download with progress bar
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  python3 -c "
import requests
from tqdm import tqdm

url = 'https://example.com/large-file.mp4'
output = '/data/videos/video.mp4'

response = requests.get(url, stream=True)
total_size = int(response.headers.get('content-length', 0))

with open(output, 'wb') as f, tqdm(total=total_size, unit='B', unit_scale=True) as pbar:
    for chunk in response.iter_content(chunk_size=8192):
        f.write(chunk)
        pbar.update(len(chunk))
"
```

**Download and extract in one step:**
```bash
# Download and extract tar.gz
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  bash -c "wget -O- https://example.com/dataset.tar.gz | tar -xzf - -C /data/"

# Download and extract zip
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  bash -c "curl -L https://example.com/dataset.zip -o /tmp/dataset.zip && \
           unzip /tmp/dataset.zip -d /data/ && \
           rm /tmp/dataset.zip"
```

**Download from Google Drive (public files):**
```bash
# Install gdown
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  pip install gdown

# Download file (replace FILE_ID with your Google Drive file ID)
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  gdown https://drive.google.com/uc?id=FILE_ID -O /data/videos/video.mp4

# Download entire folder
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  gdown --folder https://drive.google.com/drive/folders/FOLDER_ID -O /data/datasets/
```

**Download Hugging Face datasets:**
```bash
# Install huggingface-hub
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  pip install huggingface-hub

# Download model or dataset
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='username/dataset-name',
    repo_type='dataset',
    local_dir='/data/datasets/my-dataset'
)
"
```

### Verify Upload

```bash
# List files
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- ls -lh /data/videos/

# Check disk space
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- df -h /data
```

**💡 Tip:** For easier browsing, consider deploying the [Visual File Browser](#visual-file-browser-for-pvcs) to view PVC contents in your web browser instead of using terminal commands.

### Using Shared Data in Test Pods

Update your pod YAML to mount the PVC:

```yaml
# In k8s/pod-deepti-nerc.yaml, add:
volumes:
- name: shared-data
  persistentVolumeClaim:
    claimName: deepti-videos

# And in containers volumeMounts:
volumeMounts:
- name: shared-data
  mountPath: /data
```

Then update `deepti.py` to use the shared video:

```python
# Use video from shared storage
VIDEO_PATH = "/data/videos/my-test-video.mp4"

# Comment out the ffmpeg generation section
```

### Download Results

**Download checkpoints or outputs:**
```bash
# Download single file
oc cp deepti-data:/data/checkpoints/model.pt /local/path/ -n mllm-interpretation-and-failure-investigation-c8fa7f

# Download directory
oc cp deepti-data:/data/outputs/ /local/outputs/ -n mllm-interpretation-and-failure-investigation-c8fa7f
```

### Cleanup

```bash
# Delete data pod (PVC data persists)
oc delete pod deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f

# Delete specific files
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  rm -rf /data/old-videos/
```

### Quick Reference

```bash
# Upload video
oc cp video.mp4 deepti-data:/data/videos/ -n mllm-interpretation-and-failure-investigation-c8fa7f

# List contents
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- ls -lh /data/

# Check space
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- df -h /data

# Download results
oc cp deepti-data:/data/outputs/ /local/ -n mllm-interpretation-and-failure-investigation-c8fa7f

# Delete pod
oc delete pod deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f
```

---

## Visual File Browser for PVCs

For easier browsing and downloading of files from your PVCs, you can deploy a web-based file browser.

### Why Use a File Browser?

Instead of using `oc exec` and `ls` commands repeatedly, a file browser provides:
- Web-based interface to browse directories
- Click to download individual files
- View file sizes and modification times
- No terminal commands needed

### Deploy File Browser

**1. Edit the configuration:**

```bash
# Edit k8s/pvc-filebrowser.yaml
# Replace YOUR-PVC-NAME with your actual PVC name (e.g., dahye-test)
sed 's/YOUR-PVC-NAME/dahye-test/' k8s/pvc-filebrowser.yaml > /tmp/pvc-filebrowser-dahye.yaml
```

**2. Deploy to your namespace:**

```bash
oc apply -f /tmp/pvc-filebrowser-dahye.yaml -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**3. Wait for it to start:**

```bash
# Check pod status
oc get pods -l app=pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f

# Wait until STATUS shows "Running"
```

**4. Get the URL:**

```bash
oc get route pvc-browser -n mllm-interpretation-and-failure-investigation-c8fa7f -o jsonpath='https://{.spec.host}' && echo
```

**5. Open in your browser:**

Copy the URL from step 4 and open it in your web browser. You'll see a directory listing of your PVC contents.

### Using the File Browser

- **Browse directories:** Click on folder names to navigate
- **Download files:** Click on any file name to download it
- **View details:** See file sizes and modification times in the listing
- **Go up:** Use the parent directory link to navigate up

**Note:** This is a read-only browser - you can view and download files, but not upload or modify them through the web interface.

### Browse Multiple PVCs

To browse multiple PVCs at once, edit the deployment to add more volume mounts:

```yaml
# In k8s/pvc-filebrowser.yaml
volumeMounts:
- name: pvc1
  mountPath: /data/pvc1
- name: pvc2
  mountPath: /data/pvc2

volumes:
- name: pvc1
  persistentVolumeClaim:
    claimName: dahye-test
- name: pvc2
  persistentVolumeClaim:
    claimName: deepti-videos
```

Then access `/data/pvc1/` and `/data/pvc2/` in the browser.

### Cleanup

When you're done browsing:

```bash
oc delete deployment pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete service pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete route pvc-browser -n mllm-interpretation-and-failure-investigation-c8fa7f
```

Or simply delete everything with the label:

```bash
oc delete all -l app=pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete route pvc-browser -n mllm-interpretation-and-failure-investigation-c8fa7f
```

### Quick Reference

```bash
# Deploy (replace PVC name first!)
sed 's/YOUR-PVC-NAME/dahye-test/' k8s/pvc-filebrowser.yaml > /tmp/pvc-filebrowser-dahye.yaml
oc apply -f /tmp/pvc-filebrowser-dahye.yaml -n mllm-interpretation-and-failure-investigation-c8fa7f

# Get URL
oc get route pvc-browser -n mllm-interpretation-and-failure-investigation-c8fa7f -o jsonpath='https://{.spec.host}' && echo

# Check status
oc get pods -l app=pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f

# Cleanup
oc delete all -l app=pvc-filebrowser -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete route pvc-browser -n mllm-interpretation-and-failure-investigation-c8fa7f
```

---

## Advanced: Customizing the Test

### Use Your Own Video

Edit `deepti.py` and change the video path:

```python
# Instead of generating dummy video, use your video:
VIDEO_PATH = "/path/to/your/video.mp4"

# Comment out the ffmpeg generation section (lines 28-45)
```

Mount your video into the pod by adding a volume.

### Change the Prompt

Edit the `messages` variable (around line 118):

```python
messages = [
    {
        "role": "user",
        "content": [
            {"type": "video", "video": VIDEO_PATH},
            {"type": "text", "text": "Your custom prompt here"},
        ],
    }
]
```

### Adjust Generation Parameters

Around line 128, modify generation settings:

```python
output_ids = model.generate(
    **text,
    max_new_tokens=256,  # Increase for longer responses
    do_sample=True,       # Enable sampling
    temperature=0.7,      # Control randomness (0.0-1.0)
    top_p=0.9,           # Nucleus sampling
)
```

---

## Additional Documentation

For more details, see:

- **[IMAGE-INFO.md](IMAGE-INFO.md)** - Full details about the ml-dev-env container image
- **[REMOTE-DEBUG-GUIDE.md](REMOTE-DEBUG-GUIDE.md)** - Comprehensive debugging guide with examples
- **[clusters/nerc-production.yaml](clusters/nerc-production.yaml)** - Cluster configuration reference

---

## Need Help?

**Check pod status:**
```bash
oc describe pod <pod-name> -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**View pod logs:**
```bash
oc logs <pod-name> -n mllm-interpretation-and-failure-investigation-c8fa7f
```

**Interactive shell (for debugging):**
```bash
oc exec -it <pod-name> -n mllm-interpretation-and-failure-investigation-c8fa7f -- /bin/bash
```

**Check available resources:**
```bash
oc get nodes -l nvidia.com/gpu.present=true
oc describe quota -n mllm-interpretation-and-failure-investigation-c8fa7f
```

---

## Summary - Common Commands

### Using Makefile (Recommended for Development)

```bash
# One-time setup
cat > .env.deepti <<EOF
NAMESPACE=mllm-interpretation-and-failure-investigation-c8fa7f
POD_NAME=deepti-debug
LOCAL_DIR=.
REMOTE_DIR=/workspace
DEBUG_PORT=5678
EOF
source .env.deepti

# Deploy debug pod
oc apply -f k8s/pod-debug-deepti-nerc.yaml

# Option 1: Full dev session (auto-sync + port-forward)
make dev-session

# Option 2: Manual control
# Terminal 1: Auto-sync code changes
make sync-code

# Terminal 2: Port-forward
make port-forward

# Then connect VSCode debugger (F5)
```

### Using Direct Commands

```bash
# Quick test run (one-time execution)
oc create configmap deepti-script --from-file=deepti.py=./deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f
oc apply -f k8s/pod-deepti-nerc.yaml
oc logs -f deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f

# Debug session (manual sync)
oc apply -f k8s/pod-debug-deepti-nerc.yaml
oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
# Then connect VSCode debugger (F5)

# Update code (manual)
oc delete configmap deepti-script -n mllm-interpretation-and-failure-investigation-c8fa7f
oc create configmap deepti-script --from-file=deepti.py=./deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
oc apply -f k8s/pod-debug-deepti-nerc.yaml

# Cleanup
oc delete pod deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
```

### Data Management

```bash
# Upload video
oc cp video.mp4 deepti-data:/data/videos/ -n mllm-interpretation-and-failure-investigation-c8fa7f

# Download from URL
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- \
  wget -P /data/videos/ https://example.com/video.mp4

# Download results
oc cp deepti-data:/data/outputs/ /local/ -n mllm-interpretation-and-failure-investigation-c8fa7f
```

Happy testing! 🚀
