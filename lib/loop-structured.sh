#!/usr/bin/env bash
# SPECTRA lib/loop-structured.sh — Typed helper bridge for plans, status, and metrics
#
# Contract:
#   Globals required: SPECTRA_HOME, SPECTRA_DIR
#
# Exports:
#   structured_helper(), structured_plan_load(), structured_plan_set_status(),
#   structured_status_snapshot(), structured_status_progress()

STRUCTURED_HELPER="${SPECTRA_HOME}/scripts/spectra-structured.py"

structured_helper() {
    python3 "${STRUCTURED_HELPER}" "$@"
}

structured_project_root() {
    if [[ "$(basename "${SPECTRA_DIR}")" == ".spectra" ]]; then
        dirname "${SPECTRA_DIR}"
    else
        pwd
    fi
}

structured_plan_load() {
    local plan_file="${SPECTRA_DIR}/plan.md"
    local plan_json="${SPECTRA_DIR}/plan.json"

    if [[ ! -f "${plan_file}" ]]; then
        echo "Error: No plan.md found." >&2
        return 1
    fi

    # RATIONALE: The helper generates a temporary shell payload at runtime for source <(...).
    # shellcheck disable=SC1090
    source <(structured_helper plan emit-shell --plan-file "${plan_file}" --plan-json "${plan_json}")
}

structured_plan_set_status() {
    local task_id="$1"
    local task_status="$2"

    structured_helper plan set-status \
        --plan-file "${SPECTRA_DIR}/plan.md" \
        --plan-json "${SPECTRA_DIR}/plan.json" \
        --task-id "${task_id}" \
        --status "${task_status}" >/dev/null
}

structured_status_snapshot() {
    structured_helper status snapshot \
        --project-root "$(structured_project_root)" \
        --output "${SPECTRA_DIR}/status.json" \
        --format json
}

structured_status_progress() {
    structured_helper status snapshot \
        --project-root "$(structured_project_root)" \
        --format progress
}
