# Kyverno Harbor Break-Glass Runbook

**Issue:** OPS-951
**Last updated:** 2026-05-25
**Applies to:** `verify-image-signatures` ClusterPolicy (Enforce mode)

---

## Background

Kyverno's `verify-image-signatures` ClusterPolicy operates in **Enforce** mode and verifies cosign signatures for all images matching `harbor.208.haist.farm/sentinel/*` at pod admission time.

When Harbor is unavailable (upgrade, disk full, reboot), this creates a circular dependency:

1. **Harbor down** → image pulls fail AND signature verification fails
2. **Signature verification fails** → Kyverno blocks new pod creation (Enforce mode)
3. **Blocked pod creation** → apps that need to restart (e.g. PostgreSQL crash loop recovery) cannot start new pods
4. **Result:** Manual operator intervention required for every affected workload

This runbook documents the break-glass procedure and restoration steps.

---

## When to Use This Runbook

Use this runbook when **ALL of the following are true**:
- Harbor is unreachable or degraded
- Pods that should restart cannot because Kyverno admission is blocking them
- You see Kyverno deny events in `oc describe pod <pod>` referencing `verify-image-signatures`
- The situation cannot wait for Harbor to recover naturally

**Do NOT use this runbook** for routine Harbor maintenance where pods are expected to remain running (iSCSI timeout fix in OPS-951 prevents sessions from dropping during short reboots).

---

## Diagnosis

### 1. Confirm Kyverno is blocking pods

```bash
# Check recent Kyverno policy failures
oc get policyreport -A | grep fail

# Check events on a stuck pod
oc describe pod <pod-name> -n <namespace> | grep -A 5 "Failed"
# Look for: admission webhook denied: image signature verification failed
```

### 2. Confirm Harbor is the root cause

```bash
# Test Harbor connectivity from a node
curl -sk https://harbor.208.haist.farm/api/v2.0/health | jq .status
# Expected when healthy: "healthy"
```

### 3. Check Kyverno policy status

```bash
oc get clusterpolicy verify-image-signatures -o jsonpath='{.spec.validationFailureAction}'
# Should show: Enforce
```

---

## Option A: Namespace Exclusion (Preferred)

Add a namespace exclusion to the `verify-image-signatures` ClusterPolicy for the affected namespace. This is less disruptive than switching to Audit mode because it only affects the specific namespace.

### Step 1: Identify current exclusion list

```bash
oc get clusterpolicy verify-image-signatures -o yaml | grep -A 20 namespaceSelector
```

### Step 2: Add the affected namespace to the policy exception

The policy exceptions are managed in `apps/kyverno-policies/`. Check if a `PolicyException` resource exists for the target namespace, or create one:

```bash
# Apply a temporary PolicyException (do NOT commit to gitops without operator sign-off)
cat <<EOF | oc apply -f -
apiVersion: kyverno.io/v2
kind: PolicyException
metadata:
  name: harbor-breakglass-<namespace>
  namespace: <namespace>
  annotations:
    ops-issue: "OPS-951-harbor-breakglass"
    created-by: "operator-break-glass"
    expires: "$(date -d '+2 hours' --iso-8601=minutes)"
spec:
  exceptions:
  - policyName: verify-image-signatures
    ruleNames:
    - verify-sentinel-images
  match:
    any:
    - resources:
        namespaces:
        - <namespace>
        kinds:
        - Pod
EOF
```

### Step 3: Restart affected pods

```bash
oc rollout restart deployment/<deployment> -n <namespace>
```

### Step 4: Monitor

```bash
oc get pods -n <namespace> -w
```

### Step 5: Restore (REQUIRED — do not leave exception in place)

Once Harbor recovers:

```bash
# Delete the temporary exception
oc delete policyexception harbor-breakglass-<namespace> -n <namespace>

# Verify policy is enforcing again
oc get clusterpolicy verify-image-signatures -o jsonpath='{.spec.validationFailureAction}'
```

---

## Option B: Switch Policy to Audit Mode (Last Resort)

Switch the entire `verify-image-signatures` policy to Audit mode. This affects ALL namespaces and should only be used when Option A is insufficient (e.g., multiple namespaces affected simultaneously).

**Security impact:** In Audit mode, pods with unverified images CAN start. Kyverno records the violation but does not block admission. This reduces the security posture until Enforce mode is restored.

### Step 1: Record current state

```bash
oc get clusterpolicy verify-image-signatures -o yaml > /tmp/kyverno-policy-backup-$(date +%s).yaml
```

### Step 2: Switch to Audit mode

```bash
oc patch clusterpolicy verify-image-signatures \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Audit"}}'
```

### Step 3: Restart affected pods

```bash
# Restart wedged workloads
oc rollout restart deployment/<deployment> -n <namespace>
```

### Step 4: Restore Enforce mode (REQUIRED — restore immediately when Harbor recovers)

```bash
oc patch clusterpolicy verify-image-signatures \
  --type merge \
  -p '{"spec":{"validationFailureAction":"Enforce"}}'

# Verify
oc get clusterpolicy verify-image-signatures -o jsonpath='{.spec.validationFailureAction}'
# Expected: Enforce
```

**Note:** Do NOT commit the Audit-mode patch to gitops. The gitops repo (with ArgoCD selfHeal=true) will revert the policy to Enforce on the next sync cycle. That revert is **desired** — it restores the security control. Ensure Harbor is healthy before the next ArgoCD sync or the pods will be blocked again.

---

## Option C: IaC-Side Gitops Change (Planned Maintenance Only)

For planned Harbor maintenance where pods may need to restart (e.g., major Harbor upgrades):

1. Open a Plane issue before the maintenance window
2. Submit a PR to `apps/kyverno-policies/` adding a `PolicyException` for affected namespaces
3. Merge BEFORE the maintenance window starts
4. After Harbor recovers and is verified healthy, submit a second PR removing the exception
5. Do NOT leave exceptions in place after maintenance

---

## Prevention

The root cause of the OPS-951 incident was `iSCSI replacement_timeout=120s` being shorter than the TrueNAS reboot duration (188s). This caused pods to lose their backing store and restart — triggering the Kyverno circular dependency.

**Primary fix (OPS-951 D1):** Raise `replacement_timeout` to 600s in the iscsid MachineConfig. This prevents iSCSI sessions from dropping during TrueNAS reboots ≤10 minutes, eliminating the need for pods to restart and therefore avoiding the Kyverno admission check entirely.

**Secondary fix (OPS-951 D2):** livenessProbes on stateful workloads enable K8s to detect and restart wedged pods automatically — but with the iSCSI timeout fix in place, this should rarely be needed for planned storage maintenance events.

---

## Act-Chain

```
Act-Chain: human=jim orchestrator=backlog-2026-05-25 executing=worker-951-resilience action=create resource=docs/runbooks/kyverno-harbor-break-glass.md
```
