# ML Development Environment for OpenShift

A comprehensive GPU-accelerated machine learning development environment with **cluster-based deployment** for single-node and multi-node distributed training.

## 🚀 Deployment Options

### Multi-Node Distributed Training (Recommended)

Train across **multiple GPU nodes** using DeepSpeed with cluster-based configuration:

- **RDMA/InfiniBand** - High performance for production (requires InfiniBand hardware)
- **TCP/Ethernet** - Universal compatibility (works on any cluster)
- **Cluster configs** - All settings in one YAML file per cluster

### Single-Node Development

Development and testing on one node with 4x H100 GPUs.

## ✨ Features

### ML Frameworks & Libraries

- ✅ **PyTorch 2.9.0a0** (NVIDIA 25.09) with CUDA 13.0 support
- ✅ **DeepSpeed** - Distributed training optimization (ZeRO-2/3)
- ✅ **Flash Attention 2.7.4.post1** - Efficient attention computation (NVIDIA pre-built)
- ✅ **Transformers** - Hugging Face library
- ✅ **LLaMAFactory** - Efficient LLM fine-tuning
- ✅ **VideoLLaMA2** - Video understanding with LLMs
- ✅ **EasyR1** - Reinforcement learning tools
- ✅ **NumPy 2.2.6** - Latest version, fully compatible with all packages
- ✅ **ffmpeg** - Video/audio processing

**Available Images:**

- **ml-dev-env (PyTorch 2.9)** (default, full dev environment) - `pytorch-2.9-numpy2`
  - VSCode, Jupyter, DeepSpeed, Flash Attention, LLaMAFactory
- **h-kim (PyTorch 26.01)** (minimal training) - `h-kim`
  - TorchTitan, minimal packages, ~9GB vs 12GB
  - See [H-KIM-QUICKSTART.md](deployments/archived/h-kim/QUICKSTART.md)
- **PyTorch 2.8 + NumPy 1.x** (legacy) - `pytorch-2.8-numpy1`

### Development Tools

- ✅ **VSCode Server** - Browser-based IDE with debugging
- ✅ **Jupyter Notebook** - Interactive development
- ✅ **TensorBoard** - Training visualization
- ✅ **debugpy** - Python debugging
- ✅ **wandb** - Experiment tracking

### Multi-Node Capabilities

- ✅ **Cluster-based deployment** - All settings in YAML configs
- ✅ **RDMA or TCP networking** - Choose based on hardware
- ✅ **GPU-to-NIC affinity detection** - Optimal RDMA paths (10-25% faster)
- ✅ **RWX shared storage** - Shared workspace across pods (when available)
- ✅ **Per-pod storage** - Fallback for clusters without RWX
- ✅ **NCCL with GPUDirect RDMA** - Optimal GPU communication
- ✅ **StatefulSet** - Distributed training pods
- ✅ **Automatic configuration** - RDMA devices, storage, security per cluster

## 🚀 Quick Start

### Option 1: Interactive Wizard (Recommended for New Users)

The deployment wizard guides you through cluster selection, feature configuration, and **application-specific deployment**:

```bash
# Run the interactive wizard with project mode
make wizard PROJECT=my-training

# Follow the prompts to:
# 1. Select your cluster
# 2. Choose single-node or multi-node
# 3. Select features (VSCode, Jupyter, file browser, etc.)
# 4. Select/build container image
# 5. Configure your application (NEW!)
#    - Specify your training script or code directory
#    - Choose execution mode (manual, auto-start, or Job)
#    - Set CLI arguments and requirements
# 6. Configure resources (GPUs, storage)
# 7. Generate deployment with your app name

# This creates: deployments/my-training/ with all scripts customized
# - Pods named: my-training-0, my-training-1, ...
# - Scripts: run-app.sh, submit-job.sh (if Job mode), etc.
# - QUICKSTART.md personalized for your application
```

**Application-aware features:**
- 🎯 **Custom naming** - All resources named after your application
- 🚀 **Multiple execution modes** - Manual, auto-start, or Kubernetes Jobs
- 📦 **Requirements handling** - Automatic installation from requirements.txt
- 📁 **Project isolation** - Each deployment in its own directory
- 🔧 **Application scripts** - run-app.sh, submit-job.sh tailored to your app

See [DEPLOYMENT-WIZARD-GUIDE.md](docs/DEPLOYMENT-WIZARD-GUIDE.md) for details.

### Option 2: Manual Deployment

### 1. List Available Clusters

```bash
make list-clusters
```

Example output:

```
Available cluster configurations:
  - barcelona       (NERC Barcelona - RDMA + per-pod storage)
  - nerc-production (NERC Production - TCP + RWX storage)
```

### 2. Deploy to a Cluster

**Multi-Node with RDMA (High Performance - Barcelona):**

```bash
make deploy-cluster CLUSTER=barcelona MODE=rdma
```

**Multi-Node with TCP (Production cluster):**

```bash
make deploy-cluster CLUSTER=nerc-production MODE=tcp
```

**Preview before deploying:**

```bash
make deploy-cluster-dry-run CLUSTER=barcelona MODE=rdma
```

### 3. Sync Your Code

```bash
make sync-multi-node
```

### 4. Run Training

```bash
# Shell into master node
make shell-multi-node

# Inside pod:
cd /workspace
./launch_deepspeed.sh train_multi_node.py
```

### 5. Monitor

```bash
# View deployment status
make status-cluster CLUSTER=barcelona

# Follow training logs
oc logs -f ml-dev-env-0 -n nccl-test
```

That's it! See [MULTI-NODE-QUICKSTART.md](docs/MULTI-NODE-QUICKSTART.md) for details.

## 📖 Documentation

### Getting Started

- **[DEPLOYMENT-WIZARD-GUIDE.md](docs/DEPLOYMENT-WIZARD-GUIDE.md)** - Interactive deployment wizard (recommended)
- **[QUICKSTART.md](docs/QUICKSTART.md)** - Single-node deployment basics
- **[MULTI-NODE-QUICKSTART.md](docs/MULTI-NODE-QUICKSTART.md)** - Multi-node in 5 minutes
- **[BUILD-ON-CLUSTER.md](docs/BUILD-ON-CLUSTER.md)** - Building container images

### Cluster Configuration

- **[CLUSTER-DISCOVERY-GUIDE.md](docs/CLUSTER-DISCOVERY-GUIDE.md)** - Auto-discover cluster config
  - Automatic cluster detection
  - GPU and RDMA discovery
  - Storage and network configuration
  - Troubleshooting
- **[CLUSTER-CONFIG-GUIDE.md](docs/CLUSTER-CONFIG-GUIDE.md)** - Complete cluster config guide
  - Creating cluster configurations
  - Configuration reference
  - Deployment workflows
  - Manual configuration

### Multi-Node Training

- **[MULTI-NODE-GUIDE.md](docs/MULTI-NODE-GUIDE.md)** - Detailed multi-node guide
  - Architecture and components
  - DeepSpeed training
  - Monitoring and debugging
  - Performance tuning
- **[MULTI-NODE-TCP-GUIDE.md](docs/MULTI-NODE-TCP-GUIDE.md)** - TCP vs RDMA
  - When to use each mode
  - Performance comparison
  - Configuration examples
  - Benchmarking
- **[GPU-NIC-AFFINITY-GUIDE.md](docs/GPU-NIC-AFFINITY-GUIDE.md)** - GPU-to-NIC affinity
  - Automatic topology detection
  - NUMA-aware RDMA configuration
  - 10-25% performance improvement
  - See also: [GPU-NIC-AFFINITY-QUICKSTART.md](docs/GPU-NIC-AFFINITY-QUICKSTART.md)

### Development Workflows

- **[QUICK-DEV-GUIDE.md](docs/QUICK-DEV-GUIDE.md)** - Fast development workflow
- **[AUTOMATION-GUIDE.md](docs/AUTOMATION-GUIDE.md)** - Dev automation overview
- **[CONFIGURATION-GUIDE.md](docs/CONFIGURATION-GUIDE.md)** - Script configuration

### VSCode & Debugging

- **[VSCODE-SETUP.md](docs/VSCODE-SETUP.md)** - VSCode setup
- **[VSCODE-DEBUG-GUIDE.md](docs/VSCODE-DEBUG-GUIDE.md)** - Debugging guide
- **[VSCODE-DEBUG-TROUBLESHOOTING.md](docs/VSCODE-DEBUG-TROUBLESHOOTING.md)** - Debug troubleshooting
- **[REMOTE-DEBUG-WALKTHROUGH.md](docs/REMOTE-DEBUG-WALKTHROUGH.md)** - Remote debugging

### Test Results

- Test results documented in multi-node guides above

## 🔧 Cluster-Based Deployment

### Why Use Cluster Configs?

Traditional approach (manual editing):

- ❌ Edit multiple YAML files for each cluster
- ❌ Easy to make mistakes with device names
- ❌ Hard to track cluster-specific settings
- ❌ Manual updates when switching clusters

Cluster config approach:

- ✅ All settings in one YAML file per cluster
- ✅ Automatic substitution of cluster-specific values
- ✅ Version control cluster configurations
- ✅ Single command deployment: `make deploy-cluster CLUSTER=barcelona MODE=rdma`
- ✅ **Automatic RDMA detection**: Clusters indicate if RDMA/InfiniBand is available
  - RDMA mode automatically falls back to TCP if cluster doesn't support RDMA
  - No need to remember which clusters have InfiniBand

### Available Clusters

**Barcelona** - NERC Barcelona cluster:

- Per-pod storage (volumeClaimTemplates)
- RDMA: mlx5_6,7,10,11
- No privileged SCC required
- Nodes: moc-r4pcc04u25-nairr, moc-r4pcc04u23-nairr

**NERC Production** - NERC Production cluster (shift.nerc.mghpcc.org):

- RWX storage via NFS (nfs-csi)
- TCP only (no RDMA/InfiniBand)
- No privileged SCC required
- 25 GPU nodes available (wrk-97 through wrk-128)
- 4x H100 80GB HBM3 per node

### Deploy to a Cluster

```bash
# List clusters
make list-clusters

# Deploy with RDMA (high performance - Barcelona)
make deploy-cluster CLUSTER=barcelona MODE=rdma

# Deploy with TCP (Production cluster)
make deploy-cluster CLUSTER=nerc-production MODE=tcp

# Dry run (preview)
make deploy-cluster-dry-run CLUSTER=barcelona MODE=rdma

# Check status
make status-cluster CLUSTER=barcelona

# Clean up
make clean-cluster CLUSTER=barcelona
```

### Create a New Cluster Config

**Option 1: Auto-Discovery (Recommended)**

```bash
# Login to your cluster
oc login https://api.your-cluster.com:6443
oc project my-namespace

# Auto-discover configuration
make discover-cluster NAME=my-cluster

# Review and edit if needed
vim clusters/my-cluster.yaml

# Deploy
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

**Option 2: Manual Configuration**

```bash
# 1. Copy template
cp clusters/template.yaml clusters/my-cluster.yaml

# 2. Edit configuration (see template for all options)
vim clusters/my-cluster.yaml

# 3. Deploy
make deploy-cluster CLUSTER=my-cluster MODE=rdma
```

Example configuration:

```yaml
cluster:
  name: my-cluster
  api: api.my-cluster.example.com
  namespace: nccl-test

nodes:
  gpu_nodes:
    - gpu-node-1
    - gpu-node-2

storage:
  mode: rwx  # or "volumeClaimTemplates"
  class_rwx: nfs-csi
  workspace_size: 100Gi
  datasets_size: 500Gi

network:
  rdma:
    enabled: true
    devices: "mlx5_2,mlx5_3,mlx5_4,mlx5_5"
    interfaces: "net1,net2,net3,net4"
    gid_index: "3"
    gdr_level: "5"

security:
  service_account: ml-dev-sa
  requires_privileged_scc: true
  ipc_lock: true

gpus:
  per_node: 4
  default_nodes: 2
```

See [CLUSTER-CONFIG-GUIDE.md](docs/CLUSTER-CONFIG-GUIDE.md) for complete documentation.

## 🎯 Single-Node Deployment

For single-node development (alternative to cluster-based deployment):

### 1. Build Container Image (if needed)

```bash
make build
```

See [BUILD-ON-CLUSTER.md](docs/BUILD-ON-CLUSTER.md) for details.

### 2. Deploy Development Environment

```bash
# Deploy everything (build + PVCs + pod + services)
make deploy

# Or step by step:
oc apply -f k8s/pvcs.yaml
oc apply -f k8s/pod-multi-gpu.yaml
oc apply -f k8s/service.yaml
```

### 3. Access VSCode

```bash
make vscode
```

### 4. Test GPUs

```bash
make test
```

See [QUICKSTART.md](docs/QUICKSTART.md) for complete single-node guide.

## 💻 Development Workflow

### Automated Development Session (Recommended)

The fastest way to develop and debug on the cluster:

```bash
# Start everything in one command
make dev-session
```

This automatically:

1. ✅ Syncs your local code to the pod
2. ✅ Watches for changes and auto-syncs every 2 seconds
3. ✅ Sets up port-forwarding for VSCode debugging (port 5678)
4. ✅ Keeps everything running while you develop

Then in VSCode:
- Set breakpoints in your code
- Press **F5** to attach debugger
- Edit code locally - it auto-syncs to the pod
- Debug live on the cluster GPUs

See [QUICK-DEV-GUIDE.md](docs/QUICK-DEV-GUIDE.md) for complete workflow guide.

### Individual Commands

```bash
# One-time code sync
make sync-once

# Auto-sync on file changes (watch mode)
make sync-code

# Port-forward for debugging
make port-forward

# Shell into pod
make shell
```

### Configuration

Customize namespace, pod name, directories:

```bash
# Environment variables
export NAMESPACE=my-namespace
export POD_NAME=my-pod
export LOCAL_DIR=./workspace
export REMOTE_DIR=/workspace
export DEBUG_PORT=5678

make dev-session
```

See [CONFIGURATION-GUIDE.md](docs/CONFIGURATION-GUIDE.md) for all options.

## 📊 Architecture

### Multi-Node Architecture

```
┌─────────────────────────────────────────────┐
│  Headless Service (ml-dev-env-headless)    │
│  - DNS: ml-dev-env-0.ml-dev-env-headless   │
│  - DNS: ml-dev-env-1.ml-dev-env-headless   │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
┌───────▼────────┐    ┌────────▼────────┐
│ ml-dev-env-0   │    │ ml-dev-env-1    │
│ (Master)       │    │ (Worker)        │
│ - 4 H100 GPUs  │    │ - 4 H100 GPUs   │
│ - Rank 0-3     │    │ - Rank 4-7      │
│ - /workspace   │◄───►│ - /workspace    │
└────────────────┘    └─────────────────┘
        │                       │
        └───────────┬───────────┘
                    │
        ┌───────────▼───────────┐
        │  Shared Storage       │
        │  (RWX or per-pod)     │
        └───────────────────────┘
```

### Single-Node Architecture

```
┌─────────────────────────────────────────────┐
│          ML Development Pod                 │
│                                             │
│  ┌─────────┐  ┌─────────┐  ┌────────────┐ │
│  │ VSCode  │  │ Jupyter │  │TensorBoard │ │
│  │  :8080  │  │  :8888  │  │   :6006    │ │
│  └─────────┘  └─────────┘  └────────────┘ │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   Python 3.12 + ML Frameworks       │   │
│  │   PyTorch, DeepSpeed, Flash Attn    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   4x H100 GPUs + CUDA 13.0          │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌──────────────┐  ┌──────────────────┐   │
│  │  Workspace   │  │    Datasets      │   │
│  │   (100GB)    │  │     (500GB)      │   │
│  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────┘
```

## 🗂️ File Organization

```
ml-dev-env/
├── README.md                  # This file
├── Makefile                   # Build and deployment automation
│
├── clusters/                  # Cluster configuration files
│   ├── barcelona.yaml         # Barcelona cluster config
│   ├── nerc-production.yaml   # NERC Production cluster config
│   └── template.yaml          # Template for new clusters
│
├── claude_guidance/           # Operational guides for cluster management
│
├── deployments/               # Deployment configurations
│   ├── archived/              # Completed deployments (h-kim, yunshi, deepti)
│   ├── ops/                   # Operational benchmark templates and tools
│   └── prism/                 # Active prism deployment
│
├── k8s/                       # Kubernetes/OpenShift manifests
│   ├── gold-standard-kustomize/  # Kustomize-based benchmark deployments
│   ├── network-attachments/   # Network attachment definitions
│   ├── rdma-perftest/         # RDMA perftest pod templates
│   ├── machineconfigs/        # OpenShift MachineConfig resources
│   ├── buildconfig.yaml       # Container image build
│   ├── pod-multi-gpu.yaml     # Single-node pod (4 GPUs)
│   ├── statefulset-multi-node-rdma.yaml  # Multi-node RDMA
│   └── statefulset-multi-node-tcp.yaml   # Multi-node TCP
│
├── scripts/                   # Automation scripts
│   ├── mellanox-firmware/     # Mellanox firmware check/apply scripts
│   ├── deployment_wizard.py   # Interactive deployment wizard
│   ├── discover_cluster.py    # Auto-discover cluster config
│   ├── deploy_cluster.py      # Cluster-based deployment
│   ├── run-rdma-perftest.sh   # Automated RDMA testing
│   └── ...                    # Deploy, sync, and dev scripts
│
├── docs/                      # Documentation
│   ├── investigations/        # Historical investigation summaries
│   ├── rdma/                  # RDMA setup documentation
│   └── ...                    # Guides for deployment, debugging, etc.
│
├── examples/                  # Example code and configs
│   ├── test_multi_gpu.py
│   ├── test_deepspeed.py
│   ├── test_flash_attn.py
│   ├── inference/             # Inference deployment examples
│   ├── research/              # Research workflow examples
│   └── vscode/                # VSCode configs for pod
│
├── templates/                 # Deployment wizard templates
│
└── workspace/                 # Development workspace (syncs to pod)
    ├── ds_config.json         # DeepSpeed configuration
    ├── launch_deepspeed.sh    # Launch script
    └── train_multi_node.py
```

## 🧪 Testing

### Test GPU Access

```bash
# Quick test
make test

# Detailed test
oc exec ml-dev-env -- python /workspace/examples/test_multi_gpu.py
```

### Test Multi-Node Communication

```bash
# Test NCCL
oc exec ml-dev-env-0 -n nccl-test -- bash -c '
python3 -c "
import torch
import torch.distributed as dist
dist.init_process_group(backend=\"nccl\")
print(\"NCCL working!\")
"
'
```

### Test RDMA (if using RDMA mode)

```bash
# Check InfiniBand devices
oc exec ml-dev-env-0 -n nccl-test -- ibstat

# Check NCCL can see IB devices
oc exec ml-dev-env-0 -n nccl-test -- env | grep NCCL
```

## 🔍 Monitoring

### GPU Monitoring

```bash
# Real-time monitoring
oc exec ml-dev-env -- watch -n 1 nvidia-smi

# GPU topology
oc exec ml-dev-env -- nvidia-smi topo -m

# All nodes (multi-node)
for i in 0 1; do
  echo "=== Node $i ==="
  oc exec ml-dev-env-$i -n nccl-test -- nvidia-smi
done
```

### Training Logs

```bash
# Single-node
oc logs -f ml-dev-env -n nccl-test

# Multi-node (master)
oc logs -f ml-dev-env-0 -n nccl-test
```

### TensorBoard

```bash
# Start TensorBoard
oc exec ml-dev-env -- tensorboard --logdir=/workspace/runs --bind_all &

# Get URL
TENSORBOARD_URL=$(oc get route ml-dev-tensorboard -o jsonpath='{.spec.host}')
echo "TensorBoard: https://$TENSORBOARD_URL"
```

## 🐛 Troubleshooting

### Common Issues

**GPUs not detected:**

```bash
oc describe pod ml-dev-env | grep -A 5 "Limits"
oc exec ml-dev-env -- nvidia-smi
```

**Multi-node pods not starting:**

```bash
make status-cluster CLUSTER=barcelona
oc describe pod ml-dev-env-0 -n nccl-test
```

**NCCL hangs:**

```bash
# Check DNS resolution
oc exec ml-dev-env-0 -n nccl-test -- ping -c 3 ml-dev-env-1.ml-dev-env-headless

# Check RDMA devices (if using RDMA)
oc exec ml-dev-env-0 -n nccl-test -- ibstat
```

**Storage issues:**

```bash
oc get pvc -n nccl-test
oc describe pvc ml-dev-workspace -n nccl-test
```

See individual documentation files for detailed troubleshooting.

## 📦 Resource Requirements

### Minimum (Single-Node)

- 1x NVIDIA GPU (Compute Capability >= 7.0)
- 32 GB RAM
- 50 GB storage

### Recommended (Multi-Node)

- 4x NVIDIA H100 GPUs per node
- 128 GB RAM per node
- 500 GB+ shared storage
- InfiniBand network for RDMA (optional but recommended)

## 🔒 Security Considerations

Multi-node deployments may require elevated privileges:

- **Privileged SCC**: Required for IPC_LOCK capability (RDMA mode)
- **Host Network**: Required for InfiniBand access (RDMA mode)
- **Service Account**: Created automatically by cluster config

Best practices:

1. Use dedicated GPU nodes with node selectors
2. Apply appropriate RBAC policies
3. Use network policies to restrict access
4. Enable authentication for VSCode/Jupyter
5. Use secrets for API keys (wandb, HuggingFace)

## 🚀 Next Steps

### For Single-Node Development

1. Deploy with `make deploy`
2. Access VSCode with `make vscode`
3. Clone your code to `/workspace`
4. Start training with 4 GPUs

### For Multi-Node Training

1. Choose cluster: `make list-clusters`
2. Deploy: `make deploy-cluster CLUSTER=barcelona MODE=rdma`
3. Sync code: `make sync-multi-node`
4. Shell in: `make shell-multi-node`
5. Run training: `./launch_deepspeed.sh`

### General Setup

1. **Download datasets**: Use `/datasets` for large datasets
2. **Configure wandb**: `wandb login` for experiment tracking
3. **Set up Git**: Clone your repositories to `/workspace`
4. **Configure VSCode**: Install extensions and set up debugging
5. **Monitor training**: Use TensorBoard and wandb

## 📚 Additional Resources

### Official Documentation

- [PyTorch Distributed Training](https://pytorch.org/tutorials/beginner/dist_overview.html)
- [DeepSpeed Documentation](https://www.deepspeed.ai/)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [Flash Attention](https://github.com/Dao-AILab/flash-attention)

### Project-Specific

- [LLaMAFactory](https://github.com/hiyouga/LLaMA-Factory)
- [VideoLLaMA2](https://github.com/DAMO-NLP-SG/VideoLLaMA2)

### OpenShift/Kubernetes

- [OpenShift Documentation](https://docs.openshift.com/)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## 📝 License

This example configuration is provided as-is for educational and development purposes.

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

### Quick Start for Contributors

```bash
# Install dependencies
pip install -r requirements-dev.txt

# Install pre-commit hooks
pre-commit install

# Run tests
pytest --cov

# Make changes and commit (hooks run automatically)
git add <files>
git commit -m "Your changes"
```

**Automated Testing:**
- ✅ Python 3.9-3.12 compatibility
- ✅ 76% code coverage with pytest
- ✅ CI/CD with GitHub Actions
- ✅ Pre-commit hooks (Black, Ruff, ShellCheck, yamllint, markdownlint)

### Adding a New Cluster

1. Auto-discover: `make discover-cluster NAME=<cluster>`
2. Or copy template: `cp clusters/template.yaml clusters/<cluster>.yaml`
3. Test: `make deploy-cluster-dry-run CLUSTER=<cluster> MODE=tcp`
4. Deploy: `make deploy-cluster CLUSTER=<cluster> MODE=tcp`

See [CLUSTER-CONFIG-GUIDE.md](docs/CLUSTER-CONFIG-GUIDE.md) for details.

---

**Quick Commands:**

```bash
# Interactive deployment wizard (recommended)
make wizard

# List clusters
make list-clusters

# Deploy multi-node
make deploy-cluster CLUSTER=barcelona MODE=rdma

# Sync code
make sync-multi-node

# Shell into master
make shell-multi-node

# Check status
make status-cluster CLUSTER=barcelona

# Single-node dev
make dev-session
```

For detailed guides, see the [docs/](docs/) directory.
