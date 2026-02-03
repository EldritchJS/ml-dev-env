# Namespace Configuration Guide

The ML development environment can be deployed to any OpenShift namespace. By default, it uses `nccl-test`, but this can be easily changed.

## Why Use Custom Namespace?

- **Multi-tenancy**: Different teams use different namespaces
- **Environment separation**: dev, staging, production
- **Resource quotas**: Different quotas per namespace
- **Access control**: RBAC policies per namespace
- **Isolation**: Separate workloads and resources

## Configuration Methods

### Method 1: Environment Variable (Recommended)

Set the `NAMESPACE` environment variable before running make commands:

```bash
# One-time for a single command
NAMESPACE=my-ml-team make deploy

# Or export for all subsequent commands
export NAMESPACE=my-ml-team
make build
make deploy
make status
make shell
```

**Advantages:**
- Simple and flexible
- No file changes needed
- Easy to switch between namespaces

### Method 2: Deploy Script

Use the included `deploy.sh` script with namespace override:

```bash
# Deploy to custom namespace
NAMESPACE=ml-production ./deploy.sh deploy

# Check status
NAMESPACE=ml-production ./deploy.sh status

# Open shell
NAMESPACE=ml-production ./deploy.sh shell

# Clean up
NAMESPACE=ml-production ./deploy.sh clean
```

### Method 3: .env File

Create a `.env` file for persistent configuration:

```bash
# Create from template
cp .env.example .env

# Edit .env file
cat > .env << 'EOF'
NAMESPACE=my-gpu-namespace
EOF

# Source it
source .env

# Now all make commands use your namespace
make deploy
make status
```

**Advantages:**
- Configuration stored in file
- Easy to track in git (if not sensitive)
- Team can share configuration

### Method 4: Direct YAML Editing

For permanent changes, edit the namespace in YAML files:

```bash
# Using sed to replace in all files
sed -i.bak 's/namespace: nccl-test/namespace: my-namespace/g' *.yaml

# Or manually edit each YAML file:
# - imagestream.yaml
# - buildconfig.yaml
# - pod-multi-gpu.yaml
# - pvcs.yaml
# - service.yaml
```

Then deploy normally:
```bash
oc apply -f imagestream.yaml
oc apply -f buildconfig.yaml
# ... etc
```

**Advantages:**
- No need to remember to set NAMESPACE
- Good for single-namespace deployments

**Disadvantages:**
- Harder to switch namespaces
- Need to track changes in git

## Examples

### Example 1: Development Environment

```bash
export NAMESPACE=ml-dev
make deploy
make test
```

### Example 2: Production Deployment

```bash
# production.env
NAMESPACE=ml-production

# Deploy
source production.env
make deploy
```

### Example 3: Multiple Teams

```bash
# Team A
NAMESPACE=team-a-gpu make deploy

# Team B
NAMESPACE=team-b-gpu make deploy

# Each team has isolated environment
```

### Example 4: Per-User Namespaces

```bash
# User-specific namespace
export NAMESPACE=gpu-$(whoami)
make deploy

# Results in: gpu-jschless, gpu-alice, etc.
```

### Example 5: CI/CD Pipeline

```bash
#!/bin/bash
# ci-deploy.sh

# Determine namespace from branch
if [ "$GIT_BRANCH" = "main" ]; then
  NAMESPACE=ml-production
elif [ "$GIT_BRANCH" = "staging" ]; then
  NAMESPACE=ml-staging
else
  NAMESPACE=ml-dev-${GIT_BRANCH}
fi

# Deploy
NAMESPACE=$NAMESPACE make deploy
```

## Namespace Requirements

Ensure your target namespace has:

1. **GPU Resource Quota**
```bash
oc describe quota -n $NAMESPACE
# Should allow nvidia.com/gpu requests
```

2. **Storage Classes**
```bash
oc get storageclass
# Ensure 'standard' or update pvcs.yaml
```

3. **Image Pull Rights**
```bash
# Namespace needs access to NVIDIA NGC registry
oc get serviceaccount default -n $NAMESPACE -o yaml
# Check imagePullSecrets
```

4. **Network Policies** (if using host networking)
```bash
# Namespace may need network policy adjustments
oc get networkpolicies -n $NAMESPACE
```

## Switching Namespaces

To switch an existing deployment to a new namespace:

### Option A: Redeploy

```bash
# Clean up old namespace
NAMESPACE=old-namespace make clean

# Deploy to new namespace
NAMESPACE=new-namespace make deploy
```

### Option B: Copy Data

```bash
# If you need to preserve PVC data:

# 1. Create PVCs in new namespace
NAMESPACE=new-namespace oc apply -f pvcs.yaml

# 2. Run a data copy pod in old namespace
oc run data-copy --image=busybox -n old-namespace \
  --command -- sleep infinity

# 3. Mount both old and new PVCs, rsync data
# (requires custom pod with both PVCs mounted)

# 4. Deploy in new namespace
NAMESPACE=new-namespace make deploy
```

## Verification

After deploying to a custom namespace, verify:

```bash
# Set your namespace
export NAMESPACE=my-namespace

# Check all resources
make status

# Should show resources in your namespace
oc get all -n $NAMESPACE

# Verify pod is running
oc get pod ml-dev-env -n $NAMESPACE

# Check routes (URLs will include namespace)
oc get routes -n $NAMESPACE
```

## Troubleshooting

### Issue: "namespace not found"

```bash
# Create the namespace first
oc new-project $NAMESPACE
# Or: oc create namespace $NAMESPACE
```

### Issue: "insufficient quota"

```bash
# Check quotas
oc describe quota -n $NAMESPACE

# May need to request quota increase or use different namespace
```

### Issue: "can't pull image"

```bash
# Grant image pull access
oc policy add-role-to-user system:image-puller system:serviceaccount:$NAMESPACE:default \
  -n nccl-test

# Or make ImageStream pull from external registry
```

### Issue: Wrong namespace in URLs

Routes include the namespace in the URL pattern. If you see `nccl-test` in URLs but want `my-namespace`:

```bash
# Verify you're using namespace substitution
NAMESPACE=my-namespace make deploy

# Check routes
oc get routes -n my-namespace
```

## Best Practices

1. **Use environment variables** for flexibility
2. **Document namespace choice** in your project README
3. **Set resource quotas** per namespace to prevent over-allocation
4. **Use RBAC** to control who can deploy to which namespace
5. **Label resources** for easier filtering:
   ```bash
   oc label namespace $NAMESPACE team=ml-team
   ```

## Quick Reference

```bash
# Set namespace (choose one method)
export NAMESPACE=my-namespace          # Session-wide
NAMESPACE=my-namespace make deploy      # One-time
source .env                             # From file

# Deploy
make deploy                             # Uses $NAMESPACE or default

# Verify
make status                             # Shows current namespace
oc get all -n $NAMESPACE                # All resources

# Access
make shell                              # Opens shell in pod
make vscode                             # Get VSCode URL

# Clean up
make clean                              # Removes from $NAMESPACE
```

## Summary

- **Default**: `nccl-test`
- **Override**: Set `NAMESPACE` environment variable
- **Persistent**: Use `.env` file
- **Flexible**: Works with Makefile and deploy.sh
- **Validation**: Use `make status` to verify namespace

Choose the method that best fits your workflow!
