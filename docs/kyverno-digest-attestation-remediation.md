# Kyverno Digest + Attestation Remediation Design

**Issue:** OPS-1165  
**Worker:** worker/OPS-1165-digest-attest-design  
**Date:** 2026-06-03  
**Status:** Design + pilot committed; policies remain Audit (no flip to Enforce)

---

## 1. Background — Violation Accounting

Live cluster (2026-06-03, PolicyReport):

| Policy | Violations | Mode |
|--------|-----------|------|
| `require-image-digest` | 552 | Audit |
| `verify-attestations` | 543 | Audit |

**Why 552 violations from ~48 tag-based image references?**

Kyverno autogen creates sibling rules for every workload controller kind
(Deployment, StatefulSet, ReplicaSet, DaemonSet, Job, CronJob) in addition to
the base Pod rule. Each running resource that contains a tag-based image
generates one violation entry. A single image in a Deployment produces
violations against: Deployment, ReplicaSet, and individual Pod objects.

**Distinct tag-based images (actual root causes — 48 total):**

| Category | Count | Examples |
|----------|-------|---------|
| Istio injected sidecars | ~55 slots / 3 images | `registry.istio.io/release/proxyv2:1.28.3` (inject-time, not in gitops) |
| Helm chart images (external registries) | ~25 images | `docker.io/goharbor/*:v2.14.2`, `ghcr.io/kyverno/*:v1.13.2`, `quay.io/jetstack/*` |
| Harbor sentinel/* images via Helm values | ~12 images | `sentinel/langfuse:3.169.0`, `sentinel/valkey:7.2.12-alpine3.23`, `sentinel/minio:latest` |
| Operator-deployed images (sail-operator, jaeger-operator, cert-manager) | ~8 images | `quay.io/sail-dev/sail-operator:1.30.0` |

**What is already digest-pinned:** All custom deployment.yaml files for
platform-built apps (haists-website, cfwc-website, overwatch-console, scanopy,
backstage, etc.) use `@sha256:` references. The plane app uses patch YAMLs
(`plane-web-cmd-patch.yaml`, `plane-api-stability-patch.yaml`, etc.) to
override Helm chart tag-based images with digest references for the main
application containers. The remaining violations are infrastructure images.

---

## 2. Category Analysis and Chosen Approach

### 2.1 Category A: Our CI-built images (sentinel/*)

**Current state:** Build pipeline (build-sentinel-ops.yml, build-netbox-acls.yml,
overwatch-console build.yml) already:
1. Pushes image, captures digest from `buildah push --digestfile`
2. Signs image via `cosign sign` (OCI 1.1 Referrers)
3. Attests SLSA v1.0 provenance via `cosign attest`
4. Updates gitops manifest with `harbor/.../image@sha256:digest` via
   `update-gitops` composite action (OPS-1074 mode)

**Gap:** Some sentinel/* images deployed via Helm chart values use `:tag`
because the Helm chart template hardcodes `repository:tag` format and the
values files predate OPS-1074.

**Chosen approach: Digest in Helm values (direct image string override)**

The plane Helm chart uses sentinel/* images for minio/rabbitmq/valkey as
full strings (`image: harbor.../sentinel/valkey:tag`). The chart passes
these verbatim to pod specs. We can replace `:tag` with `@sha256:digest`
directly in values.yaml — the chart does not append a tag for these
infrastructure components.

For Helm charts where the template hardcodes `repository:tag` format and
the digest cannot be expressed in values (e.g. langfuse chart:
`image: "{{ .Values.web.image.repository }}:{{ .Values.image.tag }}"`),
the established pattern on this platform is to use **ArgoCD/kustomize
patch YAMLs** that override the generated pod spec image field (see
`apps/plane/plane-web-cmd-patch.yaml` for the precedent).

**Rollout sequence for Category A:**
1. For Helm charts that accept a full image string: update `image:` field
   to `@sha256:` form directly in values (piloted here for plane minio/rabbitmq/valkey)
2. For Helm charts that template `repo:tag` separately: add patch YAML per
   the plane precedent (see §5 sub-issues)
3. When images are rebuilt: CI update-gitops action already writes digest
   via OPS-1074 for custom-built images; Helm chart images updated manually
   or via Renovate digest pinning

### 2.2 Category B: Istio sidecar images

**Root cause:** Istio control plane injects `registry.istio.io/release/proxyv2:1.28.3`
sidecars at pod admission time. The tag comes from the IstioOperator CR, not
from any gitops manifest. 55 of the 552 violations come from ~18 meshed pods
each having the proxyv2 sidecar appear in their PolicyReport.

**Chosen approach: Exclude Istio system namespaces + sidecar image prefix**

The `require-image-digest` policy already excludes `openshift-*` namespaces.
The remaining Istio sidecar violations come from user-workload namespaces
where pods are mesh-injected. The solution is a Kyverno policy exception
(`PolicyException`) scoped to the Istio proxy image prefix, or to update
the IstioOperator to reference the Sail-managed image by digest via the
Sail operator's `IstioRevisionTag` or `Istio` CR.

**Recommended:** File OPS-1167 (Istio/Sail) to configure the Sail operator
to reference `registry.istio.io/release/proxyv2` by digest in the
`MeshConfig`/`IstioOperator`. This is non-trivial (requires understanding
which Sail CR field controls the sidecar image reference) and is a separate
rollout from digest-pinning our own images.

Short-term: add a `PolicyException` for `registry.istio.io/release/*` images
to reduce noise while the Sail operator digest-pinning is designed.

### 2.3 Category C: Third-party Helm chart images (goharbor, kyverno, cert-manager, etc.)

**Root cause:** Helm charts for Harbor, Kyverno, cert-manager, loki, jaeger,
external-secrets etc. pull images from upstream registries using tags. These
are managed by Renovate (OPS-855), which bumps chart versions on CVE alerts.

**Chosen approach: Renovate digest pinning + Kyverno PolicyException**

Two sub-approaches depending on urgency:

**(a) PolicyException for trusted Helm chart registries (short-term):**
Kyverno `PolicyException` can exempt specific image prefixes or namespaces
from `require-image-digest` with a comment linking to the tracking issue.
This removes noise while the longer-term solution is built.

**(b) Renovate digest manager (medium-term — OPS-1168):**
Renovate supports a `docker-digest` manager that creates PRs to pin images
to `@sha256:` in Helm values. Enable it in `renovate.json5` with:
```json
{
  "digest": { "enabled": true },
  "packageRules": [{ "matchManagers": ["argocd", "helm-values"], "pinDigests": true }]
}
```
This produces automated PRs pinning every `docker.io/goharbor/*:v2.14.2`
to `docker.io/goharbor/*:v2.14.2@sha256:abc123`. Requires testing that
Renovate's Helm values manager correctly identifies image fields in our
values.yaml structure.

**(c) Mirror to Harbor sentinel/* (long-term — existing supply-chain initiative):**
`mirror-upstream-image.sh` signs + attests mirrored images. Migrating
all Helm chart images to `harbor.208.haist.farm/sentinel/` mirrors would
allow both `require-image-digest` (digest-pinned) and `verify-attestations`
(signed+attested) to pass for ALL images. This is the full
`project_supply_chain_admission` goal and is tracked separately.

---

## 3. verify-attestations — Design

### 3.1 What the policy checks

`verify-attestations` ClusterPolicy (SEC-62) checks pods whose images match
`harbor.208.haist.farm/sentinel/*` for SLSA v1.0 provenance attestations:

```yaml
attestations:
  - predicateType: https://slsa.dev/provenance/v1
    conditions:
      - all:
          - key: "{{ predicate.runDetails.builder.id }}"
            operator: AnyIn
            value:
              - "https://forgejo.208.haist.farm/sentinel-admin/sentinel-iac/actions/runner"
              - "https://forgejo.208.haist.farm/sentinel-admin/overwatch-console/actions/runner"
              - "https://forgejo.208.haist.farm/sentinel-admin/overwatch-gitops/actions/runner"
```

Required: `required: true`, `imageReferences: ["harbor.208.haist.farm/sentinel/*"]`

### 3.2 Current pipeline state

The `attest` composite action (`.forgejo/actions/attest/action.yml`, OPS-701)
is already wired into:
- `build-sentinel-ops.yml` (sentinel/sentinel-ops images)
- `build-netbox-acls.yml` (sentinel/netbox-with-acls images)
- `overwatch-console/build.yml` (sentinel/overwatch-console images)

The attest composite:
- Generates SLSA v1.0 predicate via `generate-slsa-predicate.py`
- Calls `cosign attest --type slsaprovenance1 --tlog-upload=false --replace`
- Stores attestation as legacy `sha256-XXX.att` tag (OCI 1.1 not supported
  by cosign attest at any released version — operator decision OPS-701)
- Attestation `builder.id` = `https://forgejo.208.haist.farm/$REPO/actions/runner`
- Attestation `externalParameters.source.repository` = Forgejo repo URL

### 3.3 Why 543 violations remain

The 543 violations are because:
1. Most `harbor.208.haist.farm/sentinel/*` images were mirrored upstream
   (valkey, rabbitmq, minio, grafana, langfuse, etc.) and never went through
   the Forgejo Actions build+attest pipeline
2. The attest composite adds attestations only when CI builds an image —
   mirrored images have no SLSA provenance because no Forgejo Actions job
   built them
3. Images built before OPS-701 (before 2026-05-16) may have been signed
   but not attested

### 3.4 Remediation path — two tracks

**Track 1: New builds (zero-new-work)**
All future CI builds via `build-sentinel-ops.yml`, `build-netbox-acls.yml`,
`overwatch-console/build.yml` already emit attestations. No change needed
for the CI pipeline for these repos.

Additional repos that need the attest composite wired in for their builds:
- Any workflow that builds `harbor.208.haist.farm/sentinel/*` images but
  does not yet call `.forgejo/actions/attest`
- Check: `sign-harbor-image.yml` explicitly documents it does NOT attest
  mirrored images (correct — no build provenance to attest)

**Track 2: Mirrored images (requires new workflow — OPS-1169)**

For mirrored upstream images (`sentinel/langfuse`, `sentinel/valkey`,
`sentinel/minio`, etc.) there is no Forgejo Actions build job, so the
`runDetails.builder.id` cannot truthfully claim a Forgejo runner built it.

Options:
1. **Add `mirror-and-attest` workflow:** When mirroring an image,
   run a Forgejo Actions job that: (a) pulls upstream image,
   (b) re-tags to `harbor.../sentinel/`, (c) pushes, (d) attests with
   a special `buildType` = `https://forgejo.208.haist.farm/mirror@v1`
   and `externalParameters.source.repository` = upstream source.
   Then update `verify-attestations` policy to also allow the mirror
   builder ID.

2. **Kyverno PolicyException for mirror images:** Scope `verify-attestations`
   to only apply to images built by our CI (e.g., add an annotation
   `sentinel.haist.farm/build-origin: ci` to images attested by our CI),
   and exempt mirrored images via PolicyException.

3. **Accept 543 violations for Audit-only:** Since `verify-attestations` is
   Audit-mode and there is no plan to flip it to Enforce until a remediation
   plan exists, the violations are informational. The actionable work is
   Track 1 (new builds) + designing Track 2 for the sub-issue.

**Recommended:** Implement option 2 (Kyverno PolicyException for mirror images
identified by image prefix pattern) as short-term noise reduction, file OPS-1169
for `mirror-and-attest` workflow as the sustainable solution.

### 3.5 Adding attest to additional build workflows

Any Forgejo Actions workflow that builds and pushes to `sentinel/*` but does
not yet call the attest composite needs the following added after the `sign`
step:

```yaml
- name: Attest (SLSA v1.0 + SBOM, legacy .att tag)
  uses: ./.forgejo/actions/attest
  with:
    image-ref: ${{ env.HARBOR_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
    cosign-key: ${{ secrets.COSIGN_KEY }}
    cosign-password: ${{ secrets.COSIGN_PASSWORD || '' }}
    sbom-file: sbom.cyclonedx.json
```

The `builder.id` field in `generate-slsa-predicate.py` is constructed as:
`https://forgejo.208.haist.farm/$GITHUB_REPOSITORY/actions/runner`

For this to satisfy the Kyverno policy condition, the repo must be in the
`verify-attestations` allowlist. Current allowlist:
- `sentinel-admin/sentinel-iac`
- `sentinel-admin/overwatch-console`
- `sentinel-admin/overwatch-gitops`

If new build repos are added (e.g., a dedicated `sentinel-admin/sentinel-images`
repo for mirroring), the `verify-attestations` policy must be updated to add
the new builder ID. Track in OPS-1169.

---

## 4. Pilot — Plane Infrastructure Images

**Pilot scope:** Pin `minio`, `rabbitmq`, and `valkey` images in
`clusters/overwatch/apps/plane/values.yaml` to digest form.

**Why this pilot:**
- The plane Helm chart passes these image values verbatim to pod specs
  (template: `image: {{ .Values.redis.image }}`) — digest form works
  without needing a patch YAML
- These 3 images account for 3 of the 48 distinct tag-based image refs
- Piloting in `plane` namespace (86 violations, largest count) gives
  maximum signal on the approach

**Digest values pinned (Harbor, 2026-06-03):**

| Image | Tag | Digest |
|-------|-----|--------|
| `sentinel/valkey` | `7.2.12-alpine3.23` | `sha256:db7675f9627ab5ea395dcfc817bfc332a4d6757f96782856c3d0e13def8557b5` |
| `sentinel/rabbitmq` | `3.13.7-management-alpine` | `sha256:dd304be0d945869c49ff122ea898d3a1460e5d7a207e661e831572bae4d51992` |
| `sentinel/minio` | `latest` | `sha256:a614d3fd833e346ab37cd0ff0c540f88d5d7ed0d6f0034b20418bb91e1769a51` |
| `sentinel/mc` | `latest` | `sha256:dce495b4f330bf87354c62743e06c3c7d68eedd23f8f94853a441931469cebdb` |

**Change:** `clusters/overwatch/apps/plane/values.yaml` — `redis.image`,
`rabbitmq.image`, `minio.image`, `minio.image_mc` updated to `@sha256:` form.

**Expected effect:** After ArgoCD reconciles (~3 min):
- `plane-redis-wl-0`, `plane-rabbitmq-wl-0`, `plane-minio-wl-0` pods
  restart with digest-pinned images
- PolicyReport violations in `plane` namespace drop by ~3 violations
  (one per statefulset, reduced by the autogen multiplier)
- The 83 other violations in `plane` namespace from Helm-generated
  app containers (plane-admin, plane-space, plane-backend) are handled
  separately via existing patch YAMLs — this pilot does not touch those

**Important caveat on `minio:latest`:**
The `latest` tag is not reproducible. Pinning by digest at time T means
future security patches to minio will NOT be applied until the digest is
manually updated. File OPS-1170 to track minio version management
and switch from `:latest` to a versioned tag.

**Rollback:** Revert to tag form in values.yaml. ArgoCD will reconcile within 3 min.

---

## 5. Staleness Problem and Sustainable Digest Management

### 5.1 The core tension

Digest-pinning ensures immutability but creates staleness: a pinned digest
cannot receive upstream security patches unless the pin is explicitly updated.
552 violations cannot be fixed by "hand-pin 552 digests" because those pins
go stale every time an image is rebuilt.

### 5.2 Sustainable approaches by image category

**Category A: Our CI-built images**
Already sustainable. The `update-gitops` composite action (OPS-1074) writes
`@sha256:digest` on every CI build. New builds automatically update the pin.

**Category B: Istio sidecar**
Sustainable through Sail operator digest configuration. When Sail operator
upgrades Istio (e.g., 1.28.3 → 1.29.x), the sidecar image changes. The
Sail CR should reference the new image by digest. File OPS-1167.

**Category C: Helm chart images (minio, rabbitmq, valkey, langfuse, etc.)**
These need either:
1. **Renovate digest manager** (OPS-1168): Renovate `pinDigests: true`
   creates automated PRs that pin Helm image values to `@sha256:` AND
   update the digest when upstream releases a new tag. This is the most
   sustainable approach — each chart version bump re-pins the digest.
2. **Harbor mirroring pipeline** (existing supply-chain initiative):
   `mirror-upstream-image.sh` re-signs images. Add a step that also
   updates the gitops values file digest after mirroring (OPS-1169).

**Category D: Operator-managed images (harbor itself, OLM operators)**
Harbor's own images (`docker.io/goharbor/*`) are managed by the Harbor
Helm chart. These can be pinned by digest in the Harbor chart values
(`clusters/overwatch/apps/harbor/values.yaml`). Renovate digest manager
handles updates. File OPS-1171.

---

## 6. Rollout Sequence (proposed sub-issues)

The 552 violations break down into logical work packages:

| Sub-issue | Scope | Approach | Blast radius |
|-----------|-------|---------|--------------|
| OPS-1166 | Plane minio/rabbitmq/valkey digest pilot | values.yaml edit (THIS PR) | 3 images, ~3 violations → 0 |
| OPS-1167 | Istio sidecar digest pinning via Sail operator | IstioRevisionTag/MeshConfig | 55 slots, many namespaces |
| OPS-1168 | Renovate digest manager for Helm chart images | renovate.json5 + packageRules | All Helm-deployed images |
| OPS-1169 | mirror-and-attest workflow for mirrored images | New CI workflow + policy update | verify-attestations for sentinel/* mirrors |
| OPS-1170 | Replace minio:latest with versioned tag + rotate digest | values.yaml + Harbor | sentinel/minio image management |
| OPS-1171 | Harbor self-image digest pinning | Harbor chart values.yaml | harbor ns violations |

**Ordering rationale:**
1. OPS-1166 (this PR): pilot proves the approach works; low risk
2. OPS-1167: reduces ~10% of violations (Istio sidecars) without touching our images
3. OPS-1168: highest leverage — Renovate handles the long tail of Helm chart images
4. OPS-1169: prerequisite for flipping verify-attestations to Enforce in future
5. OPS-1170, OPS-1171: cleanup items after larger wins are in

**Timeline to Enforce (require-image-digest):**
`require-image-digest` should NOT be flipped to Enforce until ALL of the following are true:
- OPS-1167 done (Istio sidecars no longer violate)
- OPS-1168 done and running for at least one Renovate cycle (digest PRs merged)
- A dedicated PolicyException exists for any legitimately non-pinnable images
  (e.g., OLM index images that rotate frequently)
- Zero violations in PolicyReport for 24h sustained

---

## 7. Files Modified in This PR

- `clusters/overwatch/apps/plane/values.yaml` — pilot: digest-pin minio, rabbitmq, valkey
- `docs/kyverno-digest-attestation-remediation.md` — this document

Files NOT modified (scope boundary):
- `apps/kyverno-policies/require-image-digest.yaml` — stays Audit, no flip
- `apps/kyverno-policies/verify-attestations.yaml` — stays Audit, no flip
- Any other workload files (other app namespaces are out of scope for this pilot)

---

## 8. Verification Commands

After PR merge and ArgoCD sync (~3 min):

```bash
# Check plane pods restarted with digest images
kubectl get pods -n plane -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Verify PolicyReport violations in plane namespace (expect ~3 fewer)
kubectl get policyreport -n plane -o json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('plane violations:', len([v for r in d.get('items',[]) for v in r.get('results',[]) if v.get('result')=='fail' and v.get('policy')=='require-image-digest']))"
```

Expected: `plane-redis-wl-0`, `plane-rabbitmq-wl-0`, `plane-minio-wl-0` show
`harbor.208.haist.farm/sentinel/valkey@sha256:...`,
`harbor.208.haist.farm/sentinel/rabbitmq@sha256:...`,
`harbor.208.haist.farm/sentinel/minio@sha256:...` respectively.
