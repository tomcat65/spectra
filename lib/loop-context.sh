#!/usr/bin/env bash
# SPECTRA lib/loop-context.sh — Centralized context loading policy
#
# Single source of truth for what context files are available and how they
# should be referenced in agent prompts. Builder and verifier both call
# through this library instead of duplicating file references.
#
# Contract:
#   Globals required:
#     SPECTRA_HOME   — framework install root
#     SPECTRA_DIR    — project .spectra/ directory (typically ".spectra")
#     LOGS_DIR       — project logs directory
#
# Exports:
#   context_files_for_build()  — list of files builder should read
#   context_files_for_verify() — list of files verifier should read
#   context_prompt_suffix()    — shared context instructions for any agent

if ! declare -f structured_helper >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${SPECTRA_HOME}/lib/loop-structured.sh"
fi

# ── Context file existence check ──
# Returns 0 if the file exists, 1 otherwise. Logs optional warning.
_context_file_exists() {
    local path="$1"
    local label="${2:-}"
    if [[ -f "$path" ]]; then
        return 0
    else
        [[ -n "$label" ]] && echo "  context: ${label} not found (${path}), skipping" >&2
        return 1
    fi
}

# ── Core context files (always included) ──
# Returns newline-separated list of "Read <path>" instructions.
_core_context() {
    local task_id="$1"
    local instructions=""

    instructions+="Read CLAUDE.md for project context."
    instructions+=" Read ${SPECTRA_DIR}/plan.md section '## Task ${task_id}' for acceptance criteria and file ownership."

    if _context_file_exists "${SPECTRA_DIR}/guardrails.md"; then
        instructions+=" Read ${SPECTRA_DIR}/guardrails.md for active Signs."
    fi

    echo "$instructions"
}

# ── Lessons context (conditional) ──
# Only included if lessons-active.md exists.
_lessons_context() {
    if _context_file_exists "${SPECTRA_DIR}/lessons-active.md"; then
        echo " Read ${SPECTRA_DIR}/lessons-active.md for lessons from prior tasks."
    fi
}

# ── Reference materials for verification ──
_verify_references() {
    local refs=""

    local ref_dir="${SPECTRA_HOME}/agents/references"
    if _context_file_exists "${ref_dir}/failure-types.md"; then
        refs+=" Reference ${ref_dir}/failure-types.md for failure classification."
    fi

    echo "$refs"
}

# ══════════════════════════════════════════
# Public API
# ══════════════════════════════════════════

# context_files_for_build — Generate context instructions for builder prompt.
#   Args: task_id, iteration, preflight_advisory
#   Stdout: context instruction string (<500 bytes target)
context_files_for_build() {
    local task_id="$1"
    local iteration="${2:-1}"
    local preflight_advisory="${3:-}"

    local ctx
    ctx=$(_core_context "$task_id")
    ctx+=$(_lessons_context)

    if [[ "$iteration" -gt 1 ]]; then
        ctx+=" This is retry ${iteration}. Read ${SPECTRA_DIR}/logs/task-${task_id}-verify.md for the failure report. Fix the specific issues."
    fi

    if [[ -n "$preflight_advisory" ]]; then
        ctx+=" Pre-flight advisory: ${preflight_advisory}"
    fi

    # Phase F: Prior failure warnings from metrics history
    local prior_warning
    prior_warning=$(_prior_failure_context "$task_id" 2>/dev/null || echo "")
    if [[ -n "$prior_warning" ]]; then
        ctx+=" ${prior_warning}"
    fi

    echo "$ctx"
}

# context_files_for_verify — Generate context instructions for verifier prompt.
#   Args: task_id, verify_depth
#   Stdout: context instruction string (<500 bytes target)
context_files_for_verify() {
    local task_id="$1"
    local verify_depth="${2:-full}"

    local ctx
    ctx=$(_core_context "$task_id")
    ctx+=$(_lessons_context)
    ctx+=$(_verify_references)
    ctx+=" Depth: ${verify_depth}."

    echo "$ctx"
}

# _prior_failure_context — Check if similar failures occurred in recent history (Phase F).
#   Args: task_id
#   Stdout: warning string if relevant prior failure exists, empty otherwise
_prior_failure_context() {
    local task_id="$1"

    structured_helper metrics prior-failure \
        --spectra-dir "${SPECTRA_DIR}" \
        --task-id "${task_id}" 2>/dev/null || true
}

# context_prompt_suffix — Shared suffix for any agent context.
#   Currently returns empty string; reserved for future use
#   (e.g., cost budgets, time constraints).
context_prompt_suffix() {
    echo ""
}
