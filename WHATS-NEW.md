# What's New: Configurable Development Scripts

The development automation scripts now support full configuration via environment variables, command-line arguments, or .env files.

## 🎉 New Features

### 1. Configurable Everything

You can now customize:
- **Namespace** (`NAMESPACE`)
- **Pod name** (`POD_NAME`)
- **Local directory** (`LOCAL_DIR`)
- **Remote directory** (`REMOTE_DIR`)
- **Debug port** (`DEBUG_PORT`)

### 2. Multiple Configuration Methods

**Environment Variables:**
```bash
export NAMESPACE=my-namespace
export POD_NAME=my-pod
make dev-session
```

**Inline with Make:**
```bash
NAMESPACE=ml-prod POD_NAME=prod-pod make sync-code
```

**.env File:**
```bash
cp .env.example .env
# Edit .env
source .env
make dev-session
```

**Script Arguments:**
```bash
./scripts/sync-code.sh ./src /app my-pod my-namespace
```

### 3. New Files

- **`.env.example`** - Example configuration file
- **`CONFIGURATION-GUIDE.md`** - Complete configuration documentation
- **`QUICK-CONFIG-REFERENCE.md`** - Quick reference card

## 📝 Updated Files

### Scripts (scripts/)
- **`sync-code.sh`** - Now accepts: `[local_dir] [remote_dir] [pod_name] [namespace]`
- **`debug-remote.sh`** - Now accepts: `[script] [pod_name] [namespace] [port]`
- **`dev-session.sh`** - Now accepts: `[script] [local_dir] [remote_dir] [pod] [namespace] [port]`

### Makefile
- Added `NAMESPACE`, `POD_NAME`, `LOCAL_DIR`, `REMOTE_DIR`, `DEBUG_PORT` variables
- Updated all dev targets to pass variables to scripts
- Updated `help` output to show configuration

### Documentation
- **`AUTOMATION-GUIDE.md`** - Added configuration section
- **`QUICK-DEV-GUIDE.md`** - Still works with defaults
- **`REMOTE-DEBUG-WALKTHROUGH.md`** - Still works as-is

## 🔄 Backwards Compatible

All existing commands still work with defaults:

```bash
make dev-session              # Still works!
./scripts/sync-code.sh        # Still works!
make debug-remote FILE=test.py # Still works!
```

## 🚀 Quick Start

**Using defaults (no changes needed):**
```bash
make dev-session
```

**Custom configuration:**
```bash
# Method 1: Environment variables
export NAMESPACE=ml-team
export POD_NAME=gpu-worker
make dev-session

# Method 2: Inline
NAMESPACE=ml-prod make sync-code

# Method 3: .env file
cp .env.example .env
source .env
make dev-session
```

## 📚 Documentation

- **Quick reference:** `QUICK-CONFIG-REFERENCE.md`
- **Full guide:** `CONFIGURATION-GUIDE.md`
- **Examples:** `AUTOMATION-GUIDE.md`

## 🎯 Common Use Cases

### Multiple Namespaces
```bash
NAMESPACE=dev make dev-session
NAMESPACE=prod make sync-code
```

### Different Directory Structure
```bash
LOCAL_DIR=./src REMOTE_DIR=/app make sync-code
```

### Multiple Pods
```bash
POD_NAME=worker-1 make dev-session
POD_NAME=worker-2 DEBUG_PORT=5679 make dev-session
```

### Team Configuration
```bash
cat > .env.team << 'END'
NAMESPACE=ml-team
POD_NAME=shared-gpu
LOCAL_DIR=./models
REMOTE_DIR=/workspace/models
END

source .env.team
make dev-session
```

## ✅ Check Configuration

See what configuration will be used:
```bash
make help
```

Shows:
```
Current configuration:
  Namespace:   nccl-test
  Pod name:    ml-dev-env
  Local dir:   ./workspace
  Remote dir:  /workspace
  Debug port:  5678
```

## 🎓 Learn More

1. Read **QUICK-CONFIG-REFERENCE.md** for quick examples
2. Read **CONFIGURATION-GUIDE.md** for complete documentation
3. Try different configurations with your workflow

Everything is backwards compatible - your existing commands work unchanged! 🎉
