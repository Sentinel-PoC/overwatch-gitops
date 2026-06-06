# GitOps Workflow

## Deployment Process

All changes to the OKD cluster follow the GitOps workflow:

```
1. Edit manifests locally (overwatch-gitops/)
2. Commit changes
3. Push to main branch on GitLab
4. ArgoCD detects change and auto-syncs
5. OKD cluster is updated
```

### Step-by-Step

```bash
# 1. Pull latest from GitLab
cd ~/overwatch-gitops
git pull origin main

# 2. Make changes to application manifests
# Edit files in apps/<application>/

# 3. Commit and push
git add <changed-files>
git commit -m "description of change"
git push origin main
# ArgoCD auto-syncs within ~3 minutes
```

### Verify Deployment

```bash
# From iac-control:
export KUBECONFIG=~/overwatch-repo/auth/kubeconfig

# Check ArgoCD sync status
oc get applications -n openshift-gitops

# Check specific app
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.sync.status}'
```

Or check the ArgoCD dashboard at [argocd.208.haist.farm](https://argocd.208.haist.farm).

## Rules

### Never Patch Directly

Do not use `oc patch`, `kubectl edit`, `oc set`, or any imperative command to modify resources managed by ArgoCD. These changes will be reverted by ArgoCD's self-heal.

```bash
# WRONG - will be reverted
oc patch deployment my-app -n my-namespace -p '{"spec":{"replicas":3}}'

# RIGHT - edit the manifest and push
vim apps/my-app/deployment.yaml  # change replicas to 3
git add apps/my-app/deployment.yaml
git commit -m "Scale my-app to 3 replicas"
git push origin main
```

### Exception: pangolin-internal

`pangolin-internal` is the sole exception — it is NOT managed by the app-of-apps pattern:

```bash
# This is the correct way to deploy pangolin-internal changes
oc apply -f apps/pangolin-internal/
```

### Air-Gapped Considerations

The OKD cluster has no internet egress. When adding new applications:

- Container images must be available in Harbor (`harbor.208.haist.farm`)
- Helm charts must be vendored or use inline values
- Grafana dashboards must use inline JSON (not `gnetId` references)
- External webhook/API references will fail silently

## CI Pipeline

The overwatch-gitops CI pipeline runs validation only (no deployment — ArgoCD handles that):

**Stages**: `lint` → `security-scan`

| Job | Tool | Purpose |
|-----|------|---------|
| yamllint | yamllint | YAML syntax validation |
| trivy-config | Trivy | Kubernetes manifest security scan |
| gitleaks | Gitleaks | Secret detection (hard block) |

Security scan results are uploaded to DefectDojo for tracking.

## Troubleshooting

### Application Stuck in OutOfSync

```bash
# Check sync status details
oc get application <app> -n openshift-gitops -o yaml | grep -A 20 status

# Force sync (resolves cosmetic issues like completed Jobs)
# Use ArgoCD UI: App → Sync → Replace checked → Synchronize
```

### Self-Heal Not Working (StatefulSet)

ArgoCD cannot self-heal immutable field changes on StatefulSets. Force sync with Replace strategy resolves this:

1. Open ArgoCD UI
2. Select the application
3. Click Sync → check "Replace" → Synchronize

### New Application Not Appearing

1. Verify the app definition exists in `argocd/` (for app-of-apps managed) or is applied directly
2. Check the root app-of-apps for sync errors
3. Verify YAML syntax passes yamllint
