# Schedule Auto-Merge Stuck on Protected-File PRs

**Issue:** OPS-395
**Last updated:** 2026-05-29
**Applies to:** `sentinel-admin/overwatch-gitops` — PRs whose diff matches `protected_file_patterns`

---

## Problem

Forgejo shows a **Schedule auto-merge** option on PRs that will never merge via that
mechanism. Clicking it sets a green "merge scheduled" badge on the PR, but the
merge never fires.

**Root cause:** Forgejo's auto-merge system actor is not listed in the
`approvals_whitelist` or `merge_whitelist` for `protected_file_patterns` paths.
CODEOWNERS requires `@koiakoia` to approve those paths — a condition the system
actor can never satisfy. The schedule condition is evaluated against the normal
required-approval count, which the system actor can satisfy, so Forgejo considers
the schedule valid. The protected-files gate is evaluated only at merge time, by
a separate code path, and is never satisfied.

The UI offers no warning that scheduling is futile.

**Affected configuration (as of 2026-05-06):**

Protected file patterns on `main`:
```
CLAUDE.md
clusters/overwatch/machineconfigs/**
clusters/overwatch/system/**
apps/kyverno-helm/**
**/trust-policy*.yaml
**/cosign-pubkey*.yaml
.gitea/CODEOWNERS
```

Any PR touching at least one file matching these patterns is affected.

---

## Detecting a Stuck Schedule

Signs the schedule is stuck:

1. Green "merge scheduled" badge visible in Forgejo PR UI
2. PR remains open after waiting several minutes
3. Forgejo API returns `merge_commit_sha: null` on the PR
4. PR diff includes files matching `protected_file_patterns`

Check via API:

```bash
FORGEJO_TOKEN=$(vault kv get -field=api_token secret/forgejo-worker)
PR_NUMBER=<your PR number>

curl -s \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  "https://forgejo.208.haist.farm/api/v1/repos/sentinel-admin/overwatch-gitops/pulls/${PR_NUMBER}" \
  | jq '{state, mergeable, merge_commit_sha}'
```

A stuck schedule shows `"merge_commit_sha": null` with `"state": "open"`.

---

## Workaround: Do Not Use Schedule Auto-Merge

When the PR diff touches any path in `protected_file_patterns`:

1. Do **not** click "Schedule auto-merge" (the dropdown option at the bottom of the merge panel).
2. Instead, have `@koiakoia` (or `sentinel-judge`) click the top-level **Merge** button directly once all checks pass.

The top-level Merge button bypasses the scheduling system and invokes the merge
immediately. The protected-files gate still applies — only an operator in the
`approvals_whitelist` can complete it — but the action is synchronous and returns
an immediate error if the gate is not satisfied, rather than silently deferring.

---

## Cancelling a Stuck Schedule

If a schedule is already set, cancel it via the Forgejo API before attempting a
direct merge:

```bash
FORGEJO_TOKEN=$(vault kv get -field=api_token secret/forgejo-worker)
PR_NUMBER=<your PR number>

# Cancel scheduled auto-merge
curl -s --request DELETE \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  "https://forgejo.208.haist.farm/api/v1/repos/sentinel-admin/overwatch-gitops/pulls/${PR_NUMBER}/merge" \
  -w "\nHTTP: %{http_code}\n"
```

HTTP 204 = schedule cancelled. HTTP 404 = no schedule was set (safe to ignore).

After cancelling, proceed with a direct merge via the Forgejo UI or the sentinel-judge
workflow.

---

## Judge Merge Path (Normal)

For PRs that touch protected files, the standard merge path is:

1. sentinel-judge posts `APPROVED` review via judge token.
2. `@koiakoia` reviews in Forgejo UI (Files-changed tab, not Conversation).
3. `@koiakoia` clicks the top-level **Merge** (squash) button directly.

The sentinel-admin (vault-autogen-bot) token can be used for break-glass merges
when `@koiakoia` is unavailable, per `feedback_forgejo_force_merge_tokens`.

---

## Related

- OPS-332 — CODEOWNERS gating design that introduced `protected_file_patterns`
- OPS-391 — Loki deploy where this bug was first encountered (PR #140)
- `docs/runbooks/kyverno-harbor-break-glass.md` — separate break-glass procedure
- Memory: `feedback_forgejo_branch_protection_mechanisms.md`
