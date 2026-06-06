# Langfuse LLM-as-judge evaluators (OPS-239)

Closes the verification gap named in Jim's BSides Fort Wayne 2026 talk by
running 8 automated LLM-as-judge evaluators against every sampled trace
from the `overwatch-agents` Langfuse project.

## What this deploys

| Manifest | Purpose |
|---|---|
| [`external-secret.yaml`](external-secret.yaml) | Pulls `GEMINI_API_KEY`, `LANGFUSE_PROJECT_PUBLIC_KEY`, and `LANGFUSE_PROJECT_SECRET_KEY` from Vault via `vault-backend` ClusterSecretStore. |
| [`prompts-configmap.yaml`](prompts-configmap.yaml) | 8 evaluator prompt templates, each anchored to a BSides talk pillar. Source of truth for prompt text — operator copies these into the Langfuse UI. |
| [`setup-job.yaml`](setup-job.yaml) | One-time Job that upserts the Gemini LLM connection via `PUT /api/public/llm-connections`. Evaluator templates and running-evaluator configs are created once by the operator via the Langfuse UI per runbook 08. |

## Why templates + configs are not automated

`PUT /api/public/evaluator-templates/{name}` and
`PUT /api/public/evaluator-configs/{name}` do not exist in the Langfuse
v3 public API — they are tRPC-internal endpoints not exposed over HTTP.
Automating template/config creation via curl would 404 on every run.
Runbook 08 walks the one-time UI procedure.

## Talk pillar → judge mapping

| Pillar | Judges |
|---|---|
| 2 — Trust expansion, not replacement | `scope_adherence`, `privileged_action_disclosure` |
| 3 — Confident bad code (the verification gap) | `intent_vs_implementation_drift`, `hallucination_on_security_facts`, `architectural_soundness_flag` |
| 4 — Compliance honesty | `compliance_citation_accuracy` |
| 5 — Human as verifier | `uncertainty_expression`, `problem_reframing_transparency` |

## Bootstrap prerequisites

Before `argocd app sync` succeeds on this app, these Vault entries must
exist. The setup Job fails fast with clear messages if any are missing.

```bash
# Gemini — already exists as of 2026-03-18
vault kv get secret/gemini            # expect field: api_key

# Langfuse project keys — stored in Vault (not hardcoded):
vault kv put secret/langfuse/overwatch-agents \
  public_key=<pk-lf-...> \
  secret_key=<sk-lf-...>
```

Runbook 08 (sentinel-iac/docs/runbooks/08-langfuse-evaluator-calibration.md)
walks this plus the one-time UI procedure for templates and configs.

## Cost envelope

Default sampling: **10%** of traces.

| Variable | Value |
|---|---|
| Trace rate during active platform work | ~1500/week |
| Sampled for eval | ~150/week |
| Evaluators per sampled trace | 8 |
| Eval calls/week | ~1200 |
| Tokens/eval call (input + output) | ~1500 |
| Model | `gemini-2.5-flash` |
| Cost estimate (Gemini 2.5 Flash pricing, Apr 2026) | **~$8–15/month** |

Raise sampling to 100% during BSides demo week for full-signal data;
drop to 5% thereafter.

## Modifying prompts

1. Edit the relevant `.txt` key in `prompts-configmap.yaml`.
2. Commit + push. ArgoCD sync changes the ConfigMap.
3. **Also update the corresponding template in the Langfuse UI** —
   the ConfigMap is the source of truth but the UI does not auto-sync.
   Operator copies the updated prompt text from the ConfigMap into
   Settings → Evaluations → Templates → [template name] → Edit.

## Job re-run procedure

The Job has no ArgoCD hook — it runs once on initial deploy. To re-run
(e.g., after rotating the Gemini API key):

```bash
kubectl -n langfuse delete job langfuse-evaluators-setup
argocd app sync langfuse
kubectl -n langfuse logs job/langfuse-evaluators-setup -f
```

## Debugging

- **Job fails with 401**: `LANGFUSE_PROJECT_PUBLIC_KEY` or
  `LANGFUSE_PROJECT_SECRET_KEY` is wrong or not yet in Vault. Verify
  with `vault kv get secret/langfuse/overwatch-agents` and confirm
  the ExternalSecret synced (`kubectl -n langfuse get externalsecret
  langfuse-evaluators-credentials`).
- **Job fails with 403**: the project keys don't belong to the
  `overwatch-agents` project in Langfuse. Regenerate via Langfuse UI →
  Project Settings → API Keys and update Vault.
- **Evaluators run but all return null scores**: prompts produce output
  that doesn't parse the JSON schema. Check Gemini output in Langfuse
  UI under Evaluations → Runs → Raw.
- **Gemini rate-limits**: drop `sampling` to 0.05 via the running
  evaluator config in the Langfuse UI, or switch to `gemini-2.5-pro`.

## Verification

Use `scripts/verify-langfuse-evaluators.sh` (added in OPS-239 workstream A)
to confirm that score presence in Langfuse matches expected evaluator coverage.

```bash
# From overwatch-gitops root — uses Vault fallback for keys
bash scripts/verify-langfuse-evaluators.sh 50

# Or with keys from env
export LANGFUSE_PROJECT_PUBLIC_KEY=pk-lf-...
export LANGFUSE_PROJECT_SECRET_KEY=sk-lf-...
bash scripts/verify-langfuse-evaluators.sh 50
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | No partial coverage (`sampled_incomplete == 0`) — pass |
| `1` | One or more traces have 1..7 of 8 judges scoring — evaluator config bug |
| `2` | No traces returned, API error, or missing credentials |

### What to expect before vs. after operator UI config (workstream B)

**Before evaluators are configured** (current state, workstream A):
all traces will show `not_sampled` and exit code 0. This is expected — the
script does not flag absence of scoring as an error, only *partial* scoring.

```
Trace classification:
  sampled_complete (all 8):      0
  sampled_incomplete (1..7):     0
  not_sampled (0 scores):        N
RESULT: OK — no incomplete sampling detected (sampled_incomplete=0)
```

**After evaluators are configured and a sampling window has passed**:
at 10% sampling with ~1500 traces/week, expect roughly 150 sampled traces per
week. A healthy output will show nonzero `sampled_complete` and zero
`sampled_incomplete`:

```
Per-judge coverage:
  scope_adherence                               15  10.0%
  privileged_action_disclosure                  15  10.0%
  intent_vs_implementation_drift                15  10.0%
  ...
Trace classification:
  sampled_complete (all 8):      15
  sampled_incomplete (1..7):     0
  not_sampled (0 scores):        135
RESULT: OK — no incomplete sampling detected (sampled_incomplete=0)
```

If `sampled_incomplete > 0`, the incomplete trace IDs are printed (up to 10).
Inspect them in the Langfuse UI under Traces → [traceId] → Scores to diagnose
which judges are missing and whether Gemini returned an unparseable response.

### CI integration

The script can be added to a CI step after workstream B lands:

```yaml
- name: Check evaluator coverage
  run: |
    bash scripts/verify-langfuse-evaluators.sh 100
  env:
    LANGFUSE_PROJECT_PUBLIC_KEY: ${{ secrets.LANGFUSE_PK }}
    LANGFUSE_PROJECT_SECRET_KEY: ${{ secrets.LANGFUSE_SK }}
```

Exit code 1 fails the step; exit code 0 passes.
