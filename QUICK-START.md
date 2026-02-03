# Quick Start Guide

## Pod is Deployed

Your ML development environment pod is now deployed:
- **Name:** ml-dev-env
- **Namespace:** nccl-test
- **Node:** moc-r4pcc04u25-nairr
- **GPUs:** 4x H100
- **RDMA:** mlx5_6, mlx5_7, mlx5_10, mlx5_11
- **Network:** net1, net2, net3, net4

## Wait for Pod to be Ready

Check pod status:
```bash
oc get pod ml-dev-env -n nccl-test
```

Wait until STATUS shows "Running" (may take 2-5 minutes for image pull).

## Option 1: Quick VSCode Browser Access (Recommended)

1. **Port-forward code-server:**
   ```bash
   oc port-forward -n nccl-test ml-dev-env 8080:8080
   ```

2. **Open browser:**
   ```
   http://localhost:8080
   ```

3. **Start coding!**
   - You now have VSCode in your browser
   - Connected directly to the GPU cluster
   - Files saved to `/workspace` are persistent

## Option 2: Shell Access

```bash
oc exec -it ml-dev-env -n nccl-test -- bash
```

## Option 3: Jupyter Notebook

1. **Start Jupyter in the pod:**
   ```bash
   oc exec ml-dev-env -n nccl-test -- bash -c "jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root" &
   ```

2. **Port-forward:**
   ```bash
   oc port-forward -n nccl-test ml-dev-env 8888:8888
   ```

3. **Get the token:**
   ```bash
   oc exec ml-dev-env -n nccl-test -- jupyter notebook list
   ```

4. **Open browser:**
   ```
   http://localhost:8888/?token=YOUR_TOKEN
   ```

## Verify GPU Access

Once inside (via shell or code-server terminal):

```bash
# Check GPUs
nvidia-smi

# Check PyTorch
python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"

# Check flash-attn
python -c "import flash_attn; print('flash-attn working!')"

# Check RDMA devices
ibstat
```

## Test Multi-GPU Communication

Create `/workspace/test_nccl.py`:

```python
import torch
import torch.distributed as dist

# Initialize NCCL
dist.init_process_group(backend="nccl")

# Create tensors on all GPUs
devices = [torch.device(f"cuda:{i}") for i in range(4)]
tensors = [torch.ones(1000, 1000, device=d) for d in devices]

# All-reduce across all GPUs
for tensor in tensors:
    dist.all_reduce(tensor)

print("Multi-GPU communication working via NCCL/RDMA!")
```

## Debug with VSCode

See **VSCODE-DEBUG-GUIDE.md** for detailed debugging instructions.

**Fastest method:**
1. Port-forward: `oc port-forward -n nccl-test ml-dev-env 8080:8080`
2. Open: http://localhost:8080
3. Use built-in debugger in browser VSCode

## Persistent Storage

- **Workspace:** `/workspace` → PVC `ml-dev-workspace` (100Gi)
- **Datasets:** `/datasets` → PVC `ml-datasets` (500Gi)

Your code and data persist between pod restarts.

## Installed Libraries

- PyTorch 2.5.0 (CUDA 12.6)
- flash-attn 2.8.3
- transformers
- deepspeed
- LLaMAFactory
- VideoLLaMA2
- bitsandbytes, peft, trl
- Jupyter, ipython, debugpy
- wandb, tensorboard

## Common Commands

```bash
# Check pod status
oc get pod ml-dev-env -n nccl-test

# View pod logs
oc logs ml-dev-env -n nccl-test

# Shell access
oc exec -it ml-dev-env -n nccl-test -- bash

# Copy files to pod
oc cp ./myfile.py nccl-test/ml-dev-env:/workspace/

# Copy files from pod
oc cp nccl-test/ml-dev-env:/workspace/results.txt ./

# Delete pod (to recreate with changes)
oc delete pod ml-dev-env -n nccl-test

# Recreate pod
oc apply -f pod-multi-gpu.yaml
```

## Need Help?

- **VSCode debugging:** See VSCODE-DEBUG-GUIDE.md
- **CUDA concepts:** See docs/CUDA-CONCEPTS.md
- **Performance tips:** See docs/PERFORMANCE-TIPS.md

## Next Steps

1. ✅ Wait for pod to be "Running"
2. ✅ Port-forward code-server (port 8080)
3. ✅ Open http://localhost:8080
4. ✅ Start developing ML models on 4x H100s!
