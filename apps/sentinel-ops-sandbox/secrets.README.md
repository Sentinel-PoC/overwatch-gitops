# Out-of-Band Secrets — sentinel-ops-sandbox

These Secrets are **never committed to git**. Apply them manually to the sandbox
cluster before running `kustomize build | kubectl apply` or before the first
ArgoCD sync.

---

## Why out-of-band?

The sandbox cluster does not yet have External Secrets Operator (ESO) wired to
Vault (tracked in OPS-289 — k8s-auth 403 blocker). Until OPS-289 resolves,
credentials are injected via static Secrets created with `kubectl create secret`.

---

## Secret 1: `etcd-backup-vault-creds`

**Namespace:** `sentinel-ops`

Holds the Vault workload token used by the etcd-backup script to authenticate
to Vault transit for DEK encryption. This bypasses the k8s-auth path (VAULT_TOKEN
env variable takes precedence over VAULT_K8S_ROLE in the script).

**Required key:**

| Key | Description |
|-----|-------------|
| `VAULT_TOKEN` | Vault token scoped to transit encrypt/decrypt for `etcd-backup-sandbox` key |

**Vault path for token:** `secret/etcd-backup-sandbox` → field `token`

> **Note:** As of OPS-278 authoring (2026-05-02), `secret/etcd-backup-sandbox`
> does not yet exist in Vault. The operator must create this path and a suitably
> scoped workload token before Judge can run the first backup test. The token
> must have policy: `transit/encrypt/etcd-backup-sandbox` + `transit/decrypt/etcd-backup-sandbox`.

**Apply command:**

```bash
# Fetch token from Vault (prod Vault, scoped policy)
VAULT_SANDBOX_TOKEN=$(vault kv get -field=token secret/etcd-backup-sandbox)

kubectl create secret generic etcd-backup-vault-creds \
  -n sentinel-ops \
  --from-literal=VAULT_TOKEN="${VAULT_SANDBOX_TOKEN}"
```

---

## Secret 2: `ops-minio-sandbox-creds`

**Namespace:** `sentinel-ops`

Holds MinIO credentials for the sandbox scoped user. The sandbox uses the same
MinIO primary endpoint as prod (`192.168.12.58:9000`) but a different bucket
(`etcd-backups-sandbox`) and a scoped IAM user.

**Required keys:**

| Key | Description | Source |
|-----|-------------|--------|
| `MINIO_ACCESS_KEY` | MinIO access key for sandbox user | `secret/minio-sandbox` → `access_key` |
| `MINIO_SECRET_KEY` | MinIO secret key for sandbox user | `secret/minio-sandbox` → `secret_key` |
| `MINIO_ENDPOINT` | MinIO endpoint URL | `secret/minio-sandbox` → `endpoint` |

**Vault path:** `secret/minio-sandbox`

**Apply command:**

```bash
MINIO_AK=$(vault kv get -field=access_key secret/minio-sandbox)
MINIO_SK=$(vault kv get -field=secret_key secret/minio-sandbox)
MINIO_EP=$(vault kv get -field=endpoint secret/minio-sandbox)

kubectl create secret generic ops-minio-sandbox-creds \
  -n sentinel-ops \
  --from-literal=MINIO_ACCESS_KEY="${MINIO_AK}" \
  --from-literal=MINIO_SECRET_KEY="${MINIO_SK}" \
  --from-literal=MINIO_ENDPOINT="${MINIO_EP}"
```

---

## Full Judge apply sequence

```bash
# 1. Apply kustomize manifests to sandbox cluster
KUBECONFIG=/tmp/kc kustomize build apps/sentinel-ops-sandbox/ | kubectl apply -f -

# 2. Apply out-of-band Secrets (fetch from prod Vault)
KUBECONFIG=/tmp/kc kubectl create secret generic etcd-backup-vault-creds \
  -n sentinel-ops \
  --from-literal=VAULT_TOKEN="$(vault kv get -field=token secret/etcd-backup-sandbox)"

KUBECONFIG=/tmp/kc kubectl create secret generic ops-minio-sandbox-creds \
  -n sentinel-ops \
  --from-literal=MINIO_ACCESS_KEY="$(vault kv get -field=access_key secret/minio-sandbox)" \
  --from-literal=MINIO_SECRET_KEY="$(vault kv get -field=secret_key secret/minio-sandbox)" \
  --from-literal=MINIO_ENDPOINT="$(vault kv get -field=endpoint secret/minio-sandbox)"

# 3. Trigger a one-off backup Job to verify end-to-end
KUBECONFIG=/tmp/kc kubectl create job etcd-backup-test-$(date +%s) \
  --from=cronjob/etcd-backup -n sentinel-ops

# 4. Wait for Job completion and check logs
KUBECONFIG=/tmp/kc kubectl wait --for=condition=complete job/etcd-backup-test-... \
  -n sentinel-ops --timeout=1800s
KUBECONFIG=/tmp/kc kubectl logs job/etcd-backup-test-... -n sentinel-ops

# 5. Verify snapshot in MinIO bucket etcd-backups-sandbox
mc alias set sandbox-minio http://192.168.12.58:9000 <access_key> <secret_key>
mc ls sandbox-minio/etcd-backups-sandbox/
```

---

## Cleanup note

When OPS-289 resolves (k8s-auth wired for sandbox), replace the static
`etcd-backup-vault-creds` Secret with an ESO `ExternalSecret` and remove
the `VAULT_TOKEN` env entry from the CronJob (set `VAULT_K8S_ROLE=etcd-backup-sandbox`
instead). Until then, the static Secret must be rotated manually when the token expires.
