# Overwatch GitOps

GitOps manifests for the **Overwatch** OKD 4.19 cluster, managed by ArgoCD with an app-of-apps pattern.

## Overview

This repository is the single source of truth for all workloads running on the OKD cluster. Pushing to `main` triggers ArgoCD auto-sync — **pushing is deploying**.

```
Edit locally → git commit → git push origin main → ArgoCD auto-sync → OKD cluster updated
```

> **Critical**: Never patch running deployments directly (`oc patch`, `kubectl edit`). ArgoCD will revert direct changes. Always modify manifests in this repo.

## Application Catalog

| Application | Namespace | Type | Description |
|-------------|-----------|------|-------------|
| ArgoCD | openshift-gitops | GitOps | Continuous delivery, app-of-apps controller |
| Backstage | backstage | Portal | Developer portal and service catalog |
| Grafana | monitoring | Observability | 11 dashboards, Keycloak OIDC |
| Harbor | harbor | Registry | Container images, vulnerability scanning |
| DefectDojo | defectdojo | Security | Application security management |
| Keycloak | keycloak | Identity | SSO/OIDC for all platform services |
| Kyverno | kyverno | Policy | OKD policy enforcement |
| Istio | istio-system | Mesh | Service mesh control plane |
| Jaeger | jaeger | Tracing | Distributed tracing |
| Kiali | kiali | Mesh UI | Service mesh observability |
| Homepage | homepage | Dashboard | Platform service dashboard |
| Seedbox | seedbox | Media | Download management |
| NetBox | netbox | IPAM | Network documentation |
| NFS Provisioner | nfs-provisioner | Storage | Dynamic PV provisioning |
| External Secrets | external-secrets | Secrets | Vault-to-K8s secret sync |
| Console | console | UI | OKD web console customization |

## Repository Structure

```
overwatch-gitops/
├── apps/                    # Application manifests
│   ├── argocd/              # ArgoCD configuration
│   ├── backstage/           # Backstage developer portal
│   ├── console/             # OKD console customization
│   ├── defectdojo/          # DefectDojo ASDB
│   ├── external-secrets/    # ESO + ClusterSecretStore
│   ├── harbor/              # Harbor container registry
│   ├── hello-world/         # Test application
│   ├── homepage/            # Platform homepage
│   ├── istio-controlplane/  # Istio service mesh
│   ├── jaeger/              # Distributed tracing
│   ├── keycloak/            # Identity provider
│   ├── kyverno-policies/    # Policy definitions
│   ├── mesh-config/         # Istio mesh configuration
│   ├── monitoring/          # Prometheus + Thanos
│   ├── netbox/              # Network documentation
│   ├── observability/       # Kiali + observability tools
│   └── seedbox/             # Download management
├── argocd/                  # App-of-apps definitions
├── backstage-catalog/       # Backstage catalog entities
├── clusters/                # Cluster-level configs
└── ci-templates/            # Shared CI templates
```

## Access

| Service | URL |
|---------|-----|
| ArgoCD | [argocd.208.haist.farm](https://argocd.208.haist.farm) |
| OKD Console | [console.208.haist.farm](https://console.208.haist.farm) |
| Grafana | [grafana.208.haist.farm](https://grafana.208.haist.farm) |

All services authenticate via Keycloak OIDC (`auth.208.haist.farm`).
