#!/usr/bin/env bash
# verify-langfuse-evaluators.sh — OPS-239 workstream A
#
# Report per-judge score coverage across the last N Langfuse traces for the
# overwatch-agents project.  Intended to gate acceptance on actual score
# presence after the operator click-configures evaluators via the UI.
#
# Usage: verify-langfuse-evaluators.sh [N]   (default N=50)
#
# Environment:
#   LANGFUSE_PROJECT_PUBLIC_KEY  — Langfuse project public key (or read from Vault)
#   LANGFUSE_PROJECT_SECRET_KEY  — Langfuse project secret key (or read from Vault)
#   LANGFUSE_URL                 — override Langfuse base URL
#   VAULT_ADDR                   — override Vault address
#
# Exit codes:
#   0 — success, sampled_incomplete == 0
#   1 — sampled_incomplete > 0 (judges configured but not all scoring)
#   2 — no traces returned (API error or empty project)

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
LANGFUSE_URL="${LANGFUSE_URL:-https://langfuse.208.haist.farm}"
VAULT_ADDR="${VAULT_ADDR:-https://192.168.12.206:8200}"
VAULT_BIN="${HOME}/.local/bin/vault"
N="${1:-50}"

# 8 expected judge score names (case-sensitive)
JUDGE_NAMES=(
  "scope_adherence"
  "privileged_action_disclosure"
  "intent_vs_implementation_drift"
  "hallucination_on_security_facts"
  "architectural_soundness_flag"
  "compliance_citation_accuracy"
  "uncertainty_expression"
  "problem_reframing_transparency"
)

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
for bin in curl jq base64; do
  if ! command -v "$bin" &>/dev/null; then
    echo "ERROR: required tool '$bin' not found in PATH" >&2
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# Resolve Langfuse credentials
# ---------------------------------------------------------------------------
resolve_keys() {
  # Prefer environment variables
  if [[ -n "${LANGFUSE_PROJECT_PUBLIC_KEY:-}" && -n "${LANGFUSE_PROJECT_SECRET_KEY:-}" ]]; then
    echo "INFO: using Langfuse keys from environment variables" >&2
    LF_PK="$LANGFUSE_PROJECT_PUBLIC_KEY"
    LF_SK="$LANGFUSE_PROJECT_SECRET_KEY"
    return
  fi

  echo "INFO: LANGFUSE_PROJECT_PUBLIC_KEY not set — falling back to Vault" >&2

  if [[ ! -x "$VAULT_BIN" ]]; then
    echo "ERROR: Vault binary not found at $VAULT_BIN and env vars not set" >&2
    exit 2
  fi

  local vault_path="secret/langfuse/overwatch-agents"
  local vault_err
  if ! vault_err=$(VAULT_ADDR="$VAULT_ADDR" VAULT_SKIP_VERIFY=true \
      "$VAULT_BIN" kv get -format=json "$vault_path" 2>&1); then
    echo "ERROR: Vault kv get $vault_path failed:" >&2
    echo "$vault_err" >&2
    exit 2
  fi

  LF_PK=$(printf '%s' "$vault_err" | jq -r '.data.data.public_key // empty')
  LF_SK=$(printf '%s' "$vault_err" | jq -r '.data.data.secret_key // empty')

  if [[ -z "$LF_PK" || -z "$LF_SK" ]]; then
    echo "ERROR: Vault returned empty public_key or secret_key from $vault_path" >&2
    exit 2
  fi

  echo "INFO: Langfuse keys loaded from Vault ($vault_path)" >&2
}

resolve_keys

# Build Basic auth header — keys are not printed
AUTH_HEADER="Authorization: Basic $(printf '%s:%s' "$LF_PK" "$LF_SK" | base64 -w0)"

# ---------------------------------------------------------------------------
# API helper with non-2xx guard
# ---------------------------------------------------------------------------
lf_get() {
  local url="$1"
  local response http_code body
  response=$(curl -sk -w "\n%{http_code}" -H "$AUTH_HEADER" "$url")
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | head -n -1)

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "ERROR: Langfuse API returned HTTP $http_code for $url" >&2
    echo "       Response: $body" >&2
    exit 2
  fi

  printf '%s' "$body"
}

# ---------------------------------------------------------------------------
# Fetch traces
# ---------------------------------------------------------------------------
echo "INFO: fetching last $N traces from $LANGFUSE_URL" >&2

traces_json=$(lf_get "${LANGFUSE_URL}/api/public/traces?limit=${N}&page=1")
total_items=$(printf '%s' "$traces_json" | jq -r '.meta.totalItems // 0')
trace_count=$(printf '%s' "$traces_json" | jq '.data | length')

if [[ "$trace_count" -eq 0 ]]; then
  echo "ERROR: no traces returned (totalItems=$total_items). API error or empty project." >&2
  exit 2
fi

echo "INFO: $trace_count trace(s) returned (totalItems=$total_items)" >&2

# ---------------------------------------------------------------------------
# Per-trace scoring
# ---------------------------------------------------------------------------
declare -A judge_counts
for j in "${JUDGE_NAMES[@]}"; do
  judge_counts["$j"]=0
done

sampled_complete=0
sampled_incomplete=0
not_sampled=0
incomplete_ids=()

trace_ids=$(printf '%s' "$traces_json" | jq -r '.data[].id')

while IFS= read -r trace_id; do
  [[ -z "$trace_id" ]] && continue

  scores_json=$(lf_get "${LANGFUSE_URL}/api/public/scores?traceId=${trace_id}&limit=100")
  score_names=$(printf '%s' "$scores_json" | jq -r '[.data[].name] | unique | .[]' 2>/dev/null || true)

  hit_count=0
  for j in "${JUDGE_NAMES[@]}"; do
    if printf '%s\n' "$score_names" | grep -qxF "$j"; then
      judge_counts["$j"]=$(( judge_counts["$j"] + 1 ))
      hit_count=$(( hit_count + 1 ))
    fi
  done

  if [[ "$hit_count" -eq 0 ]]; then
    not_sampled=$(( not_sampled + 1 ))
  elif [[ "$hit_count" -eq "${#JUDGE_NAMES[@]}" ]]; then
    sampled_complete=$(( sampled_complete + 1 ))
  else
    sampled_incomplete=$(( sampled_incomplete + 1 ))
    incomplete_ids+=("$trace_id")
  fi
done <<< "$trace_ids"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo " Langfuse evaluator coverage report"
echo " Project:  overwatch-agents"
echo " URL:      $LANGFUSE_URL"
echo " Traces:   last $trace_count (of $total_items total)"
echo "======================================================================"
echo ""
echo "Per-judge coverage:"
printf "  %-45s %6s  %s\n" "Judge name" "Count" "Pct"
printf "  %-45s %6s  %s\n" "---------" "-----" "---"
for j in "${JUDGE_NAMES[@]}"; do
  cnt="${judge_counts[$j]}"
  pct=$(awk "BEGIN { printf \"%.1f%%\", ($cnt / $trace_count) * 100 }")
  printf "  %-45s %6d  %s\n" "$j" "$cnt" "$pct"
done
echo ""
echo "Trace classification:"
printf "  %-30s %d\n" "sampled_complete (all 8):" "$sampled_complete"
printf "  %-30s %d\n" "sampled_incomplete (1..7):" "$sampled_incomplete"
printf "  %-30s %d\n" "not_sampled (0 scores):" "$not_sampled"
echo ""

# List incomplete trace IDs
if [[ "$sampled_incomplete" -gt 0 ]]; then
  echo "Incomplete trace IDs (partial judge coverage — real failure):"
  limit=10
  count=0
  for tid in "${incomplete_ids[@]}"; do
    echo "  $tid"
    count=$(( count + 1 ))
    if [[ "$count" -ge "$limit" ]]; then
      remaining=$(( sampled_incomplete - count ))
      if [[ "$remaining" -gt 0 ]]; then
        echo "  ... and $remaining more"
      fi
      break
    fi
  done
  echo ""
fi

# ---------------------------------------------------------------------------
# Exit code
# ---------------------------------------------------------------------------
if [[ "$sampled_incomplete" -gt 0 ]]; then
  echo "RESULT: FAIL — $sampled_incomplete trace(s) have partial judge coverage"
  exit 1
else
  echo "RESULT: OK — no incomplete sampling detected (sampled_incomplete=0)"
  exit 0
fi
