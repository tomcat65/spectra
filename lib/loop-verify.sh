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

    local prompt="Verify Task ${task_id}. Read CLAUDE.md and .spectra/plan.md section '## Task ${task_id}' for context. Output your verification report with 'Result: PASS' or 'Result: FAIL' and 'Failure Type:' if applicable. Depth: ${verify_depth}."

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
                verifier_type=$(grep -oiP 'Failure Type:\s*\K\S+' "${LOGS_DIR}/task-${task_id}-verify.md" | head -1 || echo "")
            fi
            echo "${verifier_type:-test_failure}"
            ;;
    esac
}
