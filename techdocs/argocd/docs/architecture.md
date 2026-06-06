# Architecture

## App-of-Apps Pattern

ArgoCD uses a **root application** (`root-app`) that recursively scans the `clusters/overwatch/` directory tree for files matching the glob `*-app.yaml`. Each matching file defines a child Application resource that ArgoCD creates and manages.

```
root-app
  source: overwatch-gitops/clusters/overwatch/
  include: *-app.yaml (recursive)
  |
  +-- clusters/overwatch/apps/*-app.yaml          (16 app definitions)
  +-- clusters/overwatch/apps/monitoring/*-app.yaml (2 monitoring apps)
  +-- clusters/overwatch/system/ingress/*-app.yaml  (2 ingress apps)
  +-- clusters/overwatch/system/storage/*-app.yaml  (1 storage app)
  +-- clusters/overwatch/system/reloader-app.yaml   (1 system app)
```

The root-app itself is bootstrapped manually (`oc apply`) and then self-manages from Git.

### Directory Structure

```
overwatch-gitops/
+-- apps/                              # Application manifests (what gets deployed)
|   +-- argocd/                        # ArgoCD config (AppProject, Route)
|   +-- backstage/                     # Backstage developer portal
|   +-- defectdojo/                    # DefectDojo ASDB
|   +-- external-secrets/              # ESO ClusterSecretStore + auth (oc apply only)
|   +-- falco/                         # Falco runtime security
|   +-- haists-website/                # Public website
|   +-- harbor/                        # Container registry
|   +-- homepage/                      # Platform dashboard
|   +-- istio-controlplane/            # Istio CRs (reference, oc apply via Sail Operator)
|   +-- jaeger/                        # Distributed tracing (reference, Jaeger Operator)
|   +-- keycloak/                      # Identity provider
|   +-- kyverno-policies/              # Admission policies
|   +-- matrix/                        # Synapse + Element + MAS
|   +-- mesh-config/                   # Istio PeerAuth, DestinationRules, AuthzPolicies
|   +-- monitoring/                    # Prometheus + Thanos config
|   +-- netbox/                        # Network documentation
|   +-- observability/                 # Kiali config
|   +-- overwatch-console/             # Security operations dashboard
|   +-- pangolin-internal/             # Traefik ingress resources (was oc apply, now in root-app)
|   +-- reloader/                      # Stakater Reloader
|   +-- seedbox/                       # Download management
|   +-- sentinel-ops/                  # Platform automation CronJobs
|
+-- clusters/overwatch/                # App-of-apps definitions (what ArgoCD watches)
|   +-- apps/                          # Application-level app definitions
|   |   +-- monitoring/                # Grafana + dashboards app defs + values
|   |   +-- defectdojo/                # DefectDojo Helm values
|   |   +-- harbor/                    # Harbor Helm values
|   |   +-- netbox/                    # NetBox Helm values
|   +-- service-mesh/                  # Reference-only app defs (not applied)
|   +-- system/                        # System-level app definitions
|       +-- ingress/                   # Pangolin + Newt tunnel
|       +-- rbac/                      # Cluster RBAC
|       +-- static-storage/            # PV + StorageClass manifests
|       +-- storage/                   # NFS provisioner app def
```

## AppProject Configuration

All applications use the **`default`** AppProject (`apps/argocd/appproject-default.yaml`). This project is a bootstrap resource -- ArgoCD cannot manage its own AppProject, so it is applied manually.

**Allowed cluster-scoped resources** (minimized blast radius):

| API Group | Kind | Used By |
|-----------|------|---------|
| `security.openshift.io` | SecurityContextConstraints | seedbox, reloader, haists-website |
| `rbac.authorization.k8s.io` | ClusterRole, ClusterRoleBinding | backstage K8s plugin, reloader |
| `kyverno.io` | ClusterPolicy, ClusterCleanupPolicy | kyverno-policies |
| `storage.k8s.io` | StorageClass | static-storage (manual-nfs) |
| `""` (core) | PersistentVolume | static-storage (nfs-media-root-pv) |

**Source repos**: Unrestricted (`*`) -- all repos are trusted (internal GitLab + known Helm registries).

**Destinations**: Unrestricted (`*/*`) -- all namespaces on the local cluster.

### Bootstrap: Enabling Cluster-Scoped Resources

The OpenShift GitOps operator creates an in-cluster secret with a `namespaces` field derived from `argocd.argoproj.io/managed-by` labels. This puts ArgoCD in namespace-scoped mode by default. To manage cluster-scoped resources, you must **one-time patch** the cluster secret:

```bash
oc patch secret openshift-gitops-default-cluster-config -n openshift-gitops \
  --type merge -p '{"data":{"clusterResources":"'$(echo -n true | base64)'"}}'
```

## Namespace Requirements

For ArgoCD to manage resources in a namespace, **two conditions** must be met:

1. **Label**: The namespace must have `argocd.argoproj.io/managed-by=openshift-gitops`
2. **Cluster secret**: The namespace must be listed in the `namespaces` field of the `openshift-gitops-default-cluster-config` Secret in `openshift-gitops`

Most Application manifests include `CreateNamespace=true` in syncOptions, which handles namespace creation. But the label and cluster-secret update are prerequisites handled by the operator when a namespace is first added.

## Adding a New Application

1. Create manifest directory in `apps/<new-app>/` with K8s resources (Deployment, Service, Route, etc.)
2. Create an Application definition in `clusters/overwatch/apps/<new-app>-app.yaml`:
   - Filename MUST end with `-app.yaml` to match the root-app glob
   - Set `spec.project: default`
   - Set source to `http://192.168.12.68/admin1/overwatch-gitops.git`, path `apps/<new-app>`, targetRevision `main`
   - Set destination namespace
   - Add `syncPolicy.automated` with `prune: true` and `selfHeal: true`
   - Add `CreateNamespace=true` to syncOptions
3. Ensure container images are in Harbor and cosign-signed (Kyverno blocks unsigned images)
4. Commit and push to `main` -- root-app will detect the new `*-app.yaml` and create the Application

## Resources NOT Managed by App-of-Apps

Several resources are applied manually (`oc apply`) due to namespace-scoped ArgoCD limitations:

| Resource | Reason | Apply Method |
|----------|--------|--------------|
| `external-secrets/` (ClusterSecretStore, OperatorConfig) | ClusterSecretStore is cluster-scoped; external-secrets namespace not managed | `oc apply -f apps/external-secrets/` |
| `istio-controlplane/` (Istio, IstioCNI CRs) | Cluster-scoped CRDs managed by Sail Operator (OLM) | `oc apply -f apps/istio-controlplane/` |
| `jaeger/` (Jaeger CR) | Cluster-scoped CRD managed by Jaeger Operator (OLM) | `oc apply -f apps/jaeger/` |
| `mesh-config/` (PeerAuth, AuthzPolicies) | Resources span unmanaged namespaces + cluster-scoped CRBs | `oc apply -Rf apps/mesh-config/` |
| Kiali | Installed via Helm directly (ClusterRole constraints) | `helm install kiali ...` (see reference yaml) |
| AppProject `default` | Bootstrap resource -- ArgoCD cannot manage its own project | `oc apply -f apps/argocd/appproject-default.yaml` |

Reference-only Application definitions for these are kept in `clusters/overwatch/service-mesh/` with `-reference.yaml` suffix. They are annotated with `sentinel.haist.farm/managed-by` to document the actual management method.
