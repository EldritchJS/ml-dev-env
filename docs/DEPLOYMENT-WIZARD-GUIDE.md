# Deployment Wizard Guide

Interactive tool to configure and deploy your ML development environment with exactly the features you need.

## Overview

The deployment wizard guides you through:

1. ✅ **Selecting a cluster** from available configurations
2. ✅ **Choosing deployment mode** (single-node or multi-node)
3. ✅ **Selecting features** (VSCode, Jupyter, file browser, etc.)
4. ✅ **Configuring resources** (GPUs, memory, storage)
5. ✅ **Generating deployment commands** ready to execute
6. ✅ **Saving configurations** for reuse

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
  Step 4: Configure Resources
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

## Best Practices

1. **Save configurations** - Always save for documentation and reuse
2. **Version control** - Commit deployment configs to git
3. **Test first** - Try single-node before multi-node
4. **Start small** - Begin with fewer resources, scale up as needed
5. **Document choices** - Add comments to saved configs explaining decisions
6. **Review commands** - Always review generated commands before executing
7. **Incremental deployment** - Deploy base environment first, add features later

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
- ✅ Generating correct deployment commands
- ✅ Creating reusable configurations
- ✅ Providing executable deployment scripts

Perfect for:
- New users getting started
- Teams standardizing deployments
- Quickly deploying to new clusters
- Documenting deployment configurations
