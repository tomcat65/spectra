#!/usr/bin/env bash
# SPECTRA lib/loop-wiring.sh — Wiring gate for pre-commit verification
#
# Contract:
#   Globals required: SPECTRA_HOME, LOGS_DIR, BRANCH_NAME, SPECTRA_SKIP_WIRING (optional)
#   Functions required: (none)
#
# Exports:
#   run_wiring_gate() — returns 0 if OK, 1 if wiring failed

run_wiring_gate() {
    local task_id="$1"

    if [[ ! -f ".spectra/verify.yaml" ]] || ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        return 0
    fi

    echo "    Running wiring proof for Task ${task_id}..."
    git add -A 2>/dev/null || true

    local wiring_exit=0
    "${SPECTRA_HOME}/bin/spectra-verify-wiring.sh" . --task "${task_id}" \
        > "${LOGS_DIR}/task-${task_id}-wiring.log" 2>&1 || wiring_exit=$?

    if [[ "${SPECTRA_SKIP_WIRING:-0}" == "1" ]]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WIRING BYPASS: Task ${task_id} on branch ${BRANCH_NAME} — SPECTRA_SKIP_WIRING=1" \
            >> "${LOGS_DIR}/task-${task_id}-wiring.log"
        echo "    WARNING: Wiring proof bypassed (SPECTRA_SKIP_WIRING=1)"
        return 0
    elif [[ $wiring_exit -ne 0 ]]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WIRING FAILED: Task ${task_id} on branch ${BRANCH_NAME}" \
            >> "${LOGS_DIR}/task-${task_id}-wiring.log"
        echo "    WIRING FAILED: Task ${task_id} — routing to retry (wiring_gap)"
        return 1
    fi

    return 0
}
