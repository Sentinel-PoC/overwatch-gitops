# Secrets Management

## Overview

ArgoCD applications consume Kubernetes Secrets that are populated by **External Secrets Operator (ESO)** v0.11.0 from **HashiCorp Vault**. ArgoCD itself does not manage secrets directly -- it deploys ExternalSecret resources as part of application manifests, and ESO handles the Vault-to-K8s sync.

```
Vault (secret/*)
    |
    v
ClusterSecretStore (vault-backend)
    |
    v
ExternalSecret (per-namespace)
    |
    v
Kubernetes Secret (target)
    |
    v
Pod (env vars / volume mounts)
    |
    v  (optional)
Reloader (restarts pod on secret change)
```

## ClusterSecretStore

A single `ClusterSecretStore` named `vault-backend` serves all namespaces:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.208.haist.farm"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "vault-auth"
            namespace: "external-secrets"
```

**Authentication flow**: The `vault-auth` ServiceAccount in `external-secrets` namespace has a long-lived token (`vault-auth-token`). ESO uses this token for Kubernetes auth against Vault's `kubernetes` auth backend, bound to role `external-secrets`. A `ClusterRoleBinding` grants `system:auth-delegator` for TokenReview.

**Important**: The ClusterSecretStore and auth resources are NOT managed by ArgoCD's app-of-apps. They must be applied manually:

```bash
oc apply -f apps/external-secrets/
```

## ExternalSecrets by Namespace

### openshift-gitops (ArgoCD)

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `argocd-oidc-keycloak` | `argocd-secret` (Merge) | `secret/keycloak/argocd` | Keycloak OIDC client secret for ArgoCD SSO |
| `argocd-gitlab-repo` | `argocd-gitlab-repo` (Owner) | `secret/gitlab` | GitLab PAT for repo access (labeled `argocd.argoproj.io/secret-type: repository`) |

The OIDC secret uses `creationPolicy: Merge` to add the `oidc.keycloak.clientSecret` key to the existing `argocd-secret` without overwriting other fields. The repo secret uses `creationPolicy: Owner` with a template that adds the ArgoCD repo label.

### backstage

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `backstage-credentials` | `backstage-credentials` | `secret/backstage` | Backend secret, PostgreSQL creds, Keycloak OIDC |

### defectdojo

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `defectdojo-credentials` | `defectdojo` | `secret/defectdojo` | Django secret key, admin password, AES key, metrics auth |

### haists-website

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `haists-website-credentials` | `haists-website-credentials` | `secret/keycloak/haists-website`, `secret/haists-website` | OIDC client secret, contact email |

### harbor

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `harbor-credentials` | `harbor-credentials` | `secret/harbor` | Admin password, secret key |
| `harbor-database` | `harbor-database` | `secret/harbor` | PostgreSQL credentials |

### keycloak

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `keycloak-admin-credentials` | `keycloak-admin-credentials` | `secret/keycloak/admin` | Admin username + password |
| `postgresql-credentials` | `postgresql-credentials` | `secret/keycloak/postgresql` | PostgreSQL DB name, user, password |

### matrix

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `matrix-postgresql-credentials` | `matrix-postgresql-credentials` | `secret/matrix/postgresql` | PostgreSQL credentials |
| `synapse-credentials` | `synapse-credentials` | `secret/matrix/synapse` [VERIFY] | Synapse secrets |
| `mas-credentials` | `mas-credentials` | `secret/matrix/mas` | MAS encryption secret, shared secret, DB password |
| `mas-oidc-credentials` | `mas-oidc-credentials` | `secret/keycloak/synapse` [VERIFY] | Keycloak OIDC client secret for MAS |

### netbox

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `netbox-credentials` | `netbox-credentials` | `secret/netbox` | Secret key, admin password, API token, email password |

### overwatch-console

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `overwatch-console-credentials` | `overwatch-console-credentials` | `secret/keycloak/overwatch-console`, `secret/proxmox`, `secret/vault/root-token` | OIDC secret, Proxmox API token, Vault token |

### sentinel-ops

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `ops-wazuh-creds` | `ops-wazuh-creds` | `secret/wazuh/api` | Wazuh API username + password |
| `ops-minio-creds` | `ops-minio-creds` | `secret/minio` [VERIFY] | MinIO credentials |
| `ops-gitlab-creds` | `ops-gitlab-creds` | `secret/gitlab` [VERIFY] | GitLab PAT |
| `ops-proxmox-creds` | `ops-proxmox-creds` | `secret/proxmox` [VERIFY] | Proxmox API token |
| `ops-grafana-creds` | `ops-grafana-creds` | `secret/grafana` [VERIFY] | Grafana API key |

### pangolin-internal

| ExternalSecret | Target Secret | Vault Path | Purpose |
|----------------|---------------|------------|---------|
| `newt-tunnel-credentials` | `newt-tunnel-newt-main-tunnel` | `secret/newt` | Newt WireGuard tunnel secret |

## Refresh Intervals

| Interval | Applications |
|----------|-------------|
| 30m | ArgoCD GitLab repo secret |
| 1h | All other ExternalSecrets |

## Stakater Reloader Integration

Reloader v1.3.0 watches for Secret changes and triggers rolling restarts on pods that reference them. This is critical for the ESO workflow -- when Vault secrets rotate and ESO refreshes the K8s Secret, Reloader ensures pods pick up the new values without manual intervention.

To enable Reloader for a Deployment, add the annotation:

```yaml
metadata:
  annotations:
    secret.reloader.stakater.com/reload: "secret-name"
```

Or for ConfigMaps:

```yaml
metadata:
  annotations:
    configmap.reloader.stakater.com/reload: "configmap-name"
```

## ESO Troubleshooting

### Backoff Recovery

If an ExternalSecret enters backoff (e.g., Vault temporarily unavailable), force a reconciliation:

```bash
oc annotate externalsecret <name> -n <namespace> \
  reconcile.external-secrets.io/trigger=$(date +%s)
```

### Checking Secret Status

```bash
# List all ExternalSecrets and their sync status
oc get externalsecrets -A

# Check specific ExternalSecret conditions
oc get externalsecret <name> -n <namespace> -o jsonpath='{.status.conditions}'
```

### ArgoCD ignoreDifferences for ExternalSecrets

ArgoCD's SSA reorders `data[]` entries in ExternalSecret specs, causing perpetual OutOfSync. All apps with ExternalSecrets include `ignoreDifferences` for the ExternalSecret kind (see Sync Policies page). Adding `RespectIgnoreDifferences=true` ensures the ignored fields are truly excluded during sync, not just during diff display.

### Adding New ExternalSecret Fields

When adding new `data` entries to an existing ExternalSecret, ArgoCD's `ignoreDifferences + RespectIgnoreDifferences` may block the new entries from syncing (because the entire `.spec.data[]?.remoteRef` is ignored). Workaround: manually apply the updated ExternalSecret with `oc apply`, then ArgoCD will track the new live state.
