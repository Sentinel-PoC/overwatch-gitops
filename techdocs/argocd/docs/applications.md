# Applications

Complete inventory of all ArgoCD-managed applications, derived from both the YAML manifests in the `overwatch-gitops` repository and live MCP discovery (as of 2026-03-04).

## Summary

- **Total applications**: 21 (including root-app)
- **Synced**: 19
- **OutOfSync**: 2 (defectdojo, kyverno-policies)
- **Healthy**: 22

## Platform Services

| Application | Namespace | Source Type | Chart/Path | Sync Status | Health |
|-------------|-----------|------------|------------|-------------|--------|
| keycloak | keycloak | Plain manifests | `apps/keycloak` | Synced | Healthy |
| harbor | harbor | Helm + manifests | `harbor` chart v1.18.2 + `apps/harbor` | Synced | Healthy |
| grafana | monitoring | Helm | `grafana` chart v10.5.15 | Synced | Healthy |
| grafana-dashboards | monitoring | Directory (recurse) | `clusters/overwatch/apps/monitoring/grafana/dashboards` | Synced | Healthy |
| defectdojo | defectdojo | Helm + manifests | `defectdojo` chart v1.9.12 + `apps/defectdojo` | OutOfSync | Healthy |
| netbox | netbox | Helm + manifests | `netbox` chart v7.4.8 + `apps/netbox` | Synced | Healthy |
| backstage | backstage | Plain manifests | `apps/backstage` | Synced | Healthy |

### Notes

- **defectdojo** OutOfSync is expected -- StatefulSet immutable fields and PVC volumeName cause perpetual diff. The app uses `Replace=true` sync option and `ignoreDifferences` to mitigate. Health is Healthy.
- **grafana** uses multi-source: Helm chart from `grafana.github.io/helm-charts` with values from the Git repo.
- **grafana-dashboards** is a separate app deploying ConfigMaps via sidecar discovery. Uses `ServerSideApply=true` for ConfigMaps that may exceed 262KB.
- **harbor** uses multi-source: Helm chart from `helm.goharbor.io` with values from Git, plus additional manifests from `apps/harbor`.
- **netbox** uses multi-source: Helm chart from `charts.netbox.oss.netboxlabs.com` with values from Git, plus additional manifests from `apps/netbox`.
- **defectdojo** images are overridden to Harbor-hosted copies via Helm parameters (air-gapped cluster).

## Security & Policy

| Application | Namespace | Source Type | Chart/Path | Sync Status | Health |
|-------------|-----------|------------|------------|-------------|--------|
| kyverno-policies | kyverno | Plain manifests | `apps/kyverno-policies` | OutOfSync | Healthy |
| falco | falco-system | Plain manifests | `apps/falco` | Synced | Healthy |
| reloader | reloader | Kustomize | `apps/reloader` | Synced | Healthy |

### Notes

- **kyverno-policies** OutOfSync is **cosmetic and accepted risk**. Kyverno's admission webhook injects `skipBackgroundRequests`, `allowExistingViolations`, and `autogen-*` rules into ClusterPolicy specs. Extensive `ignoreDifferences` with jqPathExpressions mitigate most drift, but some always remains. Uses `ServerSideDiff=true,IncludeMutationWebhook=true` compare options.
- **falco** deploys Falco runtime security in `falco-system` namespace. Image: `harbor.208.haist.farm/sentinel/falco:0.40.0`.
- **reloader** is Stakater Reloader v1.3.0. Watches Secrets/ConfigMaps for annotation-triggered pod restarts when secrets rotate (especially useful with ExternalSecrets).

## Applications & Dashboards

| Application | Namespace | Source Type | Chart/Path | Sync Status | Health |
|-------------|-----------|------------|------------|-------------|--------|
| overwatch-console | overwatch-console | Plain manifests | `apps/overwatch-console` | Synced | Healthy |
| haists-website | haists-website | Plain manifests | `apps/haists-website` | Synced | Healthy |
| matrix | matrix | Plain manifests | `apps/matrix` | Synced | Healthy |
| homepage | homepage | Plain manifests | `apps/homepage` | Synced | Healthy |
| sentinel-ops | sentinel-ops | Plain manifests | `apps/sentinel-ops` | Synced | Healthy |

### Notes

- **overwatch-console** is the security operations dashboard (FastAPI + React). Image: `harbor.208.haist.farm/sentinel/overwatch-console`.
- **haists-website** is the public-facing website at `www.haist.farm`. Includes SCC `ignoreDifferences` for OpenShift security context field injection.
- **matrix** deploys Synapse v1.139.2, Element Web v1.12.11, MAS v0.12.0, and PostgreSQL 16.8.
- **homepage** is the platform service dashboard at `home.208.haist.farm`.
- **sentinel-ops** runs 4 CronJobs: grafana-health (5min), nist-compliance-check (daily), minio-replicate (6h), evidence-pipeline (daily).

## System / Infrastructure

| Application | Namespace | Source Type | Chart/Path | Sync Status | Health |
|-------------|-----------|------------|------------|-------------|--------|
| pangolin-internal | pangolin-internal | Helm | Traefik chart v26.0.0 | Synced | Healthy |
| newt-tunnel | pangolin-internal | Plain manifests | `clusters/overwatch/system/ingress/newt-resources` | Synced | Healthy |
| nfs-provisioner | nfs-provisioner | Helm | `nfs-subdir-external-provisioner` chart v4.0.18 | Synced | Healthy |
| static-storage | default | Plain manifests | `clusters/overwatch/system/static-storage` | Synced | Healthy |

### Notes

- **pangolin-internal** is the in-cluster Traefik instance (2 replicas, NodePort 30080/30443). Istio sidecar injection disabled.
- **newt-tunnel** is the Pangolin/Newt WireGuard tunnel for external ingress (NodePort 31820 UDP). Uses ExternalSecret for credentials from Vault `secret/newt`.
- **nfs-provisioner** provides dynamic PV provisioning from the NFS server at `192.168.12.205:/mnt/DATA/data`. RBAC and StorageClass creation disabled (handled separately).
- **static-storage** deploys the `manual-nfs` StorageClass and `nfs-media-root-pv` PersistentVolume (20Ti, NFS).

## Root Application

| Application | Namespace | Source Type | Chart/Path | Sync Status | Health |
|-------------|-----------|------------|------------|-------------|--------|
| root-app | openshift-gitops | Directory (recurse, glob) | `clusters/overwatch` (include `*-app.yaml`) | Synced | Healthy |

The root-app is the app-of-apps controller. It recursively scans `clusters/overwatch/` for `*-app.yaml` files and creates/manages all child Applications listed above.

## Resources Applied Manually (Not in App-of-Apps)

These resources have Git-tracked manifests but are NOT managed by ArgoCD. Reference-only Application definitions exist in `clusters/overwatch/service-mesh/`.

| Resource | Namespace | Management | Manifests |
|----------|-----------|------------|-----------|
| Istio control plane | istio-system | Sail Operator (OLM) | `apps/istio-controlplane/` |
| Jaeger | observability | Jaeger Operator (OLM) | `apps/jaeger/` |
| Kiali | istio-system | Helm direct install | See `kiali-reference.yaml` |
| Mesh config | Multiple | `oc apply -Rf` | `apps/mesh-config/` |
| External Secrets config | external-secrets | `oc apply -f` | `apps/external-secrets/` |
| AppProject default | openshift-gitops | `oc apply -f` | `apps/argocd/appproject-default.yaml` |

## Image Summary

All application images are hosted in Harbor (`harbor.208.haist.farm/sentinel/`) due to the air-gapped cluster. Key images observed in live state:

- `backstage:v2.0.0`, `keycloak:26.1.4`, `grafana:12.4.0`, `netbox:v4.5.3`
- `falco:0.40.0`, `reloader:v1.3.0`, `overwatch-console:d859574`
- `haists-website:f3a42fb`, `homepage:v1.2.0`, `sentinel-ops:v1`
- `synapse:v1.139.2`, `element-web:v1.12.11`, `mas:v0.12.0`
- `newt:1.10.0`, `postgres:16.8` (shared across multiple apps)
- `traefik:v2.10.6` (pangolin-internal)
- Istio sidecar: `gcr.io/istio-release/proxyv2` (injected into meshed pods)
