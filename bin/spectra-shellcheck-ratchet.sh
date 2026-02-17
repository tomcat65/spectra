#!/usr/bin/env bash
set -euo pipefail

# SPECTRA ShellCheck Ratchet
# Enforces that ShellCheck warning counts never increase per-file or per-rule.
# Two modes:
#   --check           Compare current warnings against baseline; fail if any increase or new file
#   --update-baseline Generate/update the baseline JSON file
#
# Auditor constraints:
#   - Per-file + per-rule baselines (no global hiding)
#   - Pinned ShellCheck version (baseline records it, --check validates match)
#   - --update-baseline fails if any file count increased (unless --allow-increase "rationale")
#   - --check fails on files missing from baseline (new files require explicit update)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"
BASELINE_FILE="${SPECTRA_HOME}/shellcheck-baseline.json"

# Configurable ShellCheck binary (for testing)
SHELLCHECK="${SHELLCHECK_BIN:-shellcheck}"

MODE=""
ALLOW_INCREASE=false
INCREASE_RATIONALE=""

usage() {
    cat <<'USAGE'
Usage: spectra-shellcheck-ratchet.sh [OPTIONS]

Options:
  --check                 Compare current warnings against baseline
  --update-baseline       Generate or update baseline JSON
  --allow-increase "why"  Allow baseline increases (requires rationale)
  --baseline FILE         Override baseline file path
  --help                  Show this help

Environment:
  SHELLCHECK_BIN          Override shellcheck binary path
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --update-baseline) MODE="update"; shift ;;
        --allow-increase)
            ALLOW_INCREASE=true
            if [[ $# -lt 2 ]] || [[ "$2" == --* ]]; then
                echo "ERROR: --allow-increase requires a non-empty rationale string" >&2
                exit 1
            fi
            # Reject empty or whitespace-only rationale
            trimmed=$(echo "$2" | tr -d '[:space:]')
            if [[ -z "$trimmed" ]]; then
                echo "ERROR: --allow-increase rationale must not be empty or whitespace-only" >&2
                exit 1
            fi
            INCREASE_RATIONALE="$2"
            shift 2
            ;;
        --baseline)
            BASELINE_FILE="$2"
            shift 2
            ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: Must specify --check or --update-baseline" >&2
    usage >&2
    exit 1
fi

# ── Discover target files (dedup symlinks by realpath) ──
discover_targets() {
    local targets=()
    local -A seen_realpaths=()
    for f in "${SPECTRA_HOME}"/bin/*.sh; do
        [[ -f "$f" ]] || continue
        local real
        real=$(realpath "$f" 2>/dev/null || readlink -f "$f" 2>/dev/null || echo "$f")
        if [[ -z "${seen_realpaths[$real]+x}" ]]; then
            seen_realpaths["$real"]=1
            targets+=("$f")
        fi
    done
    if [[ -f "${SPECTRA_HOME}/hooks/pre-commit" ]]; then
        local real
        real=$(realpath "${SPECTRA_HOME}/hooks/pre-commit" 2>/dev/null || echo "${SPECTRA_HOME}/hooks/pre-commit")
        if [[ -z "${seen_realpaths[$real]+x}" ]]; then
            seen_realpaths["$real"]=1
            targets+=("${SPECTRA_HOME}/hooks/pre-commit")
        fi
    fi
    printf '%s\n' "${targets[@]}"
}

# ── Get ShellCheck version ──
get_sc_version() {
    "$SHELLCHECK" --version 2>/dev/null | grep '^version:' | awk '{print $2}'
}

# ── Run ShellCheck on a single file, output JSON warnings ──
run_shellcheck_file() {
    local file="$1"
    "$SHELLCHECK" --severity=warning --format=json "$file" 2>/dev/null || true
}

# ── Build per-file, per-rule counts from ShellCheck JSON output ──
# Outputs JSON: { "total": N, "rules": { "SC1234": N, ... } }
count_warnings() {
    local json_output="$1"
    if [[ -z "$json_output" ]] || [[ "$json_output" == "[]" ]]; then
        echo '{"total":0,"rules":{}}'
        return
    fi
    echo "$json_output" | jq -c '
        {
            total: length,
            rules: (group_by(.code) | map({key: ("SC" + (.[0].code | tostring)), value: length}) | from_entries)
        }
    '
}

# ── Relative path from SPECTRA_HOME ──
rel_path() {
    local full="$1"
    echo "${full#"${SPECTRA_HOME}"/}"
}

# ══════════════════════════════════════════
# MODE: --update-baseline
# ══════════════════════════════════════════
if [[ "$MODE" == "update" ]]; then
    SC_VERSION=$(get_sc_version)
    if [[ -z "$SC_VERSION" ]]; then
        echo "ERROR: Could not determine shellcheck version" >&2
        exit 1
    fi

    GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    GRAND_TOTAL=0
    FILES_JSON="{}"

    while IFS= read -r target; do
        rel=$(rel_path "$target")
        json_output=$(run_shellcheck_file "$target")
        counts=$(count_warnings "$json_output")
        file_total=$(echo "$counts" | jq '.total')
        GRAND_TOTAL=$((GRAND_TOTAL + file_total))
        FILES_JSON=$(echo "$FILES_JSON" | jq --arg key "$rel" --argjson val "$counts" '. + {($key): $val}')
    done < <(discover_targets)

    # ── Check for increases if baseline already exists ──
    if [[ -f "$BASELINE_FILE" ]]; then
        HAS_INCREASE=false
        INCREASE_DETAILS=""

        while IFS= read -r key; do
            old_total=$(jq -r --arg k "$key" '.files[$k].total // 0' "$BASELINE_FILE")
            new_total=$(echo "$FILES_JSON" | jq -r --arg k "$key" '.[$k].total // 0')
            if [[ "$new_total" -gt "$old_total" ]]; then
                HAS_INCREASE=true
                INCREASE_DETAILS="${INCREASE_DETAILS}  ${key}: ${old_total} -> ${new_total}\n"
            fi
        done < <(echo "$FILES_JSON" | jq -r 'keys[]')

        if [[ "$HAS_INCREASE" == true ]]; then
            if [[ "$ALLOW_INCREASE" == true ]]; then
                echo "WARNING: Baseline increase allowed with rationale: ${INCREASE_RATIONALE}"
                echo -e "Increased files:\n${INCREASE_DETAILS}"
            else
                echo "ERROR: Baseline would increase for the following files:" >&2
                echo -e "${INCREASE_DETAILS}" >&2
                echo "Use --allow-increase \"rationale\" to override" >&2
                exit 1
            fi
        fi
    fi

    # ── Write baseline ──
    jq -n \
        --arg version "$SC_VERSION" \
        --arg generated "$GENERATED_AT" \
        --argjson files "$FILES_JSON" \
        --argjson total "$GRAND_TOTAL" \
        '{
            shellcheck_version: $version,
            generated_at: $generated,
            files: $files,
            total: $total
        }' > "$BASELINE_FILE"

    echo "Baseline written to ${BASELINE_FILE}"
    echo "  shellcheck_version: ${SC_VERSION}"
    echo "  total warnings: ${GRAND_TOTAL}"
    echo "  files: $(echo "$FILES_JSON" | jq 'keys | length')"
    exit 0
fi

# ══════════════════════════════════════════
# MODE: --check
# ══════════════════════════════════════════
if [[ "$MODE" == "check" ]]; then
    if [[ ! -f "$BASELINE_FILE" ]]; then
        echo "ERROR: Baseline file not found: ${BASELINE_FILE}" >&2
        echo "Run --update-baseline first" >&2
        exit 1
    fi

    # ── Version check ──
    SC_VERSION=$(get_sc_version)
    BASELINE_VERSION=$(jq -r '.shellcheck_version' "$BASELINE_FILE")
    if [[ "$SC_VERSION" != "$BASELINE_VERSION" ]]; then
        echo "ERROR: ShellCheck version mismatch" >&2
        echo "  runtime:  ${SC_VERSION}" >&2
        echo "  baseline: ${BASELINE_VERSION}" >&2
        echo "Update baseline with matching version or install shellcheck ${BASELINE_VERSION}" >&2
        exit 1
    fi

    VIOLATIONS=0

    while IFS= read -r target; do
        rel=$(rel_path "$target")

        # ── Check file exists in baseline ──
        baseline_entry=$(jq -r --arg k "$rel" '.files[$k] // empty' "$BASELINE_FILE")
        if [[ -z "$baseline_entry" ]]; then
            echo "FAIL  ${rel}: not in baseline (run --update-baseline to add)"
            VIOLATIONS=$((VIOLATIONS + 1))
            continue
        fi

        json_output=$(run_shellcheck_file "$target")
        counts=$(count_warnings "$json_output")

        # ── Per-file total check ──
        new_total=$(echo "$counts" | jq '.total')
        old_total=$(jq -r --arg k "$rel" '.files[$k].total' "$BASELINE_FILE")

        if [[ "$new_total" -gt "$old_total" ]]; then
            echo "FAIL  ${rel}: total warnings increased (${old_total} -> ${new_total})"
            VIOLATIONS=$((VIOLATIONS + 1))
        elif [[ "$new_total" -lt "$old_total" ]]; then
            echo "IMPROVED  ${rel}: warnings decreased (${old_total} -> ${new_total}) — update baseline to lock in"
        else
            echo "PASS  ${rel}: ${new_total} warnings (matches baseline)"
        fi

        # ── Per-rule check ──
        while IFS= read -r rule; do
            new_count=$(echo "$counts" | jq -r --arg r "$rule" '.rules[$r] // 0')
            old_count=$(jq -r --arg k "$rel" --arg r "$rule" '.files[$k].rules[$r] // 0' "$BASELINE_FILE")

            if [[ "$new_count" -gt "$old_count" ]]; then
                echo "  FAIL  ${rel} ${rule}: ${old_count} -> ${new_count}"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        done < <(echo "$counts" | jq -r '.rules | keys[]')

        # ── Check for new rules not in baseline ──
        while IFS= read -r rule; do
            baseline_has=$(jq -r --arg k "$rel" --arg r "$rule" '.files[$k].rules[$r] // empty' "$BASELINE_FILE")
            if [[ -z "$baseline_has" ]]; then
                new_count=$(echo "$counts" | jq -r --arg r "$rule" '.rules[$r] // 0')
                if [[ "$new_count" -gt 0 ]]; then
                    echo "  FAIL  ${rel} ${rule}: new rule not in baseline (${new_count} warnings)"
                    VIOLATIONS=$((VIOLATIONS + 1))
                fi
            fi
        done < <(echo "$counts" | jq -r '.rules | keys[]')

    done < <(discover_targets)

    echo ""
    if [[ $VIOLATIONS -gt 0 ]]; then
        echo "RATCHET FAILED: ${VIOLATIONS} violation(s)"
        exit 1
    else
        echo "RATCHET PASSED: all files within baseline"
        exit 0
    fi
fi
