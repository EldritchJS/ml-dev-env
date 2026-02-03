.PHONY: help build deploy clean test shell vscode jupyter logs status

# Configuration with environment variable overrides
NAMESPACE ?= nccl-test
POD_NAME ?= ml-dev-env
LOCAL_DIR ?= ./workspace
REMOTE_DIR ?= /workspace
DEBUG_PORT ?= 5678

# Build configuration
BUILD_CONFIG := k8s/buildconfig.yaml
POD_CONFIG := k8s/pod-multi-gpu.yaml
IMAGE_TAG := latest

help:
	@echo "ML Development Environment - OpenShift Deployment"
	@echo ""
	@echo "Current configuration:"
	@echo "  Namespace:   $(NAMESPACE)"
	@echo "  Pod name:    $(POD_NAME)"
	@echo "  Local dir:   $(LOCAL_DIR)"
	@echo "  Remote dir:  $(REMOTE_DIR)"
	@echo "  Debug port:  $(DEBUG_PORT)"
	@echo "  Image tag:   $(IMAGE_TAG)"
	@echo "  Base:        NVIDIA PyTorch (Ubuntu 22.04)"
	@echo ""
	@echo "Available targets:"
	@echo "  make build       - Build the container image"
	@echo "  make deploy      - Deploy the full environment"
	@echo "  make clean       - Remove all resources"
	@echo "  make test        - Run GPU and multi-GPU tests"
	@echo "  make shell       - Open shell in the pod"
	@echo "  make vscode      - Get VSCode URL"
	@echo "  make jupyter     - Start Jupyter and get URL"
	@echo "  make logs        - Show pod logs"
	@echo "  make status      - Show deployment status"
	@echo "  make gpu-info    - Show GPU topology and info"
	@echo ""
	@echo "Development automation (single-node):"
	@echo "  make dev-session    - Start full dev session (sync + port-forward + debug)"
	@echo "  make sync-code      - Watch and auto-sync code changes"
	@echo "  make debug-remote   - Port-forward and run script (FILE=script.py)"
	@echo "  make port-forward   - Just port-forward debug port (5678)"
	@echo "  make sync-once      - One-time code sync"
	@echo ""
	@echo "Multi-node training (4 nodes × 4 GPUs = 16 H100s):"
	@echo "  make deploy-multi-node-rdma - Deploy multi-node (RDMA/RoCE mode)"
	@echo "  make deploy-multi-node-tcp  - Deploy multi-node (TCP/Ethernet mode - no RDMA)"
	@echo "  make sync-multi-node        - Sync code to all nodes"
	@echo "  make shell-multi-node       - Shell into master node (ml-dev-env-0)"
	@echo "  make status-multi-node      - Show multi-node deployment status"
	@echo "  make clean-multi-node   - Remove multi-node deployment"
	@echo ""
	@echo "Configuration options (via environment variables):"
	@echo "  NAMESPACE=<name>     - OpenShift namespace (default: nccl-test)"
	@echo "  POD_NAME=<name>      - Pod name (default: ml-dev-env)"
	@echo "  LOCAL_DIR=<path>     - Local code directory (default: ./workspace)"
	@echo "  REMOTE_DIR=<path>    - Remote code directory (default: /workspace)"
	@echo "  DEBUG_PORT=<port>    - Debug port (default: 5678)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                      # Build with defaults"
	@echo "  NAMESPACE=ml-prod make deploy                   # Deploy to ml-prod"
	@echo "  POD_NAME=my-pod make dev-session                # Use custom pod"
	@echo "  LOCAL_DIR=./src REMOTE_DIR=/app make sync-code  # Custom directories"
	@echo ""
	@echo "Or use .env file:"
	@echo "  cp .env.example .env    # Copy example config"
	@echo "  # Edit .env with your settings"
	@echo "  source .env             # Load variables"
	@echo "  make dev-session        # Use loaded config"

build:
	@echo "Building ML Development Environment"
	@echo "  Namespace:  $(NAMESPACE)"
	@echo "  Config:     $(BUILD_CONFIG)"
	@echo ""
	@echo "Creating ImageStream..."
	cat k8s/imagestream.yaml | sed 's/namespace: nccl-test/namespace: $(NAMESPACE)/' | oc apply -f -
	@echo "Starting build (this will take 15-20 minutes)..."
	cat $(BUILD_CONFIG) | sed 's/namespace: nccl-test/namespace: $(NAMESPACE)/' | oc apply -f -
	@echo "Waiting for build to start..."
	@sleep 5
	@echo "Following build logs (Ctrl+C to stop watching, build continues)..."
	oc logs -f bc/$(POD_NAME) -n $(NAMESPACE) || true

deploy: build
	@echo "Deploying ML Development Environment"
	@echo "  Namespace:  $(NAMESPACE)"
	@echo "  Pod config: $(POD_CONFIG)"
	@echo ""
	@echo "Creating PVCs..."
	cat k8s/pvcs.yaml | sed 's/namespace: nccl-test/namespace: $(NAMESPACE)/g' | oc apply -f -
	@echo "Deploying pod..."
	cat $(POD_CONFIG) | sed 's/namespace: nccl-test/namespace: $(NAMESPACE)/' | oc apply -f -
	@echo "Creating services and routes..."
	cat k8s/service.yaml | sed 's/namespace: nccl-test/namespace: $(NAMESPACE)/g' | oc apply -f -
	@echo "Waiting for pod to be ready..."
	oc wait --for=condition=Ready pod/$(POD_NAME) -n $(NAMESPACE) --timeout=300s || true
	@echo ""
	@echo "Deployment complete!"
	@make status

clean:
	@echo "Cleaning up ML Development Environment"
	@echo "  Namespace:  $(NAMESPACE)"
	@echo ""
	@echo "Deleting pod..."
	oc delete pod $(POD_NAME) -n $(NAMESPACE) --ignore-not-found=true
	@echo "Deleting services and routes..."
	oc delete service ml-dev-env -n $(NAMESPACE) --ignore-not-found=true
	oc delete route ml-dev-vscode ml-dev-jupyter ml-dev-tensorboard -n $(NAMESPACE) --ignore-not-found=true
	@echo "Deleting PVCs (this will delete your data!)..."
	@read -p "Are you sure you want to delete PVCs? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		oc delete pvc ml-dev-workspace ml-datasets -n $(NAMESPACE) --ignore-not-found=true; \
	fi
	@echo "Deleting build resources..."
	oc delete bc ml-dev-env -n $(NAMESPACE) --ignore-not-found=true
	oc delete is ml-dev-env -n $(NAMESPACE) --ignore-not-found=true
	@echo "Cleanup complete!"

test:
	@echo "Running GPU tests..."
	oc cp examples/test_multi_gpu.py $(NAMESPACE)/$(POD_NAME):/workspace/
	oc exec $(POD_NAME) -n $(NAMESPACE) -- python /workspace/test_multi_gpu.py

shell:
	@echo "Opening shell in $(POD_NAME)..."
	oc rsh $(POD_NAME) -n $(NAMESPACE)

vscode:
	@VSCODE_URL=$$(oc get route ml-dev-vscode -n $(NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null); \
	if [ -z "$$VSCODE_URL" ]; then \
		echo "VSCode route not found. Run 'make deploy' first."; \
	else \
		echo "VSCode Server: https://$$VSCODE_URL"; \
	fi

jupyter:
	@echo "Starting Jupyter Notebook..."
	oc exec $(POD_NAME) -n $(NAMESPACE) -- bash -c "nohup jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root > /tmp/jupyter.log 2>&1 &"
	@sleep 2
	@JUPYTER_URL=$$(oc get route ml-dev-jupyter -n $(NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null); \
	if [ -z "$$JUPYTER_URL" ]; then \
		echo "Jupyter route not found. Run 'make deploy' first."; \
	else \
		echo "Jupyter Notebook: https://$$JUPYTER_URL"; \
	fi

logs:
	oc logs $(POD_NAME) -n $(NAMESPACE)

status:
	@echo "=== Configuration ==="
	@echo "Namespace:  $(NAMESPACE)"
	@echo "Image tag:  $(IMAGE_TAG)"
	@echo "Base:       NVIDIA PyTorch (Ubuntu 22.04)"
	@echo ""
	@echo "=== Pod Status ==="
	@oc get pod $(POD_NAME) -n $(NAMESPACE) 2>/dev/null || echo "Pod not found: $(POD_NAME)"
	@echo ""
	@echo "=== Build Status ==="
	@oc get builds -n $(NAMESPACE) 2>/dev/null | head -1
	@oc get builds -n $(NAMESPACE) 2>/dev/null | grep ml-dev || echo "No builds found"
	@echo ""
	@echo "=== PVC Status ==="
	@oc get pvc -n $(NAMESPACE) 2>/dev/null | grep ml-dev || echo "No PVCs found"
	@echo ""
	@echo "=== Routes ==="
	@oc get routes -n $(NAMESPACE) 2>/dev/null | grep ml-dev || echo "No routes found"
	@echo ""
	@echo "=== ImageStreams ==="
	@oc get is -n $(NAMESPACE) 2>/dev/null | grep ml-dev || echo "No ImageStreams found"

gpu-info:
	@echo "=== GPU Information ==="
	oc exec $(POD_NAME) -n $(NAMESPACE) -- nvidia-smi
	@echo ""
	@echo "=== GPU Topology ==="
	oc exec $(POD_NAME) -n $(NAMESPACE) -- nvidia-smi topo -m
	@echo ""
	@echo "=== InfiniBand Devices ==="
	oc exec $(POD_NAME) -n $(NAMESPACE) -- ibstat 2>/dev/null || echo "No IB devices or host network not enabled"

# Development Automation
# These targets pass environment variables to scripts for configuration
dev-session:
	@NAMESPACE=$(NAMESPACE) POD_NAME=$(POD_NAME) LOCAL_DIR=$(LOCAL_DIR) REMOTE_DIR=$(REMOTE_DIR) DEBUG_PORT=$(DEBUG_PORT) \
		./scripts/dev-session.sh $(FILE)

sync-code:
	@NAMESPACE=$(NAMESPACE) POD_NAME=$(POD_NAME) LOCAL_DIR=$(LOCAL_DIR) REMOTE_DIR=$(REMOTE_DIR) \
		./scripts/sync-code.sh

debug-remote:
	@NAMESPACE=$(NAMESPACE) POD_NAME=$(POD_NAME) DEBUG_PORT=$(DEBUG_PORT) \
		./scripts/debug-remote.sh $(FILE)

port-forward:
	@echo "Starting port-forward on $(DEBUG_PORT)..."
	@echo "Press Ctrl+C to stop"
	oc port-forward -n $(NAMESPACE) $(POD_NAME) $(DEBUG_PORT):$(DEBUG_PORT)

sync-once:
	@echo "Syncing code to pod..."
	@echo "  Local:  $(LOCAL_DIR)"
	@echo "  Remote: $(POD_NAME):$(REMOTE_DIR)"
	oc rsync $(LOCAL_DIR)/ $(POD_NAME):$(REMOTE_DIR)/ -n $(NAMESPACE) --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' --exclude='.DS_Store'
	@echo "✅ Sync complete"

# Multi-Node DeepSpeed Training
deploy-multi-node-rdma:
	@NAMESPACE=$(NAMESPACE) ./scripts/deploy-multi-node-rdma.sh

deploy-multi-node-tcp:
	@NAMESPACE=$(NAMESPACE) ./scripts/deploy-multi-node-tcp.sh

sync-multi-node:
	@NAMESPACE=$(NAMESPACE) LOCAL_DIR=$(LOCAL_DIR) REMOTE_DIR=$(REMOTE_DIR) ./scripts/sync-multi-node.sh

shell-multi-node:
	@echo "Opening shell in master node (ml-dev-env-0)..."
	oc exec -it ml-dev-env-0 -n $(NAMESPACE) -- bash

clean-multi-node:
	@echo "Cleaning up multi-node deployment..."
	@echo "  Namespace: $(NAMESPACE)"
	oc delete statefulset ml-dev-env -n $(NAMESPACE) --ignore-not-found=true
	oc delete service ml-dev-env-headless -n $(NAMESPACE) --ignore-not-found=true
	@echo "✅ Multi-node deployment cleaned up"
	@echo "Note: PVCs are preserved. Delete manually if needed."

status-multi-node:
	@echo "=== Multi-Node Status ==="
	@echo "Namespace: $(NAMESPACE)"
	@echo ""
	@echo "=== Pods ==="
	@oc get pods -n $(NAMESPACE) -l app=ml-dev-env-multi -o wide 2>/dev/null || echo "No multi-node pods found"
	@echo ""
	@echo "=== Service ==="
	@oc get svc ml-dev-env-headless -n $(NAMESPACE) 2>/dev/null || echo "Service not found"
	@echo ""
	@echo "=== StatefulSet ==="
	@oc get statefulset ml-dev-env -n $(NAMESPACE) 2>/dev/null || echo "StatefulSet not found"
