# Remote Debugging with VSCode and debugpy

This guide shows how to debug Python code running on GPU clusters using VSCode and debugpy.

## Current Setup

**Debug Pod:** `deepti-debug` running on NERC Production cluster

- **Namespace:** `mllm-interpretation-and-failure-investigation-c8fa7f`
- **GPUs:** 4x NVIDIA H100 80GB HBM3
- **Code:** `/workspace/deepti.py` (Qwen2.5-Omni test)
- **Debugpy Port:** 5678

## Prerequisites

1. **VSCode Extension:** Install "Python" extension (includes debugpy support)
2. **Port Forwarding:** Already running on `localhost:5678`

## Quick Start

### Step 1: Verify Port Forwarding

Port forwarding is already active. To check:

```bash
nc -zv localhost 5678
```

If not running, start it manually:

```bash
oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
```

### Step 2: Open VSCode

```bash
cd /Users/jschless/nairr/deepti/ml-dev-env
code .
```

### Step 3: Set Breakpoints

Open `deepti.py` and set breakpoints by clicking in the left gutter (next to line numbers).

**Suggested breakpoint locations:**

- Line 56: Model initialization
- Line 70: Model loading
- Line 128: Model.generate() call
- Line 144: Output processing

### Step 4: Start Debugging

1. Go to **Run and Debug** panel (Cmd+Shift+D)
2. Select "**Debug Deepti (Remote - NERC Production)**" from dropdown
3. Click the green **Start Debugging** button (or press F5)

VSCode will connect to the remote debugpy server on the cluster.

### Step 5: Debug

Once connected:

- **F10** - Step Over
- **F11** - Step Into
- **Shift+F11** - Step Out
- **F5** - Continue
- **Shift+F5** - Stop Debugging

**Debug panels:**

- **Variables** - Inspect current variable values
- **Watch** - Add expressions to monitor
- **Call Stack** - See execution path
- **Debug Console** - Execute Python expressions in the current context

## Example Debugging Session

```python
# Set breakpoint at line 128 (model.generate call)
# When debugger pauses, you can:

# Inspect variables in Debug Console:
>>> input_ids.shape
>>> torch.cuda.memory_allocated(0)
>>> type(model)

# Check GPU memory
>>> import torch
>>> for i in range(4):
...     print(f"GPU {i}: {torch.cuda.memory_allocated(i) / 1024**3:.2f} GB")

# Modify variables (for testing)
>>> max_new_tokens = 100  # Change generation length

# Then press F5 to continue execution
```

## Debugging Multi-GPU Code

The pod has 4 GPUs. You can debug multi-GPU behavior:

```python
# In Debug Console, check device placement:
>>> model.device
>>> next(model.parameters()).device

# Check which GPUs are being used:
>>> import torch
>>> [torch.cuda.get_device_properties(i).name for i in range(torch.cuda.device_count())]
```

## Troubleshooting

### Connection Refused

If VSCode can't connect:

1. **Check pod is running:**

   ```bash
   oc get pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

2. **Check debugpy is listening:**

   ```bash
   oc logs deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

   Should show: "Starting debugpy server on port 5678..."

3. **Restart port forwarding:**

   ```bash
   pkill -f "port-forward deepti-debug"
   oc port-forward deepti-debug 5678:5678 -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

### Breakpoints Not Working

- Make sure `justMyCode` is set to `false` in `.vscode/launch.json`
- Check that `pathMappings` are correct (local vs remote paths)
- Try setting breakpoints after connecting (instead of before)

### Code Changes Not Reflected

The code in the pod is a copy. To update:

1. Update `deepti.py` locally
2. Update the ConfigMap:

   ```bash
   oc delete configmap deepti-script -n mllm-interpretation-and-failure-investigation-c8fa7f
   oc create configmap deepti-script --from-file=deepti.py=/Users/jschless/nairr/deepti/ml-dev-env/deepti.py -n mllm-interpretation-and-failure-investigation-c8fa7f
   ```

3. Restart the debug pod:

   ```bash
   oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
   oc apply -f k8s/pod-debug-deepti-nerc.yaml
   ```

## Advanced: Debug Pod Manifest

The debug pod is defined in `k8s/pod-debug-deepti-nerc.yaml` and uses:

```bash
python -m debugpy --listen 0.0.0.0:5678 --wait-for-client deepti.py
```

**Flags:**

- `--listen 0.0.0.0:5678` - Listen on all interfaces, port 5678
- `--wait-for-client` - Pause execution until debugger attaches

## Cleanup

When done debugging:

```bash
# Stop port forwarding
pkill -f "port-forward deepti-debug"

# Delete debug pod
oc delete pod deepti-debug -n mllm-interpretation-and-failure-investigation-c8fa7f
```

## Next Steps

- Try debugging the model loading (lines 56-70)
- Inspect flash-attention usage during inference
- Monitor GPU memory during model.generate()
- Debug multi-modal input processing (video, text)

Happy debugging! 🐛🔍
