# ML Job Portal Design (Future Work)

**Status:** Design phase - not yet implemented
**Created:** 2024-02-24
**Purpose:** Enable researchers without OpenShift experience to run experiments on existing infrastructure

## Problem Statement

### Current State
- Deployment wizard creates and configures ML cluster infrastructure
- Researchers need to use CLI to submit jobs and monitor experiments
- Requires OpenShift/Kubernetes knowledge

### Target State
- Admin uses deployment wizard to set up infrastructure (one-time)
- Researchers use web portal to submit jobs and monitor experiments (daily)
- No OpenShift knowledge required for researchers

## Use Case

**Researcher workflow:**
1. Go to web portal: `https://ml-jobs.cluster.com`
2. Upload training script or select from workspace
3. Fill simple form with hyperparameters
4. Click "Submit Job"
5. Monitor progress in dashboard
6. View logs in real-time
7. Download results when complete

**No CLI, no YAML, no kubectl required.**

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────┐
│  ML Job Portal (Web Application)            │
│  - Runs as pod in existing cluster          │
│  - Web UI for job submission/monitoring     │
│  - REST API for programmatic access         │
└─────────────────────────────────────────────┘
                    ↓
            (Uses existing)
                    ↓
┌─────────────────────────────────────────────┐
│  ML Cluster (from deployment wizard)        │
│  - StatefulSet pods for development         │
│  - Kubernetes Jobs for experiments          │
│  - Uses existing templates/job.yaml         │
└─────────────────────────────────────────────┘
```

### Components

**Backend:**
- Flask or FastAPI (Python web framework)
- Kubernetes Python client
- Job submission API
- Log streaming (WebSockets)
- Status monitoring
- Authentication (optional)

**Frontend:**
- Simple HTML/CSS/JavaScript or React
- Job submission forms
- Dashboard with job list
- Real-time log viewer
- Metrics visualization

**Deployment:**
- Single pod in existing cluster
- OpenShift Route for external access
- ServiceAccount with permissions to create Jobs
- Persistent storage for job history (optional)

## UI Design

### Page 1: Job Submission Form

```
╔════════════════════════════════════════════════╗
║  Submit Training Job                           ║
╠════════════════════════════════════════════════╣
║                                                ║
║  Experiment Name: [gpt-finetune-v2        ]   ║
║                                                ║
║  Training Script:                              ║
║  ○ Upload new script                           ║
║  ● Use from workspace: [train.py ▼]           ║
║                                                ║
║  Parameters:                                   ║
║  ┌──────────────────────────────────────────┐ ║
║  │ Learning Rate:  [0.001            ]      │ ║
║  │ Epochs:         [100              ]      │ ║
║  │ Batch Size:     [32               ]      │ ║
║  │ Dataset Path:   [/datasets/wikitext]     │ ║
║  │ Additional Args: [                 ]     │ ║
║  └──────────────────────────────────────────┘ ║
║                                                ║
║  Resources:                                    ║
║  GPUs: [4 ▼]  Nodes: [2 ▼]                   ║
║                                                ║
║  Advanced:                                     ║
║  [ ] Use mixed precision                       ║
║  [ ] Enable gradient checkpointing             ║
║  [ ] Save checkpoints every N epochs           ║
║                                                ║
║  Estimated Cost: $12.50/hour                   ║
║  Max Runtime: [8] hours                        ║
║                                                ║
║          [Cancel]  [Submit Job →]              ║
╚════════════════════════════════════════════════╝
```

### Page 2: Job Dashboard

```
╔════════════════════════════════════════════════╗
║  My Experiments                    [+ New Job] ║
╠════════════════════════════════════════════════╣
║  Filter: [All ▼] [Running] [Completed] [Failed]║
║  Search: [                               ] 🔍  ║
║                                                ║
║  🟢 Running (2)                                ║
║  ┌──────────────────────────────────────────┐ ║
║  │ gpt-finetune-v2          Epoch 47/100    │ ║
║  │ Started: 2h ago          ETA: 1.5h       │ ║
║  │ GPU: 95%  Loss: 0.342                    │ ║
║  │ [View Logs] [Metrics] [Stop]             │ ║
║  └──────────────────────────────────────────┘ ║
║  ┌──────────────────────────────────────────┐ ║
║  │ llm-experiment-3         Epoch 12/50     │ ║
║  │ Started: 30m ago         ETA: 3.2h       │ ║
║  │ GPU: 87%  Loss: 0.456                    │ ║
║  │ [View Logs] [Metrics] [Stop]             │ ║
║  └──────────────────────────────────────────┘ ║
║                                                ║
║  ✅ Completed (5)                              ║
║  ┌──────────────────────────────────────────┐ ║
║  │ gpt-finetune-v1          ✓ Success       │ ║
║  │ Finished: 3h ago         Final Loss: 0.245│║
║  │ Runtime: 5h 23m          Cost: $67.50    │ ║
║  │ [View Results] [Clone] [Download]        │ ║
║  └──────────────────────────────────────────┘ ║
║                                                ║
║  ❌ Failed (1)                                 ║
║  ┌──────────────────────────────────────────┐ ║
║  │ test-run-1               OOM Error       │ ║
║  │ Failed: 1d ago           at Epoch 5/100  │ ║
║  │ [View Logs] [Retry] [Delete]             │ ║
║  └──────────────────────────────────────────┘ ║
║                                                ║
║  [Load More...]                                ║
╚════════════════════════════════════════════════╝
```

### Page 3: Live Logs & Metrics

```
╔════════════════════════════════════════════════╗
║  gpt-finetune-v2                   [← Back]    ║
╠════════════════════════════════════════════════╣
║  Status: 🟢 Running    Epoch 47/100            ║
║  Started: 2h ago       ETA: 1.5h               ║
║                                                ║
║  [Logs] [Metrics] [Config] [Files]            ║
║                                                ║
║  📋 Logs (Live)                   [Download]   ║
║  ┌──────────────────────────────────────────┐ ║
║  │ [2024-02-24 15:23:45] Epoch 47/100       │ ║
║  │ [2024-02-24 15:23:46] Loss: 0.342        │ ║
║  │ [2024-02-24 15:23:47] Accuracy: 0.856    │ ║
║  │ [2024-02-24 15:23:48] GPU Memory: 72GB   │ ║
║  │ [2024-02-24 15:23:49] Samples/sec: 1250  │ ║
║  │ [2024-02-24 15:23:50] Gradient norm: 0.8 │ ║
║  │ ⋮                                         │ ║
║  │ [Auto-scroll ✓] [Pause] [Download]      │ ║
║  └──────────────────────────────────────────┘ ║
║                                                ║
║  📊 Training Metrics                           ║
║  [Interactive loss/accuracy charts]            ║
║  [GPU utilization graph]                       ║
║  [Memory usage graph]                          ║
║                                                ║
║          [Stop Job]  [Save Checkpoint]         ║
╚════════════════════════════════════════════════╝
```

## Technical Implementation

### Backend API Endpoints

```python
# Job Management
POST   /api/jobs              # Submit new job
GET    /api/jobs              # List all jobs
GET    /api/jobs/{id}         # Get job details
DELETE /api/jobs/{id}         # Stop/delete job
POST   /api/jobs/{id}/clone   # Clone job with new params

# Monitoring
GET    /api/jobs/{id}/logs    # Get job logs
WS     /api/jobs/{id}/logs    # Stream logs (WebSocket)
GET    /api/jobs/{id}/metrics # Get metrics
GET    /api/jobs/{id}/status  # Get current status

# Files
POST   /api/files/upload      # Upload training script
GET    /api/files             # List workspace files
GET    /api/files/{path}      # Download file

# Templates
GET    /api/templates         # List job templates
POST   /api/templates         # Save job as template
```

### Backend Code Structure

```python
ml-job-portal/
├── app/
│   ├── __init__.py
│   ├── main.py                 # Flask/FastAPI app
│   ├── api/
│   │   ├── jobs.py            # Job submission/management
│   │   ├── logs.py            # Log streaming
│   │   ├── files.py           # File upload/download
│   │   └── auth.py            # Authentication (optional)
│   ├── k8s/
│   │   ├── client.py          # Kubernetes client wrapper
│   │   ├── job_manager.py     # Job CRUD operations
│   │   └── log_streamer.py    # Log streaming logic
│   ├── models/
│   │   ├── job.py             # Job data model
│   │   └── user.py            # User model (optional)
│   └── templates/
│       └── job_template.yaml  # Uses existing templates/job.yaml
├── frontend/
│   ├── index.html
│   ├── dashboard.html
│   ├── logs.html
│   ├── static/
│   │   ├── css/
│   │   │   └── style.css
│   │   └── js/
│   │       ├── app.js
│   │       ├── job-submit.js
│   │       └── log-viewer.js
│   └── package.json           # If using React/Vue
├── k8s/
│   ├── deployment.yaml        # Deploy portal itself
│   ├── service.yaml
│   ├── route.yaml
│   └── serviceaccount.yaml    # Permissions for portal
├── requirements.txt
├── Dockerfile
└── README.md
```

### Sample Backend Code

```python
# app/api/jobs.py
from flask import Blueprint, request, jsonify
from app.k8s.job_manager import JobManager

jobs_bp = Blueprint('jobs', __name__)
job_manager = JobManager()

@jobs_bp.route('/api/jobs', methods=['POST'])
def submit_job():
    """Submit a new training job"""
    data = request.json

    # Validate input
    required = ['name', 'script', 'parameters']
    if not all(k in data for k in required):
        return jsonify({'error': 'Missing required fields'}), 400

    # Create job from template
    job_spec = job_manager.create_job_spec(
        name=data['name'],
        script=data['script'],
        parameters=data['parameters'],
        resources=data.get('resources', {})
    )

    # Submit to Kubernetes
    job_id = job_manager.submit_job(job_spec)

    return jsonify({
        'job_id': job_id,
        'status': 'submitted',
        'message': f'Job {data["name"]} submitted successfully'
    })

@jobs_bp.route('/api/jobs', methods=['GET'])
def list_jobs():
    """List all jobs for current user"""
    user = request.args.get('user', 'default')
    status_filter = request.args.get('status', None)

    jobs = job_manager.list_jobs(
        user=user,
        status=status_filter
    )

    return jsonify({'jobs': jobs})

@jobs_bp.route('/api/jobs/<job_id>/logs', methods=['GET'])
def get_logs(job_id):
    """Get logs for a specific job"""
    follow = request.args.get('follow', 'false') == 'true'

    if follow:
        # Return streaming response
        return Response(
            job_manager.stream_logs(job_id),
            mimetype='text/event-stream'
        )
    else:
        # Return full logs
        logs = job_manager.get_logs(job_id)
        return jsonify({'logs': logs})
```

```python
# app/k8s/job_manager.py
from kubernetes import client, config
from jinja2 import Template
import yaml

class JobManager:
    def __init__(self):
        config.load_incluster_config()  # Running in cluster
        self.batch_api = client.BatchV1Api()
        self.core_api = client.CoreV1Api()

    def create_job_spec(self, name, script, parameters, resources=None):
        """Create Kubernetes Job spec from template"""
        # Load existing template from ml-dev-env
        with open('/templates/job.yaml') as f:
            template = Template(f.read())

        # Render with user parameters
        job_yaml = template.render(
            app_name=name,
            job_id=self._generate_job_id(),
            entry_point=script,
            arguments=self._build_arguments(parameters),
            **resources or {}
        )

        return yaml.safe_load(job_yaml)

    def submit_job(self, job_spec):
        """Submit job to Kubernetes"""
        namespace = job_spec['metadata']['namespace']
        response = self.batch_api.create_namespaced_job(
            namespace=namespace,
            body=job_spec
        )
        return response.metadata.name

    def list_jobs(self, user=None, status=None):
        """List jobs with optional filters"""
        label_selector = f'user={user}' if user else None
        jobs = self.batch_api.list_namespaced_job(
            namespace='default',
            label_selector=label_selector
        )

        # Convert to simple dict format
        result = []
        for job in jobs.items:
            job_info = {
                'id': job.metadata.name,
                'name': job.metadata.labels.get('app'),
                'status': self._get_job_status(job),
                'start_time': job.status.start_time,
                'completion_time': job.status.completion_time,
            }
            result.append(job_info)

        return result

    def stream_logs(self, job_id):
        """Stream logs from job pod"""
        # Find pod for this job
        pods = self.core_api.list_namespaced_pod(
            namespace='default',
            label_selector=f'job-name={job_id}'
        )

        if not pods.items:
            yield 'No pods found for job\n'
            return

        pod_name = pods.items[0].metadata.name

        # Stream logs
        for line in self.core_api.read_namespaced_pod_log(
            name=pod_name,
            namespace='default',
            follow=True,
            _preload_content=False
        ).stream():
            yield line
```

### Frontend Code Structure

```javascript
// static/js/job-submit.js
class JobSubmitter {
    constructor() {
        this.form = document.getElementById('job-form');
        this.setupEventListeners();
    }

    setupEventListeners() {
        this.form.addEventListener('submit', (e) => {
            e.preventDefault();
            this.submitJob();
        });
    }

    async submitJob() {
        const formData = {
            name: document.getElementById('job-name').value,
            script: document.getElementById('script-select').value,
            parameters: {
                learning_rate: parseFloat(document.getElementById('lr').value),
                epochs: parseInt(document.getElementById('epochs').value),
                batch_size: parseInt(document.getElementById('batch-size').value),
                dataset: document.getElementById('dataset').value
            }
        };

        try {
            const response = await fetch('/api/jobs', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(formData)
            });

            const result = await response.json();

            if (response.ok) {
                // Redirect to dashboard
                window.location.href = `/dashboard?highlight=${result.job_id}`;
            } else {
                alert(`Error: ${result.error}`);
            }
        } catch (error) {
            alert(`Failed to submit job: ${error}`);
        }
    }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    new JobSubmitter();
});
```

```javascript
// static/js/log-viewer.js
class LogViewer {
    constructor(jobId) {
        this.jobId = jobId;
        this.logContainer = document.getElementById('log-container');
        this.autoScroll = true;
        this.connectWebSocket();
    }

    connectWebSocket() {
        const wsUrl = `ws://${window.location.host}/api/jobs/${this.jobId}/logs`;
        this.ws = new WebSocket(wsUrl);

        this.ws.onmessage = (event) => {
            this.appendLog(event.data);
        };

        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }

    appendLog(line) {
        const logLine = document.createElement('div');
        logLine.className = 'log-line';
        logLine.textContent = line;
        this.logContainer.appendChild(logLine);

        if (this.autoScroll) {
            this.logContainer.scrollTop = this.logContainer.scrollHeight;
        }
    }
}

// Initialize for job logs page
const jobId = new URLSearchParams(window.location.search).get('job');
if (jobId) {
    new LogViewer(jobId);
}
```

## Deployment

### Portal Deployment YAML

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-job-portal
  namespace: ml-cluster
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ml-job-portal
  template:
    metadata:
      labels:
        app: ml-job-portal
    spec:
      serviceAccountName: ml-job-portal-sa
      containers:
      - name: portal
        image: ml-job-portal:latest
        ports:
        - containerPort: 5000
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: job-templates
          mountPath: /templates
          readOnly: true
      volumes:
      - name: job-templates
        configMap:
          name: job-templates
---
apiVersion: v1
kind: Service
metadata:
  name: ml-job-portal
  namespace: ml-cluster
spec:
  selector:
    app: ml-job-portal
  ports:
  - port: 80
    targetPort: 5000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ml-jobs
  namespace: ml-cluster
spec:
  to:
    kind: Service
    name: ml-job-portal
  tls:
    termination: edge
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ml-job-portal-sa
  namespace: ml-cluster
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ml-job-portal-role
  namespace: ml-cluster
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "delete"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ml-job-portal-binding
  namespace: ml-cluster
subjects:
- kind: ServiceAccount
  name: ml-job-portal-sa
roleRef:
  kind: Role
  name: ml-job-portal-role
  apiGroup: rbac.authorization.k8s.io
```

## Implementation Timeline

### Week 1: Backend MVP
- **Day 1-2:** Basic Flask app with job submission endpoint
- **Day 3-4:** Kubernetes integration (create/list/delete jobs)
- **Day 5:** Log streaming implementation

### Week 2: Frontend MVP
- **Day 1-2:** Job submission form (HTML/CSS/JS)
- **Day 3-4:** Dashboard with job list
- **Day 5:** Log viewer with WebSocket streaming

### Week 3: Polish & Deploy
- **Day 1-2:** Error handling, validation
- **Day 3:** Docker image and deployment manifests
- **Day 4:** Testing and documentation
- **Day 5:** Deploy to cluster and user testing

## Future Enhancements

### Phase 2 (After MVP)
- Job templates/presets for common tasks
- Parameter sweeps (hyperparameter search)
- Cost tracking and budgets
- Email notifications on completion
- Experiment comparison tools
- Model registry integration

### Phase 3 (Advanced)
- Multi-user authentication (LDAP/OAuth)
- Team collaboration features
- Jupyter notebook integration
- TensorBoard integration
- Advanced metrics and visualization
- Resource quotas and limits
- Scheduling and priorities

## Integration with Existing Infrastructure

**Leverages existing work:**
- ✅ Uses `templates/job.yaml` we already built
- ✅ Uses same Kubernetes Job system
- ✅ Runs on infrastructure created by deployment wizard
- ✅ No changes to core deployment logic
- ✅ Portal is optional - CLI still works

**Portal workflow:**
1. Admin runs deployment wizard → Creates cluster
2. Admin deploys portal → Adds web UI
3. Researchers use portal → Submit jobs to cluster
4. (Advanced users can still use CLI directly)

## Alternative: Jupyter-Based Approach

For teams already using Jupyter:

```python
# jupyter-job-submitter.ipynb
from ml_job_portal import JobClient

client = JobClient(cluster_url='https://ml-jobs.cluster.com')

# Submit job interactively
job = client.submit_job(
    name='gpt-finetune-v3',
    script='train.py',
    learning_rate=0.001,
    epochs=100,
    batch_size=32
)

# Monitor in notebook
for log in job.stream_logs():
    print(log)

# Get results
results = job.get_results()
print(f"Final loss: {results.final_loss}")
```

This could be built alongside or instead of web UI.

## Cost/Benefit Analysis

**Development Cost:**
- 3 weeks for MVP (1 developer)
- 1 week for testing and refinement
- Total: 1 month

**Benefits:**
- Researchers can submit jobs without OpenShift training
- Lower barrier to entry for cluster usage
- Better resource utilization (more users)
- Trackable experiment history
- Reduced support burden on admins

**Maintenance:**
- Low - uses existing infrastructure
- Mostly frontend/UI updates
- Kubernetes API is stable

## Notes

- Keep portal simple and focused on job submission/monitoring
- Don't duplicate deployment wizard logic
- Let wizard handle infrastructure, portal handles experiments
- Authentication can be added later if needed
- Start with read-only for non-owners (users can only manage their jobs)

## Related Documentation

- [DEPLOYMENT-WIZARD-GUIDE.md](DEPLOYMENT-WIZARD-GUIDE.md) - Infrastructure deployment
- [APPLICATION-DEPLOYMENT-GUIDE.md](APPLICATION-DEPLOYMENT-GUIDE.md) - Application-aware deployment
- Kubernetes Jobs documentation
- Flask/FastAPI documentation

---

**When ready to implement:** Start with Week 1 backend MVP to validate approach
