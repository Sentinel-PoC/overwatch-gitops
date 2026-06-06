# Deployment

## Helm Chart

Grafana is deployed via the official `grafana/grafana` Helm chart through ArgoCD.

| Property | Value |
|----------|-------|
| **Chart** | `grafana` from `https://grafana.github.io/helm-charts` |
| **Version** | 10.5.15 |
| **Values** | `clusters/overwatch/apps/monitoring/grafana/values.yaml` |
| **ArgoCD App** | `clusters/overwatch/apps/monitoring/grafana-app.yaml` |
| **Sync Policy** | Automated with prune and self-heal |

## Image Sources

All images are pulled from Harbor (air-gapped cluster):

| Image | Tag | Purpose |
|-------|-----|---------|
| `harbor.208.haist.farm/sentinel/grafana` | 12.4.0 | Main Grafana server |
| `harbor.208.haist.farm/sentinel/k8s-sidecar` | 1.28.0 | Dashboard ConfigMap watcher |

## Security Context

Runs as OKD-assigned UID `1000780000` with restricted capabilities:

- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ALL`
- `seccompProfile.type: RuntimeDefault`

## Resource Allocation

| | Requests | Limits |
|-|----------|--------|
| **CPU** | 250m | 500m |
| **Memory** | 256Mi | 512Mi |

Sidecar: 50m/64Mi requests, 100m/128Mi limits.

## Secrets Management

Secrets are injected via External Secrets Operator (ESO) from Vault:

| Secret | Vault Path | Contents |
|--------|-----------|----------|
| `grafana-admin-credentials` | `secret/grafana` | `admin_user`, `admin_password` |
| `grafana-prometheus-token` | (ExternalSecret) | Bearer token for Thanos Querier |
| `grafana-keycloak-secret` | (ExternalSecret) | OIDC client secret |

## Networking

- **OKD Route**: `grafana.208.haist.farm` with TLS reencrypt termination
- **Service port**: 3000 (named `service`)
- **Health check**: `GET /api/health` on port 3000

## Making Changes

All changes go through GitOps:

1. Edit `clusters/overwatch/apps/monitoring/grafana/values.yaml`
2. Commit to a branch, create MR
3. After merge to `main`, ArgoCD auto-syncs

**Never** modify Grafana configuration through the UI — ArgoCD will revert it.
