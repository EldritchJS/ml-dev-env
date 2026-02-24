# Application-Aware Deployment Guide

Deploy your specific ML applications with customized resource naming, execution modes, and project-based workflows.

## Overview

The deployment wizard now supports **application-aware deployment**, transforming the generic "ml-dev-env" infrastructure into application-specific deployments where:

- All resources named after your application (`gpt-training-0` instead of `ml-dev-env-0`)
- Scripts tailored to run your specific code
- Multiple execution modes (manual, auto-start, Kubernetes Jobs)
- Project-based directory structure for isolation

## Quick Start

### Deploy a Training Script

```bash
# Start wizard with project name
make wizard PROJECT=gpt-training

# When prompted "Configure application deployment?": YES
# - Type: Single Python file
# - Source: ./train.py
# - Name: gpt-training (auto-extracted)
# - Mode: Manual
# - Arguments: --epochs 100 --batch-size 32

# This creates deployments/gpt-training/ with:
cd deployments/gpt-training/

# Copy your code
cp ~/my-project/train.py workspace/
./scripts/sync.sh

# Deploy
./scripts/deploy.sh

# Run application
./scripts/run-app.sh
```

## Application Types

### 1. Single Python File

**When to use:** You have one main training script

```
Configure application deployment? [y/N]: y

Application Type: Single Python file
Source: ./train.py
Name: training (auto-extracted from train.py)
```

**File structure:**
```
deployments/training/
├── workspace/
│   └── train.py         # Your script
└── scripts/
    └── run-app.sh       # Executes: python train.py
```

### 2. Directory with Multiple Files

**When to use:** Full project with multiple Python files

```
Application Type: Directory with multiple files
Source: ./my-ml-project/
Entry point: train.py
Name: llm-training (auto-extracted from my-ml-project)
```

**File structure:**
```
deployments/llm-training/
├── workspace/
│   ├── train.py         # Entry point
│   ├── model.py
│   ├── dataset.py
│   └── utils/
│       └── helpers.py
└── scripts/
    └── run-app.sh       # Executes: python train.py
```

All imports work because the entire directory is synced.

### 3. Custom Command

**When to use:** Advanced execution with specific tools (accelerate, torchrun, etc.)

```
Application Type: Custom command
Command: accelerate launch --multi_gpu train.py --config deepspeed.yaml
Name: accelerate-training
```

**Executes exactly as specified:**
```bash
./scripts/run-app.sh
# Runs: accelerate launch --multi_gpu train.py --config deepspeed.yaml
```

## Execution Modes

### Manual Mode (Recommended for Development)

**Best for:** Interactive development, debugging, experimentation

```
Execution Mode: Manual
```

**How it works:**
- Pods start and wait
- You manually trigger execution with `./scripts/run-app.sh`
- Can run multiple times with different arguments
- Easy to debug and iterate

**Usage:**
```bash
# Run on all pods
./scripts/run-app.sh

# Run on specific pod
./scripts/run-app.sh --node 0

# Stream logs while running
./scripts/run-app.sh --watch

# Access shell for debugging
./scripts/shell.sh
```

### Auto-Start Mode (Production Pipelines)

**Best for:** Automated training pipelines, continuous training

```
Execution Mode: Auto-start
```

**How it works:**
- Application starts automatically when pods launch
- Runs in foreground (pod restarts if training crashes)
- Ideal for production deployments
- No manual intervention needed

**Usage:**
```bash
# Deploy (application starts automatically)
./scripts/deploy.sh

# Monitor logs
./scripts/logs.sh -f

# Application is already running!
```

**StatefulSet includes:**
```yaml
command:
  - /bin/bash
  - -c
  - |
    cd /workspace/gpt-training
    pip install -r requirements.txt  # If configured
    exec python train.py --epochs 100
```

### Job Mode (Batch Experiments)

**Best for:** One-time executions, hyperparameter sweeps, batch experiments

```
Execution Mode: Job
```

**How it works:**
- Creates Kubernetes Jobs on-demand
- Each job is independent and tracked
- Automatic cleanup after completion
- Perfect for experiments

**Usage:**
```bash
# Deploy infrastructure first
./scripts/deploy.sh

# Submit experiment 1
./scripts/submit-job.sh

# Output:
# Job ID: 20260224-153045
# Job name: gpt-training-job-20260224-153045

# Monitor
./scripts/watch-job.sh 20260224-153045

# Submit experiment 2 with different config
# (edit your code/config first)
./scripts/submit-job.sh

# List all jobs
oc get jobs -n <namespace> -l app=gpt-training
```

**Benefits:**
- Parallel experiments
- Independent tracking
- Resource cleanup
- Failed jobs can be retried

## Resource Naming

### With Application Configuration

**Application name:** `gpt-training`

**Resources created:**
- Pods: `gpt-training-0`, `gpt-training-1`, `gpt-training-2`, `gpt-training-3`
- StatefulSet: `gpt-training`
- Service: `gpt-training-headless`
- Routes: `gpt-training-vscode`, `gpt-training-jupyter`, `gpt-training-tensorboard`
- Working directory: `/workspace/gpt-training/`
- FQDNs: `gpt-training-0.gpt-training-headless.<namespace>.svc.cluster.local`

### Without Application Configuration

**Default behavior:**

```
Configure application deployment? [y/N]: n
```

**Resources created:**
- Pods: `ml-dev-env-0`, `ml-dev-env-1`
- Service: `ml-dev-env-headless`
- Routes: `ml-dev-vscode`, `ml-dev-jupyter`
- Working directory: `/workspace/`

## Requirements Handling

### Pod Startup Installation

**When to use:** Any image, flexible

```
Requirements: Install at pod startup
File: ./requirements.txt
```

**How it works:**
- requirements.txt copied to workspace
- `pip install -r requirements.txt` runs when pods start
- Works with pre-built images
- Can modify requirements.txt and redeploy

**Generated code:**
```bash
if [ -f "/workspace/gpt-training/requirements.txt" ]; then
  pip install --no-cache-dir -r /workspace/gpt-training/requirements.txt
fi
```

### Skip (Manual Management)

**When to use:** Packages already in image, custom installation

```
Requirements: Skip
```

**How it works:**
- No automatic installation
- You manually install packages in shell
- Or all packages already in custom image

## Project Structure

Each application deployment creates an isolated project:

```
deployments/gpt-training/
├── config.yaml              # Full deployment configuration
├── QUICKSTART.md           # Personalized guide for YOUR app
├── workspace/              # Your code (syncs to pods)
│   ├── train.py
│   ├── requirements.txt
│   └── ...
├── generated/              # Kubernetes manifests (auto-generated)
│   ├── statefulset.yaml
│   ├── service.yaml
│   └── ...
└── scripts/                # Application-specific scripts
    ├── deploy.sh           # Deploy gpt-training resources
    ├── run-app.sh          # Execute your application
    ├── submit-job.sh       # Submit Kubernetes Jobs (Job mode only)
    ├── watch-job.sh        # Monitor job execution (Job mode only)
    ├── sync.sh             # Sync to /workspace/gpt-training/
    ├── shell.sh            # Shell into gpt-training-0
    ├── vscode.sh           # Open gpt-training-vscode route
    ├── jupyter.sh          # Open gpt-training-jupyter
    ├── status.sh           # Status of gpt-training pods
    ├── logs.sh             # Logs from gpt-training-0
    └── cleanup.sh          # Remove gpt-training resources
```

## Complete Examples

### Example 1: Simple Training Script

**Scenario:** Fine-tune a GPT model with one script

```bash
# 1. Run wizard
make wizard PROJECT=gpt-finetuning

# 2. Configure application
#    - Type: Single file
#    - Source: ./finetune_gpt.py
#    - Name: gpt-finetuning (auto)
#    - Mode: Manual
#    - Arguments: --model gpt2 --dataset wikitext
#    - Requirements: ./requirements.txt (pod_startup)

# 3. Deploy
cd deployments/gpt-finetuning/
cp ~/my-project/finetune_gpt.py workspace/
cp ~/my-project/requirements.txt workspace/
./scripts/deploy.sh

# 4. Run
./scripts/sync.sh
./scripts/run-app.sh

# 5. Monitor
./scripts/vscode.sh  # Opens gpt-finetuning-vscode
./scripts/logs.sh -f
```

### Example 2: Multi-File Project with Auto-Start

**Scenario:** Production training that starts automatically

```bash
# 1. Run wizard
make wizard PROJECT=production-training

# 2. Configure application
#    - Type: Directory
#    - Source: ./my-training-project/
#    - Entry point: main.py
#    - Name: production-training
#    - Mode: Auto-start  ← Starts automatically!
#    - Arguments: --config production.yaml
#    - Requirements: pod_startup

# 3. Deploy
cd deployments/production-training/
cp -r ~/my-training-project/* workspace/
./scripts/deploy.sh

# Application starts automatically!
# Just monitor:
./scripts/logs.sh -f
```

### Example 3: Hyperparameter Sweep with Jobs

**Scenario:** Run multiple experiments with different parameters

```bash
# 1. Run wizard
make wizard PROJECT=hyperparam-search

# 2. Configure application
#    - Type: Single file
#    - Source: ./train.py
#    - Name: hyperparam-search
#    - Mode: Job  ← Batch execution!
#    - Arguments: --lr 0.001 --batch-size 32
#    - Requirements: pod_startup

# 3. Deploy infrastructure
cd deployments/hyperparam-search/
cp ~/my-project/train.py workspace/
./scripts/deploy.sh

# 4. Run experiment 1
./scripts/submit-job.sh
# Job ID: 20260224-120000

# 5. Modify arguments in config.yaml for experiment 2
vim config.yaml
# Change: arguments: "--lr 0.0001 --batch-size 64"

# 6. Run experiment 2
./scripts/submit-job.sh
# Job ID: 20260224-120130

# 7. Monitor both
./scripts/watch-job.sh 20260224-120000
./scripts/watch-job.sh 20260224-120130

# 8. List all experiments
oc get jobs -n <namespace> -l app=hyperparam-search
```

### Example 4: DeepSpeed Multi-Node Training

**Scenario:** Distributed training with custom launch command

```bash
# 1. Run wizard
make wizard PROJECT=deepspeed-training

# 2. Configure application
#    - Type: Custom command
#    - Command: deepspeed --hostfile /workspace/.deepspeed/hostfile train.py --deepspeed
#    - Name: deepspeed-training
#    - Mode: Manual
#    - Arguments: (none - included in command)

# 3. Deploy multi-node
cd deployments/deepspeed-training/
cp ~/my-project/train.py workspace/
cp ~/my-project/ds_config.json workspace/
./scripts/deploy.sh  # Creates 4 nodes with DeepSpeed hostfile

# 4. Run distributed training
./scripts/run-app.sh --node 0  # Run from master node
# Executes: deepspeed --hostfile /workspace/.deepspeed/hostfile train.py --deepspeed
```

## Workflow Patterns

### Pattern 1: Development → Production

**Development (Manual mode):**
```bash
make wizard PROJECT=my-model-dev
# Mode: Manual
# Iterate, debug, test
./scripts/run-app.sh --watch
```

**Production (Auto-start mode):**
```bash
make wizard PROJECT=my-model-prod
# Mode: Auto-start
# Same code, automatic execution
./scripts/deploy.sh
# Training starts immediately
```

### Pattern 2: Experiment Tracking

```bash
# Base infrastructure
make wizard PROJECT=experiments
# Mode: Job

# Run experiments
for lr in 0.001 0.0001 0.00001; do
  # Update config
  sed -i "s/--lr [0-9.]*/--lr $lr/" config.yaml
  ./scripts/submit-job.sh
  echo "Submitted job with lr=$lr"
done

# Track all
oc get jobs -n <namespace> -l app=experiments -w
```

### Pattern 3: Code Sync During Development

```bash
# Deploy once
./scripts/deploy.sh

# Continuous sync
./scripts/sync.sh --watch &

# Edit code locally
vim ~/my-project/train.py

# Automatically synced!
# Run updated version
./scripts/run-app.sh
```

## Troubleshooting

### Application Not Starting (Auto-Start Mode)

**Check pod logs:**
```bash
./scripts/logs.sh

# Look for:
# - Python errors
# - Missing packages
# - Incorrect working directory
```

**Common issues:**
- Requirements installation failed → Check requirements.txt syntax
- Entry point not found → Verify entry_point in config.yaml
- Import errors → Ensure all files synced with `./scripts/sync.sh`

### Job Fails Immediately

**Check job status:**
```bash
oc get jobs -n <namespace> -l app=<app-name>
oc describe job <job-name>
```

**Common issues:**
- Image pull errors → Verify image URL in config.yaml
- Resource limits → Check GPU/memory requests
- Arguments error → Verify application arguments

### Resources Using Wrong Names

**If resources still named "ml-dev-env":**

**Check config.yaml:**
```bash
cat deployments/my-app/config.yaml

# Should have:
application:
  enabled: true
  name: my-app
```

**If `enabled: false`, redeploy with application config**

### Multiple Deployments Conflict

**Use unique names per project:**
```bash
make wizard PROJECT=experiment-1
make wizard PROJECT=experiment-2
make wizard PROJECT=experiment-3
```

Each creates isolated resources:
- `experiment-1-0`, `experiment-1-vscode`
- `experiment-2-0`, `experiment-2-vscode`
- `experiment-3-0`, `experiment-3-vscode`

## Best Practices

1. **Use descriptive names** - `gpt-finetuning` not `test123`
2. **Start with manual mode** - Debug first, automate later
3. **Keep requirements.txt minimal** - Only what you need
4. **Version control configs** - Commit `config.yaml` to git
5. **Isolate experiments** - One project per experiment
6. **Use Jobs for sweeps** - Parallel experiments, clean tracking
7. **Sync often** - Use `--watch` during active development
8. **Test locally first** - Verify code works before deploying

## Related Documentation

- [DEPLOYMENT-WIZARD-GUIDE.md](DEPLOYMENT-WIZARD-GUIDE.md) - Full wizard documentation
- [QUICKSTART.md](QUICKSTART.md) - General deployment guide
- [MULTI-NODE-GUIDE.md](MULTI-NODE-GUIDE.md) - Multi-node distributed training

## Summary

Application-aware deployment transforms the wizard from generic infrastructure into application-specific deployments:

**Benefits:**
- ✅ All resources named after your application
- ✅ Scripts tailored to your code
- ✅ Multiple execution modes (manual, auto-start, job)
- ✅ Project isolation and organization
- ✅ Requirements handling
- ✅ Kubernetes Job support for experiments
- ✅ Automated hyperparameter sweep support

**Use cases:**
- Training specific models (GPT fine-tuning, LLaMA training, etc.)
- Hyperparameter sweeps with automated job submission
- Production training pipelines with auto-start
- Multi-project development with isolation
- Batch experiments and A/B testing

---

## Hyperparameter Sweep Automation

For Job mode applications, you can enable automated hyperparameter sweeps that submit multiple jobs with different parameter combinations.

### What is Sweep Automation?

Instead of manually creating bash scripts to loop through hyperparameters, the wizard generates scripts that automatically:
- Generate all parameter combinations (grid search)
- Submit jobs with unique IDs containing parameter values
- Control job concurrency (max parallel jobs)
- Monitor sweep progress with beautiful status tables
- Stream logs from running jobs

### Configuration

Enable sweep during the wizard when selecting Job execution mode:

```yaml
application:
  enabled: true
  type: single_file
  name: my-experiment
  source:
    path: ./train.py
  execution:
    mode: job
    arguments: "--epochs 100"  # Base arguments
    sweep:
      enabled: true
      strategy: grid  # Grid search (more strategies coming)
      max_concurrent: 3  # Max parallel jobs
      parameters:
        - name: lr
          flag: --lr
          values: [0.0001, 0.001, 0.01]
        - name: batch_size
          flag: --batch-size
          values: [16, 32, 64]
```

This configuration creates:
- **9 jobs total** (3 learning rates × 3 batch sizes)
- **Max 3 concurrent** jobs running at once
- **Automatic naming**: `my-experiment-job-lr0.001-bs32`

### Generated Scripts

When sweep is enabled, the wizard generates:

#### `scripts/submit-sweep.sh`
Submits all sweep jobs automatically:
```bash
cd deployments/my-experiment/
./scripts/submit-sweep.sh

# Output:
# 📊 Generated 9 job combinations
# 🚀 Submitting jobs...
#   ✓ Job 1/9: my-experiment-job-lr1e-04-bs16
#   ✓ Job 2/9: my-experiment-job-lr1e-04-bs32
#   ...
```

#### `scripts/watch-sweep.sh`
Monitor all sweep jobs:
```bash
# Show status table
./scripts/watch-sweep.sh

# Output:
# Status     Job ID                    Duration     Started
# ─────────────────────────────────────────────────────────
# 🔄 Running   lr0.001-bs32             0:03:45      2024-02-24 10:15
# ✅ Succeeded lr0.0001-bs16            0:05:23      2024-02-24 10:10
# ⏳ Pending   lr0.01-bs64              Not started  Pending
# ...
#
# 📊 Summary: 9 total | ✅ 2 succeeded | ❌ 0 failed | 🔄 3 running | ⏳ 4 pending
```

### Usage Examples

#### Example 1: Learning Rate Sweep

**Goal:** Find best learning rate for your model

```yaml
sweep:
  enabled: true
  parameters:
    - name: lr
      flag: --learning-rate
      values: [1e-5, 5e-5, 1e-4, 5e-4, 1e-3]
```

**Submit:**
```bash
./scripts/submit-sweep.sh
# Submits 5 jobs with different learning rates
```

#### Example 2: Full Grid Search

**Goal:** Optimize learning rate, batch size, and optimizer

```yaml
sweep:
  enabled: true
  max_concurrent: 4
  parameters:
    - name: lr
      flag: --lr
      values: [0.0001, 0.001, 0.01]
    - name: batch_size
      flag: --batch-size
      values: [16, 32, 64]
    - name: optimizer
      flag: --optimizer
      values: [adam, adamw, sgd]
```

**Total jobs:** 3 × 3 × 3 = 27 jobs

**Submit:**
```bash
./scripts/submit-sweep.sh
# Automatically manages 27 jobs with max 4 running concurrently
```

#### Example 3: Monitor Specific Job

**Watch logs from a specific parameter combination:**

```bash
# Show all jobs
./scripts/watch-sweep.sh

# Follow logs from lr=0.001, batch_size=32
./scripts/watch-sweep.sh --job lr0.001-bs32

# Follow all running jobs (rotates through them)
./scripts/watch-sweep.sh --follow
```

### Sweep Workflow

**1. Configure sweep in YAML:**
```yaml
execution:
  mode: job
  sweep:
    enabled: true
    parameters:
      - name: lr
        flag: --lr
        values: [0.0001, 0.001, 0.01]
```

**2. Deploy project:**
```bash
./scripts/deployment-wizard.py --config my-sweep.yaml --project my-sweep
cd deployments/my-sweep/
./scripts/deploy.sh
```

**3. Submit all jobs:**
```bash
./scripts/submit-sweep.sh
# Confirms before submitting
# Shows progress as jobs are created
```

**4. Monitor progress:**
```bash
# Status table (refresh manually)
./scripts/watch-sweep.sh

# Continuous monitoring (with watch command)
watch -n 5 ./scripts/watch-sweep.sh

# Follow specific job logs
./scripts/watch-sweep.sh --job lr0.001-bs32
```

**5. Analyze results:**
All jobs are labeled with `sweep=true` and tagged with your app name:
```bash
# List all sweep jobs
oc get jobs -n <namespace> -l app=my-sweep,sweep=true

# Check job outputs in /workspace/
# View metrics in wandb (if enabled)
```

### Advanced Features

#### Concurrency Control

Limit parallel jobs to manage cluster resources:

```yaml
sweep:
  max_concurrent: 3  # Only 3 jobs running at once
```

The `submit-sweep.sh` script automatically:
- Submits jobs up to the concurrent limit
- Waits for jobs to complete
- Submits next batch when slots available

#### Job Naming Convention

Jobs are automatically named with parameter values:

**Pattern:** `{app_name}-job-{param1}{value1}-{param2}{value2}`

**Examples:**
- `lr0.001-bs32` → lr=0.001, batch_size=32
- `lr1e-04-bs16-opt adam` → lr=0.0001, batch_size=16, optimizer=adam

This makes it easy to identify which job ran which parameters.

#### Wandb Integration

If wandb is enabled, each job logs with unique tags:

```python
import wandb

wandb.init(
    project="my-sweep",
    name=f"lr{args.lr}-bs{args.batch_size}",
    tags=["my-sweep", f"lr={args.lr}", f"bs={args.batch_size}"]
)
```

View all experiments in wandb dashboard grouped by sweep.

### Comparison: Manual vs Automated

**Before (Manual Bash Scripting):**

```bash
# Write custom bash script
for lr in 0.0001 0.001 0.01; do
  for bs in 16 32 64; do
    # Manually edit config
    sed -i "s/--lr [0-9.]*/--lr $lr/" config.yaml
    sed -i "s/--batch-size [0-9]*/--batch-size $bs/" config.yaml

    # Submit job
    ./scripts/submit-job.sh

    # Manual naming and tracking
    echo "Submitted: lr=$lr, bs=$bs"
    sleep 2
  done
done

# Manual monitoring
oc get jobs -w
```

**After (Sweep Automation):**

```bash
# One command to submit all
./scripts/submit-sweep.sh

# Beautiful status table
./scripts/watch-sweep.sh

# Follow specific job
./scripts/watch-sweep.sh --job lr0.001-bs32
```

**Benefits:**
- ✅ **No bash scripting** - Just configure YAML
- ✅ **Automatic naming** - Parameters embedded in job IDs
- ✅ **Concurrency control** - Managed automatically
- ✅ **Better monitoring** - Status tables and log streaming
- ✅ **Easier to use** - Researchers don't need scripting skills

### Best Practices

**1. Start small:**
Test with 2-3 parameter combinations before running large sweeps:
```yaml
# Test first
values: [0.001, 0.01]  # 2 values

# Then scale up
values: [1e-5, 5e-5, 1e-4, 5e-4, 1e-3]  # 5 values
```

**2. Use concurrency limits:**
Don't overwhelm the cluster:
```yaml
max_concurrent: 3  # Reasonable for most clusters
```

**3. Include base arguments:**
Sweep parameters are added to base arguments:
```yaml
arguments: "--epochs 100 --dataset wikitext"  # Base
sweep:
  parameters:
    - name: lr
      flag: --lr
      values: [0.001, 0.01]  # Added to base
```

**4. Log to wandb:**
Enable wandb for easy result comparison:
```yaml
features:
  wandb: true
```

**5. Monitor early:**
Check first few jobs before all complete:
```bash
./scripts/watch-sweep.sh --job lr0.001-bs32
# Verify job is running correctly before waiting for all 27 jobs
```

### Troubleshooting

**Issue:** "Sweep not configured in config.yaml"

**Solution:** Enable sweep in execution section:
```yaml
execution:
  mode: job
  sweep:
    enabled: true
```

**Issue:** Jobs pending forever

**Solution:** Check cluster resources:
```bash
oc describe job my-experiment-job-lr0.001-bs32
# Look for resource constraints
```

**Issue:** Can't find job logs

**Solution:** Jobs may not have started yet:
```bash
# Check job status
oc get jobs -l app=my-experiment,sweep=true

# Wait for pod creation
./scripts/watch-sweep.sh
```

**Issue:** Too many jobs running simultaneously

**Solution:** Reduce max_concurrent:
```yaml
sweep:
  max_concurrent: 2  # Lower limit
```

### Real-World Example

See `examples/research/hyperparameter-sweep.yaml` for a complete working example:

```bash
# Use the example
./scripts/deployment-wizard.py \
  --config examples/research/hyperparameter-sweep.yaml \
  --project my-lr-sweep

cd deployments/my-lr-sweep/
./scripts/submit-sweep.sh

# 9 jobs submitted automatically (3 LRs × 3 batch sizes)
# Monitor with ./scripts/watch-sweep.sh
```

---

## Summary
