# Quick Configuration Reference

## Default Configuration

```bash
NAMESPACE=nccl-test
POD_NAME=ml-dev-env
LOCAL_DIR=./workspace
REMOTE_DIR=/workspace
DEBUG_PORT=5678
```

## Override Methods

### 1. Environment Variables (Recommended)

```bash
export NAMESPACE=my-namespace
export POD_NAME=my-pod
export LOCAL_DIR=./src
export REMOTE_DIR=/app
export DEBUG_PORT=5679

make dev-session
```

### 2. Inline with Make

```bash
NAMESPACE=my-ns POD_NAME=my-pod make dev-session
```

### 3. .env File

```bash
cp .env.example .env
# Edit .env with your values
source .env
make dev-session
```

### 4. Script Arguments

```bash
# sync-code.sh [local_dir] [remote_dir] [pod_name] [namespace]
./scripts/sync-code.sh ./src /app my-pod my-namespace

# debug-remote.sh [script] [pod_name] [namespace] [port]
./scripts/debug-remote.sh train.py my-pod my-namespace 5679

# dev-session.sh [script] [local_dir] [remote_dir] [pod] [namespace] [port]
./scripts/dev-session.sh train.py ./src /app my-pod my-ns 5679
```

## Common Commands

```bash
# Check current configuration
make help

# Dev session with custom pod
POD_NAME=gpu-pod make dev-session

# Sync custom directory
LOCAL_DIR=./src REMOTE_DIR=/app make sync-code

# Debug on custom port
DEBUG_PORT=5679 make debug-remote FILE=train.py

# Full custom config
NAMESPACE=ml-prod POD_NAME=prod-pod LOCAL_DIR=./code make dev-session
```

## Quick Examples

```bash
# Team namespace
NAMESPACE=ml-team make dev-session

# Different directory structure
LOCAL_DIR=./src REMOTE_DIR=/app/src make sync-code

# Multiple pods (different terminals)
POD_NAME=worker-1 DEBUG_PORT=5678 make dev-session
POD_NAME=worker-2 DEBUG_PORT=5679 make dev-session

# Production deployment
source .env.prod && make sync-code
```
