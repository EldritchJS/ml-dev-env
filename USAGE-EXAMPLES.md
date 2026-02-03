# Usage Examples

Quick examples of common deployment scenarios with namespace configuration.

## Default Namespace

```bash
# Uses nccl-test by default
make deploy
make status
make shell
```

## Custom Namespace - One Command

```bash
# Deploy to ml-production
NAMESPACE=ml-production make deploy

# Check status in ml-staging
NAMESPACE=ml-staging make status

# Shell into ml-dev
NAMESPACE=ml-dev make shell
```

## Custom Namespace - Persistent

```bash
# Set once, use everywhere
export NAMESPACE=team-gpu-cluster
make deploy
make test
make shell
make vscode
```

## Using .env File

```bash
# Create config
cat > .env << 'ENVFILE'
NAMESPACE=my-ml-namespace
ENVFILE

# Load it
source .env

# Deploy
make deploy
```

## Using Deploy Script

```bash
# All operations support namespace
NAMESPACE=ml-prod ./deploy.sh deploy
NAMESPACE=ml-prod ./deploy.sh status
NAMESPACE=ml-prod ./deploy.sh shell
NAMESPACE=ml-prod ./deploy.sh clean
```

## Multiple Namespaces

```bash
# Deploy to dev
NAMESPACE=ml-dev make deploy

# Deploy to staging (different namespace)
NAMESPACE=ml-staging make deploy

# Deploy to production
NAMESPACE=ml-production make deploy

# Each namespace is independent with own resources
```

## Per-User Namespaces

```bash
# Each user gets their own namespace
export NAMESPACE=gpu-$(whoami)
make deploy

# Results in:
# - gpu-jschless
# - gpu-alice
# - gpu-bob
```

## CI/CD Example

```bash
#!/bin/bash
# deploy-pipeline.sh

# Set namespace based on git branch
case "$GIT_BRANCH" in
  main)
    NAMESPACE=ml-production
    ;;
  staging)
    NAMESPACE=ml-staging
    ;;
  develop)
    NAMESPACE=ml-dev
    ;;
  *)
    NAMESPACE=ml-feature-${GIT_BRANCH}
    ;;
esac

echo "Deploying to namespace: $NAMESPACE"
NAMESPACE=$NAMESPACE make deploy
```

## Quick Commands Reference

```bash
# Build
NAMESPACE=my-ns make build

# Deploy
NAMESPACE=my-ns make deploy

# Status
NAMESPACE=my-ns make status

# Shell
NAMESPACE=my-ns make shell

# VSCode URL
NAMESPACE=my-ns make vscode

# GPU info
NAMESPACE=my-ns make gpu-info

# Test
NAMESPACE=my-ns make test

# Clean
NAMESPACE=my-ns make clean
```

## Verifying Current Namespace

```bash
# See current namespace in help
make help

# Output shows:
# Current namespace: nccl-test (or your custom namespace)
```

## Full Workflow Example

```bash
# 1. Set your namespace
export NAMESPACE=ml-team-alpha

# 2. Build the image
make build

# 3. Deploy everything
make deploy

# 4. Verify deployment
make status

# 5. Get URLs
make vscode
make jupyter

# 6. Test GPUs
make test

# 7. Open shell
make shell

# 8. Later: clean up
make clean
```

All commands respect the `NAMESPACE` environment variable!
