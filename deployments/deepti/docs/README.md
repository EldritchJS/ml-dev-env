# Deepti Documentation

Additional documentation and archived guides for the deepti deployment.

## Active Documentation

For current deployment instructions, see:
- **[../README.md](../README.md)** - Main project overview
- **[../QUICKSTART.md](../QUICKSTART.md)** - Quick start guide
- **[../MIGRATION.md](../MIGRATION.md)** - Migration guide

## Archived Guides (Reference)

### DEEPTI-QUICKSTART.md (881 lines)

**Comprehensive guide from February 2025** covering:

**Key Content:**
- VSCode remote debugging setup (detailed walkthrough)
- debugpy configuration for remote development
- Breakpoint recommendations and debugging strategies
- Debug console usage examples
- NERC-specific cluster configuration
- Step-by-step debugging workflow

**Why kept:**
This guide contains extensive VSCode remote debugging documentation that may be useful for developers who want to debug Qwen2.5-Omni model inference interactively.

**Use when:**
- Setting up remote debugging with VSCode
- Debugging model loading or inference issues
- Learning debugpy configuration
- Need step-by-step debugging tutorials

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

**If you need debugging capabilities**, the VSCode remote debugging content from `DEEPTI-QUICKSTART.md` is particularly valuable and not covered in the main quick start guide.

## Current vs Archived

| Feature | Current Docs | Archived Docs |
|---------|-------------|---------------|
| **Multi-cluster support** | ✅ Barcelona + NERC | NERC only |
| **PyTorch versions** | ✅ Multiple variants | Single version |
| **Deployment methods** | ✅ Multiple options | ConfigMap only |
| **VSCode debugging** | ❌ Not covered | ✅ Extensive guide |
| **Flash Attention** | ✅ Documented | ✅ Documented |
| **Remote debugging** | ❌ Not covered | ✅ debugpy setup |

## Integration Suggestions

If you find the VSCode debugging content useful, consider:
1. Adding a "Remote Debugging" section to the main QUICKSTART.md
2. Creating a dedicated debugging guide in this docs/ folder
3. Updating the debug pod configuration references to new paths

## Related Files

- **[../workspace/deepti.py](../workspace/deepti.py)** - Main test script
- **[../generated/pod-debug-deepti-nerc.yaml](../generated/pod-debug-deepti-nerc.yaml)** - Debug pod configuration
- **[.vscode/launch.json](../../../.vscode/launch.json)** - VSCode debug configuration (if exists)
