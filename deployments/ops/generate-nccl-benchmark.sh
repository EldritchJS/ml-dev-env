#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<USAGE
Usage: $(basename "$0") -c CONFIG_FILE [-o OUTPUT_FILE] [--stdout]

Generate an NCCL benchmark YAML from a config file.

Options:
  -c, --config FILE    Config file (required). See configs/example.conf
  -o, --output FILE    Output file path (default: generated/<deploy-name>.yaml)
  --stdout             Print to stdout instead of file (for piping to oc apply)
  -h, --help           Show this help

Examples:
  $(basename "$0") -c configs/barcelona-5node-prism.conf
  $(basename "$0") -c configs/barcelona-5node-prism.conf -o /tmp/benchmark.yaml
  $(basename "$0") -c configs/barcelona-5node-prism.conf --stdout | oc apply -f -
USAGE
    exit "${1:-0}"
}

CONFIG_FILE=""
OUTPUT_FILE=""
USE_STDOUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)  CONFIG_FILE="$2"; shift 2 ;;
        -o|--output)  OUTPUT_FILE="$2"; shift 2 ;;
        --stdout)     USE_STDOUT=true; shift ;;
        -h|--help)    usage 0 ;;
        *)            echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: config file required (-c)" >&2
    usage 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Source config
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ---------------------------------------------------------------------------
# Gold standard NCCL defaults (config values take precedence)
# ---------------------------------------------------------------------------
: "${NCCL_DMABUF_ENABLE:=1}"
: "${NCCL_CROSS_NIC:=0}"
: "${NCCL_DEBUG:=INFO}"
: "${NCCL_DEBUG_SUBSYS:=INIT,NET}"
: "${NCCL_MIN_NCHANNELS:=8}"
: "${NCCL_MAX_NCHANNELS:=16}"
: "${NCCL_NET_GDR_LEVEL:=5}"
: "${NCCL_NET_GDR_READ:=1}"
: "${NCCL_IB_GID_INDEX:=3}"
: "${NCCL_IB_TC:=106}"
: "${NCCL_IB_TIMEOUT:=23}"
: "${NCCL_IB_RETRY_CNT:=7}"
: "${NCCL_IB_SL:=0}"
: "${NCCL_IB_AR_THRESHOLD:=8192}"
: "${NCCL_IB_PCI_RELAXED_ORDERING:=1}"
: "${NCCL_PROTO:=Simple}"
: "${NCCL_ALGO:=Ring}"
: "${NCCL_BUFFSIZE:=8388608}"
: "${NCCL_NTHREADS:=640}"
: "${NCCL_LL_THRESHOLD:=0}"
: "${NCCL_TREE_THRESHOLD:=0}"
: "${NCCL_SOCKET_FAMILY:=4}"
: "${NCCL_NSOCKS_PERTHREAD:=8}"
: "${NCCL_NVLS_ENABLE:=0}"
: "${NCCL_NET_SHARED_BUFFERS:=1}"
: "${NCCL_NET_OVERHEAD:=0}"
: "${NCCL_IGNORE_CPU_AFFINITY:=1}"

# Hardware defaults (Barcelona cluster)
: "${NETWORK_ATTACHMENTS:=eno5np0-network,eno6np0-network,eno7np0-network,eno8np0-network}"
: "${RDMA_RESOURCES:=openshift.io/eno5np0rdma openshift.io/eno6np0rdma openshift.io/eno7np0rdma openshift.io/eno8np0rdma}"
: "${MLX5_DEVICES:=mlx5_6,mlx5_7,mlx5_8,mlx5_9}"
: "${SOCKET_IFNAMES:=net1,net2,net3,net4}"
: "${GPU_PRODUCT:=NVIDIA-H100-80GB-HBM3}"
: "${GPU_COUNT:=4}"
: "${CUDA_VISIBLE_DEVICES:=0,1,2,3}"
: "${MASTER_PORT:=29501}"
: "${CPU_REQUEST:=32}"
: "${CPU_LIMIT:=64}"
: "${MEMORY:=1200Gi}"

# ---------------------------------------------------------------------------
# Validate required fields
# ---------------------------------------------------------------------------
errors=()
[[ -z "${NAMESPACE:-}" ]]       && errors+=("NAMESPACE is required")
[[ -z "${DEPLOY_NAME:-}" ]]     && errors+=("DEPLOY_NAME is required")
[[ -z "${IMAGE:-}" ]]           && errors+=("IMAGE is required")
[[ -z "${SERVICE_ACCOUNT:-}" ]] && errors+=("SERVICE_ACCOUNT is required")
[[ -z "${NODES:-}" ]]           && errors+=("NODES is required")

if [[ ${#errors[@]} -gt 0 ]]; then
    for e in "${errors[@]}"; do echo "Error: $e" >&2; done
    exit 1
fi

# Derive replica count from node list
read -ra NODE_ARRAY <<< "$NODES"
REPLICAS=${#NODE_ARRAY[@]}

if [[ $REPLICAS -lt 1 ]]; then
    echo "Error: NODES must contain at least one hostname" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve benchmark script path
# ---------------------------------------------------------------------------
BENCHMARK_SCRIPT="$SCRIPT_DIR/allreduce-loop.py"
if [[ ! -f "$BENCHMARK_SCRIPT" ]]; then
    echo "Error: benchmark script not found: $BENCHMARK_SCRIPT" >&2
    echo "Expected deployments/ops/allreduce-loop.py" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Output destination
# ---------------------------------------------------------------------------
if [[ "$USE_STDOUT" == true ]]; then
    OUTPUT="/dev/stdout"
elif [[ -n "$OUTPUT_FILE" ]]; then
    OUTPUT="$OUTPUT_FILE"
else
    mkdir -p "$SCRIPT_DIR/generated"
    OUTPUT="$SCRIPT_DIR/generated/${DEPLOY_NAME}.yaml"
fi

# ---------------------------------------------------------------------------
# Build dynamic YAML sections
# ---------------------------------------------------------------------------

generate_node_list() {
    for node in "${NODE_ARRAY[@]}"; do
        echo "                - ${node}"
    done
}

generate_rdma_resources() {
    local indent="$1"
    for res in $RDMA_RESOURCES; do
        echo "${indent}${res}: 1"
    done
}

generate_cuda_devices() {
    local devices=""
    for ((i=0; i<GPU_COUNT; i++)); do
        [[ -n "$devices" ]] && devices+=","
        devices+="$i"
    done
    echo "$devices"
}

# Build the embedded entrypoint script (runtime vars must NOT expand)
build_entrypoint() {
    cat <<'ENTRYPOINT'
set -e

export NODE_RANK=${HOSTNAME##*-}
export MASTER_ADDR="__DEPLOY_NAME__-0.__DEPLOY_NAME__-svc"
export MASTER_PORT=__MASTER_PORT__
export NPROC_PER_NODE=__GPU_COUNT__

echo "=========================================="
echo "GOLD STANDARD NCCL ALL-REDUCE BENCHMARK"
echo "__REPLICAS__ NODES"
echo "=========================================="
echo "Pod: ${POD_NAME}"
echo "Node: ${NODE_RANK}"
echo "Master: ${MASTER_ADDR}:${MASTER_PORT}"
echo ""

nvidia-smi --query-gpu=index,name --format=csv,noheader
echo ""

echo "NCCL Configuration:"
env | grep NCCL | sort
echo ""

echo "Ready to run benchmark."
echo "Exec into pod-0 and run:"
echo "  torchrun --nnodes=__REPLICAS__ --nproc_per_node=__GPU_COUNT__ --node_rank=0 \\"
echo "    --master_addr=__DEPLOY_NAME__-0.__DEPLOY_NAME__-svc \\"
echo "    --master_port=__MASTER_PORT__ /benchmark/allreduce-loop.py -r 3"
echo ""

sleep infinity
ENTRYPOINT
}

ENTRYPOINT_SCRIPT=$(build_entrypoint)
ENTRYPOINT_SCRIPT="${ENTRYPOINT_SCRIPT//__DEPLOY_NAME__/$DEPLOY_NAME}"
ENTRYPOINT_SCRIPT="${ENTRYPOINT_SCRIPT//__MASTER_PORT__/$MASTER_PORT}"
ENTRYPOINT_SCRIPT="${ENTRYPOINT_SCRIPT//__GPU_COUNT__/$GPU_COUNT}"
ENTRYPOINT_SCRIPT="${ENTRYPOINT_SCRIPT//__REPLICAS__/$REPLICAS}"

# Indent the entrypoint for YAML embedding (10 spaces for args block, blank lines stay blank)
INDENTED_ENTRYPOINT=""
while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        INDENTED_ENTRYPOINT+=""$'\n'
    else
        INDENTED_ENTRYPOINT+="          ${line}"$'\n'
    fi
done <<< "$ENTRYPOINT_SCRIPT"

# Indent the benchmark script for ConfigMap embedding (4 spaces, blank lines stay blank)
INDENTED_BENCHMARK=""
while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        INDENTED_BENCHMARK+=""$'\n'
    else
        INDENTED_BENCHMARK+="    ${line}"$'\n'
    fi
done < "$BENCHMARK_SCRIPT"

# Build RDMA resource blocks
RDMA_REQUESTS=$(generate_rdma_resources "            ")
RDMA_LIMITS=$(generate_rdma_resources "            ")

# Build node list
NODE_LIST=$(generate_node_list)

# ---------------------------------------------------------------------------
# Generate YAML
# ---------------------------------------------------------------------------
cat > "$OUTPUT" <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: ${DEPLOY_NAME}-svc
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOY_NAME}
spec:
  clusterIP: None
  selector:
    app: ${DEPLOY_NAME}
  ports:
  - port: ${MASTER_PORT}
    name: master
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${DEPLOY_NAME}-script
  namespace: ${NAMESPACE}
data:
  allreduce-loop.py: |
${INDENTED_BENCHMARK}---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${DEPLOY_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOY_NAME}
spec:
  serviceName: ${DEPLOY_NAME}-svc
  replicas: ${REPLICAS}
  podManagementPolicy: Parallel

  selector:
    matchLabels:
      app: ${DEPLOY_NAME}

  template:
    metadata:
      labels:
        app: ${DEPLOY_NAME}
      annotations:
        k8s.v1.cni.cncf.io/networks: ${NETWORK_ATTACHMENTS}

    spec:
      serviceAccountName: ${SERVICE_ACCOUNT}
      hostIPC: true

      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - ${DEPLOY_NAME}
            topologyKey: kubernetes.io/hostname
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: nvidia.com/gpu.product
                operator: In
                values:
                - ${GPU_PRODUCT}
              - key: kubernetes.io/hostname
                operator: In
                values:
${NODE_LIST}

      containers:
      - name: benchmark
        image: ${IMAGE}
        command: ["/bin/bash", "-c"]
        args:
        - |
${INDENTED_ENTRYPOINT}
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP

        - name: NCCL_DMABUF_ENABLE
          value: "${NCCL_DMABUF_ENABLE}"

        - name: NCCL_DEBUG
          value: "${NCCL_DEBUG}"
        - name: NCCL_DEBUG_SUBSYS
          value: "${NCCL_DEBUG_SUBSYS}"

        - name: NCCL_MIN_NCHANNELS
          value: "${NCCL_MIN_NCHANNELS}"
        - name: NCCL_MAX_NCHANNELS
          value: "${NCCL_MAX_NCHANNELS}"

        - name: NCCL_SOCKET_IFNAME
          value: "${SOCKET_IFNAMES}"
        - name: NCCL_IB_HCA
          value: "${MLX5_DEVICES}"

        - name: NCCL_NET_GDR_LEVEL
          value: "${NCCL_NET_GDR_LEVEL}"
        - name: NCCL_NET_GDR_READ
          value: "${NCCL_NET_GDR_READ}"

        - name: NCCL_IB_GID_INDEX
          value: "${NCCL_IB_GID_INDEX}"
        - name: NCCL_IB_TC
          value: "${NCCL_IB_TC}"
        - name: NCCL_IB_TIMEOUT
          value: "${NCCL_IB_TIMEOUT}"
        - name: NCCL_IB_RETRY_CNT
          value: "${NCCL_IB_RETRY_CNT}"
        - name: NCCL_IB_SL
          value: "${NCCL_IB_SL}"
        - name: NCCL_IB_AR_THRESHOLD
          value: "${NCCL_IB_AR_THRESHOLD}"
        - name: NCCL_IB_PCI_RELAXED_ORDERING
          value: "${NCCL_IB_PCI_RELAXED_ORDERING}"

        - name: NCCL_PROTO
          value: "${NCCL_PROTO}"
        - name: NCCL_ALGO
          value: "${NCCL_ALGO}"

        - name: NCCL_BUFFSIZE
          value: "${NCCL_BUFFSIZE}"
        - name: NCCL_NTHREADS
          value: "${NCCL_NTHREADS}"

        - name: NCCL_LL_THRESHOLD
          value: "${NCCL_LL_THRESHOLD}"
        - name: NCCL_TREE_THRESHOLD
          value: "${NCCL_TREE_THRESHOLD}"

        - name: NCCL_SOCKET_FAMILY
          value: "${NCCL_SOCKET_FAMILY}"
        - name: NCCL_NSOCKS_PERTHREAD
          value: "${NCCL_NSOCKS_PERTHREAD}"

        - name: NCCL_CROSS_NIC
          value: "${NCCL_CROSS_NIC}"

        - name: NCCL_NVLS_ENABLE
          value: "${NCCL_NVLS_ENABLE}"

        - name: NCCL_NET_SHARED_BUFFERS
          value: "${NCCL_NET_SHARED_BUFFERS}"

        - name: NCCL_NET_OVERHEAD
          value: "${NCCL_NET_OVERHEAD}"

        - name: NCCL_IGNORE_CPU_AFFINITY
          value: "${NCCL_IGNORE_CPU_AFFINITY}"

        - name: CUDA_VISIBLE_DEVICES
          value: "${CUDA_VISIBLE_DEVICES}"

        resources:
          requests:
            nvidia.com/gpu: ${GPU_COUNT}
${RDMA_REQUESTS}
            cpu: "${CPU_REQUEST}"
            memory: "${MEMORY}"
          limits:
            nvidia.com/gpu: ${GPU_COUNT}
${RDMA_LIMITS}
            cpu: "${CPU_LIMIT}"
            memory: "${MEMORY}"

        volumeMounts:
        - name: benchmark-script
          mountPath: /benchmark
        - name: dshm
          mountPath: /dev/shm

        securityContext:
          privileged: false
          capabilities:
            add:
            - IPC_LOCK
            - SYS_ADMIN

      volumes:
      - name: benchmark-script
        configMap:
          name: ${DEPLOY_NAME}-script
      - name: dshm
        emptyDir:
          medium: Memory
EOF

if [[ "$USE_STDOUT" != true ]]; then
    echo "Generated: $OUTPUT" >&2
    echo "  Namespace: $NAMESPACE" >&2
    echo "  Nodes: $REPLICAS (${NODES})" >&2
    echo "  Image: $IMAGE" >&2
fi
