# Development Automation Guide

This guide shows you how to automatically sync code, forward ports, and debug on the cluster.

## 🚀 Quick Start: All-in-One Dev Session

The easiest way to start developing:

```bash
./scripts/dev-session.sh
```

This single command:
- ✅ Syncs your local code to the pod
- ✅ Watches for changes and auto-syncs continuously
- ✅ Sets up port-forwarding for debugging
- ✅ Waits for you to run your script
- ✅ Keeps everything running until you stop it

## ⚙️ Configuration

All scripts support custom configuration. See **CONFIGURATION-GUIDE.md** for details.

**Quick config via environment variables:**
```bash
export NAMESPACE=my-namespace    # Default: nccl-test
export POD_NAME=my-pod           # Default: ml-dev-env
export LOCAL_DIR=./src           # Default: ./workspace
export REMOTE_DIR=/app           # Default: /workspace
export DEBUG_PORT=5679           # Default: 5678

make dev-session
```

**Or inline:**
```bash
NAMESPACE=ml-team POD_NAME=gpu-pod make dev-session
```

**Or use .env file:**
```bash
cp .env.example .env
# Edit .env
source .env
make dev-session
```

See **QUICK-CONFIG-REFERENCE.md** for quick examples.

### How It Works

1. **Run the script:**
   ```bash
   ./scripts/dev-session.sh test_debug.py
   ```

2. **It will:**
   - Check pod is running
   - Do initial code sync
   - Start watching for changes
   - Start port-forward on 5678
   - Wait for you to press ENTER

3. **Edit your code locally:**
   - Open `workspace/test_debug.py` in any editor
   - Make changes
   - Changes automatically sync to the pod!

4. **Press ENTER** in the terminal when ready to run

5. **In VSCode, press F5** to attach debugger

6. **Debug!** Your local changes are on the cluster

## 🔄 Option 1: Auto Code Sync Only

If you just want to sync code changes automatically:

```bash
./scripts/sync-code.sh
```

**What it does:**
- Syncs `./workspace/` to pod's `/workspace/`
- Watches for local changes
- Automatically syncs when you save files
- Excludes: `.git`, `__pycache__`, `*.pyc`, `.DS_Store`

**Requirements:**
- Install `fswatch` for instant sync (recommended):
  ```bash
  brew install fswatch
  ```
- Without fswatch, it polls every 5 seconds

**Example workflow:**
```bash
# Terminal 1: Start sync
./scripts/sync-code.sh

# Terminal 2: Make changes
code workspace/my_model.py
# Save your changes → automatically synced!

# Terminal 3: Run on cluster
oc exec -it ml-dev-env -n nccl-test -- python /workspace/my_model.py
```

## 🐛 Option 2: Debug Script (Port-forward + Run)

Automates port-forwarding and running a debug script:

```bash
./scripts/debug-remote.sh test_debug.py
```

**What it does:**
- Starts port-forward on 5678
- Runs the specified Python script on the pod
- Waits for debugger to attach
- Cleans up port-forward when done

**Workflow:**
```bash
# Terminal 1
./scripts/debug-remote.sh my_script.py

# VSCode: Press F5 to attach debugger
# Debug your code!
# Ctrl+C in terminal when done
```

## 🎯 Option 3: VSCode Tasks (Keyboard Shortcuts)

Run automation directly from VSCode!

### Access Tasks

1. **Press `Cmd+Shift+P`**
2. **Type:** `Tasks: Run Task`
3. **Select a task:**

### Available Tasks

| Task | What It Does |
|------|--------------|
| **Start Dev Session** | All-in-one: sync + port-forward + debug |
| **Start Code Sync** | Watch and sync code changes |
| **Run Remote Debug Script** | Port-forward + run current file |
| **Port-forward Debug Port** | Just port-forward (5678) |
| **Sync Code Once** | Manual one-time sync |
| **Open Shell in Pod** | Open bash in the pod |
| **Check Pod Status** | Show pod status and recent events |

### Keyboard Shortcuts (Optional)

Add to your `keybindings.json` (Cmd+Shift+P → "Preferences: Open Keyboard Shortcuts (JSON)"):

```json
[
    {
        "key": "cmd+shift+d",
        "command": "workbench.action.tasks.runTask",
        "args": "Start Dev Session (Sync + Port-forward + Debug)"
    },
    {
        "key": "cmd+shift+s",
        "command": "workbench.action.tasks.runTask",
        "args": "Start Code Sync (Watch Mode)"
    }
]
```

Then you can just press `Cmd+Shift+D` to start a full dev session!

## 📋 Common Workflows

### Workflow 1: Quick Edit & Test

```bash
# One-time sync and test
./scripts/sync-code.sh &          # Start auto-sync in background
code workspace/my_script.py        # Edit locally
# Save file → auto-synced
oc exec -it ml-dev-env -n nccl-test -- python /workspace/my_script.py
```

### Workflow 2: Interactive Debugging Session

```bash
# Full debugging setup
./scripts/dev-session.sh my_debug_script.py

# VSCode: Press F5 when script is waiting
# Edit code, save, press ENTER to re-run
# Debugger auto-attaches each time
```

### Workflow 3: Continuous Development

```bash
# Terminal 1: Keep sync running
./scripts/sync-code.sh

# Terminal 2: Port-forward (for debugging)
oc port-forward -n nccl-test ml-dev-env 5678:5678

# VSCode: Edit, save, run, debug, repeat
# All changes automatically synced!
```

### Workflow 4: From VSCode Only

1. **Press `Cmd+Shift+P`**
2. **Type:** `Tasks: Run Task`
3. **Select:** "Start Dev Session"
4. Edit code in VSCode
5. Press ENTER in terminal to run
6. Press F5 to attach debugger

## 🔧 Advanced: Custom Sync Patterns

### Sync Specific Files

```bash
# Sync just one file
oc cp ./workspace/my_file.py nccl-test/ml-dev-env:/workspace/my_file.py

# Sync entire directory once
oc rsync ./workspace/ ml-dev-env:/workspace/ -n nccl-test
```

### Exclude Additional Patterns

Edit `scripts/sync-code.sh` and add to the rsync command:

```bash
oc rsync "$LOCAL_DIR/" "$POD_NAME:$REMOTE_DIR/" -n "$NAMESPACE" \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    --exclude='data/' \          # Add this
    --exclude='models/' \        # Add this
    --exclude='*.ckpt'           # Add this
```

### Bi-directional Sync

To sync FROM pod TO local (e.g., download model checkpoints):

```bash
# Download specific file
oc cp nccl-test/ml-dev-env:/workspace/model.pth ./workspace/model.pth

# Download directory
oc rsync ml-dev-env:/workspace/outputs/ ./workspace/outputs/ -n nccl-test
```

## 💡 Tips & Tricks

### Auto-restart Script on Changes

```bash
# Watch and auto-run script when code changes
fswatch -o ./workspace/my_script.py | while read; do
    echo "🔄 Running updated script..."
    ./scripts/sync-code.sh && \
    oc exec ml-dev-env -n nccl-test -- python /workspace/my_script.py
done
```

### Multiple Debug Ports (Multi-GPU)

```bash
# Forward all 4 debug ports for multi-GPU debugging
oc port-forward -n nccl-test ml-dev-env \
    5678:5678 \
    5679:5679 \
    5680:5680 \
    5681:5681
```

### Sync on Git Commit

Add to `.git/hooks/post-commit`:

```bash
#!/bin/bash
echo "📤 Syncing to cluster..."
oc rsync ./workspace/ ml-dev-env:/workspace/ -n nccl-test --exclude='.git'
echo "✅ Sync complete"
```

### Background Sync + Notifications

```bash
# macOS: Show notification when sync completes
./scripts/sync-code.sh &
fswatch -o ./workspace | while read; do
    osascript -e 'display notification "Code synced to cluster" with title "Dev Sync"'
done
```

## 🐞 Troubleshooting

### "oc rsync failed"

**Problem:** rsync not working

**Solution:**
```bash
# Check pod is running
oc get pod ml-dev-env -n nccl-test

# Try manual copy instead
oc cp ./workspace/test.py nccl-test/ml-dev-env:/workspace/test.py
```

### "fswatch: command not found"

**Problem:** fswatch not installed

**Solution:**
```bash
# Install fswatch (recommended for macOS)
brew install fswatch

# Or use the scripts without fswatch (they'll poll instead)
```

### Port-forward keeps disconnecting

**Problem:** Port-forward stops after a while

**Solution:**
```bash
# Use a loop to auto-reconnect
while true; do
    oc port-forward -n nccl-test ml-dev-env 5678:5678
    echo "Reconnecting..."
    sleep 2
done
```

### Changes not syncing

**Problem:** Local changes don't appear on pod

**Solution:**
```bash
# Force a full sync
oc rsync ./workspace/ ml-dev-env:/workspace/ -n nccl-test --delete

# Check what's on the pod
oc exec ml-dev-env -n nccl-test -- ls -la /workspace/
```

### Script runs old code

**Problem:** Running script uses old code despite sync

**Solution:**
```bash
# Python might cache .pyc files
oc exec ml-dev-env -n nccl-test -- bash -c "find /workspace -name '*.pyc' -delete"

# Or restart Python with fresh imports
oc exec ml-dev-env -n nccl-test -- python -c "import sys; sys.dont_write_bytecode=True" /workspace/script.py
```

## 📊 Comparison

| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **dev-session.sh** | Everything automated | One terminal | Quick iteration |
| **sync-code.sh** | Continuous sync | Need to run script separately | Ongoing development |
| **debug-remote.sh** | Port-forward + run | No auto-sync | One-off debugging |
| **VSCode Tasks** | Integrated in editor | Setup required | VSCode users |
| **Manual oc cp** | Simple, precise | Tedious for many files | Single file changes |

## 🎓 Example: Complete ML Training Loop

```bash
# Terminal 1: Start dev session
./scripts/dev-session.sh train.py

# Edit code in VSCode
# workspace/train.py:
#   - Change learning rate
#   - Add logging
#   - Save file → auto-synced!

# Press ENTER in Terminal 1 to run
# Press F5 in VSCode to attach debugger

# Set breakpoint on training loop
# Inspect gradients, losses, GPU memory

# Stop debugger
# Edit code again
# Press ENTER to re-run
# Repeat!
```

## 🚀 Next Level: Makefile Integration

Add to `Makefile`:

```makefile
.PHONY: dev-session sync-code debug-remote

dev-session:
	@./scripts/dev-session.sh

sync-code:
	@./scripts/sync-code.sh

debug-remote:
	@./scripts/debug-remote.sh $(FILE)

# Usage:
# make dev-session
# make sync-code
# make debug-remote FILE=my_script.py
```

## Summary

**For quick testing:** `./scripts/dev-session.sh`

**For continuous dev:** `./scripts/sync-code.sh` (keep running)

**For one-off debug:** `./scripts/debug-remote.sh script.py`

**From VSCode:** `Cmd+Shift+P` → Tasks → Pick one

All scripts clean up automatically on Ctrl+C! 🎉
