#!/usr/bin/env bash
set -euo pipefail

# H-Kim Deployment Script
# Deploys h-kim pods with namespace and network mode configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
NAMESPACE="nccl-test"
MODE="rdma"
DEPLOYMENT_TYPE="multi"
IMAGE_SOURCE="quay"
DRY_RUN=false
#NODES="moc-r4pcc04u23-nairr,moc-r4pcc04u25-nairr"
NODES="moc-r4pcc04u09-nairr,moc-r4pcc04u11-nairr,moc-r4pcc04u12-nairr,moc-r4pcc04u16-nairr,moc-r4pcc04u25-nairr,moc-r4pcc04u36-nairr"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy h-kim image with configurable namespace and network mode.

OPTIONS:
    --namespace NAME        OpenShift namespace (default: nccl-test)
    --mode MODE            Network mode: rdma or tcp (default: rdma)
    --type TYPE            Deployment type: single or multi (default: multi)
    --image-source SOURCE  Image source: quay or build (default: quay)
    --nodes NODE1,NODE2    Comma-separated node names (default: Barcelona nodes)
    --dry-run              Show what would be deployed without applying
    -h, --help             Show this help message

EXAMPLES:
    # Deploy to custom namespace with RDMA
    $(basename "$0") --namespace b-efficient-memory-offloading-765cab --mode rdma

    # Deploy single-node with TCP fallback
    $(basename "$0") --namespace my-ns --mode tcp --type single

    # Preview deployment without applying
    $(basename "$0") --namespace my-ns --dry-run

NETWORK MODES:
    rdma - Use InfiniBand/RDMA (requires mlx5 devices, high performance)
    tcp  - Use standard Ethernet (works anywhere, lower performance)

DEPLOYMENT TYPES:
    single - Single pod with 4 GPUs
    multi  - StatefulSet with 2 pods (8 GPUs total)

IMAGE SOURCES:
    quay  - Use pre-built image from quay.io/jschless/ml-dev-env:h-kim
    build - Build image in target namespace using BuildConfig

EOF
    exit 0
}

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            if [[ "$MODE" != "rdma" && "$MODE" != "tcp" ]]; then
                log_error "Invalid mode: $MODE. Must be 'rdma' or 'tcp'"
                exit 1
            fi
            shift 2
            ;;
        --type)
            DEPLOYMENT_TYPE="$2"
            if [[ "$DEPLOYMENT_TYPE" != "single" && "$DEPLOYMENT_TYPE" != "multi" ]]; then
                log_error "Invalid type: $DEPLOYMENT_TYPE. Must be 'single' or 'multi'"
                exit 1
            fi
            shift 2
            ;;
        --image-source)
            IMAGE_SOURCE="$2"
            if [[ "$IMAGE_SOURCE" != "quay" && "$IMAGE_SOURCE" != "build" ]]; then
                log_error "Invalid image source: $IMAGE_SOURCE. Must be 'quay' or 'build'"
                exit 1
            fi
            shift 2
            ;;
        --nodes)
            NODES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Convert comma-separated nodes to array
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

log_info "=========================================="
log_info "H-Kim Deployment Configuration"
log_info "=========================================="
log_info "Namespace:        $NAMESPACE"
log_info "Network Mode:     $MODE"
log_info "Deployment Type:  $DEPLOYMENT_TYPE"
log_info "Image Source:     $IMAGE_SOURCE"
log_info "Target Nodes:     ${NODE_ARRAY[*]}"
log_info "Dry Run:          $DRY_RUN"
log_info "=========================================="
echo

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_warn "Namespace '$NAMESPACE' does not exist"
    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Create namespace? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            oc create namespace "$NAMESPACE"
            log_success "Created namespace: $NAMESPACE"
        else
            log_error "Namespace required. Exiting."
            exit 1
        fi
    fi
fi

# Function to apply or show manifest
apply_manifest() {
    local manifest="$1"
    local description="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would deploy: $description"
        echo "---"
        echo "$manifest" | head -20
        echo "... (truncated)"
        echo
    else
        log_info "Deploying: $description"
        echo "$manifest" | oc apply -f -
        log_success "Deployed: $description"
    fi
}

# Determine image to use
if [[ "$IMAGE_SOURCE" == "quay" ]]; then
    IMAGE="quay.io/jschless/ml-dev-env:h-kim"
else
    IMAGE="image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/h-kim:latest"

    # Deploy ImageStream and BuildConfig if building
    log_info "Deploying build infrastructure..."

    imagestream=$(sed "s/namespace: nccl-test/namespace: $NAMESPACE/g" "$PROJECT_ROOT/k8s/imagestream-h-kim.yaml")
    apply_manifest "$imagestream" "ImageStream"

    buildconfig=$(sed "s/namespace: nccl-test/namespace: $NAMESPACE/g" "$PROJECT_ROOT/k8s/buildconfig-h-kim.yaml")
    apply_manifest "$buildconfig" "BuildConfig"

    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Starting image build (this takes ~10-15 minutes)..."
        oc start-build h-kim -n "$NAMESPACE" --follow
    else
        log_info "Would start build: oc start-build h-kim -n $NAMESPACE --follow"
    fi
fi

# Deploy NCCL IB auto-detection ConfigMap
log_info "Deploying NCCL InfiniBand auto-detection ConfigMap..."
configmap=$(cat << 'EOFCONFIGMAP'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nccl-ib-autodetect
  labels:
    app: ml-training
    component: nccl-config
data:
  nccl-wrapper.sh: |
    #!/bin/bash

    # Set unlimited locked memory (critical for RDMA)
    ulimit -l unlimited 2>/dev/null || echo "Warning: Could not set unlimited memlock"

    echo "=== NCCL InfiniBand Auto-Detection ==="

    # Check memory lock limit
    MEMLOCK_LIMIT=$(ulimit -l)
    if [ "$MEMLOCK_LIMIT" != "unlimited" ]; then
        echo "⚠ WARNING: Memory lock limit is $MEMLOCK_LIMIT KB (should be unlimited for RDMA)"
        echo "  This may cause RDMA errors. Trying to increase..."
        ulimit -l unlimited 2>/dev/null && echo "  ✓ Set to unlimited" || echo "  ✗ Failed to set unlimited"
    else
        echo "✓ Memory lock limit: unlimited"
    fi

    # Auto-detect allocated SR-IOV RDMA devices from device plugin env vars
    IB_DEVICES=""

    # Extract rdma_dev from SR-IOV device plugin INFO environment variables
    for var in $(env | grep "PCIDEVICE_.*_INFO=" | cut -d= -f1); do
        rdma_dev=$(eval echo \$$var | grep -o '"rdma_dev":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$rdma_dev" ]; then
            if [ -z "$IB_DEVICES" ]; then
                IB_DEVICES="$rdma_dev"
            else
                IB_DEVICES="$IB_DEVICES,$rdma_dev"
            fi
        fi
    done

    if [ -n "$IB_DEVICES" ]; then
        export NCCL_IB_HCA="$IB_DEVICES"
        echo "✓ Auto-detected allocated SR-IOV devices: $NCCL_IB_HCA"
        IB_COUNT=$(echo "$IB_DEVICES" | tr ',' '\n' | wc -l)
        echo "✓ Found $IB_COUNT SR-IOV allocated device(s)"
    else
        echo "⚠ Warning: No SR-IOV devices found in environment variables"
        echo "  Falling back to SR-IOV VF detection..."

        # Fallback: Filter for SR-IOV VF devices
        if command -v ibv_devinfo &> /dev/null; then
            VF_DEVICES=""
            for dev in $(ibv_devinfo -l 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'); do
                if [ -L "/sys/class/infiniband/$dev/device/physfn" ]; then
                    if [ -z "$VF_DEVICES" ]; then
                        VF_DEVICES="$dev"
                    else
                        VF_DEVICES="$VF_DEVICES,$dev"
                    fi
                fi
            done

            if [ -n "$VF_DEVICES" ]; then
                export NCCL_IB_HCA="$VF_DEVICES"
                echo "✓ Using SR-IOV VF devices: $NCCL_IB_HCA"
            fi
        fi
    fi

    # Set NCCL environment variables
    export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
    export NCCL_IB_DISABLE=${NCCL_IB_DISABLE:-0}
    export NCCL_NET_GDR_LEVEL=${NCCL_NET_GDR_LEVEL:-5}
    export NCCL_IB_GID_INDEX=${NCCL_IB_GID_INDEX:-3}
    export NCCL_IB_TIMEOUT=${NCCL_IB_TIMEOUT:-22}

    echo ""
    echo "=== NCCL Configuration ==="
    env | grep ^NCCL_ | sort | sed 's/^/  /'
    echo "  MEMLOCK_LIMIT=$(ulimit -l)"
    echo "=========================="
    echo ""

    exec "$@"
EOFCONFIGMAP
)

# Update the ConfigMap namespace
configmap=$(echo "$configmap" | sed "s/  name: nccl-ib-autodetect/  name: nccl-ib-autodetect\n  namespace: $NAMESPACE/")
apply_manifest "$configmap" "NCCL IB Auto-Detection ConfigMap"

# Configure network settings based on mode
if [[ "$MODE" == "rdma" ]]; then
    NCCL_SOCKET_IFNAME="eth0"  # Use eth0 for bootstrap, IB devices for RDMA data
    NCCL_IB_DISABLE="0"
    # NCCL_IB_HCA is now auto-detected by the wrapper script at runtime
    # Old hardcoded value: NCCL_IB_HCA="mlx5_6,mlx5_7,mlx5_10,mlx5_11"
    NCCL_IB_HCA=""  # Will be set by auto-detection wrapper
    NCCL_IB_GID_INDEX="3"
    NCCL_NET_GDR_LEVEL="5"
    NETWORK_ANNOTATIONS="      annotations:
        k8s.v1.cni.cncf.io/networks: ${NAMESPACE}/eno5np0-network, ${NAMESPACE}/eno6np0-network, ${NAMESPACE}/eno7np0-network, ${NAMESPACE}/eno8np0-network"
    SRIOV_RESOURCES="            openshift.io/eno5np0rdma: 1
            openshift.io/eno6np0rdma: 1
            openshift.io/eno7np0rdma: 1
            openshift.io/eno8np0rdma: 1"
    SECURITY_CONTEXT="        securityContext:
          privileged: true
          capabilities:
            add:
              - IPC_LOCK"
    SERVICE_ACCOUNT="      serviceAccountName: h-kim-sa"
else
    NCCL_SOCKET_IFNAME="eth0"
    NCCL_IB_DISABLE="1"
    NCCL_IB_HCA=""
    NCCL_IB_GID_INDEX="0"
    NCCL_NET_GDR_LEVEL="0"
    NETWORK_ANNOTATIONS=""
    SRIOV_RESOURCES=""
    SECURITY_CONTEXT=""
    SERVICE_ACCOUNT=""
fi

# Build node affinity YAML (just the nodeAffinity part, not the wrapper)
build_node_affinity() {
    if [[ ${#NODE_ARRAY[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    cat << EOF
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
EOF
    for node in "${NODE_ARRAY[@]}"; do
        echo "                - $node"
    done
}

# Deploy based on type
if [[ "$DEPLOYMENT_TYPE" == "single" ]]; then
    log_info "Deploying single-node h-kim pod..."

    NODE_AFFINITY=$(build_node_affinity)

    manifest=$(cat << EOF
apiVersion: v1
kind: Pod
metadata:
  name: h-kim-dev
  namespace: $NAMESPACE
  labels:
    app: h-kim
$NETWORK_ANNOTATIONS
spec:
  restartPolicy: Always
$SERVICE_ACCOUNT

$NODE_AFFINITY

  nodeSelector:
    nvidia.com/gpu.present: "true"

  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule

  containers:
  - name: h-kim
    image: $IMAGE
    imagePullPolicy: Always

$SECURITY_CONTEXT

    resources:
      requests:
        nvidia.com/gpu: 4
        memory: 128Gi
        cpu: 32
$SRIOV_RESOURCES
      limits:
        nvidia.com/gpu: 4
        memory: 256Gi
        cpu: 64
$SRIOV_RESOURCES

    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: "all"
    - name: NCCL_SOCKET_IFNAME
      value: "$NCCL_SOCKET_IFNAME"
    - name: NCCL_IB_DISABLE
      value: "$NCCL_IB_DISABLE"
    # NCCL_IB_HCA is auto-detected by wrapper script
    - name: NCCL_IB_GID_INDEX
      value: "$NCCL_IB_GID_INDEX"
    - name: NCCL_NET_GDR_LEVEL
      value: "$NCCL_NET_GDR_LEVEL"
    - name: NCCL_DEBUG
      value: "INFO"

    volumeMounts:
    - name: workspace
      mountPath: /workspace
    - name: dshm
      mountPath: /dev/shm
    - name: nccl-wrapper
      mountPath: /scripts

    command: ["/bin/bash", "/scripts/nccl-wrapper.sh", "sleep", "infinity"]

  volumes:
  - name: workspace
    emptyDir: {}
  - name: dshm
    emptyDir:
      medium: Memory
      sizeLimit: 32Gi
  - name: nccl-wrapper
    configMap:
      name: nccl-ib-autodetect
      defaultMode: 0755
EOF
)

    apply_manifest "$manifest" "Single-node Pod"

else
    log_info "Deploying multi-node h-kim StatefulSet..."

    SERVICE_DNS="h-kim-0.h-kim-headless.${NAMESPACE}.svc.cluster.local"

    NODE_AFFINITY=$(build_node_affinity)

    # Deploy headless service
    service=$(cat << EOF
apiVersion: v1
kind: Service
metadata:
  name: h-kim-headless
  namespace: $NAMESPACE
  labels:
    app: h-kim-multi
spec:
  clusterIP: None
  selector:
    app: h-kim-multi
  ports:
  - port: 29500
    name: master
EOF
)

    apply_manifest "$service" "Headless Service"

    # Deploy StatefulSet
    statefulset=$(cat << EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: h-kim
  namespace: $NAMESPACE
  labels:
    app: h-kim-multi
spec:
  serviceName: h-kim-headless
  replicas: 2
  podManagementPolicy: Parallel

  selector:
    matchLabels:
      app: h-kim-multi

  template:
    metadata:
      labels:
        app: h-kim-multi
$NETWORK_ANNOTATIONS

    spec:
      restartPolicy: Always
$SERVICE_ACCOUNT

      affinity:
$NODE_AFFINITY
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - h-kim-multi
            topologyKey: kubernetes.io/hostname

      nodeSelector:
        nvidia.com/gpu.present: "true"

      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule

      containers:
      - name: h-kim
        image: $IMAGE
        imagePullPolicy: Always

$SECURITY_CONTEXT

        resources:
          requests:
            nvidia.com/gpu: 4
            memory: 128Gi
            cpu: 32
$SRIOV_RESOURCES
          limits:
            nvidia.com/gpu: 4
            memory: 256Gi
            cpu: 64
$SRIOV_RESOURCES

        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_SOCKET_IFNAME
          value: "$NCCL_SOCKET_IFNAME"
        - name: NCCL_IB_DISABLE
          value: "$NCCL_IB_DISABLE"
        # NCCL_IB_HCA is auto-detected by wrapper script
        - name: NCCL_IB_GID_INDEX
          value: "$NCCL_IB_GID_INDEX"
        - name: NCCL_NET_GDR_LEVEL
          value: "$NCCL_NET_GDR_LEVEL"
        - name: MASTER_ADDR
          value: "$SERVICE_DNS"
        - name: MASTER_PORT
          value: "29500"
        - name: WORLD_SIZE
          value: "8"
        - name: GPUS_PER_NODE
          value: "4"

        volumeMounts:
        - name: workspace
          mountPath: /workspace
        - name: dshm
          mountPath: /dev/shm
        - name: nccl-wrapper
          mountPath: /scripts

        command:
        - /bin/bash
        - /scripts/nccl-wrapper.sh
        - bash
        - -c
        - |
          set -e
          POD_ORDINAL=\${HOSTNAME##*-}
          export NODE_RANK=\$POD_ORDINAL
          echo "=========================================="
          echo "H-Kim Multi-Node Environment"
          echo "=========================================="
          echo "Pod: \$HOSTNAME"
          echo "Node Rank: \$NODE_RANK"
          echo "World Size: \$WORLD_SIZE"
          echo "Master: \$MASTER_ADDR:\$MASTER_PORT"
          echo ""
          nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
          echo ""
          echo "Environment ready. Waiting for training job..."
          sleep infinity

      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 32Gi
      - name: nccl-wrapper
        configMap:
          name: nccl-ib-autodetect
          defaultMode: 0755

  volumeClaimTemplates:
  - metadata:
      name: workspace
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
      storageClassName: ocs-external-storagecluster-ceph-rbd
EOF
)

    apply_manifest "$statefulset" "Multi-node StatefulSet"
fi

echo
log_success "=========================================="
log_success "Deployment Complete!"
log_success "=========================================="

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "This was a dry run. No resources were created."
    log_info "Run without --dry-run to actually deploy."
else
    log_info "Check pod status:"
    if [[ "$DEPLOYMENT_TYPE" == "single" ]]; then
        echo "  oc get pod h-kim-dev -n $NAMESPACE"
        echo "  oc exec -it h-kim-dev -n $NAMESPACE -- bash"
    else
        echo "  oc get pods -n $NAMESPACE -l app=h-kim-multi -w"
        echo "  oc exec -it h-kim-0 -n $NAMESPACE -- bash"
    fi

    log_info ""
    log_info "To run training:"
    echo "  # Copy training script to pod"
    echo "  oc cp h-kim-openshift.sh h-kim-0:/workspace/ -n $NAMESPACE"
    echo "  "
    echo "  # Override namespace in training script"
    echo "  oc exec h-kim-0 -n $NAMESPACE -- bash -c \\"
    echo "    'MASTER_ADDR=$SERVICE_DNS /workspace/h-kim-openshift.sh'"
fi

echo
