# Sync Policies

## Default Sync Policy

Most applications use automated sync with prune and self-heal enabled:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources from cluster that are no longer in Git
    selfHeal: true   # Revert manual changes to match Git state
  syncOptions:
    - CreateNamespace=true
```

This means:

- **Pushing to `main` is deploying**. ArgoCD detects changes within approximately 3 minutes and auto-syncs.
- **Direct changes are reverted**. Any `oc patch`, `kubectl edit`, or imperative command will be overwritten by self-heal.
- **Deleted manifests cause resource deletion**. Removing a YAML file from Git prunes the corresponding cluster resource.

## Per-Application Sync Configuration

### Applications with ServerSideApply

ServerSideApply (`ServerSideApply=true`) is required for resources that exceed the 262KB annotation limit or have field ownership conflicts:

| Application | Why SSA |
|-------------|---------|
| backstage | ExternalSecret ignoreDifferences requires RespectIgnoreDifferences |
| defectdojo | StatefulSet volumeClaimTemplates + ExternalSecret field reordering |
| grafana-dashboards | Dashboard ConfigMaps may exceed 262KB |
| haists-website | SCC field injection by OpenShift admission |
| harbor | ExternalSecret field reordering |
| kyverno-policies | Kyverno webhook injects fields; uses ServerSideDiff compare |
| matrix | ExternalSecret ignoreDifferences |
| overwatch-console | ExternalSecret ignoreDifferences |
| reloader | ClusterRole/CRB ownership conflicts |

### Applications with RespectIgnoreDifferences

`RespectIgnoreDifferences=true` ensures that fields listed in `ignoreDifferences` are truly ignored during sync (not just diff display). Required when `ignoreDifferences` is used:

- backstage, defectdojo, haists-website, harbor, kyverno-policies, matrix, overwatch-console, sentinel-ops

### Applications with Replace Strategy

| Application | Reason |
|-------------|--------|
| defectdojo | `Replace=true` -- StatefulSet immutable field conflicts cannot be resolved by normal apply. Force-replaces resources during sync. |

### Applications WITHOUT CreateNamespace

| Application | Namespace | Reason |
|-------------|-----------|--------|
| static-storage | default | Deploys to `default` namespace (cluster-scoped PV/SC) |

### Applications with Minimal Sync Options

These applications use only `automated.prune + selfHeal` without additional syncOptions:

- homepage, seedbox, keycloak, static-storage

## ignoreDifferences Configuration

### ExternalSecret Field Reordering

ArgoCD's Server-Side Apply (SSA) normalizes the order of `data[]` entries in ExternalSecrets, causing perpetual OutOfSync. Multiple applications ignore ExternalSecret fields:

```yaml
ignoreDifferences:
  - group: external-secrets.io
    kind: ExternalSecret
    jqPathExpressions:
      - .spec.data[]?.remoteRef
      - .spec.target
```

**Affected apps**: backstage, defectdojo, harbor, sentinel-ops

Some apps use a broader ignore:

```yaml
ignoreDifferences:
  - group: external-secrets.io
    kind: ExternalSecret
    jqPathExpressions:
      - .spec
```

**Affected apps**: haists-website, matrix, overwatch-console

### Kyverno Webhook Injection

Kyverno's admission controller injects multiple fields into ClusterPolicy specs that do not exist in the Git manifests:

```yaml
ignoreDifferences:
  - group: kyverno.io
    kind: ClusterPolicy
    jqPathExpressions:
      - .spec.rules[]?.skipBackgroundRequests
      - .spec.rules[]?.validate.allowExistingViolations
      - .spec.rules[] | select(.name|test("autogen-."))
      - .spec.admission
      - .spec.emitWarning
      - .spec.webhookConfiguration
      - .status
    managedFieldsManagers:
      - kyverno
```

Despite these ignores, kyverno-policies remains permanently **OutOfSync** -- this is an **accepted risk** and does not indicate a problem. The app is Healthy.

### DefectDojo StatefulSet / PVC

```yaml
ignoreDifferences:
  - kind: PersistentVolumeClaim
    jsonPointers:
      - /spec/volumeName
  - group: apps
    kind: StatefulSet
    jqPathExpressions:
      - .spec.volumeClaimTemplates
      - .spec.persistentVolumeClaimRetentionPolicy
      - .spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"]
```

### OpenShift SCC Injection (haists-website)

OpenShift admission injects fields into SecurityContextConstraints:

```yaml
ignoreDifferences:
  - group: security.openshift.io
    kind: SecurityContextConstraints
    jqPathExpressions:
      - .allowPrivilegeEscalation
      - .readOnlyRootFilesystem
      - .groups
      - .allowedCapabilities
      - .defaultAddCapabilities
      - .requiredDropCapabilities
      - .volumes
```

## Sync Waves

The mesh-config reference application uses a sync-wave annotation:

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "3"
```

This is a reference-only definition (not applied), but documents the intended ordering: mesh-config should sync after the Istio control plane (wave 0-2).

No other applications in the current deployment use explicit sync waves.

## Multi-Source Applications

Several applications use ArgoCD's multi-source feature to combine Helm charts with Git-based values and additional manifests:

| Application | Sources |
|-------------|---------|
| grafana | Helm chart (grafana.github.io) + Git ref (values) |
| harbor | Helm chart (helm.goharbor.io) + Git ref (values) + Git path (apps/harbor) |
| defectdojo | Helm chart (GitHub raw) + Git ref (values) + Git path (apps/defectdojo) |
| netbox | Helm chart (netboxlabs.com) + Git ref (values) + Git path (apps/netbox) |

The pattern uses `ref: values` as a Git source reference, then `$values/clusters/overwatch/apps/<app>/values.yaml` in the Helm valueFiles to reference values from the Git repo.
