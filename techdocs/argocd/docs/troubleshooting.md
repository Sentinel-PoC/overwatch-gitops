# Troubleshooting

## OutOfSync Diagnosis

### Step 1: Check if it is cosmetic

Two applications are **permanently OutOfSync** by design:

| Application | Reason | Action |
|-------------|--------|--------|
| **kyverno-policies** | Kyverno webhook injects `skipBackgroundRequests`, `allowExistingViolations`, `autogen-*` rules, `.admission`, `.emitWarning`, `.webhookConfiguration` into ClusterPolicy specs | None required. Accepted risk. App is Healthy. |
| **defectdojo** | StatefulSet immutable fields (volumeClaimTemplates), PVC volumeName binding, restartedAt annotations | None required if Healthy. Force sync with Replace if needed. |

### Step 2: Inspect the diff

```bash
# From iac-control:
export KUBECONFIG=~/overwatch-repo/auth/kubeconfig

# Check sync status
oc get application <app-name> -n openshift-gitops -o yaml | less

# Look at the status.sync.comparedTo and status.conditions sections
# The diff shows what ArgoCD sees as different between Git and live state
```

Or use the ArgoCD UI at `argocd.208.haist.farm` -- click the application, then "App Diff" to see the exact resource differences.

### Step 3: Common causes

| Symptom | Cause | Fix |
|---------|-------|-----|
| ExternalSecret fields reordered | SSA normalizes data[] order | Already handled by ignoreDifferences; verify RespectIgnoreDifferences=true |
| SCC fields added | OpenShift admission injects defaults | Add ignoreDifferences for SCC jqPathExpressions |
| ConfigMap too large | Exceeds 262KB annotation limit | Add ServerSideApply=true to syncOptions |
| StatefulSet immutable field | volumeClaimTemplates changed | Force sync with Replace strategy (UI or CLI) |
| New ExternalSecret data[] entry not syncing | ignoreDifferences blocks new fields | `oc apply` the ExternalSecret manually first |

## ArgoCD Configuration Changes

### CRITICAL: Never patch argocd-cm directly

The OpenShift GitOps operator manages the `argocd-cm` ConfigMap. Direct patches via `oc patch configmap argocd-cm` will be **reverted by the operator**.

**Correct approach**: Patch the ArgoCD CR's `spec.extraConfig`:

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '
{
  "spec": {
    "extraConfig": {
      "your.config.key": "value"
    }
  }
}'
```

The operator will reconcile `argocd-cm` from the CR spec.

### OIDC Configuration

ArgoCD authenticates via Keycloak OIDC. The client secret comes from an ExternalSecret (`argocd-oidc-keycloak`) that merges into `argocd-secret`. If OIDC login fails:

1. Check the ExternalSecret status: `oc get externalsecret argocd-oidc-keycloak -n openshift-gitops`
2. Verify the Vault secret exists at `secret/keycloak/argocd`
3. Check Keycloak client `argocd` in realm `sentinel` at `auth.208.haist.farm`

### Repository Credentials

ArgoCD accesses the GitLab repo via an ExternalSecret (`argocd-gitlab-repo`) that creates a labeled Secret with the GitLab PAT. If sync fails with authentication errors:

1. Check: `oc get externalsecret argocd-gitlab-repo -n openshift-gitops`
2. Verify Vault `secret/gitlab` contains a valid `pat`
3. Test connectivity: ArgoCD server must reach `http://192.168.12.68` (GitLab direct, not through Cloudflare)

## Force Sync Procedures

### Standard Force Sync (UI)

1. Open `argocd.208.haist.farm`
2. Click the application
3. Click **Sync**
4. Optionally check **Prune**, **Force**, or **Replace**
5. Click **Synchronize**

### Force Sync with Replace (StatefulSet conflicts)

When StatefulSet immutable fields change (e.g., volumeClaimTemplates), normal sync fails. Replace strategy deletes and recreates the resource:

1. Open ArgoCD UI
2. Select the application (e.g., defectdojo)
3. Click **Sync** -> check **Replace** -> **Synchronize**

**Warning**: Replace deletes the resource before recreating it. For StatefulSets, this causes a brief downtime. PVCs are retained if `persistentVolumeReclaimPolicy: Retain`.

### CLI Force Sync

```bash
# From iac-control (requires argocd CLI, which may not be installed):
# Alternative: use oc to delete the resource and let ArgoCD recreate
oc delete <resource-type> <name> -n <namespace>
# ArgoCD self-heal will recreate from Git within ~3 minutes
```

## Common Sync Failures

### "namespace not managed by ArgoCD"

The target namespace lacks the required label or is not in the cluster secret:

```bash
# Add the managed-by label
oc label namespace <ns> argocd.argoproj.io/managed-by=openshift-gitops

# Verify cluster secret includes the namespace
oc get secret openshift-gitops-default-cluster-config -n openshift-gitops \
  -o jsonpath='{.data.namespaces}' | base64 -d
```

### "cluster-scoped resource not allowed"

The resource kind is not in the AppProject's `clusterResourceWhitelist`. Update `apps/argocd/appproject-default.yaml` and apply:

```bash
oc apply -f apps/argocd/appproject-default.yaml
```

### "ComparisonError" on large ConfigMaps

ConfigMaps exceeding 262KB hit the `last-applied-configuration` annotation limit:

```yaml
syncOptions:
  - ServerSideApply=true
```

Add this to the Application's syncOptions in the `*-app.yaml` definition.

### Helm chart fetch failure (air-gapped)

ArgoCD fetches external Helm charts through iac-control's Squid proxy. If chart fetch fails:

1. Check Squid is running on iac-control (port 3128)
2. Verify the chart registry domain is in Squid's allowlist
3. Check ArgoCD repo-server logs: `oc logs -n openshift-gitops -l app.kubernetes.io/component=repo-server`

## pangolin-internal / External Secrets Manual Apply

### pangolin-internal

While now managed by the root-app, if the pangolin-internal Application itself is missing or broken:

```bash
# From iac-control:
cd ~/overwatch-gitops
oc apply -f clusters/overwatch/system/ingress/pangolin-app.yaml
```

### External Secrets Resources

The ClusterSecretStore and Vault auth resources are never in the app-of-apps:

```bash
cd ~/overwatch-gitops
oc apply -f apps/external-secrets/
```

This creates/updates:
- `ClusterSecretStore/vault-backend`
- `ServiceAccount/vault-auth` in external-secrets
- `Secret/vault-auth-token` in external-secrets
- `ClusterRoleBinding/vault-auth-tokenreview`
- `OperatorConfig/cluster` in external-secrets

## Health Check Failures

### Application shows "Degraded"

1. Check pod status in the target namespace: `oc get pods -n <namespace>`
2. Check events: `oc get events -n <namespace> --sort-by='.lastTimestamp'`
3. If pods are in CrashLoopBackOff, check logs: `oc logs -n <namespace> <pod>`
4. For Kyverno-blocked pods: check `oc get policyreport -A` for violations

### Application shows "Missing"

Resources defined in Git do not exist in the cluster. Usually caused by:
- CRDs not installed (e.g., Istio CRDs needed before mesh-config)
- Namespace not created (check CreateNamespace syncOption)
- RBAC preventing resource creation

### Application shows "Progressing" for extended time

1. Check if pods are stuck in pending (resource limits, node capacity)
2. Check if PVCs are unbound (NFS server down, StorageClass missing)
3. Check if init containers are waiting (Istio sidecar injection issues)

## Root-App Troubleshooting

If the root-app itself is broken, child applications stop being managed:

```bash
# Check root-app status
oc get application root-app -n openshift-gitops

# If root-app is missing, recreate it (requires the root-app definition)
# The root-app definition should be stored separately or applied from a known commit
oc get applications -n openshift-gitops  # verify which apps still exist
```

The root-app watches `clusters/overwatch/` with glob `*-app.yaml` (recursive). If a child app definition file is renamed to not match this glob, the child Application will be pruned.
