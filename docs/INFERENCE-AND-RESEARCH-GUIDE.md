# Inference & Research Experiments Guide

**Status:** Design + Partial Implementation
**Purpose:** Use the application-aware deployment system for model serving, batch inference, and research experiments

## Overview

The deployment wizard supports three primary use cases:

1. **Training** - Train models with distributed GPUs
2. **Inference** - Serve models for predictions (NEW)
3. **Research** - Run experiments, evaluations, analysis (NEW)

All three use the same application-aware infrastructure with different configurations.

## Use Case 1: Model Serving (Inference)

### Supported Frameworks

- **vLLM** - High-throughput LLM inference
- **TGI (Text Generation Inference)** - Hugging Face inference server
- **TensorRT-LLM** - NVIDIA optimized inference
- **Triton** - Multi-framework serving
- **FastAPI/Flask** - Custom inference APIs

### Example: vLLM Inference Server

**Deploy LLaMA-3-70B with vLLM:**

```bash
make wizard PROJECT=llama-inference

# Application Configuration:
# - Type: Custom command
# - Command: python -m vllm.entrypoints.openai.api_server --model meta-llama/Llama-3-70b-hf --tensor-parallel-size 8
# - Name: llama-inference
# - Mode: Auto-start ← Server starts automatically
# - Requirements: requirements-inference.txt (contains vllm)
# - Resources: 8 GPUs, 256GB RAM

cd deployments/llama-inference/

# Deploy server
./scripts/deploy.sh

# Server starts automatically on pod launch!
# Check logs to see when model is loaded
./scripts/logs.sh -f

# Output:
# INFO: Loading model meta-llama/Llama-3-70b-hf
# INFO: Model loaded in 45 seconds
# INFO: vLLM server running on 0.0.0.0:8000
```

**Access inference endpoint:**

```bash
# Get the inference route (needs to be added)
oc get route llama-inference-api -n <namespace>

# Or port-forward for now
oc port-forward llama-inference-0 8000:8000

# Test inference
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3-70b-hf",
    "prompt": "Once upon a time",
    "max_tokens": 100
  }'
```

### Example: Batch Inference Job

**Process large dataset with inference:**

```bash
make wizard PROJECT=batch-inference

# Application Configuration:
# - Type: Single file
# - Source: ./batch_predict.py
# - Name: batch-inference
# - Mode: Job ← One-time batch processing
# - Arguments: --input /datasets/unlabeled --output /workspace/predictions --batch-size 32
# - Resources: 4 GPUs

cd deployments/batch-inference/

# Submit batch job
./scripts/submit-job.sh

# Monitor progress
./scripts/watch-job.sh <job-id>

# Results saved to /workspace/predictions
# Download results
oc rsync batch-inference-job-<id>:/workspace/predictions ./local-predictions/
```

### Example: Multi-Model Serving

**Serve multiple models simultaneously:**

```bash
# Model 1: GPT-2 (small)
make wizard PROJECT=gpt2-inference
# - Model: gpt2
# - GPUs: 1

# Model 2: BERT (classification)
make wizard PROJECT=bert-classifier
# - Model: bert-base-uncased
# - GPUs: 1

# Model 3: LLaMA-3 (large)
make wizard PROJECT=llama-inference
# - Model: meta-llama/Llama-3-70b-hf
# - GPUs: 8

# All running simultaneously with isolated names!
```

## Use Case 2: Research Experiments

### Experiment Types

- **Hyperparameter sweeps** - Try different configurations
- **Ablation studies** - Test component importance
- **Model comparisons** - Compare architectures
- **Dataset analysis** - Explore data characteristics
- **Benchmarking** - Performance evaluation
- **Reproducibility** - Re-run published experiments

### Example: Hyperparameter Sweep

**Test different learning rates:**

```bash
make wizard PROJECT=lr-sweep

# Application Configuration:
# - Type: Single file
# - Source: ./train.py
# - Name: lr-sweep
# - Mode: Job
# - Arguments: --lr 0.001 --epochs 20

cd deployments/lr-sweep/

# Create sweep script
cat > run_sweep.sh << 'EOF'
#!/bin/bash
for lr in 0.0001 0.001 0.01 0.1; do
  echo "Submitting experiment with lr=$lr"

  # Update arguments in config
  sed -i "s/--lr [0-9.]*/--lr $lr/" config.yaml

  # Submit job
  ./scripts/submit-job.sh

  sleep 2
done
EOF

chmod +x run_sweep.sh
./run_sweep.sh

# Monitor all experiments
oc get jobs -l app=lr-sweep -w

# Compare results
for job in $(oc get jobs -l app=lr-sweep -o name); do
  echo "=== $job ==="
  oc logs $job | grep "Final"
done
```

### Example: Model Evaluation Suite

**Evaluate model on multiple benchmarks:**

```bash
make wizard PROJECT=model-eval

# Application Configuration:
# - Type: Directory
# - Source: ./evaluation_suite/
# - Entry point: run_eval.py
# - Name: model-eval
# - Mode: Job
# - Arguments: --model /models/my-model --benchmark all

cd deployments/model-eval/
cp -r ~/evaluation_suite/* workspace/

# Run evaluation
./scripts/submit-job.sh

# Results include:
# - MMLU score
# - HumanEval score
# - TruthfulQA score
# - All saved to /workspace/results/
```

### Example: Ablation Study

**Test importance of different components:**

```bash
make wizard PROJECT=ablation-study

# Application Configuration:
# - Type: Single file
# - Source: ./train.py
# - Name: ablation-study
# - Mode: Job
# - Arguments: --use-attention --use-normalization --use-residual

cd deployments/ablation-study/

# Experiment 1: Full model
# (default arguments)
./scripts/submit-job.sh

# Experiment 2: No attention
sed -i 's/--use-attention/--no-attention/' config.yaml
./scripts/submit-job.sh

# Experiment 3: No normalization
sed -i 's/--use-normalization/--no-normalization/' config.yaml
./scripts/submit-job.sh

# Experiment 4: No residual connections
sed -i 's/--use-residual/--no-residual/' config.yaml
./scripts/submit-job.sh

# Compare results
oc get jobs -l app=ablation-study
```

### Example: Data Analysis Pipeline

**Analyze dataset characteristics:**

```bash
make wizard PROJECT=data-analysis

# Application Configuration:
# - Type: Jupyter notebook or Python script
# - Source: ./analyze_dataset.py
# - Name: data-analysis
# - Mode: Manual ← Interactive analysis
# - Resources: 1 GPU (for processing)

cd deployments/data-analysis/

# Deploy
./scripts/deploy.sh

# Access Jupyter for interactive analysis
./scripts/jupyter.sh

# Or run analysis script
./scripts/run-app.sh

# View results in VSCode
./scripts/vscode.sh
```

## Use Case 3: Continuous Deployment Patterns

### A/B Testing Models

**Deploy two model versions simultaneously:**

```bash
# Model A (current production)
make wizard PROJECT=model-v1
# - Name: model-v1
# - Mode: Auto-start
# - Route: model-v1-api

# Model B (new version)
make wizard PROJECT=model-v2
# - Name: model-v2
# - Mode: Auto-start
# - Route: model-v2-api

# Both running, can split traffic between them
```

### Blue-Green Deployments

```bash
# Deploy green (new version)
make wizard PROJECT=model-green
./scripts/deploy.sh

# Test green
curl https://model-green-api.cluster.com/predict

# If good, update traffic routing
# Switch from blue to green externally

# Keep blue running for rollback
```

## Enhancements Needed

### 1. Inference-Specific Routes

**Add to wizard: Inference endpoint exposure**

```yaml
# In deployment wizard, add:
inference:
  enabled: true
  port: 8000
  path: /v1/completions
  health_check: /health
```

**Generated route:**
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {app_name}-api
spec:
  to:
    kind: Service
    name: {app_name}
  port:
    targetPort: inference
  path: {inference_path}
  tls:
    termination: edge
```

### 2. Health Checks for Model Servers

**Add to StatefulSet template:**

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 60  # Model loading time
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 300
  periodSeconds: 30
```

### 3. Load Balancing Configuration

**For multi-replica inference:**

```yaml
# Service with load balancing
apiVersion: v1
kind: Service
metadata:
  name: {app_name}-lb
spec:
  type: LoadBalancer
  selector:
    app: {app_name}
  ports:
  - port: 80
    targetPort: 8000
  sessionAffinity: None  # Round-robin
```

### 4. Inference Monitoring

**Metrics to track:**
- Requests per second
- Latency (p50, p95, p99)
- Throughput (tokens/sec)
- GPU utilization
- Queue depth
- Error rate

**Add to deployment:**
```yaml
# Prometheus metrics endpoint
- name: PROMETHEUS_MULTIPROC_DIR
  value: /tmp
- name: METRICS_PORT
  value: "9090"
```

### 5. Experiment Tracking Integration

**Add to wizard:**

```yaml
experiment_tracking:
  enabled: true
  backend: wandb  # or mlflow, tensorboard
  project: my-experiments
  tags: [ablation, gpt2]
```

**Auto-generated code:**
```python
# In job startup
import wandb
wandb.init(
    project="{project}",
    name="{job_name}",
    tags={tags},
    config={parameters}
)
```

## Configuration Examples

### Inference Server Config

```yaml
# config.yaml for inference deployment
deployment:
  cluster: barcelona
  mode: single-node

application:
  enabled: true
  type: custom_command
  name: llama-inference
  source:
    path: "python -m vllm.entrypoints.openai.api_server --model meta-llama/Llama-3-70b-hf --tensor-parallel-size 8"
  execution:
    mode: auto_start
  runtime:
    working_dir: /workspace/llama-inference

inference:  # NEW section
  enabled: true
  port: 8000
  protocol: http
  endpoint: /v1/completions
  health_check: /health
  metrics: /metrics

resources:
  gpus: 8

monitoring:
  type: inference  # Different from training
  metrics:
    - requests_per_second
    - latency_p99
    - throughput_tokens_per_sec
```

### Experiment Suite Config

```yaml
# config.yaml for experiment suite
deployment:
  cluster: nerc-production
  mode: multi-node
  num_nodes: 2

application:
  enabled: true
  type: directory
  name: hyperparam-sweep
  source:
    path: ./experiments/
    entry_point: sweep.py
  execution:
    mode: job
    arguments: "--config sweep_config.yaml"
  runtime:
    working_dir: /workspace/hyperparam-sweep

experiment:  # NEW section
  tracking:
    enabled: true
    backend: wandb
    project: gpt-experiments
    entity: my-team
  sweep:
    method: grid  # or random, bayes
    parameters:
      learning_rate: [0.0001, 0.001, 0.01]
      batch_size: [16, 32, 64]
      epochs: [10, 20, 50]
  parallelism: 4  # Run 4 experiments concurrently
```

## Workflow Patterns

### Pattern 1: Train → Evaluate → Deploy

```bash
# 1. Train model
make wizard PROJECT=model-training
cd deployments/model-training/
./scripts/run-app.sh

# 2. Evaluate model
make wizard PROJECT=model-eval
cp /workspace/model-training/checkpoints/best.pt deployments/model-eval/workspace/
cd deployments/model-eval/
./scripts/submit-job.sh

# 3. Deploy for inference
make wizard PROJECT=model-serving
cd deployments/model-serving/
./scripts/deploy.sh
```

### Pattern 2: Parallel Experiments → Best Model Selection

```bash
# 1. Run sweep
cd deployments/hyperparam-sweep/
./run_sweep.sh  # Submits 20 jobs

# 2. Monitor with wandb
# (opens wandb dashboard showing all experiments)

# 3. Identify best model
# Download best checkpoint

# 4. Deploy best model
make wizard PROJECT=best-model-inference
# Use best hyperparameters
```

### Pattern 3: Continuous Experimentation

```bash
# Daily experiment pipeline
cron:
  # 1am: Train on new data
  - "0 1 * * * cd deployments/daily-train && ./scripts/submit-job.sh"

  # 6am: Evaluate on benchmarks
  - "0 6 * * * cd deployments/daily-eval && ./scripts/submit-job.sh"

  # 12pm: Update inference if better
  - "0 12 * * * ./scripts/update-if-better.sh"
```

## Best Practices

### For Inference

1. **Use auto-start mode** - Keeps servers running
2. **Add health checks** - Ensure model loaded before traffic
3. **Monitor latency** - p99 latency is critical
4. **Set resource limits** - Prevent OOM during load
5. **Enable metrics** - Track requests, throughput, errors
6. **Test before production** - Use staging deployment first

### For Experiments

1. **Use Job mode** - Clean experiment lifecycle
2. **Track everything** - Use wandb/mlflow
3. **Unique names** - Include hyperparams in job name
4. **Save checkpoints** - Regular checkpointing to PVC
5. **Log abundantly** - Helps debug failed experiments
6. **Clean up** - Delete old jobs after extracting results

### For Research

1. **Version control code** - Track experiment code changes
2. **Document assumptions** - Add notes to config.yaml
3. **Reproducible seeds** - Set random seeds explicitly
4. **Share configs** - Commit configs to git
5. **Isolate experiments** - One project per experiment series

## Scripts to Add

### Inference Helper Scripts

**`scripts/test-inference.sh`** - Test inference endpoint:
```bash
#!/bin/bash
APP_NAME="{app_name}"
ROUTE=$(oc get route ${APP_NAME}-api -o jsonpath='{.spec.host}')

echo "Testing inference endpoint: https://$ROUTE"

curl -X POST https://$ROUTE/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Hello, world!",
    "max_tokens": 50
  }' | jq .
```

**`scripts/benchmark-inference.sh`** - Benchmark throughput:
```bash
#!/bin/bash
# Load test with multiple requests
wrk -t4 -c100 -d30s https://${ROUTE}/v1/completions \
  -s benchmark.lua

# benchmark.lua contains POST body
```

### Experiment Helper Scripts

**`scripts/run-sweep.sh`** - Run parameter sweep:
```bash
#!/bin/bash
# Read sweep config
PARAMS=$(yq eval '.sweep.parameters' config.yaml)

# Submit job for each combination
for lr in ${LEARNING_RATES}; do
  for bs in ${BATCH_SIZES}; do
    # Update config
    yq eval -i ".application.execution.arguments = \"--lr $lr --bs $bs\"" config.yaml

    # Submit
    ./scripts/submit-job.sh

    echo "Submitted: lr=$lr, bs=$bs"
  done
done
```

**`scripts/compare-experiments.sh`** - Compare experiment results:
```bash
#!/bin/bash
APP_NAME="{app_name}"

echo "Experiment Results:"
echo "==================="

for job in $(oc get jobs -l app=$APP_NAME -o name); do
  JOB_NAME=$(basename $job)

  # Extract final metrics from logs
  FINAL_LOSS=$(oc logs $job | grep "Final loss:" | awk '{print $3}')
  FINAL_ACC=$(oc logs $job | grep "Final accuracy:" | awk '{print $3}')

  echo "$JOB_NAME: Loss=$FINAL_LOSS, Acc=$FINAL_ACC"
done
```

## Example Applications

### 1. LLM Inference Service

```bash
make wizard PROJECT=llm-api

# Deploys:
# - vLLM server with LLaMA-3-70B
# - Auto-start mode (always running)
# - 8 GPUs
# - OpenAI-compatible API
# - Health checks
# - Prometheus metrics

# Access:
# https://llm-api.cluster.com/v1/completions
```

### 2. Batch Document Processing

```bash
make wizard PROJECT=doc-processing

# Deploys:
# - Job mode for batch processing
# - Processes 1M documents
# - Saves results to /datasets/processed/
# - Runs overnight
# - Automatic cleanup
```

### 3. Model Comparison Study

```bash
make wizard PROJECT=model-comparison

# Runs:
# - GPT-2 vs BERT vs RoBERTa
# - Same datasets
# - Same evaluation metrics
# - Parallel execution
# - Results in wandb dashboard
```

### 4. Real-time Experiment Dashboard

```bash
make wizard PROJECT=live-experiments

# Features:
# - Jupyter notebook interface
# - Launch experiments from notebook
# - Live metric visualization
# - Interactive parameter tuning
# - TensorBoard integration
```

## Implementation Priority

### Phase 1 (Existing - Works Today)
- ✅ Custom commands for inference frameworks
- ✅ Auto-start mode for servers
- ✅ Job mode for experiments
- ✅ Resource allocation
- ✅ Multiple deployments

### Phase 2 (Quick Adds - 1 Week)
- ⚠️ Inference route generation
- ⚠️ Health check configuration
- ⚠️ Helper scripts (test-inference.sh, run-sweep.sh)
- ⚠️ Documentation updates

### Phase 3 (Enhanced - 2 Weeks)
- 🔲 Load balancing configuration
- 🔲 Inference monitoring dashboards
- 🔲 Experiment tracking integration
- 🔲 Sweep automation
- 🔲 Result comparison tools

### Phase 4 (Advanced - Future)
- 🔲 Auto-scaling for inference
- 🔲 A/B testing support
- 🔲 Model registry integration
- 🔲 Cost optimization
- 🔲 Workflow orchestration (Airflow/Argo)

## Related Documentation

- [APPLICATION-DEPLOYMENT-GUIDE.md](APPLICATION-DEPLOYMENT-GUIDE.md) - Application-aware deployment basics
- [DEPLOYMENT-WIZARD-GUIDE.md](DEPLOYMENT-WIZARD-GUIDE.md) - Wizard usage
- [JOB-PORTAL-DESIGN.md](JOB-PORTAL-DESIGN.md) - Web portal for job management

## Summary

**The system already supports inference and research!**

**For Inference:**
- Use auto-start mode for long-running servers
- Custom commands for any framework (vLLM, TGI, etc.)
- Need to add: API routes, health checks, load balancing

**For Experiments:**
- Use Job mode for one-off experiments
- Multiple parallel experiments supported
- Need to add: Experiment tracking, sweep automation

**Quick wins:**
- Add inference route generation (1 day)
- Create helper scripts for sweeps (1 day)
- Document inference patterns (1 day)

Total: **3 days to make inference/research first-class citizens**
