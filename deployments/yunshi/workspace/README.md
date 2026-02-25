# Yunshi Workspace

This directory is for yunshi-specific training code, data, and outputs.

## Purpose

The workspace can be used for:
- Training scripts and configurations
- Data preprocessing utilities  
- Analysis notebooks
- Training artifacts

## Storage

The actual training data is stored on the persistent volume claim (PVC) named `tsfm`, which is mounted at `/mnt/tsfm` inside the pods.

## Structure

Inside the pods (`/mnt/tsfm/`):
```
/mnt/tsfm/
├── hybrid_tsfm/           # Training code
├── data/                  # Datasets
│   ├── GiftEval/
│   ├── GiftPretrain/
│   ├── kernel_synth_10M/
│   ├── tsmixup/
│   └── tsmixup_v01/
├── checkpoints/           # Model checkpoints
└── logs/                  # Training logs
```

## Usage

To add files to this workspace that should be available in the pods, you can:

1. **Copy to PVC** (from running pod):
   ```bash
   oc cp local-file.py tsfm-node-0:/mnt/tsfm/
   ```

2. **Create ConfigMap** (for small files):
   ```bash
   oc create configmap yunshi-config --from-file=config.yaml
   # Then mount in pod spec
   ```

3. **Use init containers** to download/prepare data before training starts
