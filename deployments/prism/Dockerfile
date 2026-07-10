# Prism Deployment - BEACON Continued Pre-training Environment
# Base: NVIDIA PyTorch NGC Container with CUDA 12.8, NCCL, cuDNN
# Target: Barcelona H100 cluster with RDMA/InfiniBand

FROM nvcr.io/nvidia/pytorch:25.06-py3

LABEL maintainer="NAIRR ML Dev Team"
LABEL description="BEACON continued pre-training environment with NeMo, DeepSpeed, and HuggingFace stack"
LABEL cluster="barcelona"
LABEL cuda.version="12.8"
LABEL pytorch.version="2.6"

# Install system dependencies for RDMA/InfiniBand
RUN apt-get update && apt-get install -y \
    infiniband-diags \
    ibverbs-utils \
    libibverbs-dev \
    rdma-core \
    && rm -rf /var/lib/apt/lists/*

# Layer 1: Install NeMo Toolkit (heaviest, changes least often)
# This includes many dependencies and takes longest to install
RUN pip install --no-cache-dir \
    nemo_toolkit[nlp]==2.0.0

# Layer 2: Install distributed training frameworks
RUN pip install --no-cache-dir \
    deepspeed==0.15.4 \
    lightning==2.4.0

# Layer 3: Install HuggingFace ecosystem
RUN pip install --no-cache-dir \
    transformers==4.46.3 \
    datasets==3.1.0 \
    accelerate==1.1.1 \
    tokenizers==0.20.3 \
    huggingface_hub==0.26.2 \
    safetensors==0.4.5 \
    sentencepiece==0.2.0

# Layer 4: Install training utilities (PEFT, TRL, evaluation)
RUN pip install --no-cache-dir \
    peft==0.13.2 \
    trl==0.12.1 \
    evaluate==0.4.3 \
    scikit-learn==1.5.2

# Layer 5: Install specialized kernels for MXFP4 support
# Note: kernels package may require specific CUDA version compatibility
RUN pip install --no-cache-dir \
    kernels>=0.12.0 || echo "WARNING: kernels package installation failed, continuing..."

# Layer 6: Install numerical and data processing libraries
RUN pip install --no-cache-dir \
    numpy==2.0.2 \
    pandas==2.2.3 \
    pyarrow==18.1.0 \
    protobuf==5.28.3 \
    einops==0.8.0 \
    packaging==24.2 \
    psutil==6.1.0 \
    tqdm==4.67.1 \
    pyyaml==6.0.2 \
    requests==2.32.3

# Layer 7: Install logging and experiment tracking tools
RUN pip install --no-cache-dir \
    wandb==0.18.7 \
    tensorboard==2.18.0

# Set unlimited memlock for RDMA (container-level, also set at pod level)
RUN echo "* soft memlock unlimited" >> /etc/security/limits.conf && \
    echo "* hard memlock unlimited" >> /etc/security/limits.conf

# Set working directory
WORKDIR /workspace

# Verify critical packages are installed
RUN python -c "import torch; print(f'PyTorch: {torch.__version__}')" && \
    python -c "import nemo; print(f'NeMo: {nemo.__version__}')" && \
    python -c "import transformers; print(f'Transformers: {transformers.__version__}')" && \
    python -c "import deepspeed; print(f'DeepSpeed: {deepspeed.__version__}')" && \
    python -c "import lightning; print(f'Lightning: {lightning.__version__}')" && \
    echo "All critical packages installed successfully"

# Default command
CMD ["/bin/bash"]
