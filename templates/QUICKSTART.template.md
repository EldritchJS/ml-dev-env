# {project_name} - ML Development Environment

**Created:** {created_date}

## Your Configuration

- **Cluster:** {cluster_name}
- **Mode:** {deployment_mode}
- **Network:** {network_mode}
- **Nodes:** {num_nodes}
- **GPUs:** {total_gpus} ({gpus_per_node} per node)
- **Image:** {image_type}
{image_details}- **Storage:** {workspace_size}GB workspace{datasets_storage}
- **Features:** {enabled_features}

## Quick Start

### 1. Deploy Your Environment

```bash
# From this directory
./scripts/deploy.sh
```

This will:
- Create service account and permissions
- Set up persistent storage volumes
- Deploy your {deployment_mode} environment
{deploy_details}

### 2. Access Your Environment

**VSCode (Browser-based IDE):**
```bash
./scripts/vscode.sh
```
Opens VSCode in your browser with full access to your workspace.

**Jupyter Notebook:**
```bash
./scripts/jupyter.sh
```
{jupyter_details}

**Shell Access:**
```bash
./scripts/shell.sh
```
Drops you into a terminal on your {shell_target}.

### 3. Sync Your Code

```bash
# Sync local code to your environment
./scripts/sync.sh

# This copies ./workspace/ to /workspace in your pods
```

**Auto-sync mode:**
```bash
# Watches for file changes and syncs automatically
./scripts/sync.sh --watch
```

### 4. Run Your Training

{training_instructions}

### 5. Monitor Your Environment

**Check Status:**
```bash
./scripts/status.sh
```

**View Logs:**
```bash
./scripts/logs.sh
```
{monitoring_details}

**GPU Monitoring:**
```bash
./scripts/shell.sh
nvidia-smi  # Inside the pod
```

### 6. Cleanup

When you're done, clean up all resources:

```bash
./scripts/cleanup.sh
```

This removes:
- All pods/StatefulSets
- Service accounts
- Routes and services
- **Note:** PVCs are preserved by default. Use `./scripts/cleanup.sh --all` to delete storage too.

## Your Workspace

Your code lives in:
- **Local:** `./workspace/`
- **Remote:** `/workspace` (in pods)
- **Storage:** Backed by {workspace_size}GB PVC
{datasets_info}

**Recommended structure:**
```
workspace/
├── data/              # Small datasets
├── models/            # Model checkpoints
├── scripts/           # Training scripts
├── notebooks/         # Jupyter notebooks
└── results/           # Training outputs
```

## Advanced Usage

### Custom Make Commands

You can still use the root Makefile with your project:

```bash
# From the ml-dev-env root directory
make deploy-cluster CLUSTER={cluster_name} MODE={network_mode} PROJECT={project_name}
make sync-multi-node PROJECT={project_name}
make shell-multi-node PROJECT={project_name}
make status-cluster CLUSTER={cluster_name} PROJECT={project_name}
```

### Project Configuration

Your project configuration is saved in `config.yaml`. You can:
- Edit it manually
- Reload it: `../../scripts/deployment_wizard.py --config config.yaml --project {project_name}`
- Copy it for new projects

### Generated Manifests

Kubernetes manifests are in `generated/`:
- `serviceaccount.yaml` - Permissions
- `pvcs.yaml` - Storage volumes
- `statefulset.yaml` - Compute pods

You can inspect or manually apply these:
```bash
oc apply -f generated/
```

## Troubleshooting

**Pods not starting:**
```bash
./scripts/status.sh
oc describe pod {pod_name} -n {namespace}
```

**GPUs not detected:**
```bash
./scripts/shell.sh
nvidia-smi
```
{rdma_troubleshooting}

**Storage issues:**
```bash
oc get pvc -n {namespace}
oc describe pvc ml-dev-workspace -n {namespace}
```

**Need to rebuild?**
```bash
./scripts/cleanup.sh
./scripts/deploy.sh
```

## Documentation

- [Main README](../../README.md)
- [Multi-Node Guide](../../docs/MULTI-NODE-GUIDE.md)
- [Deployment Wizard Guide](../../docs/DEPLOYMENT-WIZARD-GUIDE.md)
- [Cluster Configuration](../../docs/CLUSTER-CONFIG-GUIDE.md)

## Project Files

```
{project_name}/
├── config.yaml              # Your deployment configuration
├── QUICKSTART.md           # This file
├── generated/              # Generated Kubernetes manifests
├── workspace/              # Your code (syncs to /workspace in pods)
└── scripts/                # Convenience scripts
    ├── deploy.sh          # Deploy this project
    ├── sync.sh            # Sync code
    ├── shell.sh           # Shell access
    ├── vscode.sh          # Open VSCode
    ├── jupyter.sh         # Start Jupyter
    ├── status.sh          # Check status
    ├── logs.sh            # View logs
    └── cleanup.sh         # Clean up resources
```

---

**Need help?** Check the [documentation](../../docs/) or ask in your team channel.
