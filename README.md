# Overwatch GitOps

[![pipeline status](http://192.168.12.68/admin1/overwatch-gitops/badges/main/pipeline.svg)](http://192.168.12.68/admin1/overwatch-gitops/-/commits/main)

GitOps manifests for the Overwatch OKD cluster. **Pushing to `main` triggers ArgoCD deployment** — treat this repo as production.

## How It Works

ArgoCD watches this repo and auto-syncs changes pushed to `main`. Each application is defined as an ArgoCD `Application` CR in `argocd/`, pointing to manifests in `apps/`.

```
Push to main → ArgoCD detects change → Syncs to OKD cluster
```

**Exception**: `pangolin-internal` requires manual `oc apply` (not ArgoCD-managed).

## Directory Structure

```
overwatch-gitops/
├── apps/                        # Application manifests
│   ├── argocd/                  # ArgoCD operator config
│   ├── backstage/               # Backstage developer portal
│   ├── console/                 # Overwatch Console (FastAPI + React)
│   ├── defectdojo/              # DefectDojo vulnerability management
│   ├── external-secrets/        # ESO + ClusterSecretStore
│   ├── falco/                   # Falco runtime security
│   ├── haists-website/          # Public website
│   ├── harbor/                  # Harbor container registry
│   ├── homepage/                # Homepage dashboard
│   ├── istio-controlplane/      # Istio service mesh control plane
│   ├── jaeger/                  # Distributed tracing
│   ├── keycloak/                # Identity provider (OIDC)
│   ├── kyverno-policies/        # Kyverno admission policies
│   ├── matrix/                  # Matrix/Synapse + Element + MAS
│   ├── mesh-config/             # Istio mesh configuration
│   ├── monitoring/              # Grafana, Prometheus, ServiceMonitors
│   ├── netbox/                  # NetBox DCIM/IPAM
│   ├── observability/           # Observability stack
│   ├── overwatch-console/       # Security dashboard
│   ├── reloader/                # Stakater Reloader
│   ├── seedbox/                 # Seedbox services
│   ├── sentinel-ops/            # Operational CronJobs + secrets
│   └── ...
├── argocd/                      # ArgoCD Application CRs (app-of-apps)
├── backstage-catalog/           # Backstage catalog entities
├── clusters/overwatch/          # Cluster-specific overrides
│   ├── apps/                    # Helm values overrides
│   ├── machineconfigs/          # OKD MachineConfig CRs
│   ├── service-mesh/            # Mesh member roll
│   └── system/                  # Ingress, RBAC, storage
└── .gitlab-ci.yml               # Validation pipeline
```

## Adding a New Application

1. Create manifests in `apps/<app-name>/`
2. Create an ArgoCD `Application` CR in `argocd/<app-name>.yaml`
3. Push to `main` — ArgoCD picks it up automatically

For Helm-based apps, put `values.yaml` overrides in `clusters/overwatch/apps/<app-name>/`.

## CI Pipeline

Validation only (ArgoCD handles deployment):

- **yamllint**: YAML syntax validation
- **trivy-config**: K8s manifest security scan (blocks on HIGH/CRITICAL)
- **gitleaks**: Secret detection (blocks on any finding)
- **checkov**: K8s security scan (blocks on CRITICAL/HIGH)
- **DefectDojo uploads**: Scan results uploaded for tracking

## Namespaces

Applications are organized by namespace on OKD. Key namespaces: `backstage`, `defectdojo`, `external-secrets`, `harbor`, `homepage`, `istio-system`, `keycloak`, `kyverno`, `matrix`, `monitoring`, `netbox`, `sentinel-ops`.

## Important Notes

- **Kyverno**: New container images MUST be cosign-signed before deployment
- **Air-gapped**: OKD has no internet egress — `gnetId` for Grafana dashboards fails silently, use inline JSON
- **OKD networking**: Pods cannot reach 192.168.12.0/24 (management VLAN)
- **Large ConfigMaps**: Grafana dashboards >262KB need `ServerSideApply=true` annotation
- **ArgoCD CR**: Patch `spec.extraConfig`, not `argocd-cm` directly (operator reverts ConfigMap changes)
