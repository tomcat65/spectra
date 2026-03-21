#!/usr/bin/env bash
# RATIONALE: Library file — METRICS_* vars consumed by sourcing script (spectra-loop.sh)
# shellcheck disable=SC2034
# SPECTRA lib/loop-metrics.sh — Per-task Execution Metrics (Phase F)
#
# Records structured timing, retry, and failure data per task completion.
# Enables adaptive retry (F-002), retrospective (F-005), and auto-profile (F-006).
#
# Contract:
#   Globals required: SPECTRA_DIR, SPECTRA_HOME, SPECTRA_RUN_ID
#
# Exports:
#   record_task_metric()      — append one task result to JSONL metrics file
#   aggregate_metrics()       — compute summary stats from metrics history
#   read_metrics()            — read raw metrics for a project
#   generate_retrospective()  — produce human-readable run summary (F-005)
#   _suggest_profile_from_metrics() — recommend profile from history (F-006)

METRICS_DIR=""
METRICS_FILE=""

if ! declare -f structured_helper >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${SPECTRA_HOME}/lib/loop-structured.sh"
fi

_ensure_metrics_dir() {
    METRICS_DIR="${SPECTRA_DIR}/metrics"
    mkdir -p "${METRICS_DIR}"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"
}

record_task_metric() {
    local task_id="${1:?task_id required}"
    local result="${2:?result required}"
    local iterations="${3:-1}"
    local failure_type="${4:-}"
    local build_secs="${5:-0}"
    local verify_secs="${6:-0}"
    local run_id="${7:-${SPECTRA_RUN_ID:-unknown}}"

    _ensure_metrics_dir
    structured_helper metrics record \
        --spectra-dir "${SPECTRA_DIR}" \
        --task-id "${task_id}" \
        --result "${result}" \
        --iterations "${iterations}" \
        --failure-type "${failure_type}" \
        --build-secs "${build_secs}" \
        --verify-secs "${verify_secs}" \
        --run-id "${run_id}"
}

aggregate_metrics() {
    _ensure_metrics_dir
    structured_helper metrics aggregate --spectra-dir "${SPECTRA_DIR}"
}

read_metrics() {
    local max_lines="${1:-0}"

    _ensure_metrics_dir
    structured_helper metrics read --spectra-dir "${SPECTRA_DIR}" --max-lines "${max_lines}"
}

generate_retrospective() {
    local run_id="${1:-${SPECTRA_RUN_ID:-unknown}}"

    _ensure_metrics_dir
    structured_helper metrics retrospective --spectra-dir "${SPECTRA_DIR}" --run-id "${run_id}"
}

_suggest_profile_from_metrics() {
    _ensure_metrics_dir
    structured_helper metrics suggest-profile --spectra-dir "${SPECTRA_DIR}"
}
