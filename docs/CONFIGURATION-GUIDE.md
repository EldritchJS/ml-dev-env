# Configuration Guide

This guide shows how to customize pod name, namespace, directories, and ports for the development automation scripts.

## 🎯 Quick Start with Defaults

By default, scripts use:
- **Namespace:** `nccl-test`
- **Pod name:** `ml-dev-env`
- **Local directory:** `./workspace`
- **Remote directory:** `/workspace`
- **Debug port:** `5678`

To use defaults, just run:
```bash
make dev-session
```

## 📝 Three Ways to Configure

### Method 1: Command-Line Arguments (Scripts Only)

Pass arguments directly to scripts:

#### sync-code.sh
```bash
./scripts/sync-code.sh [local_dir] [remote_dir] [pod_name] [namespace]
```

Examples:
```bash
# Use custom directories
./scripts/sync-code.sh ./src /app

# Use custom pod and namespace
./scripts/sync-code.sh ./src /app my-pod my-namespace
```

#### debug-remote.sh
```bash
./scripts/debug-remote.sh [script_name] [pod_name] [namespace] [port]
```

Examples:
```bash
# Different script
./scripts/debug-remote.sh train.py

# Different pod and namespace
./scripts/debug-remote.sh train.py my-pod my-namespace

# Different port
./scripts/debug-remote.sh train.py my-pod my-namespace 5679
```

#### dev-session.sh
```bash
./scripts/dev-session.sh [script] [local_dir] [remote_dir] [pod_name] [namespace] [port]
```

Examples:
```bash
# Custom script
./scripts/dev-session.sh train.py

# Custom directories
./scripts/dev-session.sh train.py ./src /app

# Full customization
./scripts/dev-session.sh train.py ./src /app my-pod my-namespace 5679
```

### Method 2: Environment Variables (Recommended)

Export variables in your shell:

```bash
# Set variables
export NAMESPACE=my-namespace
export POD_NAME=my-pod
export LOCAL_DIR=./src
export REMOTE_DIR=/app
export DEBUG_PORT=5679

# Run commands (they use exported variables)
make dev-session
make sync-code
./scripts/debug-remote.sh train.py
```

**Advantages:**
- Works with both Makefile and scripts
- Variables persist in your shell session
- Easy to switch between configurations

### Method 3: .env File (Best for Persistent Config)

Create a `.env` file with your configuration:

```bash
# Copy example
cp .env.example .env

# Edit .env
cat > .env << 'END'
NAMESPACE=my-namespace
POD_NAME=my-custom-pod
LOCAL_DIR=./src
REMOTE_DIR=/app/src
DEBUG_PORT=5679
END

# Load variables
source .env

# Run commands
make dev-session
```

**Advantages:**
- Configuration saved in file
- Easy to version control (add `.env` to `.gitignore`)
- Can have multiple configs (`.env.dev`, `.env.prod`)

### Method 4: Inline with Make (Quick Override)

Override variables when calling make:

```bash
# Override namespace
NAMESPACE=ml-prod make dev-session

# Override multiple variables
POD_NAME=my-pod LOCAL_DIR=./src make sync-code

# Override everything
NAMESPACE=prod POD_NAME=ml-pod LOCAL_DIR=./code REMOTE_DIR=/app DEBUG_PORT=5679 make dev-session
```

## 📋 Configuration Variables

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `NAMESPACE` | `nccl-test` | OpenShift namespace | All |
| `POD_NAME` | `ml-dev-env` | Pod name | All |
| `LOCAL_DIR` | `./workspace` | Local code directory | sync-code, dev-session |
| `REMOTE_DIR` | `/workspace` | Remote code directory | sync-code, dev-session |
| `DEBUG_PORT` | `5678` | Debug port number | debug-remote, dev-session, port-forward |

## 🎯 Common Scenarios

### Scenario 1: Multiple Namespaces

You have dev and prod namespaces:

```bash
# Development
NAMESPACE=ml-dev make dev-session

# Production
NAMESPACE=ml-prod POD_NAME=ml-prod-pod make sync-code
```

### Scenario 2: Different Directory Structure

Your code is in `./src` locally and `/app` on pod:

```bash
# Option A: Environment variables
export LOCAL_DIR=./src
export REMOTE_DIR=/app
make dev-session

# Option B: Inline
LOCAL_DIR=./src REMOTE_DIR=/app make sync-code
```

### Scenario 3: Multiple Pods

You're working with multiple pods:

```bash
# Pod 1
export POD_NAME=worker-1
make dev-session

# Pod 2 (in another terminal)
export POD_NAME=worker-2
DEBUG_PORT=5679  # Different port to avoid conflict
make dev-session
```

### Scenario 4: Custom Ports (Multi-GPU Debug)

Debug different ranks on different ports:

```bash
# Rank 0
DEBUG_PORT=5678 ./scripts/debug-remote.sh train.py

# Rank 1 (another terminal)
DEBUG_PORT=5679 ./scripts/debug-remote.sh train.py
```

### Scenario 5: Team Configuration Files

Create team-specific configs:

```bash
# .env.dev
cat > .env.dev << 'END'
NAMESPACE=ml-dev
POD_NAME=dev-pod
LOCAL_DIR=./workspace
REMOTE_DIR=/workspace
DEBUG_PORT=5678
END

# .env.prod
cat > .env.prod << 'END'
NAMESPACE=ml-prod
POD_NAME=prod-pod
LOCAL_DIR=./src
REMOTE_DIR=/app
DEBUG_PORT=5678
END

# Use dev config
source .env.dev
make dev-session

# Use prod config
source .env.prod
make sync-code
```

## 🔍 Check Current Configuration

See what configuration will be used:

```bash
# Via Makefile
make help

# Shows:
# Current configuration:
#   Namespace:   nccl-test
#   Pod name:    ml-dev-env
#   Local dir:   ./workspace
#   Remote dir:  /workspace
#   Debug port:  5678
```

Or check environment variables:
```bash
env | grep -E 'NAMESPACE|POD_NAME|LOCAL_DIR|REMOTE_DIR|DEBUG_PORT'
```

## 🔧 Advanced: Priority Order

When you use multiple configuration methods, this is the priority (highest to lowest):

1. **Command-line arguments** (scripts only)
2. **Inline Make variables** (`NAMESPACE=foo make ...`)
3. **Environment variables** (`export NAMESPACE=foo`)
4. **Hardcoded defaults** (in scripts/Makefile)

Example:
```bash
# Set environment variable
export NAMESPACE=env-namespace

# Inline override takes precedence
NAMESPACE=inline-namespace make dev-session
# Uses: inline-namespace

# Script argument takes precedence over all
./scripts/sync-code.sh ./workspace /workspace ml-dev arg-namespace
# Uses: arg-namespace
```

## 📝 VSCode Integration

Update `.vscode/tasks.json` to use your config:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Dev Session (Custom Config)",
            "type": "shell",
            "command": "NAMESPACE=my-namespace POD_NAME=my-pod ./scripts/dev-session.sh",
            "options": {
                "env": {
                    "NAMESPACE": "my-namespace",
                    "POD_NAME": "my-pod",
                    "LOCAL_DIR": "./src",
                    "REMOTE_DIR": "/app"
                }
            }
        }
    ]
}
```

## 🎓 Examples

### Example 1: Quick Test with Different Pod

```bash
POD_NAME=test-pod ./scripts/debug-remote.sh test.py
```

### Example 2: Persistent Development Setup

```bash
# Create config
cat > .env << 'END'
NAMESPACE=ml-team
POD_NAME=dev-gpu-pod
LOCAL_DIR=./models
REMOTE_DIR=/workspace/models
DEBUG_PORT=5678
END

# Load and use
source .env
make dev-session
```

### Example 3: Multiple Projects

```bash
# Project A
cd ~/project-a
export NAMESPACE=project-a
export LOCAL_DIR=./src
make sync-code

# Project B
cd ~/project-b
export NAMESPACE=project-b
export LOCAL_DIR=./code
make sync-code
```

### Example 4: CI/CD Pipeline

```bash
#!/bin/bash
# deploy.sh

# Load environment-specific config
if [ "$ENV" = "production" ]; then
    export NAMESPACE=ml-prod
    export POD_NAME=ml-prod-worker
else
    export NAMESPACE=ml-dev
    export POD_NAME=ml-dev-worker
fi

# Deploy and sync
make deploy
make sync-code
```

## ✅ Best Practices

1. **Use .env for personal development**
   - Add `.env` to `.gitignore`
   - Commit `.env.example` with defaults

2. **Use environment variables for temporary changes**
   ```bash
   NAMESPACE=test make dev-session
   ```

3. **Use command-line args for one-off commands**
   ```bash
   ./scripts/debug-remote.sh train.py other-pod
   ```

4. **Document your team's config in .env.example**
   ```bash
   # .env.example
   # Team configuration for ML development
   NAMESPACE=ml-team        # Our team namespace
   POD_NAME=ml-dev-env      # Standard dev pod
   LOCAL_DIR=./workspace    # Local code location
   ```

## 🐞 Troubleshooting

### "Pod not found"

Check your POD_NAME and NAMESPACE:
```bash
# See what you're using
make help

# List available pods
oc get pods -n $NAMESPACE

# Update configuration
export POD_NAME=correct-pod-name
```

### "Directory not found"

Check your LOCAL_DIR:
```bash
# Current setting
echo $LOCAL_DIR

# List local directory
ls -la $LOCAL_DIR

# Fix path
export LOCAL_DIR=./correct/path
```

### "Port already in use"

Use a different DEBUG_PORT:
```bash
# Check what's using the port
lsof -i :5678

# Use different port
DEBUG_PORT=5679 make dev-session
```

## 📚 Summary

**Quick override:** `NAMESPACE=foo make dev-session`

**Persistent config:** Create `.env` file and `source .env`

**Script args:** `./scripts/sync-code.sh ./src /app my-pod my-ns`

**Check config:** `make help`

Choose the method that fits your workflow! 🚀
