#!/usr/bin/env bash
# SPECTRA lib/loop-retry.sh — Retry budget and task summary
#
# Contract:
#   Globals required: SPECTRA_DIR, SPECTRA_HOME
#   Functions required: (none)
#
# Exports:
#   max_retries_for(), generate_task_summary(), propagate_signs()

max_retries_for() {
    local failure_type="$1"
    case "$failure_type" in
        test_failure|missing_dependency) echo 3 ;;
        wiring_gap)                      echo 2 ;;
        *)                               echo 0 ;;  # STUCK
    esac
}

# should_fast_escalate — Check if the same failure fingerprint repeats (Phase F: adaptive retry).
#   If the same failure type appears in consecutive retries for the same task,
#   the retry is likely wasting budget. Return 0 (true) to escalate early.
#   Args: task_id, current_failure_type, task_failure_history (comma-separated)
#   Returns: 0 if should escalate, 1 if should continue retrying
should_fast_escalate() {
    local task_id="$1"
    local current_type="${2:-}"
    local history="${3:-}"

    [[ -z "${current_type}" ]] && return 1
    [[ -z "${history}" ]] && return 1

    # Count consecutive occurrences of the same type at the end of history
    local consecutive=0
    local IFS=','
    local types=()
    read -ra types <<< "${history}"

    local i
    for (( i=${#types[@]}-1; i>=0; i-- )); do
        local t="${types[$i]}"
        t=$(echo "${t}" | tr -d ' ')
        if [[ "${t}" == "${current_type}" ]]; then
            consecutive=$((consecutive + 1))
        else
            break
        fi
    done

    # 2+ consecutive identical failures → escalate
    if [[ ${consecutive} -ge 2 ]]; then
        echo "  Adaptive retry: ${consecutive} consecutive ${current_type} failures on Task ${task_id} — fast escalating" >&2
        return 0
    fi

    return 1
}

generate_task_summary() {
    local task_num="$1" task_title="$2" result="$3" iteration="$4"

    local summary_line
    if [[ "$result" == "PASS" ]] && [[ "$iteration" -eq 1 ]]; then
        summary_line="- Task ${task_num} (${task_title}): PASS on first attempt"
    elif [[ "$result" == "PASS" ]]; then
        summary_line="- Task ${task_num} (${task_title}): PASS after ${iteration} iterations"
    else
        summary_line="- Task ${task_num} (${task_title}): ${result} (${iteration} iterations)"
    fi

    local files_changed=""
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        files_changed=$(git diff --name-only HEAD~1 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//' || echo "unknown")
    fi

    if [[ -f CLAUDE.md ]]; then
        if grep -q '## Task History' CLAUDE.md 2>/dev/null; then
            {
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        else
            {
                echo ""
                echo "## Task History"
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        fi
    fi
}

propagate_signs() {
    local guardrails_local="${SPECTRA_DIR}/guardrails.md"
    local guardrails_global="${SPECTRA_HOME}/guardrails-global.md"

    if [[ ! -f "$guardrails_local" ]] || [[ ! -f "$guardrails_global" ]]; then
        return
    fi

    while IFS= read -r sign_line; do
        local sign_id
        sign_id=$(echo "$sign_line" | grep -oP 'SIGN-\d+' || echo "")
        if [[ -n "$sign_id" ]] && ! grep -q "$sign_id" "$guardrails_global" 2>/dev/null; then
            local line_num desc_line
            line_num=$(grep -n "$sign_id" "$guardrails_local" | head -1 | cut -d: -f1)
            desc_line=$(sed -n "$((line_num + 1))p" "$guardrails_local" 2>/dev/null || echo "")
            {
                echo ""
                echo "$sign_line"
                echo "$desc_line"
            } >> "$guardrails_global"
            echo "  Sign propagated to global: ${sign_id}"
        fi
    done < <(grep -E "^### SIGN-" "$guardrails_local" 2>/dev/null || true)
}
