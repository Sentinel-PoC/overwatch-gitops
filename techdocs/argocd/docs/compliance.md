# Compliance

ArgoCD's GitOps workflow provides evidence and enforcement for several NIST 800-53 controls in the Project Sentinel compliance program.

## Applicable NIST 800-53 Controls

### CM-2: Baseline Configuration

**Requirement**: Develop, document, and maintain a current baseline configuration of the system.

**How ArgoCD satisfies this**:

- The `overwatch-gitops` Git repository IS the baseline configuration for all OKD cluster workloads.
- Every Application manifest, Helm values file, and Kubernetes resource definition is version-controlled.
- Git history provides a complete audit trail of every baseline change (who, when, what, why via commit messages).
- The root-app pattern ensures that the set of managed applications is itself defined in Git.

**Evidence**: `git log` on the `overwatch-gitops` repository shows the full history of baseline changes. ArgoCD sync status shows whether the live cluster matches the defined baseline.

### CM-3: Configuration Change Control

**Requirement**: Control changes to the system through a formal change control process.

**How ArgoCD satisfies this**:

- All changes MUST go through Git (commit + push to `main`). Direct cluster modifications are automatically reverted by ArgoCD's self-heal.
- GitLab CI validates all changes before ArgoCD syncs: yamllint (syntax), trivy-config (security), gitleaks (secret detection).
- Git commits provide an immutable record of who made each change and when.

**Current status**: CM-3(2) compliance check reports **77% sync rate** (WARN). This is because 2 of 22 applications are permanently OutOfSync (kyverno-policies and defectdojo) due to controller-injected fields, not due to actual configuration drift. Both are Healthy and the OutOfSync is cosmetic.

**Calculation**: 20 Synced / 22 total = ~91% actual sync rate. The compliance check may use a different denominator that includes non-ArgoCD-managed resources (mesh-config, istio, etc.), bringing the rate to 77%.

### CM-5: Access Restrictions for Change

**Requirement**: Define, document, approve, and enforce physical and logical access restrictions for changes.

**How ArgoCD satisfies this**:

- Only users with GitLab push access to `overwatch-gitops` `main` branch can change the cluster configuration.
- ArgoCD authenticates via Keycloak OIDC with role-based access (admin/operator/viewer groups in realm `sentinel`).
- The ArgoCD dashboard at `argocd.208.haist.farm` requires authentication. Read-only access for `viewer` group; sync/modify for `admin` group.
- ArgoCD's repo credentials are managed via ExternalSecrets from Vault, not stored in plain text.

### SI-7: Software, Firmware, and Information Integrity

**Requirement**: Employ integrity verification tools to detect unauthorized changes.

**How ArgoCD satisfies this**:

- ArgoCD continuously compares live cluster state against the Git-defined desired state.
- Self-heal automatically reverts unauthorized changes (drift remediation).
- Prune removes resources that are no longer defined in Git (unauthorized additions).
- Kyverno's `verify-image-signatures` policy (Enforce mode) ensures only cosign-signed images from Harbor can run in the cluster, providing supply-chain integrity.

**Continuous monitoring**: ArgoCD sync checks run every ~3 minutes. Any drift between Git and live state triggers an automatic remediation (self-heal) or is flagged as OutOfSync for operator review.

## Evidence Collection

### Git History as Audit Trail

```bash
# Full change history for the GitOps repo
git log --oneline --since="2026-01-01" -- apps/ clusters/

# Changes to a specific application
git log --oneline -- apps/keycloak/

# Show who changed what and when
git log --format="%h %ai %an: %s" -- clusters/overwatch/apps/
```

### ArgoCD Sync Status as Drift Evidence

```bash
# From iac-control:
export KUBECONFIG=~/overwatch-repo/auth/kubeconfig

# Current sync status of all applications
oc get applications -n openshift-gitops \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Detailed sync info for a specific app
oc get application <app> -n openshift-gitops -o jsonpath='{.status.sync}'
```

### Compliance Check Integration

The daily `nist-compliance-check.sh` (runs at 6AM UTC on iac-control, also as sentinel-ops CronJob) includes an ArgoCD sync status check as part of CM-3(2). Results are committed to the `compliance-vault` repository by the evidence pipeline (7AM UTC).

The check queries all ArgoCD applications and calculates the sync percentage. The current WARN threshold is set such that the 2 cosmetically OutOfSync apps trigger a warning.

## Compliance Gaps and Mitigations

### CM-3(2) WARN: 77% Sync Rate

**Gap**: The automated compliance check reports ArgoCD sync rate below 100%.

**Root cause**: kyverno-policies and defectdojo are permanently OutOfSync due to controller-injected fields (not actual drift).

**Mitigation**: Both applications are Healthy and functioning correctly. The `ignoreDifferences` configuration minimizes the reported diff. This WARN is documented and accepted in the gap analysis (`sentinel-iac-work/docs/nist-gap-analysis.md`).

**Possible future fix**: Refine the compliance check to exclude applications with `ignoreDifferences` configurations from the sync percentage, or to treat "OutOfSync but Healthy with ignoreDifferences" as compliant.

### Manual-Apply Resources

Several resources are not managed by ArgoCD (istio, jaeger, kiali, mesh-config, external-secrets). These fall outside ArgoCD's continuous drift detection. Mitigation:

- All resources have Git-tracked manifests (audit trail exists)
- Istio and Jaeger are managed by OLM operators (operator-managed drift detection)
- Mesh-config changes are applied via `oc apply -Rf` from the Git repo

## Compliance Summary

| Control | Status | Evidence Source |
|---------|--------|----------------|
| CM-2 (Baseline Configuration) | Implemented | Git repo as baseline, ArgoCD enforces |
| CM-3 (Change Control) | Partial (WARN) | Git history + CI validation + auto-sync. 77% sync rate due to cosmetic OutOfSync |
| CM-5 (Access Restrictions) | Implemented | GitLab branch protection + Keycloak OIDC RBAC |
| SI-7 (Integrity Verification) | Implemented | Continuous sync + self-heal + Kyverno image signing |
