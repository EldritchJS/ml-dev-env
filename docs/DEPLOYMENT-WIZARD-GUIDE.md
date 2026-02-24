# Deployment Wizard Guide

Interactive tool to configure and deploy your ML development environment with exactly the features you need.

## Overview

The deployment wizard guides you through:

1. ✅ **Selecting a cluster** from available configurations
2. ✅ **Choosing deployment mode** (single-node or multi-node)
3. ✅ **Selecting features** (VSCode, Jupyter, file browser, etc.)
4. ✅ **Selecting/building container image** (pre-built or custom packages)
5. ✅ **Configuring resources** (GPUs, memory, storage)
6. ✅ **Generating deployment commands** ready to execute
7. ✅ **Saving configurations** for reuse

## Quick Start

### Run the Wizard

```bash
# Interactive wizard
make wizard

# Or run directly
./scripts/deployment-wizard.py
```

### Example Session

```
==============================================================
  🚀 ML Development Environment Deployment Wizard
==============================================================

This wizard will help you configure and deploy your
machine learning development environment.

==============================================================
  Step 1: Select Cluster
==============================================================

Available clusters:
  1. barcelona - barcelona.nerc.mghpcc.org (RDMA, VOLUMECLAIMTEMPLATES, 4 GPUs/node)
  2. nerc-production - api.shift.nerc.mghpcc.org (TCP, RWX, 4 GPUs/node)

Select cluster:
Enter choice [1-2] (default: 1): 2

✓ Selected: nerc-production

==============================================================
  Step 2: Deployment Mode
==============================================================

Select deployment mode:
  1. Single-node (1 pod, 4 GPUs) - Development & testing
  2. Multi-node (Multiple pods) - Distributed training

Enter choice [1-2] (default: 1): 2

  ℹ️  This cluster only supports TCP networking

How many nodes to use? (max 25) (default: 2): 4

✓ Deployment mode: multi-node
✓ Network mode: tcp
✓ Number of nodes: 4

==============================================================
  Step 3: Select Features
==============================================================

Select which features to enable:

📝 Development Tools:
  Enable VSCode Server (browser-based IDE)? [Y/n]: y
  Enable Jupyter Notebook? [Y/n]: y
  Enable TensorBoard? [Y/n]: y

🛠️  Utilities:
  Enable PVC file browser (web-based)? [Y/n]: y

🤖 ML Frameworks (included in image):
  ✓ PyTorch 2.9 with CUDA 13.0
  ✓ DeepSpeed (distributed training)
  ✓ Flash Attention 2.7.4
  ✓ Transformers (Hugging Face)

📊 Monitoring:
  Configure Weights & Biases tracking? [Y/n]: n

✓ Enabled features: vscode, jupyter, tensorboard, pvc_browser

==============================================================
  Step 4: Container Image
==============================================================

Choose how to provide the container image:

  1. Use pre-built image (PyTorch 2.8, 2.9, or custom URL)
  2. Build custom image (specify packages)

Select image option:
Enter choice [1-2] (default: 1): 1

📦 Pre-built Image Selection

Select pre-built image:
  1. PyTorch 2.8 + NumPy 1.x (image-registry.../ml-dev-env:pytorch-2.8-numpy1)
  2. PyTorch 2.9 + NumPy 2.x (image-registry.../ml-dev-env:pytorch-2.9-numpy2)
  3. Custom image URL (enter manually)

Enter choice [1-3] (default: 2): 2

✓ Selected image: image-registry.openshift-image-registry.svc:5000/coops-767192/ml-dev-env:pytorch-2.9-numpy2

==============================================================
  Step 5: Configure Resources
==============================================================

🖥️  Resource Configuration:

  ℹ️  Using 4 GPUs per node × 4 nodes = 16 total GPUs

💾 Storage:
Workspace PVC size (GB)? (default: 100): 200
Need separate datasets PVC? [Y/n]: y
Datasets PVC size (GB)? (default: 500): 1000

✓ Resources configured
```

## Features

### Cluster Selection

The wizard automatically discovers available cluster configurations from `clusters/` directory and displays:

- Cluster name
- API endpoint
- Networking mode (RDMA or TCP)
- Storage type (RWX or per-pod)
- GPUs per node

**What you choose:**

- Which cluster to deploy to

### Deployment Mode

**Single-node:**

- One pod with multiple GPUs
- Best for development and testing
- Simpler setup

**Multi-node:**

- Multiple pods across nodes
- Distributed training with DeepSpeed
- RDMA or TCP networking
- Configurable number of nodes

**What you choose:**

- Single-node or multi-node
- Network mode (RDMA/TCP) if available
- Number of nodes (multi-node only)

### Feature Selection

**Development Tools:**

- ✅ **VSCode Server** - Browser-based IDE
- ✅ **Jupyter Notebook** - Interactive development
- ✅ **TensorBoard** - Training visualization

**Utilities:**

- ✅ **PVC File Browser** - Web-based file management

**Monitoring:**

- ✅ **Weights & Biases** - Experiment tracking

**What you choose:**

- Which tools to enable/configure

### Container Image Selection

Choose between pre-built images or build custom images with your specific package requirements.

**Pre-built Images:**

- ✅ **PyTorch 2.8 + NumPy 1.x** - Compatible with legacy NumPy 1.x packages
- ✅ **PyTorch 2.9 + NumPy 2.x** - Latest PyTorch with NumPy 2.x (recommended)
- ✅ **Custom URL** - Provide your own image from any registry

**Custom Image Building:**

Build a container image with custom packages on-demand:

- Choose base PyTorch version (2.8, 2.9, 3.0, or custom)
- Specify packages interactively or via requirements.txt
- Real-time build monitoring with progress
- Automatic error detection and recovery
- Build completes before deployment

**When to use custom builds:**

- Need specific package versions not in pre-built images
- Require additional ML libraries (e.g., JAX, MXNet)
- Want to pre-install proprietary or internal packages
- Need different versions of transformers, datasets, etc.

**What you choose:**

- Pre-built image or custom build
- Base PyTorch version (if building)
- Additional packages to install

#### Custom Image Building Process

When you choose to build a custom image, the wizard:

1. **Selects base image:**
   - PyTorch 2.8 (nvcr.io/nvidia/pytorch:25.08-py3)
   - PyTorch 2.9 (nvcr.io/nvidia/pytorch:25.09-py3) - Recommended
   - PyTorch 3.0 (nvcr.io/nvidia/pytorch:26.01-py3)
   - Custom base image URL

2. **Specifies packages:**
   - **Interactive:** Enter packages one by one
   - **File-based:** Upload requirements.txt

3. **Builds immediately:**
   - Generates OpenShift BuildConfig
   - Triggers build on cluster
   - Monitors progress in real-time
   - Shows build steps (Step 5/12, etc.)

4. **Validates completion:**
   - Waits for build to finish
   - Retrieves final image reference
   - Uses image in deployment

5. **Handles errors:**
   - Detects network, disk space, or package errors
   - Suggests recovery actions
   - Offers retry or fallback to pre-built

**Example: Interactive Package Entry**

```
Step 2: Specify packages to install

How to specify packages:
  1. Enter packages interactively (one by one)
  2. Upload requirements.txt file

Enter choice [1-2] (default: 1): 1

Enter package names (one per line). Press Enter with empty line when done.
Package 1 (or Enter to finish): transformers==4.38.0
Package 2 (or Enter to finish): datasets
Package 3 (or Enter to finish): wandb
Package 4 (or Enter to finish):

Build Configuration
===================
Build name: ml-dev-custom-20260224143022-a4b9
Image tag: custom-barcelona-20260224143022
Packages: transformers==4.38.0, datasets, wandb

Start build now? [Y/n]: y

Building Image
==============
[00:15] [2/12] Step 2/12: FROM nvcr.io/nvidia/pytorch:25.09-py3
[00:42] [5/12] Step 5/12: RUN pip install --no-cache-dir transformers==4.38.0
[01:20] [8/12] Step 8/12: Installing datasets
[02:05] [12/12] Step 12/12: Push successful

✓ Build completed successfully!
  Image: image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env@sha256:abc123...
```

**Example: Requirements File**

```
How to specify packages:
  1. Enter packages interactively (one by one)
  2. Upload requirements.txt file

Enter choice [1-2] (default: 1): 2

Enter path to requirements.txt: ./my-requirements.txt
✓ Requirements file: ./my-requirements.txt

Build Configuration
===================
Build name: ml-dev-custom-20260224143145-k7x2
Image tag: custom-barcelona-20260224143145
Requirements: ./my-requirements.txt

Start build now? [Y/n]: y
```

**Build Error Handling**

If the build fails, the wizard analyzes the error and suggests recovery:

```
BUILD FAILED
============

Error Type: package_not_found
Message: Package not found: invalid-pkg-name
Recovery: Check package name spelling and version requirements

Options:
  1. Retry build
  2. Use a pre-built image instead
  3. Exit

Enter choice [1-3]: 2

Falling back to pre-built image...
```

**Common Build Errors:**

| Error Type | Cause | Recovery |
|------------|-------|----------|
| **package_not_found** | Typo in package name or version doesn't exist | Fix package name/version, retry |
| **dependency_conflict** | Incompatible package versions | Adjust versions, check compatibility |
| **network** | Timeout or connection failure | Retry, check cluster network |
| **disk_space** | Insufficient build storage | Contact admin to increase quota |

### Resource Configuration

**GPUs:**

- Single-node: Choose number of GPUs (1-4 typically)
- Multi-node: Uses all GPUs per node

**Storage:**

- Workspace PVC size
- Optional separate datasets PVC

**What you choose:**

- GPU allocation
- Storage sizes

## Output

### Deployment Commands

The wizard generates a complete deployment script:

```bash
# 1. Login and setup namespace
oc login  # Login to cluster
oc project coops-767192

# 2. Create service account
oc create serviceaccount ml-dev-sa -n coops-767192

# 3. Deploy multi-node environment
make deploy-cluster CLUSTER=nerc-production MODE=tcp

# 4. Deploy PVC file browser
sed 's/YOUR-PVC-NAME/ml-dev-workspace/' k8s/pvc-filebrowser.yaml | oc apply -f - -n coops-767192
oc get route pvc-browser -n coops-767192 -o jsonpath='https://{.spec.host}' && echo

# 5. Access your environment
make vscode  # Get VSCode URL
make jupyter  # Start Jupyter
make shell  # Shell into pod
```

### Saved Configuration

Optionally save your configuration to YAML:

```yaml
# ML Development Environment Deployment Configuration
# Generated by deployment-wizard.py

deployment:
  cluster: nerc-production
  mode: multi-node
  network_mode: tcp
  num_nodes: 4
features:
  vscode: true
  jupyter: true
  tensorboard: true
  pvc_browser: true
  wandb: false
image:
  type: prebuilt
  url: image-registry.openshift-image-registry.svc:5000/coops-767192/ml-dev-env:pytorch-2.9-numpy2
resources:
  gpus_per_node: 4
  total_gpus: 16
storage:
  workspace_size: 200
  datasets_size: 1000
```

### Deployment Script

The wizard creates an executable shell script:

```bash
#!/bin/bash
# Auto-generated deployment script
# Configuration: nerc-production
# Mode: multi-node

set -e

oc login
oc project coops-767192
oc create serviceaccount ml-dev-sa -n coops-767192
make deploy-cluster CLUSTER=nerc-production MODE=tcp
# ... additional commands
```

## Usage Patterns

### Pattern 1: First-Time Deployment

```bash
# Run wizard
make wizard

# Follow prompts
# Save configuration as: my-deployment.yaml
# Save script as: deploy-nerc-production.sh

# Review and execute
cat deploy-nerc-production.sh
./deploy-nerc-production.sh
```

### Pattern 2: Reuse Saved Configuration

```bash
# Load previous configuration
make wizard-load CONFIG=my-deployment.yaml

# Or with script
./scripts/deployment-wizard.py --config my-deployment.yaml

# Configuration is displayed
# Execute commands manually or create new script
```

### Pattern 3: Non-Interactive Mode

```bash
# Use defaults from saved config
./scripts/deployment-wizard.py --config my-deployment.yaml --non-interactive
```

### Pattern 4: Multiple Environments

```bash
# Create configs for different environments
make wizard  # Save as: dev-deployment.yaml
make wizard  # Save as: prod-deployment.yaml

# Deploy dev
make wizard-load CONFIG=dev-deployment.yaml

# Deploy prod
make wizard-load CONFIG=prod-deployment.yaml
```

## Advanced Usage

### Custom Configuration Files

Manually create or edit configuration YAML:

```yaml
deployment:
  cluster: barcelona
  mode: multi-node
  network_mode: rdma
  num_nodes: 2
features:
  vscode: true
  jupyter: false
  tensorboard: true
  pvc_browser: false
  wandb: true
resources:
  gpus_per_node: 4
  total_gpus: 8
storage:
  workspace_size: 100
  datasets_size: 500
```

Load with wizard:

```bash
./scripts/deployment-wizard.py --config custom-config.yaml
```

### Batch Deployments

Create multiple configurations and deploy programmatically:

```bash
# Create configs
for env in dev staging prod; do
  # Edit template for each environment
  cp deployment-template.yaml ${env}-deployment.yaml
  # Modify as needed
done

# Deploy all
for config in *-deployment.yaml; do
  echo "Deploying $config..."
  ./scripts/deployment-wizard.py --config $config --non-interactive
done
```

### Integration with CI/CD

```yaml
# .github/workflows/deploy.yml
steps:
  - name: Deploy ML Environment
    run: |
      ./scripts/deployment-wizard.py \
        --config deployments/production.yaml \
        --non-interactive
```

## Troubleshooting

### No Clusters Available

**Issue:**

```
⚠️  No cluster configurations found in clusters/ directory
```

**Solution:**
Create a cluster configuration:

```bash
# Auto-discover
make discover-cluster NAME=my-cluster

# Or manually
cp clusters/template.yaml clusters/my-cluster.yaml
vim clusters/my-cluster.yaml
```

### Configuration File Not Found

**Issue:**

```
Error: Configuration file not found: my-config.yaml
```

**Solution:**
Check the file path:

```bash
ls -l my-config.yaml
# Use absolute path if needed
./scripts/deployment-wizard.py --config /full/path/to/my-config.yaml
```

### Invalid Configuration

**Issue:**
Configuration loads but values are wrong

**Solution:**
Validate YAML syntax:

```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('my-config.yaml'))"

# Review structure
cat my-config.yaml
```

### Custom Image Build Failures

**Issue: Build fails with "package not found"**

```
ERROR: Could not find a version that satisfies the requirement my-package
```

**Solution:**
- Check package name spelling on PyPI
- Verify version exists: https://pypi.org/project/my-package/
- Try without version specifier first
- Check for typos in requirements.txt

**Issue: Build fails with dependency conflict**

```
ERROR: transformers 4.38.0 requires tokenizers>=0.19.0, but you have tokenizers 0.15.0
```

**Solution:**
- Remove conflicting version pins
- Let pip resolve dependencies automatically
- Check package compatibility matrix
- Use a different base image version

**Issue: Build timeout**

```
Build timed out after 30 minutes
```

**Solution:**
- Reduce number of packages being installed
- Split into multiple smaller builds
- Check cluster build timeout limits
- Consider pre-built image with most packages

**Issue: Network errors during build**

```
ERROR: Connection refused when trying to fetch package
```

**Solution:**
- Retry the build (network issue may be temporary)
- Check cluster internet connectivity
- Verify PyPI is accessible from cluster
- Contact cluster administrator

**Issue: Disk space errors**

```
ERROR: No space left on device
```

**Solution:**
- Contact cluster administrator to increase build storage quota
- Use pre-built image as fallback
- Reduce number of packages in custom build

**Issue: Build succeeds but pod won't start**

**Solution:**
Check image reference in deployment:

```bash
# Verify image was pushed
oc get imagestream ml-dev-env -o yaml

# Check pod events
oc get events --sort-by='.lastTimestamp'

# Verify image pull
oc describe pod <pod-name>
```

## Examples

### Example 1: Development Setup

**Goal:** Single-node setup for development

```bash
make wizard

# Selections:
# - Cluster: nerc-production
# - Mode: Single-node
# - Features: VSCode, Jupyter, TensorBoard
# - GPUs: 2
# - Storage: 50 GB workspace

# Output: deploy-dev.sh
./deploy-dev.sh
```

### Example 2: Multi-Node Training

**Goal:** 4-node distributed training with RDMA

```bash
make wizard

# Selections:
# - Cluster: barcelona
# - Mode: Multi-node
# - Network: RDMA
# - Nodes: 4
# - Features: TensorBoard, W&B
# - Storage: 100 GB workspace, 500 GB datasets

# Output: deploy-training.sh
./deploy-training.sh
```

### Example 3: Production Deployment

**Goal:** Large-scale deployment with monitoring

```bash
make wizard

# Selections:
# - Cluster: nerc-production
# - Mode: Multi-node
# - Nodes: 8
# - Features: All enabled
# - Storage: 500 GB workspace, 2 TB datasets

# Save config: production-deployment.yaml
# Save script: deploy-production.sh

# Review before deploying
cat deploy-production.sh
./deploy-production.sh
```

### Example 4: Reuse Configuration

**Goal:** Deploy same setup on different cluster

```bash
# Save initial config
make wizard  # Save as: template-deployment.yaml

# Edit for new cluster
cp template-deployment.yaml new-cluster-deployment.yaml
vim new-cluster-deployment.yaml
# Change: deployment.cluster to new-cluster

# Deploy
make wizard-load CONFIG=new-cluster-deployment.yaml
```

### Example 5: Custom Image with Specific Packages

**Goal:** Build custom image with specific transformers and LLaMA Factory versions

```bash
make wizard

# Selections:
# - Cluster: barcelona
# - Mode: Single-node
# - Features: VSCode, Jupyter
# - Image: Build custom image
#   - Base: PyTorch 2.9
#   - Packages (interactive):
#     * transformers==4.38.2
#     * datasets==2.18.0
#     * llamafactory==0.7.1
#     * peft
#     * trl
# - GPUs: 4
# - Storage: 100 GB workspace

# Build starts immediately
# Monitor progress: [02:15] [8/12] Step 8/12: Installing packages...
# ✓ Build complete

# Generated config includes:
# image:
#   type: custom_build
#   url: image-registry.../ml-dev-env@sha256:abc123...
#   build:
#     base_image: nvcr.io/nvidia/pytorch:25.09-py3
#     packages:
#       - transformers==4.38.2
#       - datasets==2.18.0
#       - llamafactory==0.7.1
#       - peft
#       - trl

# Deploy with custom image
./deploy-barcelona.sh
```

### Example 6: Custom Image with Requirements File

**Goal:** Build image from existing requirements.txt

Create `my-requirements.txt`:
```
# Custom ML packages
transformers>=4.38.0
datasets>=2.18.0
accelerate>=0.27.0
peft>=0.9.0
trl>=0.7.10

# Additional tools
wandb
tensorboard
jupyterlab
```

Run wizard:
```bash
make wizard

# Selections:
# - Cluster: nerc-production
# - Mode: Multi-node, 2 nodes
# - Features: VSCode, TensorBoard, W&B
# - Image: Build custom image
#   - Base: PyTorch 2.9
#   - Packages: Upload requirements.txt file
#   - File: ./my-requirements.txt
# - Storage: 200 GB workspace

# Build processes all packages from file
# ✓ Build complete: all 10 packages installed

# Deploy
./deploy-nerc-production.sh
```

## Best Practices

1. **Save configurations** - Always save for documentation and reuse
2. **Version control** - Commit deployment configs to git
3. **Test first** - Try single-node before multi-node
4. **Start small** - Begin with fewer resources, scale up as needed
5. **Document choices** - Add comments to saved configs explaining decisions
6. **Review commands** - Always review generated commands before executing
7. **Incremental deployment** - Deploy base environment first, add features later

### Custom Image Best Practices

8. **Start with pre-built** - Use pre-built images unless you need specific packages
9. **Test locally first** - Verify package compatibility locally before building
10. **Pin critical versions** - Pin important packages (transformers==4.38.0) but allow dependencies to resolve
11. **Keep builds minimal** - Only include packages you actually need
12. **Document requirements** - Keep requirements.txt in version control
13. **Reuse custom images** - Save image URL from successful builds for reuse
14. **Monitor build times** - Builds typically take 5-15 minutes; >30 min may indicate issues
15. **Have a fallback** - Always know which pre-built image you can fall back to

## Related Documentation

- [CLUSTER-DISCOVERY-GUIDE.md](CLUSTER-DISCOVERY-GUIDE.md) - Auto-discover clusters
- [CLUSTER-CONFIG-GUIDE.md](CLUSTER-CONFIG-GUIDE.md) - Cluster configuration reference
- [MULTI-NODE-QUICKSTART.md](MULTI-NODE-QUICKSTART.md) - Multi-node deployment
- [QUICKSTART.md](QUICKSTART.md) - Single-node deployment

## Command Reference

```bash
# Interactive wizard
make wizard
./scripts/deployment-wizard.py

# Load saved configuration
make wizard-load CONFIG=my-config.yaml
./scripts/deployment-wizard.py --config my-config.yaml

# Non-interactive mode
./scripts/deployment-wizard.py --config my-config.yaml --non-interactive

# Help
./scripts/deployment-wizard.py --help
```

## Summary

The deployment wizard simplifies ML environment deployment by:

- ✅ Guiding you through all configuration options
- ✅ Validating choices against cluster capabilities
- ✅ Building custom images with your packages on-demand
- ✅ Generating correct deployment commands
- ✅ Creating reusable configurations
- ✅ Providing executable deployment scripts

Perfect for:

- New users getting started
- Teams standardizing deployments
- Quickly deploying to new clusters
- Documenting deployment configurations
- Creating custom environments with specific package versions

## Cluster Discovery Integration

The wizard now includes built-in cluster discovery, so you don't need to run `make discover-cluster` separately.

### When to Use Discovery

**Discover a new cluster when:**
- You're connecting to a cluster for the first time
- You want to create a configuration for the currently connected cluster
- Cluster configuration has changed (new GPUs, RDMA enabled, etc.)

**Use existing cluster when:**
- You've already discovered/configured this cluster
- You want to use a pre-configured cluster from `clusters/` directory

### Discovery Workflow

When you run the wizard:

```bash
make wizard
```

You'll be prompted:

```
Step 1: Select Cluster
======================

Discover a new cluster (vs. use existing)? [y/N]:
```

**If you choose YES (discover):**

1. Enter cluster name (e.g., "my-cluster")
2. Choose to use current namespace or specify a custom one
3. The wizard auto-discovers:
   - Cluster API endpoint
   - GPU nodes and specifications
   - RDMA/InfiniBand devices
   - Storage classes (RWX/RWO)
   - Security requirements
4. Saves configuration to `clusters/my-cluster.yaml`
5. Proceeds with deployment configuration using the discovered cluster

**If you choose NO (use existing):**

1. Lists all available cluster configurations
2. You select from the list
3. Proceeds with deployment configuration

### Example: Discover and Deploy

```bash
# 1. Log in to your cluster
oc login https://api.my-cluster.com

# 2. Run the wizard
make wizard

# 3. When prompted, choose to discover:
Discover a new cluster (vs. use existing)? [y/N]: y

# 4. Name your cluster:
Cluster name [discovered-cluster]: production

# 5. Use current namespace:
Use current namespace? [Y/n]: y

# 6. Discovery runs automatically:
🔍 Discovering cluster 'production'...
✅ Cluster configuration saved to clusters/production.yaml

# 7. Continue with deployment configuration...
```

### What Gets Discovered

The wizard discovers the same information as `make discover-cluster`:

- **Cluster Info**: API endpoint, namespace
- **GPU Nodes**: Node names, GPU type, GPUs per node
- **RDMA/InfiniBand**: Mellanox devices, interfaces, configuration
- **Storage**: RWX and RWO storage classes
- **Security**: Service account requirements, SCC needs
- **Network**: TCP interface configuration

All of this is saved to a reusable cluster configuration file.

