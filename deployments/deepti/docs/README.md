# Deepti Documentation

Additional documentation and archived guides for the deepti deployment.

## Active Documentation

For current deployment instructions, see:
- **[../README.md](../README.md)** - Main project overview
- **[../QUICKSTART.md](../QUICKSTART.md)** - Quick start guide (deployment-specific)
- **[../MIGRATION.md](../MIGRATION.md)** - Migration guide

## General Documentation

For development workflows and debugging:
- **[../../../docs/QUICKSTART.md](../../../docs/QUICKSTART.md)** - Main quickstart with VSCode setup
- **[../../../docs/QUICK-DEV-GUIDE.md](../../../docs/QUICK-DEV-GUIDE.md)** - Makefile development workflow
- **[../../../docs/REMOTE-DEBUG-WALKTHROUGH.md](../../../docs/REMOTE-DEBUG-WALKTHROUGH.md)** - VSCode debugging tutorial
- **[../../../docs/VSCODE-DEBUG-GUIDE.md](../../../docs/VSCODE-DEBUG-GUIDE.md)** - Complete debugging reference

## Archived Guides (Reference)

> **Note:** The valuable VSCode debugging content from these archived guides has been integrated into the main documentation (see links above).

### DEEPTI-QUICKSTART.md (881 lines) - **Content Integrated**

**Original guide from February 2025** covering:

**Key Content (now in main docs):**
- ✅ VSCode remote debugging setup → Integrated into [QUICKSTART.md](../../../docs/QUICKSTART.md)
- ✅ Makefile workflow (make dev-session, make sync-code) → [QUICK-DEV-GUIDE.md](../../../docs/QUICK-DEV-GUIDE.md)
- ✅ debugpy configuration → [REMOTE-DEBUG-WALKTHROUGH.md](../../../docs/REMOTE-DEBUG-WALKTHROUGH.md)
- ✅ Debugging controls and console examples → [QUICKSTART.md](../../../docs/QUICKSTART.md)
- ✅ Data management with PVCs → [QUICKSTART.md](../../../docs/QUICKSTART.md)

**Why kept:**
Historical reference for the original comprehensive guide.

**Status:** ✅ Content integrated into main documentation

### DEEPTI-DEPLOYMENT.md (134 lines)

**Basic deployment guide from February 2025** covering:

**Key Content:**
- Quick NERC cluster deployment
- ConfigMap-based script deployment
- Basic monitoring and troubleshooting
- Namespace-specific configuration (coops-767192)

**Why kept:**
Contains some NERC-specific deployment patterns and namespace configurations that may differ from current setup.

**Use when:**
- Deploying to different NERC namespaces
- Using ConfigMap for script deployment (alternative approach)
- Reference for older deployment patterns

## Notes

These archived guides were moved from the repository root directory to maintain historical documentation while consolidating active docs in the standard structure.

**As of February 2025**, the VSCode debugging and Makefile workflow content has been successfully integrated into the main documentation structure.

## Current vs Archived

| Feature | Current Docs | Archived Docs | Status |
|---------|-------------|---------------|--------|
| **Multi-cluster support** | ✅ Barcelona + NERC | NERC only | Active docs |
| **PyTorch versions** | ✅ Multiple variants | Single version | Active docs |
| **Deployment methods** | ✅ Multiple options | ConfigMap only | Active docs |
| **VSCode debugging** | ✅ Integrated | ✅ Original source | **Merged** |
| **Makefile workflow** | ✅ Integrated | ✅ Original source | **Merged** |
| **Flash Attention** | ✅ Documented | ✅ Documented | Active docs |
| **Remote debugging** | ✅ Integrated | ✅ Original source | **Merged** |
| **Data management** | ✅ Integrated | ✅ Original source | **Merged** |

## Integration Complete ✅

The valuable content from the archived guides has been integrated into:

1. **[docs/QUICKSTART.md](../../../docs/QUICKSTART.md)**
   - VSCode debugging setup and controls
   - Debug console examples
   - Data download from URLs (wget, curl, HuggingFace, Google Drive)
   - Makefile workflow overview

2. **[docs/QUICK-DEV-GUIDE.md](../../../docs/QUICK-DEV-GUIDE.md)**
   - Complete Makefile workflow guide
   - Auto-sync setup
   - Development session automation

3. **[docs/REMOTE-DEBUG-WALKTHROUGH.md](../../../docs/REMOTE-DEBUG-WALKTHROUGH.md)**
   - Step-by-step debugging tutorial
   - debugpy configuration

4. **[deployments/deepti/QUICKSTART.md](../QUICKSTART.md)**
   - Deployment-specific instructions
   - References to main docs for general workflows

## Related Files

- **[../workspace/deepti.py](../workspace/deepti.py)** - Main test script
- **[../generated/pod-debug-deepti-nerc.yaml](../generated/pod-debug-deepti-nerc.yaml)** - Debug pod configuration
- **[../../../.vscode/launch.json](../../../.vscode/launch.json)** - VSCode debug configuration
