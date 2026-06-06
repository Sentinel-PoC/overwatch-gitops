# Deployment

## ArgoCD Application

Keycloak is managed by ArgoCD as part of the app-of-apps pattern.

**ArgoCD App definition**: `clusters/overwatch/apps/keycloak-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: http://192.168.12.68/admin1/overwatch-gitops.git
    targetRevision: main
    path: apps/keycloak
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Key properties:

- **Auto-sync enabled** with prune and self-heal -- any manual changes in the cluster are reverted automatically.
- **Source**: `apps/keycloak/` directory in `overwatch-gitops` repo on `main` branch.
- **Kustomize-based**: manifests are assembled via `kustomization.yaml`.

## Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: keycloak
  labels:
    istio-injection: disabled
```

Istio sidecar injection is **disabled** for this namespace. Keycloak routes through the OKD Router (not the Istio IngressGateway) because it is part of the authentication infrastructure that other meshed services depend on.

## Manifest Inventory

All manifests reside in `apps/keycloak/`:

| File | Resource | Purpose |
|------|----------|---------|
| `namespace.yaml` | Namespace | Creates `keycloak` ns with istio-injection disabled |
| `rbac.yaml` | ServiceAccount, RoleBinding | PostgreSQL SA with `anyuid` SCC |
| `keycloak-admin-external-secret.yaml` | ExternalSecret | Admin credentials from Vault |
| `postgresql-external-secret.yaml` | ExternalSecret | DB credentials from Vault |
| `postgresql-pvc.yaml` | PVC | 10Gi NFS storage for PostgreSQL data |
| `postgresql-deployment.yaml` | Deployment | PostgreSQL 16.8 database |
| `postgresql-service.yaml` | Service | PostgreSQL ClusterIP on 5432 |
| `theme-configmap.yaml` | ConfigMap | Custom Sentinel login theme |
| `keycloak-deployment.yaml` | Deployment | Keycloak 26.1.4 application |
| `keycloak-service.yaml` | Service | Keycloak ClusterIP on 8080 + 9000 |
| `keycloak-route.yaml` | Route | OKD Route for `auth.208.haist.farm` |
| `network-policies.yaml` | NetworkPolicy (x4) | Zero-trust network segmentation |

## Keycloak Deployment

**Image**: `harbor.208.haist.farm/sentinel/keycloak:26.1.4`

**Replicas**: 1

**Startup arguments**: `start --optimized=false`

**Ports**:

- `8080` (http) -- application traffic
- `9000` (management) -- health checks and metrics

**Resource allocation**:

| | CPU | Memory |
|---|-----|--------|
| Requests | 2 | 2Gi |
| Limits | 2 | 2Gi |

**Environment variables** (from manifest):

| Variable | Value / Source |
|----------|---------------|
| `KC_DB` | `postgres` |
| `KC_DB_URL` | `jdbc:postgresql://postgresql:5432/keycloak` |
| `KC_DB_USERNAME` | Secret `postgresql-credentials` key `POSTGRES_USER` |
| `KC_DB_PASSWORD` | Secret `postgresql-credentials` key `POSTGRES_PASSWORD` |
| `KC_HOSTNAME_STRICT` | `false` |
| `KC_PROXY_HEADERS` | `xforwarded` |
| `KC_HTTP_ENABLED` | `true` |
| `KC_HEALTH_ENABLED` | `true` |
| `KC_METRICS_ENABLED` | `true` |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | Secret `keycloak-admin-credentials` key `KEYCLOAK_ADMIN` |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | Secret `keycloak-admin-credentials` key `KEYCLOAK_ADMIN_PASSWORD` |
| `KC_SPI_USER_CACHE_DEFAULT_ENABLED` | `false` (cache disabled) |
| `KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_SUCCESS_LEVEL` | `info` |
| `KC_SPI_EVENTS_STORE_PROVIDER` | `jpa` |
| `KC_SPI_EVENTS_STORE_JPA_MAX_DETAIL_LENGTH` | `1000` |

Notable settings:

- **User cache disabled** (`KC_SPI_USER_CACHE_DEFAULT_ENABLED=false`) -- ensures immediate consistency for user/group changes at the cost of slightly higher DB load.
- **Event storage via JPA** -- login events are persisted to PostgreSQL for audit trail, with detail truncated at 1000 characters.
- **Proxy headers mode** (`xforwarded`) -- trusts `X-Forwarded-*` headers from the OKD Router/Traefik. Required since TLS is terminated at the Route, not at Keycloak.

**Health probes**:

| Probe | Path | Port | Initial Delay | Period | Failure Threshold |
|-------|------|------|---------------|--------|-------------------|
| Readiness | `/health/ready` | 9000 | 90s | 10s | 15 |
| Liveness | `/health/live` | 9000 | 120s | 30s | 10 |

**Security context**:

- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- All capabilities dropped

**Volume mounts**:

- Custom theme `theme.properties` mounted at `/opt/keycloak/themes/sentinel/login/theme.properties`
- Custom CSS `sentinel.css` mounted at `/opt/keycloak/themes/sentinel/login/resources/css/sentinel.css`

## PostgreSQL Deployment

**Image**: `harbor.208.haist.farm/sentinel/postgres:16.8`

**Replicas**: 1

**Strategy**: `Recreate` (not rolling -- ensures single writer on PVC)

**PostgreSQL tuning arguments**:

```
shared_buffers=256MB
effective_cache_size=1GB
maintenance_work_mem=128MB
work_mem=16MB
```

**Resource allocation**:

| | CPU | Memory |
|---|-----|--------|
| Requests | 500m | 2Gi |
| Limits | 2 | 4Gi |

**Storage**: 10Gi PVC on `nfs-storage` StorageClass, mounted at `/var/lib/postgresql/data` with `PGDATA=/var/lib/postgresql/data/pgdata`.

**Probes** (all use `pg_isready -U keycloak -d keycloak`):

| Probe | Failure Threshold | Period |
|-------|-------------------|--------|
| Startup | 360 | 10s (up to 60 min for WAL recovery) |
| Readiness | default | 10s |
| Liveness | default | 10s |

**RBAC**: Uses ServiceAccount `postgresql-sa` bound to `system:openshift:scc:anyuid` ClusterRole (PostgreSQL image requires running as specific UID).

## Secrets Management

Both secrets are sourced from HashiCorp Vault via ExternalSecrets Operator (ESO).

### Keycloak Admin Credentials

```
ExternalSecret: keycloak-admin-credentials
Vault path:    secret/keycloak/admin
Properties:    username, password
Refresh:       1h
Store:         ClusterSecretStore vault-backend
```

### PostgreSQL Credentials

```
ExternalSecret: postgresql-credentials
Vault path:    secret/keycloak/postgresql
Properties:    db_name, db_user, db_password
Refresh:       1h
Store:         ClusterSecretStore vault-backend
```

Both use `creationPolicy: Owner`, meaning the ESO-created Secret is garbage-collected if the ExternalSecret is deleted.

## Custom Login Theme

The `keycloak-sentinel-theme` ConfigMap deploys a custom "Project Sentinel" login theme:

- **Parent theme**: `keycloak` (inherits all default login pages)
- **Custom CSS**: Dark background (`#0a0e17`) with animated grid overlay, floating gradient particles, emerald green accent (`#10b981`), glassmorphism login card with backdrop blur, custom scrollbar styling.
- **Responsive**: Adjusted layout for screens under 768px width.

The theme is mounted into the Keycloak container at `/opt/keycloak/themes/sentinel/login/`. To activate it, the `sentinel` realm must have its login theme set to `sentinel` in the Keycloak admin console.

## Network Policies

Four NetworkPolicies enforce zero-trust networking:

### 1. default-deny-all

Denies all ingress and egress for every pod in the namespace. All other policies are explicit allowlists.

### 2. allow-keycloak

For pods with `app: keycloak`:

- **Ingress**: Port 8080 TCP from the OpenShift ingress namespace (policy-group label)
- **Egress**: Port 5432 TCP to PostgreSQL pods, DNS (53/5353 UDP+TCP to any namespace), SMTP port 587 TCP to external IPs (Mailjet -- excludes RFC1918 ranges)

### 3. allow-postgresql

For pods with `app: postgresql`:

- **Ingress**: Port 5432 TCP only from Keycloak pods
- **Egress**: DNS only (53/5353 UDP+TCP)

### 4. allow-istio-control-plane

For all pods in namespace:

- **Egress**: Istio control plane ports (15010, 15012, 15014 TCP to `istio-system`, 15021 TCP to `istio-ingress`)
- Present despite `istio-injection: disabled` to allow any future mesh integration without policy changes.

## OKD Route

```yaml
host: auth.208.haist.farm
tls:
  termination: edge
  insecureEdgeTerminationPolicy: Redirect
```

- TLS is terminated at the OKD Router (edge termination).
- HTTP requests are redirected to HTTPS.
- The route targets the `keycloak` Service on port 8080.

## Backstage Catalog Entry

Keycloak is registered in the Backstage service catalog:

- **Component**: `keycloak` (type: service, lifecycle: production, owner: platform-team)
- **Dependency**: `keycloak-postgresql`
- **Provides API**: `keycloak-oidc-api`
- **Labels**: `identity`, `sso`, `oidc`, `security`, `overwatch`
- **ArgoCD annotation**: `argocd/app-name: keycloak`
- **Kubernetes selector**: `app=keycloak` in namespace `keycloak`
