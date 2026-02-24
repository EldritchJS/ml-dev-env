# Example Configurations

Ready-to-use configuration files for common ML workflows.

## Directory Structure

```
examples/
├── inference/          # Model serving and inference
│   ├── vllm-llama.yaml              # LLaMA-3-70B with vLLM
│   ├── vllm-llama-small.yaml        # LLaMA-3-8B (lower resources)
│   ├── tgi-mistral.yaml             # Mistral with TGI
│   ├── batch-inference.yaml         # Batch predictions
│   └── triton-multi-model.yaml      # Multi-model serving
│
├── research/           # Experiments and analysis
│   ├── hyperparameter-sweep.yaml    # Grid search
│   ├── ablation-study.yaml          # Component importance
│   ├── model-comparison.yaml        # Architecture comparison
│   ├── benchmark-suite.yaml         # Evaluation suite
│   ├── data-analysis.yaml           # Dataset exploration
│   └── reproducibility-check.yaml   # Reproduce papers
│
└── README.md          # This file
```

## Quick Start

### Option 1: Use config directly

```bash
# Load config during wizard
make wizard PROJECT=my-project
# When prompted, select "Load configuration from file"
# Enter path: examples/inference/vllm-llama.yaml

# Or non-interactive
./scripts/deployment-wizard.py \
  --config examples/inference/vllm-llama.yaml \
  --project llama-inference \
  --non-interactive
```

### Option 2: Copy and customize

```bash
# Copy example to your project
cp examples/inference/vllm-llama.yaml deployments/my-llama/config.yaml

# Edit as needed
vim deployments/my-llama/config.yaml

# Load modified config
./scripts/deployment-wizard.py \
  --config deployments/my-llama/config.yaml \
  --project my-llama
```

## Inference Examples

### vLLM - LLaMA-3-70B
**File:** `inference/vllm-llama.yaml`

High-throughput LLM inference server:
- OpenAI-compatible API
- 8 GPUs for 70B model
- Auto-start mode (always running)
- ~2 minute startup time

**Use case:** Production LLM serving

```bash
./scripts/deployment-wizard.py \
  --config examples/inference/vllm-llama.yaml \
  --project llama-api

cd deployments/llama-api/
./scripts/deploy.sh

# Wait for model load
./scripts/logs.sh -f

# Test
oc port-forward llama-api 8000:8000
curl http://localhost:8000/v1/completions \
  -d '{"model":"meta-llama/Llama-3-70b-hf","prompt":"Hello","max_tokens":50}'
```

### vLLM - LLaMA-3-8B
**File:** `inference/vllm-llama-small.yaml`

Smaller model for faster inference:
- 1 GPU only
- Faster load time (~30 seconds)
- Higher throughput per GPU
- Good for dev/test

**Use case:** Development, testing, lower-cost serving

### TGI - Mistral-7B
**File:** `inference/tgi-mistral.yaml`

Hugging Face optimized serving:
- Continuous batching
- Flash Attention
- Quantization support
- 1 GPU

**Use case:** Mistral models, HF ecosystem integration

### Batch Inference
**File:** `inference/batch-inference.yaml`

Process large datasets:
- Job mode (one-time run)
- 4 GPUs for parallel processing
- Reads from /datasets/
- Saves to /workspace/predictions/

**Use case:** Offline batch predictions, data annotation

### Triton Multi-Model
**File:** `inference/triton-multi-model.yaml`

Serve multiple models simultaneously:
- PyTorch, TensorFlow, ONNX, TensorRT
- Dynamic batching
- Model versioning
- 4 GPUs

**Use case:** Multi-model serving, mixed frameworks

## Research Examples

### Hyperparameter Sweep
**File:** `research/hyperparameter-sweep.yaml`

**NEW: Automated sweep support!** No bash scripting required:
- One command to submit all jobs (9 total: 3 LRs × 3 batch sizes)
- Automatic parameter embedding in job names
- Concurrency control (max 3 parallel jobs)
- Beautiful status table monitoring
- Job mode with multi-node training (4 nodes)
- Wandb tracking and TensorBoard

**Use case:** Finding optimal hyperparameters without manual scripting

```bash
./scripts/deployment-wizard.py \
  --config examples/research/hyperparameter-sweep.yaml \
  --project lr-sweep

cd deployments/lr-sweep/

# Submit all 9 sweep jobs automatically
./scripts/submit-sweep.sh

# Monitor with beautiful status table
./scripts/watch-sweep.sh

# Follow specific job logs
./scripts/watch-sweep.sh --job lr0.001-bs32
```

### Ablation Study
**File:** `research/ablation-study.yaml`

Test component importance:
- Remove one component at a time
- Compare with baseline
- Wandb tracking
- 2 nodes × 4 GPUs

**Use case:** Understanding what makes model work

### Model Comparison
**File:** `research/model-comparison.yaml`

Compare architectures:
- GPT-2, BERT, RoBERTa, LLaMA
- Same dataset and metrics
- Job mode for each model
- Wandb comparison dashboard

**Use case:** Architecture selection, benchmarking

### Benchmark Suite
**File:** `research/benchmark-suite.yaml`

Comprehensive evaluation:
- MMLU, HellaSwag, TruthfulQA, GSM8K, HumanEval
- Directory structure for test suite
- Wandb tracking
- Single job runs all benchmarks

**Use case:** Model evaluation, paper results

### Data Analysis
**File:** `research/data-analysis.yaml`

Interactive data exploration:
- Manual mode with Jupyter
- VSCode notebooks
- Pandas, matplotlib, seaborn
- PVC browser for files

**Use case:** Dataset understanding, EDA

### Reproducibility Check
**File:** `research/reproducibility-check.yaml`

Reproduce published experiments:
- Fixed seeds
- Pinned dependencies
- Git tracking
- Detailed logging

**Use case:** Verifying paper results, baselines

## Customization Guide

All configs follow the same structure:

```yaml
deployment:
  cluster: <your-cluster>     # CHANGE THIS
  mode: single-node|multi-node
  network_mode: tcp|rdma
  num_nodes: N                # For multi-node

features:
  vscode: true|false
  jupyter: true|false
  tensorboard: true|false
  wandb: true|false

image:
  type: prebuilt|custom_build
  url: <image-url>

application:
  enabled: true
  type: single_file|directory|custom_command
  name: <app-name>            # CHANGE THIS
  source:
    path: <your-script>       # CHANGE THIS
  execution:
    mode: manual|auto_start|job
    arguments: <args>         # CHANGE THIS
  requirements:
    install_mode: pod_startup|skip
    packages: [...]           # CHANGE THIS

resources:
  gpus: N                     # CHANGE THIS

storage:
  workspace_size: GB          # CHANGE THIS
  datasets_size: GB           # CHANGE THIS
```

### Common Modifications

**Change cluster:**
```yaml
deployment:
  cluster: my-cluster  # Your cluster name
```

**Change resources:**
```yaml
resources:
  gpus: 8  # Your GPU count
```

**Change application:**
```yaml
application:
  name: my-experiment
  source:
    path: ./my_script.py
  execution:
    arguments: "--my-args here"
```

**Add packages:**
```yaml
application:
  requirements:
    packages:
      - my-package>=1.0.0
      - another-package
```

## Tips

1. **Start with closest example** - Pick the example most similar to your use case

2. **Test with small resources first** - Use 1 GPU initially, scale up after testing

3. **Use manual mode for debugging** - Switch to auto-start/job after it works

4. **Copy, don't modify originals** - Copy examples to your own files

5. **Version control your configs** - Commit customized configs to git

6. **Document changes** - Add comments explaining your modifications

## Creating New Examples

To contribute a new example:

1. **Test it works** - Deploy and verify functionality

2. **Document well** - Add comments explaining:
   - What it does
   - When to use it
   - How to customize
   - Expected output

3. **Include usage** - Show complete workflow

4. **Provide defaults** - Sensible defaults that work

5. **Add to README** - Document in this file

## Related Documentation

- [DEPLOYMENT-WIZARD-GUIDE.md](../docs/DEPLOYMENT-WIZARD-GUIDE.md) - Full wizard guide
- [APPLICATION-DEPLOYMENT-GUIDE.md](../docs/APPLICATION-DEPLOYMENT-GUIDE.md) - Application deployment
- [INFERENCE-AND-RESEARCH-GUIDE.md](../docs/INFERENCE-AND-RESEARCH-GUIDE.md) - Inference & research patterns

## Support

For issues or questions:
- Check example comments for inline documentation
- Read main documentation in `docs/`
- Review QUICKSTART.md in generated projects
