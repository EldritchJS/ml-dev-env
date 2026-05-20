#!/bin/bash
#
# RDMA Perftest Runner
# Run ib_write_bw tests between two nodes with flexible configuration
#
# Usage: ./run-rdma-perftest.sh [OPTIONS]
#
# Options:
#   -s, --server-node NODE      Server node hostname (required)
#   -c, --client-node NODE      Client node hostname (required)
#   -g, --gpudirect             Enable GPUDirect (CUDA) testing
#   -d, --gpu-id ID             GPU ID to use (0-3, default: 0)
#   -n, --nic-id ID             NIC ID to use (0-3 for mlx5_6-9, default: 0)
#   -q, --num-qps NUM           Number of parallel QPs/streams (1-4, default: 1)
#   -t, --test-type TYPE        Test type: write, read, send (default: write)
#   -N, --namespace NS          Kubernetes namespace (default: nccl-test)
#   -h, --help                  Show this help message

set -euo pipefail

# Default values
NAMESPACE="nccl-test"
GPUDIRECT=false
GPU_ID=0
NIC_ID=0
NUM_QPS=1
TEST_TYPE="write"
SERVER_NODE=""
CLIENT_NODE=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

cleanup() {
    log_info "Cleaning up pods..."
    kubectl delete pod perftest-server perftest-client -n "$NAMESPACE" --ignore-not-found=true
    log_success "Cleanup complete"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server-node)
            SERVER_NODE="$2"
            shift 2
            ;;
        -c|--client-node)
            CLIENT_NODE="$2"
            shift 2
            ;;
        -g|--gpudirect)
            GPUDIRECT=true
            shift
            ;;
        -d|--gpu-id)
            GPU_ID="$2"
            shift 2
            ;;
        -n|--nic-id)
            NIC_ID="$2"
            shift 2
            ;;
        -q|--num-qps)
            NUM_QPS="$2"
            shift 2
            ;;
        -t|--test-type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -N|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVER_NODE" ]] || [[ -z "$CLIENT_NODE" ]]; then
    log_error "Server and client nodes are required"
    show_help
fi

# Validate numeric arguments
if [[ ! "$GPU_ID" =~ ^[0-3]$ ]]; then
    log_error "GPU ID must be 0-3"
    exit 1
fi

if [[ ! "$NIC_ID" =~ ^[0-3]$ ]]; then
    log_error "NIC ID must be 0-3"
    exit 1
fi

if [[ ! "$NUM_QPS" =~ ^[1-4]$ ]]; then
    log_error "Number of QPs must be 1-4"
    exit 1
fi

if [[ ! "$TEST_TYPE" =~ ^(write|read|send)$ ]]; then
    log_error "Test type must be write, read, or send"
    exit 1
fi

# Map NIC ID to mlx5 device name
# NIC 0 = mlx5_6 (eno5np0), NIC 1 = mlx5_7 (eno6np0)
# NIC 2 = mlx5_8 (eno7np0), NIC 3 = mlx5_9 (eno8np0)
RDMA_DEV="mlx5_$((NIC_ID + 6))"

# Determine test binary
TEST_BIN="ib_${TEST_TYPE}_bw"

# Print configuration
log_info "=== RDMA Perftest Configuration ==="
log_info "Server Node:    $SERVER_NODE"
log_info "Client Node:    $CLIENT_NODE"
log_info "GPUDirect:      $GPUDIRECT"
if [[ "$GPUDIRECT" == "true" ]]; then
    log_info "GPU ID:         $GPU_ID"
fi
log_info "NIC ID:         $NIC_ID ($RDMA_DEV)"
log_info "Test Type:      $TEST_TYPE ($TEST_BIN)"
log_info "Num QPs:        $NUM_QPS"
log_info "Namespace:      $NAMESPACE"
log_info "===================================="
echo

# Cleanup any existing pods
trap cleanup EXIT

# Determine image and GPU resources
if [[ "$GPUDIRECT" == "true" ]]; then
    IMAGE="quay.io/jschless/ml-dev-env:cuda-perftest"
    GPU_REQUEST="nvidia.com/gpu: 1"
    GPU_LIMIT="nvidia.com/gpu: 1"
else
    IMAGE="quay.io/jschless/ml-dev-env:minimal-perftest"
    GPU_REQUEST="# No GPU"
    GPU_LIMIT="# No GPU"
fi

# Create temporary directory for manifests
TMPDIR=$(mktemp -d)
log_info "Creating pod manifests in $TMPDIR"

# Generate server pod manifest
cat > "$TMPDIR/perftest-server.yaml" <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: perftest-server
  namespace: $NAMESPACE
  annotations:
    k8s.v1.cni.cncf.io/networks: default/eno5np0-network,default/eno6np0-network,default/eno7np0-network,default/eno8np0-network
spec:
  hostIPC: true
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: $SERVER_NODE
  containers:
  - name: perftest
    image: $IMAGE
    command: ["/bin/bash", "-c"]
    args:
    - |
      set -e
      echo "=== RDMA Perftest Server ==="
      echo "Node: \$(hostname)"
      echo "RDMA Device: $RDMA_DEV"
      echo "Test: $TEST_BIN"
      echo ""

      # Show RDMA devices
      ibv_devinfo -l
      echo ""

      # Build command
      CMD="$TEST_BIN -d $RDMA_DEV -a -F --report_gbits"
      if [[ "$NUM_QPS" -gt 1 ]]; then
        CMD="\$CMD -q $NUM_QPS"
      fi
      if [[ "$GPUDIRECT" == "true" ]]; then
        CMD="\$CMD --use_cuda=$GPU_ID"
        echo "GPU: $GPU_ID"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv
        echo ""
      fi

      echo "Running: \$CMD"
      echo "Listening for client connection..."
      echo ""

      exec \$CMD
    resources:
      requests:
        $GPU_REQUEST
        openshift.io/eno5np0rdma: 1
        openshift.io/eno6np0rdma: 1
        openshift.io/eno7np0rdma: 1
        openshift.io/eno8np0rdma: 1
      limits:
        $GPU_LIMIT
        openshift.io/eno5np0rdma: 1
        openshift.io/eno6np0rdma: 1
        openshift.io/eno7np0rdma: 1
        openshift.io/eno8np0rdma: 1
    securityContext:
      privileged: false
      capabilities:
        add:
        - IPC_LOCK
EOF

# Generate client pod manifest
cat > "$TMPDIR/perftest-client.yaml" <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: perftest-client
  namespace: $NAMESPACE
  annotations:
    k8s.v1.cni.cncf.io/networks: default/eno5np0-network,default/eno6np0-network,default/eno7np0-network,default/eno8np0-network
spec:
  hostIPC: true
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: $CLIENT_NODE
  containers:
  - name: perftest
    image: $IMAGE
    command: ["/bin/bash", "-c"]
    args:
    - |
      set -e
      echo "=== RDMA Perftest Client ==="
      echo "Node: \$(hostname)"
      echo "RDMA Device: $RDMA_DEV"
      echo "Test: $TEST_BIN"
      echo ""

      # Wait for server to start
      echo "Waiting 20 seconds for server to start..."
      sleep 20
      echo ""

      # Show RDMA devices
      ibv_devinfo -l
      echo ""

      # Get server pod IP
      SERVER_IP=\$(kubectl get pod perftest-server -n $NAMESPACE -o jsonpath='{.status.podIP}' 2>/dev/null)
      if [[ -z "\$SERVER_IP" ]]; then
        echo "ERROR: Could not get server pod IP"
        exit 1
      fi
      echo "Server IP: \$SERVER_IP"
      echo ""

      # Build command
      CMD="$TEST_BIN -d $RDMA_DEV -a -F --report_gbits"
      if [[ "$NUM_QPS" -gt 1 ]]; then
        CMD="\$CMD -q $NUM_QPS"
      fi
      if [[ "$GPUDIRECT" == "true" ]]; then
        CMD="\$CMD --use_cuda=$GPU_ID"
        echo "GPU: $GPU_ID"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv
        echo ""
      fi
      CMD="\$CMD \$SERVER_IP"

      echo "Running: \$CMD"
      echo ""

      exec \$CMD
    resources:
      requests:
        $GPU_REQUEST
        openshift.io/eno5np0rdma: 1
        openshift.io/eno6np0rdma: 1
        openshift.io/eno7np0rdma: 1
        openshift.io/eno8np0rdma: 1
      limits:
        $GPU_LIMIT
        openshift.io/eno5np0rdma: 1
        openshift.io/eno6np0rdma: 1
        openshift.io/eno7np0rdma: 1
        openshift.io/eno8np0rdma: 1
    securityContext:
      privileged: false
      capabilities:
        add:
        - IPC_LOCK
EOF

# Deploy server pod
log_info "Deploying server pod on $SERVER_NODE..."
kubectl apply -f "$TMPDIR/perftest-server.yaml"

# Wait for server pod to be running
log_info "Waiting for server pod to be Running..."
kubectl wait --for=condition=Ready pod/perftest-server -n "$NAMESPACE" --timeout=120s

log_success "Server pod is ready"
sleep 5

# Get server NIC IP (based on NIC_ID mapping to net1-4)
# NIC_ID 0=net1, 1=net2, 2=net3, 3=net4
NET_INTERFACE="net$((NIC_ID + 1))"
log_info "Getting server IP from interface $NET_INTERFACE..."

# Try to get IP from server pod's network interface
SERVER_IP=$(kubectl exec -n "$NAMESPACE" perftest-server -- ip -4 addr show "$NET_INTERFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo "")

if [[ -z "$SERVER_IP" ]]; then
    log_error "Could not get server IP from $NET_INTERFACE"
    log_info "Trying to extract from network-status annotation..."
    # Fallback: try to parse from annotations (more complex)
    SERVER_IP=$(kubectl get pod perftest-server -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
    log_warn "Using pod IP as fallback: $SERVER_IP (may not work for SR-IOV)"
fi

log_info "Server $NET_INTERFACE IP: $SERVER_IP"

# Update client manifest with server IP
sed -i.bak "s|SERVER_IP=\\\$(kubectl .*2>/dev/null)|SERVER_IP=\"$SERVER_IP\"|" "$TMPDIR/perftest-client.yaml"

# Deploy client pod
log_info "Deploying client pod on $CLIENT_NODE..."
kubectl apply -f "$TMPDIR/perftest-client.yaml"

# Wait for client pod to be running
log_info "Waiting for client pod to be Running..."
kubectl wait --for=condition=Ready pod/perftest-client -n "$NAMESPACE" --timeout=120s

log_success "Client pod is ready"
echo

# Stream client logs (this is where the test results will appear)
log_info "=== Streaming test results from client pod ==="
echo
kubectl logs -f perftest-client -n "$NAMESPACE"

# Check if test completed successfully
# Wait a moment for pod to finish and update status
sleep 2
POD_STATUS=$(kubectl get pod perftest-client -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$POD_STATUS" == "Succeeded" ]]; then
    log_success "Test completed successfully!"
elif [[ "$POD_STATUS" == "Failed" ]]; then
    log_error "Test failed"
else
    log_info "Test finished (status: $POD_STATUS)"
fi

# Cleanup happens via trap
