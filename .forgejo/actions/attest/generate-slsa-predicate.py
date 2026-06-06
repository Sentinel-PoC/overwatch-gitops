#!/usr/bin/env python3
"""
generate-slsa-predicate.py — SLSA v1.0 provenance predicate generator

OPS-701: Isolated Python script for SLSA predicate generation.
Previously: inline Python in bash heredoc inside monolithic security-scan composite.
Why isolated: testable independently, reviewable as diff, no bash/Python context switching.
See OPS-699 §4 Pattern B for root cause analysis.

Generates a SLSA v1.0 provenance predicate body (buildDefinition + runDetails).

IMPORTANT: This generates the PREDICATE BODY ONLY, not a full in-toto statement.
cosign builds the outer statement (with _type, subject, predicateType) itself.
Passing a full in-toto statement to cosign causes:
  "provenance predicate: required field buildDefinition missing"
because cosign parses the outer statement as if it were the predicate.
(OPS-696 layer-6 root cause — fixed here structurally, not by patching.)

Usage:
    python3 generate-slsa-predicate.py --output slsaprovenance.json
    python3 generate-slsa-predicate.py --output slsaprovenance.json --validate

Environment variables (standard Forgejo Actions / GitHub Actions):
    GITHUB_SERVER_URL    — Forgejo/GitHub server URL
    GITHUB_REPOSITORY    — owner/repo
    GITHUB_SHA           — commit SHA
    GITHUB_REF           — refs/heads/main etc
    GITHUB_WORKFLOW      — workflow name
    GITHUB_EVENT_NAME    — push, workflow_dispatch, etc
    GITHUB_RUN_ID        — workflow run ID
    GITHUB_RUN_ATTEMPT   — attempt number (1-based)

Exit codes:
    0 — predicate written successfully
    1 — validation failed (only with --validate)
    2 — output file write error
"""

import argparse
import datetime
import json
import os
import sys


def build_predicate() -> dict:
    """Build a SLSA v1.0 provenance predicate body.

    Returns the predicate dict (buildDefinition + runDetails).
    The outer in-toto statement is constructed by cosign; we only generate the body.
    Reference: https://slsa.dev/spec/v1.0/provenance/
    """
    server_url = os.environ.get("GITHUB_SERVER_URL", "https://forgejo.208.haist.farm")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    sha = os.environ.get("GITHUB_SHA", "")
    ref = os.environ.get("GITHUB_REF", "")
    workflow = os.environ.get("GITHUB_WORKFLOW", "")
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")

    now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

    predicate = {
        "buildDefinition": {
            # buildType identifies the build platform and the schema version
            # for the externalParameters and internalParameters fields.
            "buildType": "https://forgejo.208.haist.farm/actions/runner@v1",
            "externalParameters": {
                "source": {
                    "repository": f"{server_url}/{repository}",
                    "revision": sha,
                    "ref": ref,
                },
                "workflow": workflow,
                "event": event,
            },
            "internalParameters": {
                "runner_environment": "forgejo-runner",
                "runner_host": "iac-control.208.haist.farm",
            },
        },
        "runDetails": {
            "builder": {
                # builder.id is the identifier for the build platform entity
                # that produced this provenance. Using the Forgejo Actions runner URL.
                "id": f"https://forgejo.208.haist.farm/{repository}/actions/runner",
                "version": {
                    "runner": "forgejo-runner-v5",
                },
            },
            "metadata": {
                "invocationId": f"{run_id}/{run_attempt}",
                "startedOn": now,
                "finishedOn": now,
            },
        },
    }

    return predicate


def validate_predicate(predicate: dict) -> list[str]:
    """Validate that the predicate has required SLSA v1.0 fields.

    Returns a list of validation errors (empty = valid).
    Checks the predicate body only (not the outer in-toto statement).
    """
    errors = []

    if "buildDefinition" not in predicate:
        errors.append("Missing required field: buildDefinition")
    else:
        bd = predicate["buildDefinition"]
        if "buildType" not in bd:
            errors.append("Missing required field: buildDefinition.buildType")
        if "externalParameters" not in bd:
            errors.append("Missing required field: buildDefinition.externalParameters")

    if "runDetails" not in predicate:
        errors.append("Missing required field: runDetails")
    else:
        rd = predicate["runDetails"]
        if "builder" not in rd:
            errors.append("Missing required field: runDetails.builder")
        elif "id" not in rd["builder"]:
            errors.append("Missing required field: runDetails.builder.id")

    # Verify no outer in-toto statement fields leaked in
    statement_fields = {"_type", "subject", "predicateType", "predicate"}
    leaked = statement_fields & set(predicate.keys())
    if leaked:
        errors.append(
            f"Predicate body contains outer in-toto statement fields: {leaked}. "
            "cosign expects predicate body only (buildDefinition + runDetails). "
            "See OPS-696 layer-6 root cause."
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate SLSA v1.0 provenance predicate (body only, not full statement)"
    )
    parser.add_argument(
        "--output",
        default="slsaprovenance.json",
        help="Output file path (default: slsaprovenance.json)",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate predicate fields before writing (exit 1 on validation failure)",
    )
    args = parser.parse_args()

    predicate = build_predicate()

    if args.validate:
        errors = validate_predicate(predicate)
        if errors:
            for err in errors:
                print(f"ERROR: {err}", file=sys.stderr)
            return 1
        print("Validation passed: predicate has required SLSA v1.0 fields")

    try:
        with open(args.output, "w") as f:
            json.dump(predicate, f, indent=2)
        print(f"SLSA v1.0 predicate written to {args.output}")
    except OSError as e:
        print(f"ERROR: Failed to write {args.output}: {e}", file=sys.stderr)
        return 2

    # Print summary
    bd = predicate.get("buildDefinition", {})
    rd = predicate.get("runDetails", {})
    print(f"  buildType:  {bd.get('buildType', 'N/A')}")
    print(f"  repository: {bd.get('externalParameters', {}).get('source', {}).get('repository', 'N/A')}")
    print(f"  sha:        {bd.get('externalParameters', {}).get('source', {}).get('revision', 'N/A')}")
    print(f"  builder.id: {rd.get('builder', {}).get('id', 'N/A')}")
    print(f"  invocation: {rd.get('metadata', {}).get('invocationId', 'N/A')}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
