#!/bin/bash
#
# Submit Kubernetes Job for application execution
#
# Usage:
#   ./scripts/submit-job.sh
#

set -e

APP_NAME="{app_name}"
NAMESPACE="{namespace}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Generate unique job ID
JOB_ID=$(date +%Y%m%d-%H%M%S)
JOB_NAME="${APP_NAME}-job-${JOB_ID}"

echo "🚀 Submitting Kubernetes Job"
echo "   App: $APP_NAME"
echo "   Job ID: $JOB_ID"
echo "   Namespace: $NAMESPACE"
echo ""

# Generate job manifest
echo "Generating job manifest..."
python3 scripts/deploy_cluster.py {cluster} --mode {network_mode} --project {project} --job --output-dir $PROJECT_DIR/generated

# Check if job manifest was generated
JOB_MANIFEST="$PROJECT_DIR/generated/{cluster}-job-${JOB_ID}.yaml"

if [ ! -f "$JOB_MANIFEST" ]; then
    echo "❌ Failed to generate job manifest"
    exit 1
fi

# Apply job
echo "Applying job to cluster..."
oc apply -f $JOB_MANIFEST -n $NAMESPACE

echo ""
echo "✅ Job submitted successfully!"
echo "   Job name: $JOB_NAME"
echo ""
echo "📊 Monitor job:"
echo "   ./scripts/watch-job.sh $JOB_ID"
echo ""
echo "   Or manually:"
echo "   oc get job $JOB_NAME -n $NAMESPACE"
echo "   oc logs job/$JOB_NAME -n $NAMESPACE -f"
