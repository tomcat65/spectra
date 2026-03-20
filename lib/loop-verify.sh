#!/usr/bin/env bash
# SPECTRA lib/loop-verify.sh — Verify prompt generator and oracle failure classifier
#
# Contract:
#   Globals required:
#     verify_prompt():  TASK_IDS[]
#     oracle_classify(): DRY_RUN, LOGS_DIR
#
# Exports:
#   verify_prompt(), oracle_classify()

verify_prompt() {
    local idx="$1"
    local verify_depth="${2:-full}"
    local task_id="${TASK_IDS[$idx]}"

    local prompt="Verify Task ${task_id}."

    # Centralized context loading (lib/loop-context.sh)
    if declare -f context_files_for_verify >/dev/null 2>&1; then
        prompt+=" $(context_files_for_verify "$task_id" "$verify_depth")"
    else
        # Fallback: inline context if loop-context.sh not sourced
        prompt+=" Read CLAUDE.md and .spectra/plan.md section '## Task ${task_id}' for context. Depth: ${verify_depth}."
    fi

    prompt+=" Output your verification report with 'Result: PASS' or 'Result: FAIL' and 'Failure Type:' if applicable."

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

oracle_classify() {
    local task_id="$1"

    if [[ "$DRY_RUN" == true ]]; then
        echo "test_failure"
        return
    fi

    local classification
    classification=$(claude --agent spectra-oracle -p --permission-mode plan \
        --fallback-model sonnet \
        "Read .spectra/logs/task-${task_id}-verify.md. Classify the failure as EXACTLY one of: test_failure, missing_dependency, wiring_gap, architecture_mismatch, ambiguous_spec, external_blocker. Respond with ONLY the classification word, nothing else." \
        2>&1 | tail -1 | tr -d '[:space:]' || echo "")

    # Validate classification is one of the known types
    case "$classification" in
        test_failure|missing_dependency|wiring_gap|architecture_mismatch|ambiguous_spec|external_blocker)
            echo "$classification"
            ;;
        *)
            # If oracle returned garbage, fall back to verifier's reported type
            local verifier_type=""
            if [[ -f "${LOGS_DIR}/task-${task_id}-verify.md" ]]; then
                verifier_type=$(tr -d '*#' < "${LOGS_DIR}/task-${task_id}-verify.md" \
                    | grep -oiP 'Failure Type:\s*\K(test_failure|missing_dependency|wiring_gap|architecture_mismatch|ambiguous_spec|external_blocker)' \
                    | head -1 || echo "")
            fi
            echo "${verifier_type:-test_failure}"
            ;;
    esac
}
