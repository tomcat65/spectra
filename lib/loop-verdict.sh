#!/usr/bin/env bash
# SPECTRA lib/loop-verdict.sh — Structured verdict extraction from agent output
#
# Agents are instructed (via --append-system-prompt) to append a JSON verdict
# trailer at the end of their output. This module extracts it, with regex fallback
# for backward compatibility.
#
# Contract:
#   Globals required: (none)
#   Functions required: (none)
#
# Exports:
#   extract_verdict()  — extracts a key from agent output (JSON trailer preferred, regex fallback)
#   VERDICT_SYSTEM_PROMPT — the --append-system-prompt text for verdict-producing agents

# ── System prompt appended to all verdict-producing agents ──
# RATIONALE: VERDICT_SYSTEM_PROMPT is read by spectra-loop.sh when invoking reviewer/verifier agents
# shellcheck disable=SC2034
VERDICT_SYSTEM_PROMPT='IMPORTANT: At the very end of your response, after all narrative content, append a structured verdict block in this exact format:

```json
{"result": "PASS_OR_FAIL", "verdict": "APPROVED_OR_REJECTED", "failure_type": "type_or_null"}
```

Rules for the JSON block:
- For verification: set "result" to "PASS" or "FAIL". If FAIL, set "failure_type" to one of: test_failure, missing_dependency, wiring_gap, architecture_mismatch, ambiguous_spec, external_blocker.
- For plan review: set "verdict" to "APPROVED", "APPROVED_WITH_WARNINGS", or "REJECTED".
- For negotiate review: set "verdict" to "APPROVED" or "ESCALATE".
- Only include fields relevant to your role. Omit irrelevant fields.
- The JSON must be valid and on a single line inside a json code fence.
- This block is machine-parsed. Do not modify the format.'

# ── Extract a verdict field from agent output ──
# Usage: extract_verdict FILE KEY [VALID_VALUES...]
#   FILE:         path to agent output file
#   KEY:          JSON key to extract (e.g., "result", "verdict", "failure_type")
#   VALID_VALUES: optional whitelist — if provided, only these values are accepted
#
# Returns: the extracted value on stdout, or empty string if not found/invalid
#
# Strategy:
#   1. Try JSON trailer (```json block at end of file)
#   2. Fall back to regex on markdown-stripped text
#   3. Validate against whitelist if provided
extract_verdict() {
    local file="$1"
    local key="$2"
    shift 2
    local -a valid_values=("$@")

    [[ -f "$file" ]] || return 0

    local value=""

    # ── Strategy 1: JSON trailer ──
    # Look for a ```json block in the last 30 lines of the file
    local json_line
    json_line=$(tail -30 "$file" | grep -oP '^\s*\{.*\}\s*$' | tail -1 || true)

    # Also try inside ```json fences
    if [[ -z "$json_line" ]]; then
        json_line=$(tail -30 "$file" | sed -n '/^```json/,/^```/{//!p;}' | grep -oP '\{.*\}' | tail -1 || true)
    fi

    if [[ -n "$json_line" ]]; then
        # Extract key with jq if available, otherwise grep
        if command -v jq &>/dev/null; then
            value=$(echo "$json_line" | jq -r ".${key} // empty" 2>/dev/null || true)
        else
            # Fallback: simple grep for "key": "value"
            value=$(echo "$json_line" | grep -oP "\"${key}\":\s*\"?\K[^\",}]+" | head -1 || true)
        fi
    fi

    # ── Strategy 2: Regex fallback on markdown-stripped text ──
    if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
        local stripped
        stripped=$(tr -d '*#' < "$file")

        case "$key" in
            result)
                value=$(echo "$stripped" | grep -oiP 'Result:\s*\K(PASS|FAIL)' | head -1 || true)
                # Broader fallback: scan for natural language PASS indicators
                if [[ -z "$value" ]]; then
                    if echo "$stripped" | grep -qiP '\b(all.*passed|verdict.*pass|4.*steps.*pass|wiring.*clean)\b'; then
                        value="PASS"
                    fi
                fi
                ;;
            verdict)
                value=$(echo "$stripped" | grep -oiP 'Verdict:\s*\K[A-Z_]+' | head -1 || true)
                ;;
            failure_type)
                value=$(echo "$stripped" | grep -oiP 'Failure Type:\s*\K(test_failure|missing_dependency|wiring_gap|architecture_mismatch|ambiguous_spec|external_blocker)' | head -1 || true)
                ;;
            *)
                # Generic: try "Key: Value" pattern
                value=$(echo "$stripped" | grep -oiP "${key}:\s*\K\S+" | head -1 || true)
                ;;
        esac
    fi

    # ── Normalize ──
    value=$(echo "$value" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')

    # failure_type should be lowercase
    if [[ "$key" == "failure_type" ]]; then
        value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    fi

    # ── Validate against whitelist ──
    if [[ ${#valid_values[@]} -gt 0 ]] && [[ -n "$value" ]]; then
        local valid=false
        for v in "${valid_values[@]}"; do
            if [[ "${value^^}" == "${v^^}" ]]; then
                valid=true
                # Use the canonical form from the whitelist
                value="$v"
                break
            fi
        done
        if [[ "$valid" == false ]]; then
            value=""
        fi
    fi

    echo "$value"
}
