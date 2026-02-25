# Setting Memlock at Pod Level - Options Analysis

## Question
Can we set unlimited memlock in the pod manifest instead of in scripts?

## Answer: Partially - Requires Cluster Admin

**TL;DR**: You can't set unlimited memlock directly in a pod manifest without cluster-admin privileges to modify SecurityContextConstraints (SCC). The current script-based approach (`prlimit`) is the best option for non-admin users.

---

## Why It's Not Straightforward

Kubernetes and OpenShift don't provide a standard pod-level field for setting ulimits like memlock because:

1. **Security concern**: Unlimited memlock allows processes to pin all RAM, potentially causing OOM
2. **Cluster-level control**: Admins want to control this via SCCs/PodSecurityPolicies
3. **No standard**: Kubernetes spec doesn't include ulimit configuration

---

## Option 1: CRI-O Annotation (❌ Doesn't Work on OpenShift)

**Attempt:**
```yaml
metadata:
  annotations:
    io.kubernetes.cri-o.Ulimits.memlock: "-1:-1"  # unlimited
```

**Result:** ✗ Failed
- Tested on OpenShift 4.x
- Annotation is accepted but ignored
- Memlock still limited to 8192 (8 MB)
- Likely blocked by SecurityContextConstraints

**Reason:** OpenShift SCCs override container runtime ulimit settings.

---

## Option 2: SecurityContextConstraints (✅ Works - Requires Admin)

**Best permanent solution** - Requires cluster-admin privileges.

### Step 1: Modify SCC

```bash
# As cluster admin
oc edit scc nccl-scc
```

Add to the SCC:
```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: nccl-scc
allowPrivilegedContainer: false
allowedCapabilities:
  - IPC_LOCK
  - SYS_RESOURCE  # Add this - required for setrlimit
# ... other settings ...

# Add ulimit override (if supported by OpenShift version)
# Note: This field may not be available in all versions
defaultAddCapabilities:
  - SYS_RESOURCE
```

### Step 2: Grant to Service Account

```bash
oc adm policy add-scc-to-user nccl-scc -z h-kim-sa -n nccl-test
```

### Step 3: Pod Uses SYS_RESOURCE

```yaml
securityContext:
  capabilities:
    add:
      - IPC_LOCK
      - SYS_RESOURCE  # With this, ulimit -l unlimited works
```

**Pros:**
- ✅ Clean solution - no script wrappers needed
- ✅ Works for all containers in pod
- ✅ Set once, works forever

**Cons:**
- ❌ Requires cluster-admin access
- ❌ May not be granted for security reasons

---

## Option 3: Init Container (⚠️ Limited Success)

Use an init container to attempt system-wide memlock configuration.

```yaml
initContainers:
- name: setup-memlock
  image: image-registry.openshift-image-registry.svc:5000/nccl-test/h-kim:latest
  securityContext:
    privileged: true  # Required, may not be allowed
  command:
  - /bin/bash
  - -c
  - |
    # Try to set for all processes
    echo "* soft memlock unlimited" >> /etc/security/limits.conf
    echo "* hard memlock unlimited" >> /etc/security/limits.conf

    # This won't affect the main container though
    # because each container has its own namespace
```

**Result:** ❌ Doesn't work
- Each container has its own process namespace
- limits.conf changes in init container don't carry over
- Would need shared PID namespace (not recommended)

---

## Option 4: Current Approach - Script Wrapper (✅ Best for Non-Admin)

**Current implementation in `lm-train.sh`:**
```bash
# Try to set (usually fails without SYS_RESOURCE)
ulimit -l unlimited 2>/dev/null || echo "[WARN] Could not set unlimited memlock"

# Wrap the actual command with prlimit (THIS WORKS)
exec prlimit --memlock=unlimited:unlimited \
  torchrun \
    --nnodes=2 \
    --nproc_per_node=4 \
    ...
```

**How prlimit works:**
1. Launches a child process with modified limits
2. Only affects that process and its children
3. Allowed with just `IPC_LOCK` capability (no SYS_RESOURCE needed)
4. Works around the ulimit restriction

**Pros:**
- ✅ Works without cluster-admin
- ✅ Works with current SCC (`IPC_LOCK` only)
- ✅ Proven to work with RDMA
- ✅ No cluster-wide changes needed

**Cons:**
- ⚠️ Must wrap every command that needs RDMA
- ⚠️ Adds complexity to scripts
- ⚠️ Forgotten wrapper = RDMA failures

---

## Option 5: Pod Security Context resourceRequirements (❌ Not for Memlock)

Kubernetes `resources` field only supports:
```yaml
resources:
  limits:
    memory: 256Gi     # Total RAM
    cpu: 64           # CPUs
    nvidia.com/gpu: 4 # GPUs
  # No memlock field exists
```

There's no `memlock` resource type.

---

## Comparison Table

| Option | Works? | Requires Admin? | Complexity | Recommendation |
|--------|--------|-----------------|------------|----------------|
| **CRI-O Annotation** | ❌ No | No | Low | Don't use |
| **SCC Modification** | ✅ Yes | ✅ Yes | Low | Best if admin available |
| **Init Container** | ❌ No | ✅ Yes (privileged) | Medium | Don't use |
| **prlimit Wrapper** | ✅ Yes | ❌ No | Medium | **Current best option** |
| **Pod Resources** | ❌ No | N/A | N/A | Not applicable |

---

## Recommendations

### For Current Setup (No Cluster Admin)

**Keep the current approach** - it works and is the best option without admin privileges:

```bash
# In scripts that need RDMA:
exec prlimit --memlock=unlimited:unlimited torchrun ...
```

**Advantages:**
- Already implemented and tested
- Works with existing SCC
- No cluster changes needed
- Proven with 83+ GiB/s RDMA bandwidth

### For Production (With Cluster Admin)

**Request SCC modification** to add `SYS_RESOURCE` capability:

```yaml
# SCC modification
allowedCapabilities:
  - IPC_LOCK
  - SYS_RESOURCE  # Add this
```

Then in pods:
```yaml
securityContext:
  capabilities:
    add:
      - IPC_LOCK
      - SYS_RESOURCE
```

And in containers, simple `ulimit -l unlimited` will work (no prlimit wrapper needed).

---

## Testing

To verify current setup works:

```bash
# Check memlock in pod
oc exec h-kim-0 -n nccl-test -- bash -c 'ulimit -l'
# Shows: 8192 (limited)

# Check if prlimit wrapper works
oc exec h-kim-0 -n nccl-test -- bash -c 'prlimit --memlock=unlimited:unlimited bash -c "ulimit -l"'
# Shows: unlimited (wrapper works!)
```

---

## Conclusion

**Answer to original question:**
> "Is it possible to put the memlock stuff into the pod manifest rather than in the script?"

**Short answer:** Not without cluster-admin access to modify SecurityContextConstraints.

**Practical answer:** The current script-based approach with `prlimit` is the best solution for users without admin privileges. It works, it's proven, and it requires no cluster-wide changes.

**Ideal answer:** If you have cluster-admin access, modify the SCC to allow `SYS_RESOURCE` capability, then you can set memlock directly at the pod level without script wrappers.

---

## Implementation Recommendation

**Keep current implementation** unless you can get cluster-admin to approve SCC modification.

Current script pattern:
```bash
#!/bin/bash
# RDMA training script

# Set NCCL config
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=...  # auto-detected

# Launch with unlimited memlock wrapper
exec prlimit --memlock=unlimited:unlimited \
  torchrun <training-command>
```

This is:
- ✅ Working (83+ GiB/s RDMA proven)
- ✅ Secure (doesn't require privileged/SYS_RESOURCE)
- ✅ Portable (works across OpenShift clusters)
- ✅ Maintainable (clear pattern)

The only improvement would be SCC modification, which requires cluster-admin approval.
