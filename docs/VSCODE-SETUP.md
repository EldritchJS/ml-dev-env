# VSCode Setup for Remote Debugging

## Required Extension

You need the **Python extension** from Microsoft to use remote debugging with debugpy.

## Check if You Have It

1. Open VSCode
2. Press `Cmd+Shift+X` (or click Extensions icon in left sidebar)
3. Search for "Python"
4. Look for: **"Python"** by Microsoft (ms-python.python)

## Install the Python Extension

### Method 1: From VSCode UI

1. Press `Cmd+Shift+X` to open Extensions
2. Search: `Python`
3. Click on **"Python"** by Microsoft (should be the first result)
4. Click **"Install"**

### Method 2: From Command Line

```bash
code --install-extension ms-python.python
```

### Method 3: Quick Install Command

Run this command to install it directly:

```bash
code --install-extension ms-python.python
```

## Verify Installation

After installing, verify it's working:

1. Open VSCode in the ml-dev-env directory:

   ```bash
   cd /Users/jschless/taj/cairo/ml-dev-env
   code .
   ```

2. Open `workspace/test_debug.py`

3. Press `Cmd+Shift+D` to open Run and Debug view

4. You should see the dropdown at the top with: **"Python: Remote Attach to Cluster"**

If you see that option, you're all set! ✅

## What the Python Extension Provides

- **debugpy support** - Remote debugging protocol
- **IntelliSense** - Code completion for Python
- **Linting** - Code quality checks
- **Formatting** - Code formatting (black, autopep8, etc.)
- **Testing** - Run pytest, unittest, etc.
- **Jupyter** - Notebook support (optional)

## Optional: Install Python Language Server

For better performance, the extension may prompt you to install Pylance:

- Extension name: **"Pylance"** by Microsoft (ms-python.vscode-pylance)
- This provides faster IntelliSense and type checking
- Click "Install" if prompted (recommended but not required for debugging)

## Troubleshooting

### "python" is not a recognized debug type

**Problem:** When you try to debug, you get an error about the debug type.

**Solution:**

1. The Python extension isn't installed or is disabled
2. Install it using the methods above
3. Restart VSCode after installation
4. Make sure launch.json has `"type": "python"` not "debugpy"

### Don't see "Python: Remote Attach to Cluster" in dropdown

**Problem:** The launch configuration doesn't appear.

**Solution:**

1. Make sure `.vscode/launch.json` exists in your workspace
2. Make sure you have the Python extension installed
3. Try reloading VSCode: `Cmd+Shift+P` → "Developer: Reload Window"

### Extension is installed but debugging doesn't work

**Solution:**

1. Update the Python extension to the latest version
2. Check VSCode is up to date: `Code → Check for Updates`
3. Verify launch.json uses `"type": "python"` (not other values)

## Quick Test

Once installed, test it works:

```bash
# Terminal 1: Port-forward
oc port-forward -n nccl-test ml-dev-env 5678:5678

# Terminal 2: Run script
oc exec -it ml-dev-env -n nccl-test -- python /workspace/test_debug.py

# VSCode: Press F5 and select "Python: Remote Attach to Cluster"
```

If it connects and you can debug, you're all set! 🎉

## Summary

**Required:**

- ✅ Python extension (ms-python.python)

**Optional but recommended:**

- Pylance extension (ms-python.vscode-pylance) - Better IntelliSense
- GitLens - Git integration
- Docker - If working with containers locally

**Not required:**

- Remote-SSH extension (only needed for Method 2)
- Jupyter extension (only needed for Method 4)
