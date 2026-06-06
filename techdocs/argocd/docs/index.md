# ArgoCD Operations

## Overview

ArgoCD is the GitOps continuous delivery engine for Project Sentinel's OKD 4.19 cluster ("Overwatch"). It runs on **OpenShift GitOps** via `argocd-operator v0.17.0`, deploying ArgoCD **v3.1.11** in the `openshift-gitops` namespace.

**Dashboard**: [argocd.208.haist.farm](https://argocd.208.haist.farm) (OKD Route, TLS reencrypt)

### What ArgoCD Manages

ArgoCD manages **22 applications** across the Overwatch cluster using an **app-of-apps** pattern. A single root application (`root-app`) watches the `clusters/overwatch/` directory tree in the `overwatch-gitops` GitLab repository and automatically creates/updates child Application resources.

The managed workloads span:

- **Platform services**: Keycloak (IdP), Harbor (container registry), Grafana (observability), DefectDojo (AppSec), NetBox (IPAM), Backstage (developer portal)
- **Security & policy**: Kyverno policies, Falco (runtime security), Reloader (secret rotation restarts)
- **Applications**: Overwatch Console (SecOps dashboard), Haists Website (public site), Matrix (chat), Homepage
- **Media**: Sonarr/Radarr/Prowlarr run on seedbox VM (see OPS-268); Jellyfin migrated to LXC (see OPS-495, OPS-610)
- **Infrastructure**: NFS provisioner, static storage (PVs/StorageClass), Pangolin internal (Traefik ingress), Newt tunnel
- **Operations**: Sentinel-Ops (CronJobs for compliance, health checks, replication)
- **Monitoring**: Grafana + Grafana Dashboards (sidecar ConfigMaps)

### GitOps-Only Workflow

All changes to cluster workloads MUST go through Git:

```
Edit manifests locally --> git commit --> git push origin main --> ArgoCD auto-sync --> OKD updated
```

**Never patch running deployments directly** (`oc patch`, `kubectl edit`, `oc set`). ArgoCD's self-heal will revert direct changes within minutes.

**Sole exception**: `pangolin-internal` was historically applied via `oc apply` but is now managed by the app-of-apps root-app. The `external-secrets` ClusterSecretStore and operator config are NOT in the app-of-apps and require manual `oc apply -f apps/external-secrets/`.

### Source Repository

| Property | Value |
|----------|-------|
| GitLab repo | `admin1/overwatch-gitops` (Project 3) |
| URL | `http://192.168.12.68/admin1/overwatch-gitops.git` |
| Branch | `main` (auto-sync target) |
| CI pipeline | Lint (yamllint) + Security (trivy-config, gitleaks) -- validation only, no deploy stage |
| Scan results | Uploaded to DefectDojo (`defectdojo.208.haist.farm`) |

### Air-Gapped Constraints

The OKD cluster has **no internet egress**. This affects ArgoCD operations:

- Container images must exist in Harbor (`harbor.208.haist.farm`)
- Helm charts from external registries (Grafana, Harbor, DefectDojo, NetBox, NFS, Traefik) are fetched by ArgoCD through iac-control's Squid proxy -- but only during sync
- Grafana dashboards must use inline JSON, not `gnetId` references (silently fail)
- External webhook/API references will fail silently
