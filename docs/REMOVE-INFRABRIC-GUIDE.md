# Remove Infrabric-deployer Management Guide

**Date:** 2026-03-02
**Purpose:** Remove Infrabric-deployer GitOps management while keeping all deployed infrastructure
**Repository:** https://github.com/bbenshab/Infrabric-deployer.git

---

## What is Infrabric-deployer?

Infrabric-deployer is a GitOps repository managed by **OpenShift GitOps (ArgoCD)** that deploys and controls all cluster infrastructure components.

### Currently Managed Applications

| Application | Path | Status | Purpose |
|-------------|------|--------|---------|
| root-app | rig/baremetal | OutOfSync | Root application (App of Apps) |
| operators-infra | manifests/20-operators | Synced | Base operators |
| sriov-operator | manifests/25a-sriov-operator | Synced | SR-IOV virtualization |
| nvidia-network-operator | manifests/28-nvidia-network-operator | Synced | Mellanox/InfiniBand networking |
| nvidia-mofed-ready | manifests/29-nvidia-mofed-ready | Synced | MOFED driver readiness |
| gpu-operator-nfd | manifests/30-gpu-operator-nfd | Synced | GPU operator + NFD |
| ib-interface-normalization | manifests/25b-ib-interface-normalization | OutOfSync | InfiniBand setup |
| sriov-discovery | manifests/26a-sriov-discovery | OutOfSync | SR-IOV device discovery |
| node-preparation | manifests/00-node-preparation | OutOfSync | Node setup |
| nfd-config | manifests/15-nfd | OutOfSync | Node Feature Discovery config |
| gitops | manifests/27-gitops | OutOfSync | GitOps itself |
| operator-readiness | manifests/25-operator-readiness | Synced | Operator health checks |

---

## What This Process Does

### Before Removal
- ✅ Infrabric-deployer manages everything via GitOps
- ✅ Changes in GitHub automatically sync to cluster
- ❌ Manual changes get reverted by auto-sync
- ✅ Easy rollback via Git history

### After Removal
- ❌ No GitOps management
- ✅ All infrastructure stays exactly as is
- ✅ Manual changes are permanent (no auto-revert)
- ✅ Full manual control of all components
- ❌ No automatic rollback capability
- ❌ Manual maintenance required for upgrades

---

## Step-by-Step Removal Procedure

### Step 1: Verify Current State

```bash
# List all applications managed by Infrabric
echo "=== Current ArgoCD Applications ==="
oc get applications -n openshift-gitops

# List critical infrastructure that will become unmanaged
echo -e "\n=== SR-IOV Operator ==="
oc get pods -n openshift-sriov-network-operator | head -5

echo -e "\n=== NVIDIA Network Operator ==="
oc get pods -n nvidia-network-operator | head -5

echo -e "\n=== SR-IOV Policies ==="
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator

echo -e "\n=== Network Attachments ==="
oc get network-attachment-definitions -n nccl-test
```

### Step 2: Disable Auto-Sync on All Applications

```bash
# Disable auto-sync to prevent any automatic changes during removal
echo "=== Disabling auto-sync on all applications ==="

for app in $(oc get applications -n openshift-gitops -o name); do
  echo "Patching $app..."
  oc patch $app -n openshift-gitops --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
done

echo "Auto-sync disabled on all applications"
```

### Step 3: Verify Auto-Sync is Disabled

```bash
# Verify no applications have automated sync enabled
echo "=== Verifying auto-sync is disabled ==="
oc get applications -n openshift-gitops -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.syncPolicy.automated}{"\n"}{end}'

# Should show empty/null for all applications
```

### Step 4: Delete ArgoCD Applications (Orphan Resources)

**CRITICAL**: Use `--cascade=orphan` to keep resources!

```bash
# Delete all applications WITHOUT deleting the resources they manage
echo "=== Deleting ArgoCD applications (orphaning resources) ==="

oc delete applications --all -n openshift-gitops --cascade=orphan

# Wait for deletion to complete
echo "Waiting for applications to be removed..."
sleep 10
```

### Step 5: Verify Applications Are Deleted

```bash
# Should return "No resources found"
echo "=== Verifying applications are deleted ==="
oc get applications -n openshift-gitops
```

### Step 6: Verify Infrastructure Still Exists

```bash
echo "=== Verifying infrastructure is still running ==="

# Check SR-IOV operator
echo -e "\n1. SR-IOV Operator Pods:"
oc get pods -n openshift-sriov-network-operator | grep -E "NAME|device-plugin|config-daemon" | head -6

# Check NVIDIA Network Operator
echo -e "\n2. NVIDIA Network Operator Pods:"
oc get pods -n nvidia-network-operator | grep -E "NAME|controller-manager" | head -3

# Check SR-IOV policies still exist
echo -e "\n3. SR-IOV Network Policies:"
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator

# Check network attachments still exist
echo -e "\n4. Network Attachments (nccl-test namespace):"
oc get network-attachment-definitions -n nccl-test

# Check GPU operator
echo -e "\n5. GPU Operator:"
oc get pods -n nvidia-gpu-operator 2>/dev/null | head -3 || echo "GPU operator namespace may vary"

# Check Node Feature Discovery
echo -e "\n6. Node Feature Discovery:"
oc get pods -n openshift-nfd 2>/dev/null | head -3 || echo "NFD may be in different namespace"
```

### Step 7: (Optional) Remove OpenShift GitOps Operator

If you want to completely remove the GitOps operator itself:

```bash
echo "=== Removing OpenShift GitOps Operator ==="

# Find the subscription
GITOPS_SUB=$(oc get subscription -n openshift-operators -o name | grep gitops)
echo "Found subscription: $GITOPS_SUB"

# Delete subscription
oc delete $GITOPS_SUB -n openshift-operators

# Find and delete CSV (ClusterServiceVersion)
GITOPS_CSV=$(oc get csv -n openshift-operators -o name | grep gitops)
echo "Found CSV: $GITOPS_CSV"
oc delete $GITOPS_CSV -n openshift-operators

# Delete the GitOps namespace
echo "Deleting openshift-gitops namespace..."
oc delete namespace openshift-gitops

echo "GitOps operator removal complete"
```

### Step 8: Final Verification

```bash
echo "=== Final Verification ==="

# Confirm GitOps is gone (if you removed it)
echo -e "\n1. GitOps namespace (should be Terminating or NotFound):"
oc get namespace openshift-gitops 2>&1

# Confirm critical infrastructure is still healthy
echo -e "\n2. SR-IOV operator still running:"
oc get deployment -n openshift-sriov-network-operator 2>/dev/null | grep -E "NAME|operator"

echo -e "\n3. NVIDIA Network operator still running:"
oc get deployment -n nvidia-network-operator 2>/dev/null | grep -E "NAME|controller"

echo -e "\n4. SR-IOV device plugins still running on nodes:"
oc get daemonset -n openshift-sriov-network-operator | grep device-plugin

echo -e "\n5. Check your workload can still request SR-IOV resources:"
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator

echo -e "\n=== Removal Complete ==="
echo "All infrastructure is now UNMANAGED."
echo "You must manually maintain these components going forward."
```

---

## Automated Script

Save this as `remove-infrabric.sh`:

```bash
#!/bin/bash
set -e

echo "=========================================="
echo "Remove Infrabric-deployer Management"
echo "Keep All Deployed Infrastructure"
echo "=========================================="
echo ""

read -p "This will remove GitOps management. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "[1/8] Checking current state..."
oc get applications -n openshift-gitops

echo ""
echo "[2/8] Disabling auto-sync on all applications..."
for app in $(oc get applications -n openshift-gitops -o name); do
  oc patch $app -n openshift-gitops --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}' 2>/dev/null || true
done

echo ""
echo "[3/8] Verifying auto-sync disabled..."
oc get applications -n openshift-gitops -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.syncPolicy.automated}{"\n"}{end}'

echo ""
echo "[4/8] Deleting ArgoCD applications (orphaning resources)..."
oc delete applications --all -n openshift-gitops --cascade=orphan

echo ""
echo "[5/8] Waiting for cleanup..."
sleep 10

echo ""
echo "[6/8] Verifying applications deleted..."
oc get applications -n openshift-gitops || echo "All applications removed ✓"

echo ""
echo "[7/8] Verifying infrastructure still exists..."
echo "SR-IOV operator:"
oc get pods -n openshift-sriov-network-operator | head -3
echo ""
echo "NVIDIA Network operator:"
oc get pods -n nvidia-network-operator | head -3
echo ""
echo "SR-IOV policies:"
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator

echo ""
read -p "Remove OpenShift GitOps operator entirely? (yes/no): " remove_gitops
if [ "$remove_gitops" = "yes" ]; then
  echo ""
  echo "[8/8] Removing GitOps operator..."
  oc delete subscription -n openshift-operators $(oc get subscription -n openshift-operators -o name | grep gitops) 2>/dev/null || true
  oc delete csv -n openshift-operators $(oc get csv -n openshift-operators -o name | grep gitops) 2>/dev/null || true
  oc delete namespace openshift-gitops
  echo "GitOps operator removed ✓"
else
  echo ""
  echo "[8/8] Skipping GitOps operator removal"
fi

echo ""
echo "=========================================="
echo "✓ Removal Complete"
echo "=========================================="
echo ""
echo "Infrastructure Status:"
echo "  • SR-IOV: UNMANAGED (still running)"
echo "  • NVIDIA Network Operator: UNMANAGED (still running)"
echo "  • GPU Operator: UNMANAGED (still running)"
echo "  • All policies/configs: UNMANAGED (still active)"
echo ""
echo "Next steps:"
echo "  • Manual changes will NOT be reverted"
echo "  • Update/maintain operators manually"
echo "  • Consider documenting your configurations"
echo ""
```

### Using the Script

```bash
# Save the script
cat > remove-infrabric.sh << 'EOF'
[paste script contents above]
EOF

# Make executable
chmod +x remove-infrabric.sh

# Run it
./remove-infrabric.sh
```

---

## Rollback Plan

If something goes wrong or you change your mind, you can re-enable Infrabric management:

```bash
# Re-create the root application
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/bbenshab/Infrabric-deployer.git
    targetRevision: main
    path: rig/baremetal
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# This will recreate all child applications
# Wait a few minutes for sync to complete
oc get applications -n openshift-gitops
```

---

## Alternative Approaches

### Option 1: Disable Only Specific Applications

Keep GitOps but remove management of specific components (e.g., SR-IOV only):

```bash
# Disable auto-sync for SR-IOV only
oc patch application sriov-operator -n openshift-gitops --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'

# Delete the application without cascade
oc delete application sriov-operator -n openshift-gitops --cascade=orphan
oc delete application sriov-discovery -n openshift-gitops --cascade=orphan

# SR-IOV is now unmanaged, but everything else stays under GitOps
```

### Option 2: Fork Infrabric-deployer

Create your own fork to customize configurations:

```bash
# 1. Fork https://github.com/bbenshab/Infrabric-deployer.git to your GitHub

# 2. Update the root application to point to your fork
oc patch application root-app -n openshift-gitops --type=merge -p '{"spec":{"source":{"repoURL":"https://github.com/YOUR-ORG/Infrabric-deployer.git"}}}'

# 3. Make changes in your fork
# 4. ArgoCD will auto-sync from your repository
```

---

## What Gets Removed

### Deleted Components
- ❌ ArgoCD Application CRDs (management layer)
- ❌ GitOps auto-sync/auto-heal
- ❌ Connection to Infrabric-deployer GitHub repo
- ❌ (Optional) OpenShift GitOps operator

### Preserved Components
- ✅ SR-IOV Network Operator (all pods, configs)
- ✅ NVIDIA Network Operator (all pods, configs)
- ✅ GPU Operator (all pods, configs)
- ✅ SR-IOV Network Node Policies (VF configurations)
- ✅ Network Attachment Definitions (SR-IOV networks)
- ✅ MOFED drivers (if deployed)
- ✅ All namespace, operators, and configurations

---

## Post-Removal Maintenance

### Manual Tasks You'll Need to Handle

1. **Operator Updates**
   ```bash
   # Check for operator updates
   oc get csv -A | grep -E "sriov|nvidia|gpu"

   # Manual upgrade process required
   ```

2. **Configuration Changes**
   ```bash
   # Edit SR-IOV policies manually
   oc edit sriovnetworknodepolicy h100-nodes-eno5np0 -n openshift-sriov-network-operator
   ```

3. **Adding New Nodes**
   - Manually label nodes
   - Manually create/update SR-IOV policies
   - Manually configure network attachments

4. **Troubleshooting**
   - No GitOps history to rollback
   - Document all manual changes
   - Keep backups of critical configurations

### Recommended Documentation

Create these files to track your unmanaged infrastructure:

```bash
# Save current SR-IOV config
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator -o yaml > sriov-policies-backup.yaml

# Save network attachments
oc get network-attachment-definitions -A -o yaml > network-attachments-backup.yaml

# Save NVIDIA Network Operator config
oc get nicclusterpolicy -o yaml > nicclusterpolicy-backup.yaml

# Save operator versions
oc get csv -A -o yaml > operator-versions-backup.yaml
```

---

## Troubleshooting

### Issue: Applications Won't Delete

```bash
# Force delete with finalizer removal
oc patch application <app-name> -n openshift-gitops -p '{"metadata":{"finalizers":[]}}' --type=merge
oc delete application <app-name> -n openshift-gitops --force --grace-period=0
```

### Issue: Resources Get Deleted Anyway

```bash
# If you forgot --cascade=orphan and resources were deleted:
# 1. Restore from the Infrabric-deployer manifests
git clone https://github.com/bbenshab/Infrabric-deployer.git
cd Infrabric-deployer

# 2. Apply manifests manually
oc apply -f manifests/25a-sriov-operator/
oc apply -f manifests/28-nvidia-network-operator/
# etc.
```

### Issue: Want to Re-enable GitOps

See "Rollback Plan" section above.

---

## Related Documentation

- **u17/u18 RDMA Investigation**: `u17-u18-rdma-failure-analysis.md`
- **Host Network Migration**: `HOSTNETWORK-MIGRATION-SUMMARY.md`
- **OFED Configuration**: `nicclusterpolicy-ofed-patch.yaml`
- **SR-IOV Policies**: `oc get sriovnetworknodepolicy -n openshift-sriov-network-operator -o yaml`

---

## Questions Before Proceeding

1. **Why remove Infrabric-deployer?**
   - Simplify management?
   - Fix specific issues (like u17/u18 mlx5 numbering)?
   - Gain manual control?

2. **Do you need GitOps for anything else?**
   - If yes: Consider Option 1 (disable specific apps only)
   - If no: Proceed with full removal

3. **Have you documented current configurations?**
   - Run backup commands above before removal
   - Save this guide for reference

4. **Do you have a rollback window?**
   - Test removal in non-production first
   - Keep ability to restore GitOps (see Rollback Plan)

---

## Summary

**Command to remove Infrabric management:**
```bash
oc delete applications --all -n openshift-gitops --cascade=orphan
```

**Key Points:**
- `--cascade=orphan` is CRITICAL - keeps infrastructure running
- All operators, policies, and configs remain active
- Manual maintenance required going forward
- Can re-enable GitOps via rollback plan

**Expected Downtime:** None (infrastructure keeps running)

**Reversibility:** High (can re-enable GitOps, see Rollback Plan)

---

## Contact

If issues arise, check:
- OpenShift GitOps documentation: https://docs.openshift.com/gitops/
- ArgoCD cascade delete: https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/
- Infrabric-deployer repo: https://github.com/bbenshab/Infrabric-deployer
