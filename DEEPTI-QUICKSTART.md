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

The pod uses a copy of the code from the ConfigMap. To update:

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

### Verify Upload

```bash
# List files
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- ls -lh /data/videos/

# Check disk space
oc exec deepti-data -n mllm-interpretation-and-failure-investigation-c8fa7f -- df -h /data
```

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

```bash
# Quick test run
oc create configmap deepti-script --from-file=deepti.py=./deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f
oc apply -f k8s/pod-deepti-nerc.yaml
oc logs -f deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f

# Debug session
oc apply -f k8s/pod-debug-deepti-nerc.yaml
oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
# Then connect VSCode debugger (F5)

# Cleanup
oc delete pod deepti-test -n mllm-interpretation-and-failure-investigation-c8fa7f
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
```

Happy testing! 🚀
