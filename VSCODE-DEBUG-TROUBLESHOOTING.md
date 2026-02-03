# VSCode Debug Configuration Troubleshooting

## Quick Fix Steps

### Step 1: Completely Close VSCode
Close all VSCode windows completely (Cmd+Q)

### Step 2: Open the Workspace Folder (Not Just a File!)
```bash
cd /Users/jschless/taj/cairo/ml-dev-env
/usr/local/bin/code .
```

**Important:** You must open the folder `/Users/jschless/taj/cairo/ml-dev-env`, not just open a Python file.

### Step 3: Open a Python File
In VSCode, open: `workspace/test_debug.py`

This triggers the Python extension to activate.

### Step 4: Check the Run and Debug Panel

1. **Click the "Run and Debug" icon** in the left sidebar (it looks like a play button with a bug)
   - Or press `Cmd+Shift+D`

2. **Look at the TOP of the panel** - you should see a dropdown menu

3. **The dropdown should show:** "Python: Remote Attach to Cluster"

### Step 5: If You Still Don't See It

Try this:

1. In the Run and Debug panel, look for a link that says **"create a launch.json file"** or **"Show all automatic debug configurations"**

2. Click the small gear icon (⚙️) next to the dropdown at the top

3. This should open `.vscode/launch.json` in the editor

4. You should see the configuration is already there

## Where to Look in VSCode

```
┌─────────────────────────────────────────────────┐
│ File  Edit  View  ...                          │  ← Menu bar
├─────────────────────────────────────────────────┤
│ 📂 Explorer         workspace/test_debug.py    │
│ 🔍 Search                                       │
│ 🌿 Source Control                               │
│ ▶️🐛 Run and Debug  ← CLICK HERE                │  ← Left sidebar
│ 🧩 Extensions                                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  RUN AND DEBUG                                  │
│                                                 │
│  ┌────────────────────────────────────┐        │
│  │ Python: Remote Attach to Cluster ▼ │  ← DROPDOWN IS HERE!
│  └────────────────────────────────────┘        │
│                                                 │
│  ▶️ Start Debugging  F5                         │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Verification Commands

Run these to verify everything is set up correctly:

```bash
# 1. Check VSCode is installed
ls -la "/Applications/Visual Studio Code.app"

# 2. Check code command works
/usr/local/bin/code --version

# 3. Check Python extension is installed
/usr/local/bin/code --list-extensions | grep ms-python.python

# 4. Check launch.json exists
cat /Users/jschless/taj/cairo/ml-dev-env/.vscode/launch.json

# 5. Check launch.json is valid JSON
python3 -m json.tool /Users/jschless/taj/cairo/ml-dev-env/.vscode/launch.json
```

All should succeed ✅

## Alternative: Manually Trigger Debugging

If the dropdown doesn't appear, you can still debug:

1. Open `workspace/test_debug.py` in VSCode

2. Press `Cmd+Shift+P` (Command Palette)

3. Type: **"Debug: Select and Start Debugging"**

4. Select: **"Python: Remote Attach"** or **"Python Debugger: Remote Attach"**

5. If prompted:
   - Host: `localhost`
   - Port: `5678`

## Alternative Method: Create Config from Scratch

If nothing works, try recreating the configuration:

1. **Delete** `.vscode/launch.json`:
   ```bash
   rm /Users/jschless/taj/cairo/ml-dev-env/.vscode/launch.json
   ```

2. **In VSCode:**
   - Open the folder: `/Users/jschless/taj/cairo/ml-dev-env`
   - Click "Run and Debug" in left sidebar
   - Click **"create a launch.json file"**
   - Select **"Python Debugger"**
   - Select **"Remote Attach"**
   - Enter host: `localhost`
   - Enter port: `5678`

3. **Modify** the created file to add path mappings:
   ```json
   {
       "version": "0.2.0",
       "configurations": [
           {
               "name": "Python Debugger: Remote Attach",
               "type": "debugpy",
               "request": "attach",
               "connect": {
                   "host": "localhost",
                   "port": 5678
               },
               "pathMappings": [
                   {
                       "localRoot": "${workspaceFolder}/workspace",
                       "remoteRoot": "/workspace"
                   }
               ],
               "justMyCode": false
           }
       ]
   }
   ```

## Check Python Extension is Active

In VSCode:

1. Open `workspace/test_debug.py`

2. Look at the **bottom-right status bar**

3. You should see: **Python 3.x.x** (interpreter version)

4. If you don't see it, click on the status bar and select a Python interpreter

## Nuclear Option: Reinstall Python Extension

```bash
# Uninstall
/usr/local/bin/code --uninstall-extension ms-python.python

# Reinstall
/usr/local/bin/code --install-extension ms-python.python

# Restart VSCode
# Then try again
```

## Still Not Working?

Try using the Command Palette directly:

1. Make sure port-forward is running:
   ```bash
   oc port-forward -n nccl-test ml-dev-env 5678:5678
   ```

2. Make sure script is running:
   ```bash
   oc exec -it ml-dev-env -n nccl-test -- python /workspace/test_debug.py
   ```

3. In VSCode, press `Cmd+Shift+P`

4. Type: **"Python: Attach"**

5. You should see: **"Python Debugger: Attach using Process Id"** or similar

6. Select any "Attach" option

7. When prompted:
   - Connection type: **tcp**
   - Host: **localhost**
   - Port: **5678**

## What Should Happen

When everything works:

1. ✅ Dropdown shows "Python: Remote Attach to Cluster"
2. ✅ Press F5
3. ✅ VSCode connects to localhost:5678
4. ✅ Script on cluster resumes
5. ✅ Debugger stops at first breakpoint
6. ✅ You can step through code, inspect variables

## Debug the Debugger

Enable VSCode debug logging:

1. Press `Cmd+Shift+P`
2. Type: **"Developer: Toggle Developer Tools"**
3. Click **Console** tab
4. Try to start debugging
5. Look for error messages in the console

Common errors:
- "Cannot find module 'debugpy'" → Python extension not loaded
- "Cannot connect to localhost:5678" → Port-forward not running
- "No configuration found" → launch.json not recognized

## Summary

**Most common issue:** Opening a single file instead of the folder.

**Solution:**
```bash
# Close VSCode completely
# Then:
cd /Users/jschless/taj/cairo/ml-dev-env
/usr/local/bin/code .  # The "." means "current folder"
```

Then the dropdown should appear in the Run and Debug panel!
