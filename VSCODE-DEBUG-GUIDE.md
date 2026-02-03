# VSCode Debugging Guide for OpenShift ML Development Environment

This guide covers how to debug Python code running on your OpenShift GPU cluster using VSCode.

## Method 1: Port-Forward to code-server (Browser-based VSCode)

The pod runs code-server (VSCode in browser) on port 8080.

### 1. Port-forward to your local machine
```bash
oc port-forward -n nccl-test ml-dev-env 8080:8080
```

### 2. Open in your browser
Navigate to: http://localhost:8080

### 3. Use the built-in debugger
- Open your Python file
- Set breakpoints by clicking left of line numbers
- Press F5 or click "Run and Debug"
- Select "Python File" configuration

**Advantages:**
- No local VSCode installation needed
- All extensions run on the cluster
- Direct access to GPU environment
- Code files stay on the cluster

---

## Method 2: Remote SSH with VSCode Desktop

Use VSCode's Remote-SSH extension to connect directly to the pod.

### 1. Expose SSH access (if not already configured)

You'll need to either:
- **Option A:** Install and run SSH server in the pod
- **Option B:** Use `oc port-forward` with SSH

For a quick setup, add SSH to the container:

```bash
# Exec into the pod
oc exec -it ml-dev-env -n nccl-test -- bash

# Install and start SSH server
apt-get update && apt-get install -y openssh-server
mkdir -p /var/run/sshd
echo "root:password" | chpasswd
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
/usr/sbin/sshd -D &
```

### 2. Port-forward SSH
```bash
oc port-forward -n nccl-test ml-dev-env 2222:22
```

### 3. Configure VSCode Remote-SSH
- Install "Remote - SSH" extension in VSCode
- Press Cmd+Shift+P → "Remote-SSH: Connect to Host"
- Add host: `ssh root@localhost -p 2222`
- Connect and open `/workspace` folder

### 4. Install Python extension in remote VSCode
- Once connected, install "Python" extension (it installs on the remote)
- Configure debugpy if needed

**Advantages:**
- Full VSCode desktop experience
- All your local themes/keybindings
- Better performance than browser

---

## Method 3: Remote Debugging with debugpy

Debug code running on the cluster from your local VSCode.

### 1. Install debugpy in the container (already included)
The container already has `debugpy` installed.

### 2. Add debug code to your Python script

```python
import debugpy

# Listen on port 5678 for debugger connection
debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger to attach...")
debugpy.wait_for_client()
print("Debugger attached!")

# Your code here
import torch
print(f"GPUs available: {torch.cuda.device_count()}")
```

### 3. Port-forward the debug port
```bash
oc port-forward -n nccl-test ml-dev-env 5678:5678
```

### 4. Configure VSCode launch.json

Create `.vscode/launch.json` in your local project:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python: Remote Attach",
            "type": "python",
            "request": "attach",
            "connect": {
                "host": "localhost",
                "port": 5678
            },
            "pathMappings": [
                {
                    "localRoot": "${workspaceFolder}",
                    "remoteRoot": "/workspace"
                }
            ],
            "justMyCode": false
        }
    ]
}
```

### 5. Start debugging
- Run your Python script in the pod
- In local VSCode: Press F5 and select "Python: Remote Attach"
- Set breakpoints in your local copy of the code
- Step through code executing on the cluster

**Advantages:**
- Debug distributed/multi-GPU code
- Keep code in sync between local and remote
- Attach to running processes

---

## Method 4: Jupyter Notebook Debugging

The pod runs Jupyter on port 8888.

### 1. Start Jupyter
```bash
oc exec -it ml-dev-env -n nccl-test -- bash -c "jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root &"
```

### 2. Port-forward Jupyter
```bash
oc port-forward -n nccl-test ml-dev-env 8888:8888
```

### 3. Get the token
```bash
oc exec ml-dev-env -n nccl-test -- jupyter notebook list
```

### 4. Open in browser
Navigate to: http://localhost:8888/?token=YOUR_TOKEN

### 5. Use %debug magic
In notebook cells:
```python
# Enable automatic debugging on exceptions
%pdb on

# Or manually invoke debugger
%debug

# Or use IPython debugger
from IPython.core.debugger import set_trace
set_trace()
```

**Advantages:**
- Interactive exploration
- Great for ML experimentation
- Visualizations inline

---

## Recommended Workflow for ML Development

### For Interactive Development: Use code-server (Method 1)
```bash
# Port-forward code-server
oc port-forward -n nccl-test ml-dev-env 8080:8080

# Open http://localhost:8080
# Develop directly in /workspace
```

### For Training Scripts: Use Remote Debugging (Method 3)
```python
# train.py
import debugpy
debugpy.listen(("0.0.0.0", 5678))
debugpy.wait_for_client()

import torch
from transformers import AutoModel

# Set breakpoint here in local VSCode
model = AutoModel.from_pretrained("gpt2")
# Debug model initialization, GPU allocation, etc.
```

### For Experimentation: Use Jupyter (Method 4)
```bash
# Start Jupyter
oc exec ml-dev-env -n nccl-test -- bash -c "cd /workspace && jupyter notebook --ip=0.0.0.0 --no-browser --allow-root" &

# Port-forward
oc port-forward -n nccl-test ml-dev-env 8888:8888
```

---

## Debugging Multi-GPU Code

### Example: Debugging NCCL/DDP Training

```python
# distributed_train.py
import debugpy
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

# Each process attaches to different debug port
rank = int(os.environ.get("RANK", 0))
debug_port = 5678 + rank
debugpy.listen(("0.0.0.0", debug_port))
if rank == 0:  # Only wait for debugger on rank 0
    print(f"Rank {rank} waiting on port {debug_port}")
    debugpy.wait_for_client()

# Initialize distributed
dist.init_process_group(backend="nccl")
model = DDP(YourModel().cuda())

# Set breakpoints and debug distributed training
```

Port-forward multiple debug ports:
```bash
oc port-forward -n nccl-test ml-dev-env 5678:5678 5679:5679 5680:5680 5681:5681
```

---

## Troubleshooting

### Issue: Port-forward disconnects
**Solution:** Use a persistent connection:
```bash
while true; do
    oc port-forward -n nccl-test ml-dev-env 8080:8080
    echo "Port-forward disconnected, reconnecting..."
    sleep 2
done
```

### Issue: Debugger won't attach
**Solution:** Check firewall and verify port is listening:
```bash
oc exec ml-dev-env -n nccl-test -- netstat -tlnp | grep 5678
```

### Issue: Code files out of sync
**Solution:** Use rsync to sync local files to pod:
```bash
# Copy local files to pod
oc rsync ./my-code/ ml-dev-env:/workspace/my-code/ -n nccl-test

# Or mount a PVC with your code
```

---

## Quick Start: Try It Now

1. **Start code-server:**
   ```bash
   oc port-forward -n nccl-test ml-dev-env 8080:8080
   ```

2. **Open browser:** http://localhost:8080

3. **Create a test file:** `/workspace/test_debug.py`
   ```python
   import torch
   import debugpy

   debugpy.listen(("0.0.0.0", 5678))
   print("Debugger ready on port 5678")
   debugpy.wait_for_client()

   print(f"CUDA available: {torch.cuda.is_available()}")
   print(f"GPU count: {torch.cuda.device_count()}")

   for i in range(torch.cuda.device_count()):
       print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
   ```

4. **In another terminal, port-forward debug port:**
   ```bash
   oc port-forward -n nccl-test ml-dev-env 5678:5678
   ```

5. **In local VSCode, attach debugger** (using launch.json above)

6. **Run the script in code-server** and debug from your local VSCode!

---

## Resources

- **debugpy docs:** https://github.com/microsoft/debugpy
- **VSCode Remote Development:** https://code.visualstudio.com/docs/remote/remote-overview
- **PyTorch Distributed Debugging:** https://pytorch.org/tutorials/intermediate/dist_tuto.html

## Environment Details

- **Node:** moc-r4pcc04u25-nairr
- **GPUs:** 4x H100
- **RDMA Devices:** mlx5_6, mlx5_7, mlx5_10, mlx5_11
- **Network Interfaces:** net1, net2, net3, net4
- **PyTorch:** 2.5.0 (CUDA 12.6)
- **Python:** 3.10
- **Workspace:** /workspace (persistent PVC)
