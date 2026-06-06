# `.forgejo/actions` — Composite Action Catalogue

> **OPS-701** — Phase B: modular refactor of the `security-scan` monolith.
> **Research basis:** OPS-699 Phase A (`/tmp/ops-sweep/RESEARCH-OPS-699.md`).

---

## Why We Split

The original `security-scan/` composite bundled SBOM generation, OSV scanning,
language audit, DefectDojo upload, SLSA provenance generation, and cosign signing
under **one `set -euo pipefail` scope**. This caused 4 sequential layer-bugs (OPS-696
layers 4–7) — each bug cascaded into the next because unrelated concerns shared a
single error handler.

**Root design patterns (OPS-699 §4) that enabled the bug chain:**

| Pattern | Effect |
|---------|--------|
| Coupled concerns: scan + report + sign under one error handler | DefectDojo DNS failure skipped cosign sign (layer 4) |
| Inline Python in bash heredoc | Predicate structure bugs hard to test in isolation (layers 5–6) |
| Global `set -euo pipefail` at step level | Non-critical failures cascade to critical steps |
| Hardcoded predicate type and OCI upload mode | `--type slsaprovenance` (v0.2) mismatch vs v1.0 predicate (layer 5); no OCI 1.1 accessory linkage (layer 7) |

The refactor gives each concern its own composite with its own failure policy.

---

## Composite Directory Map

```
.forgejo/actions/
├── README.md                 ← this file
├── security-scan/            ← LEGACY — do not add to; consumers are migrating away
│   └── action.yml
├── scan/                     ← OPS-701 PR 2: SBOM + OSV + language audit
│   └── action.yml
├── sign/                     ← OPS-701 PR 3: cosign sign (OCI 1.1 referrers-mode)
│   └── action.yml
├── attest/                   ← OPS-701 PR 4: SLSA + SBOM attestation (OCI 1.1)
│   ├── action.yml
│   └── generate-slsa-predicate.py
├── report/                   ← OPS-701 PR 5: DefectDojo SBOM + OSV upload (non-fatal)
│   └── action.yml
└── update-gitops/            ← OPS-313: clone+sed+push gitops manifest update (replaces GitLab update-gitops stage)
    └── action.yml
```

The old `security-scan/` will be stubbed/deleted after both consumer workflows
(`build-netbox-acls.yml`, `build-sentinel-ops.yml`) migrate to the 4-composite pattern
(OPS-701 PRs 6–8).

---

## Composite Contracts

### `scan` — SBOM generation + vulnerability scanning

**Failure policy:** Non-fatal. Missing tools produce `::warning::` annotations.
Hard-fail only on MAL-* (malicious) packages when `hard-fail-on-critical: "true"`.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-ref` | yes | — | Fully-qualified image reference (digest preferred) |
| `language` | no | `none` | `node`/`python`/`go`/`rust`/`none` — lockfile audit ecosystem |
| `source-dir` | no | `.` | Directory containing lockfiles |
| `hard-fail-on-critical` | no | `true` | Exit 1 if MAL-* entries found in OSV output |

| Output | Description |
|--------|-------------|
| `sbom-component-count` | Number of components in CycloneDX SBOM (or "unknown") |

**Artifact side-effects:** writes `sbom.cyclonedx.json` and `osv.json` to workspace
(consumed by `attest` and `report` in same job).

---

### `sign` — cosign image signing (OCI 1.1 Referrers API)

**Failure policy:** Must-succeed. Signs the image digest and exits non-zero on failure.
A failed sign step aborts the job — no downstream steps should run unsigned images.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-ref` | yes | — | Fully-qualified image reference with digest (sha256:...) |
| `cosign-key` | yes | — | PEM-encoded cosign private key |
| `cosign-password` | no | `""` | Cosign key passphrase |
| `cosign-version` | no | `v2.4.3` | Pinned cosign version; override to test newer releases |

| Output | Description |
|--------|-------------|
| `image-digest` | Digest of the signed image (echo of input digest for chaining) |

**OCI 1.1 note:** Uses `--registry-referrers-mode oci-1-1` on `cosign sign`.
Signature is stored as an OCI 1.1 Referrers API accessory (not tag-style).
Harbor, ECR, Quay all support OCI 1.1 as of 2025 (OPS-699 §7 refs).

---

### `attest` — SLSA v1.0 provenance + SBOM attestation (OCI 1.1 Referrers API)

**Failure policy:** Must-succeed. Produces attestation accessory linked to the signed
image digest. Exit non-zero on cosign failure.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-ref` | yes | — | Fully-qualified image reference with digest |
| `cosign-key` | yes | — | PEM-encoded cosign private key |
| `cosign-password` | no | `""` | Cosign key passphrase |
| `sbom-file` | no | `sbom.cyclonedx.json` | CycloneDX SBOM file (produced by `scan` composite) |
| `cosign-version` | no | `v2.4.3` | Pinned cosign version |

| Output | Description |
|--------|-------------|
| `predicate-file` | Path to generated SLSA predicate JSON (for audit trail) |

**Design notes:**
- SLSA predicate generation is in a Python script file (`generate-slsa-predicate.py`)
  rather than an inline bash heredoc — testable in isolation, reviewable as diff.
- Uses `cosign attach attestation --registry-referrers-mode oci-1-1` (not `cosign attest`)
  because `cosign attest` lacks the `--registry-referrers-mode` flag per cosign v2.4.3
  source `cmd/cosign/cli/options/attest.go`. The `attach attestation` subcommand exposes
  the flag via `cmd/cosign/cli/options/attach.go` (architect-verified, OPS-701 issue).
- Predicate type: `slsaprovenance1` (SLSA v1.0, `buildDefinition` + `runDetails` body only).
  The outer in-toto statement wrapper is built by cosign; only the predicate body is passed.

---

### `report` — DefectDojo upload (non-fatal observability)

**Failure policy:** Non-fatal end-to-end. All DefectDojo curl calls use explicit exit-code
capture (`CURL_EXIT=0; cmd || CURL_EXIT=$?`). HTTP 4xx/5xx and network errors emit
`::warning::` annotations but do not exit the step. This composites' failure NEVER
blocks sign or attest.

**Caller guidance:** If DefectDojo is known-unreachable (e.g., OPS-697 runner-DNS-context
defect), skip this composite entirely — it produces no outputs other than observability data.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-ref` | yes | — | Image reference (used in report metadata) |
| `defectdojo-url` | no | `https://defectdojo.208.haist.farm` | DefectDojo base URL |
| `defectdojo-token` | yes | — | DefectDojo API token |
| `defectdojo-engagement-id` | no | `""` | Numeric engagement ID (auto-creates if empty) |
| `defectdojo-product-name` | no | `Sentinel Platform` | Product name for auto-create context |
| `sbom-file` | no | `sbom.cyclonedx.json` | SBOM file to upload (skipped if absent) |
| `osv-file` | no | `osv.json` | OSV findings file to upload (skipped if absent) |

Outputs: none.

---

## Consumer Workflow Pattern (post-migration)

```yaml
jobs:
  build-and-push:
    steps:
      - uses: actions/checkout@v4
      - name: Build + push image
        id: push
        # ... buildah bud + push; emits outputs.digest

      - name: Scan (SBOM + OSV + language audit)
        uses: ./.forgejo/actions/scan
        with:
          image-ref: ${{ env.HARBOR_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
          language: none
          hard-fail-on-critical: "false"

      - name: Sign image
        uses: ./.forgejo/actions/sign
        with:
          image-ref: ${{ env.HARBOR_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
          cosign-key: ${{ secrets.COSIGN_KEY }}
          cosign-password: ${{ secrets.COSIGN_PASSWORD || '' }}

      - name: Attest (SLSA + SBOM)
        uses: ./.forgejo/actions/attest
        with:
          image-ref: ${{ env.HARBOR_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
          cosign-key: ${{ secrets.COSIGN_KEY }}
          cosign-password: ${{ secrets.COSIGN_PASSWORD || '' }}

      - name: Report to DefectDojo (non-fatal)
        uses: ./.forgejo/actions/report
        with:
          image-ref: ${{ env.HARBOR_REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
          defectdojo-token: ${{ secrets.DEFECTDOJO_API_KEY }}
          defectdojo-product-name: "My Product Image"

      - name: Upload scan artifacts
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: security-scan-artifacts-${{ github.run_id }}
          path: |
            sbom.cyclonedx.json
            osv.json
            slsaprovenance.json
          if-no-files-found: ignore
          retention-days: 90
```

**Why this ordering:**
- `scan` runs first (produces sbom.cyclonedx.json, osv.json consumed by attest + report)
- `sign` before `attest` (establishes image integrity before adding provenance)
- `report` last (non-fatal; runs even if scan produces warnings — but caller may use `if: always()`)
- Artifact upload always runs (`if: always()`) to capture partial outputs

---

## Vendoring Note (OPS-239)

Forgejo Runner v12.7.1 resolves cross-repo `uses:` references through `code.forgejo.org`,
which does not host private repos like `sentinel-admin/sentinel-iac`. All composites are
therefore vendored into `overwatch-gitops` at `.forgejo/actions/` and consumed via local
path (`uses: ./.forgejo/actions/scan`). The same composites live in `sentinel-iac` at
the same path. Syncing between repos is a manual copy-and-commit operation (document the
sync SHA in the header comment of each `action.yml`).

---

## Migration Status

| Consumer | Status |
|----------|--------|
| `build-netbox-acls.yml` | OPS-701 PR 6 — pending |
| `build-sentinel-ops.yml` | OPS-701 PR 7 — pending |

Old composite (`security-scan/`) will be deleted after both consumers migrate and a
post-migration build of each verifies OCI 1.1 accessory linkage (OPS-701 PR 8).
