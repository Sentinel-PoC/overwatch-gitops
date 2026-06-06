# ArgoCD Applications

## App-of-Apps Pattern

ArgoCD uses the app-of-apps pattern where a root Application manages child Applications. The root app watches the `argocd/` directory and creates/updates child apps automatically.

### Managed Applications

All applications below are managed by the app-of-apps and auto-sync from the `main` branch:

| Application | Source Path | Sync Policy | Health Check |
|-------------|------------|-------------|--------------|
| grafana | Helm (kube-prometheus-stack) | Auto-sync | Deployment ready |
| hello-world | `apps/hello-world/` | Auto-sync | Deployment ready |
| homepage | `apps/homepage/` | Auto-sync | Deployment ready |
| nfs-provisioner | `apps/nfs-provisioner/` | Auto-sync | Deployment ready |
| seedbox | `apps/seedbox/` | Auto-sync | Deployment ready |
| istio-controlplane | `apps/istio-controlplane/` | Auto-sync | Custom (Istio) |
| mesh-config | `apps/mesh-config/` | Auto-sync | Custom (Istio) |
| jaeger | `apps/jaeger/` | Auto-sync | Deployment ready |

### Self-Managed Applications

These applications manage their own sync or are applied separately:

| Application | Notes |
|-------------|-------|
| argocd | Self-manages via openshift-gitops operator |
| keycloak | ArgoCD-managed, separate from app-of-apps |
| harbor | ArgoCD-managed, separate from app-of-apps |
| defectdojo | ArgoCD-managed, separate from app-of-apps |
| kyverno-policies | ArgoCD-managed, separate from app-of-apps |
| external-secrets | Not in app-of-apps, `oc apply` to deploy ESO resources |
| backstage | ArgoCD-managed, separate from app-of-apps |

### Exception: pangolin-internal

`pangolin-internal` is **NOT** managed by ArgoCD app-of-apps. Apply manually:

```bash
oc apply -f overwatch-gitops/apps/pangolin-internal/
```

## Sync Policies

### Auto-Sync (default)

Most applications use auto-sync with self-heal:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

- **prune**: Removes resources from the cluster that are no longer in Git
- **selfHeal**: Reverts manual changes to match Git state

### Known Sync Issues

- **Harbor**: Completed Jobs get pruned by ArgoCD, causing cosmetic OutOfSync. Use force sync to resolve.
- **StatefulSet immutable fields**: ArgoCD selfHeal cannot fix immutable field conflicts on StatefulSets. Requires force sync with `Replace` strategy.

## Dependencies

```
keycloak ← grafana, argocd (OIDC)
keycloak ← harbor, okd-console (OIDC)
external-secrets ← argocd (manages OIDC secret)
nfs-provisioner ← harbor, defectdojo (PVC storage)
istio-controlplane ← mesh-config, kiali, jaeger (service mesh)
```

## Monitoring

All ArgoCD applications expose health status at [argocd.208.haist.farm](https://argocd.208.haist.farm). Grafana has a dedicated GitOps Pipeline dashboard tracking sync status and deployment frequency.
