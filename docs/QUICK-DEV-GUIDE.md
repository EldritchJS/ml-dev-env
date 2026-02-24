# Quick Development Guide

Get started with automated code sync and debugging in 2 minutes.

## 🚀 Fastest Way: All-in-One

```bash
make dev-session
```

Or:

```bash
./scripts/dev-session.sh
```

This starts everything you need:

1. ✅ Syncs your local code to the pod
2. ✅ Watches for changes (auto-syncs when you save)
3. ✅ Sets up port-forwarding for debugging
4. ✅ Waits for you to run your script

## 📝 Basic Workflow

### 1. Start Dev Session

```bash
cd /Users/jschless/taj/cairo/ml-dev-env
make dev-session
```

You'll see:

```
🚀 ML Development Session
=========================
Namespace:  nccl-test
Pod:        ml-dev-env
Local dir:  ./workspace
Script:     test_debug.py

🔍 Checking pod status...
✅ Pod is running

📤 Initial code sync...
✅ Initial sync complete

🔄 Starting continuous code sync...
✅ Auto-sync enabled

🔌 Starting port-forward on port 5678...
✅ Port-forward ready

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Development Session Ready!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Code sync:      Active
✅ Port-forward:   localhost:5678 → pod:5678

Next steps:
  1. Edit code locally
  2. Changes auto-sync to pod
  3. Press ENTER to run
  4. Attach VSCode debugger (F5)

Press ENTER to run the script, or Ctrl+C to exit
```

### 2. Edit Your Code

Open VSCode:

```bash
code .
```

Edit `workspace/test_debug.py`:

```python
import debugpy
import torch

debugpy.listen(("0.0.0.0", 5678))
print("Waiting for debugger...")
debugpy.wait_for_client()

# Your code here - edit and save!
print(f"GPUs: {torch.cuda.device_count()}")

# Changes automatically sync to the cluster!
```

**Save the file** - it's automatically synced to the pod! 🎉

### 3. Run the Script

In the terminal where `make dev-session` is running, **press ENTER**.

You'll see:

```
🐍 Running: /workspace/test_debug.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Attach your VSCode debugger now (F5)!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Waiting for debugger...
```

### 4. Attach Debugger

In VSCode:

1. **Set breakpoints** (click left margin)
2. **Press F5**
3. **Select:** "Python: Remote Attach to Cluster"

Your debugger connects and you can step through code running on 4x H100s!

### 5. Make Changes and Re-run

1. Edit code in VSCode
2. Save (auto-syncs!)
3. Press ENTER in terminal to re-run
4. Press F5 to debug again

## 🔄 Just Code Sync (No Debugging)

If you just want to sync code automatically:

```bash
make sync-code
```

Or:

```bash
./scripts/sync-code.sh
```

Then run scripts manually:

```bash
oc exec -it ml-dev-env -n nccl-test -- python /workspace/my_script.py
```

## 🐛 Just Debugging (Manual Sync)

If you want to sync once and debug:

```bash
# Terminal 1: Sync once
make sync-once

# Terminal 2: Debug
make debug-remote FILE=test_debug.py

# VSCode: Press F5 to attach
```

## 🎯 From VSCode (No Terminal)

1. **Press `Cmd+Shift+P`**
2. **Type:** `Tasks: Run Task`
3. **Select:** "Start Dev Session"
4. Edit, save, debug!

## 📋 Available Commands

### Makefile Commands

```bash
make dev-session     # All-in-one: sync + port-forward + debug
make sync-code       # Auto-sync code changes (watch mode)
make debug-remote    # Port-forward + run script
make port-forward    # Just port-forward (5678)
make sync-once       # One-time manual sync
```

### Script Commands

```bash
./scripts/dev-session.sh [script.py]   # Full dev session
./scripts/sync-code.sh                 # Watch and sync
./scripts/debug-remote.sh [script.py]  # Port-forward + run
```

## 💡 Tips

### Improve Sync Performance

Install `fswatch` for instant sync:

```bash
brew install fswatch
```

Without it, sync polls every 3-5 seconds (still works fine!).

### Sync Different Files

```bash
./scripts/dev-session.sh my_training_script.py
```

Or:

```bash
make debug-remote FILE=my_training_script.py
```

### Multiple Terminals

**Terminal 1: Keep sync running**

```bash
make sync-code
```

**Terminal 2: Port-forward**

```bash
make port-forward
```

**Terminal 3: Run scripts**

```bash
oc exec -it ml-dev-env -n nccl-test -- python /workspace/train.py
```

**VSCode: Press F5** to debug

### Check What's Synced

```bash
# List files on pod
oc exec ml-dev-env -n nccl-test -- ls -la /workspace/

# Compare local and remote
diff <(ls workspace/) <(oc exec ml-dev-env -n nccl-test -- ls /workspace/)
```

## 🐞 Troubleshooting

### "Cannot connect to pod"

```bash
# Check pod is running
oc get pod ml-dev-env -n nccl-test

# Check you're on the right cluster
oc project
```

### "Sync not working"

```bash
# Force a full sync
make sync-once

# Check pod has the file
oc exec ml-dev-env -n nccl-test -- cat /workspace/test_debug.py
```

### "Port-forward failed"

```bash
# Port 5678 might be in use
lsof -i :5678

# Kill whatever is using it
kill $(lsof -t -i :5678)

# Try again
make port-forward
```

### "VSCode won't attach"

1. Make sure port-forward is running
2. Make sure script is running and says "Waiting for debugger..."
3. Check `.vscode/launch.json` exists
4. Try `Cmd+Shift+P` → "Debug: Select and Start Debugging"

## 📚 More Info

- **Full automation guide:** `AUTOMATION-GUIDE.md`
- **VSCode debugging guide:** `REMOTE-DEBUG-WALKTHROUGH.md`
- **VSCode setup:** `VSCODE-SETUP.md`

## Summary

**Quick start:** `make dev-session`

**Edit code locally → Auto-syncs → Run on cluster → Debug with F5** 🎉

That's it! You're developing on 4x H100 GPUs from your laptop!
