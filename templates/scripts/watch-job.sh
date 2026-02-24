#!/bin/bash
#
# Watch Kubernetes Job execution
#
# Usage:
#   ./scripts/watch-job.sh <job-id>
#

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <job-id>"
    echo ""
    echo "Example: $0 20260224-153045"
    exit 1
fi

APP_NAME="{app_name}"
NAMESPACE="{namespace}"
JOB_ID="$1"
JOB_NAME="${APP_NAME}-job-${JOB_ID}"

echo "📊 Watching job: $JOB_NAME"
echo "   Namespace: $NAMESPACE"
echo ""

# Check if job exists
if ! oc get job $JOB_NAME -n $NAMESPACE &>/dev/null; then
    echo "❌ Job not found: $JOB_NAME"
    echo ""
    echo "Available jobs:"
    oc get jobs -n $NAMESPACE -l app=$APP_NAME
    exit 1
fi

# Watch job status
echo "Job status:"
oc get job $JOB_NAME -n $NAMESPACE

echo ""
echo "Streaming logs (Ctrl+C to stop):"
echo "---"

# Follow logs from job
oc logs job/$JOB_NAME -n $NAMESPACE -f

echo ""
echo "Final job status:"
oc get job $JOB_NAME -n $NAMESPACE
