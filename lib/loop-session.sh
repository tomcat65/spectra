#!/usr/bin/env bash
# RATIONALE: Library file — PROFILE_*/SESSION_* vars consumed by sourcing script (spectra-loop.sh)
# shellcheck disable=SC2034
# SPECTRA lib/loop-session.sh — Runtime Profiles and Session Persistence
#
# Provides explicit, environment-driven runtime depth profiles and
# orchestrator-only session state. Builder and verifier remain fresh-context
# by design — this module ONLY persists orchestrator/loop state.
#
# Contract:
#   Globals required: SPECTRA_DIR, LOGS_DIR
#
# Exports:
#   load_runtime_profile()    — reads SPECTRA_PROFILE or project.yaml
#   save_session_state()      — persists orchestrator checkpoint
#   load_session_state()      — restores orchestrator checkpoint
#   clear_session_state()     — removes session state (end of run)
#   session_guard_fresh()     — asserts builder/verifier have no stale state

# ══════════════════════════════════════════
# Runtime Profiles
# ══════════════════════════════════════════
# Profiles control verification depth, retry budget, and timeout behavior.
# Set via SPECTRA_PROFILE env var or project.yaml profile: field.
#
# Available profiles:
#   quick    — minimal verification, 1 retry, short timeouts (CI, demos)
#   standard — full verification, 3 retries, default timeouts (default)
#   thorough — full verification + wiring proof, 5 retries, extended timeouts

# Defaults (standard profile)
PROFILE_NAME="standard"
PROFILE_VERIFY_DEPTH="full"
PROFILE_MAX_RETRIES=3
PROFILE_BUILDER_TIMEOUT=600
PROFILE_VERIFIER_TIMEOUT=300
PROFILE_WIRING_PROOF=true

load_runtime_profile() {
    local requested_profile=""

    # Priority 1: SPECTRA_PROFILE env var (explicit, reversible)
    if [[ -n "${SPECTRA_PROFILE:-}" ]]; then
        requested_profile="${SPECTRA_PROFILE}"
    fi

    # Priority 2: project.yaml profile: field
    if [[ -z "${requested_profile}" && -f "${SPECTRA_DIR}/project.yaml" ]]; then
        requested_profile=$(grep -oP '^profile:\s*\K\S+' "${SPECTRA_DIR}/project.yaml" 2>/dev/null || true)
    fi

    # Priority 3: Auto-suggest from metrics history (Phase F)
    if [[ -z "${requested_profile}" ]] && declare -f _suggest_profile_from_metrics >/dev/null 2>&1; then
        local suggested
        suggested=$(_suggest_profile_from_metrics 2>/dev/null || echo "")
        if [[ -n "${suggested}" && "${suggested}" != "standard" ]]; then
            requested_profile="${suggested}"
            echo "  Auto-selected profile '${suggested}' from metrics history" >&2
        fi
    fi

    # Apply profile
    case "${requested_profile:-standard}" in
        quick)
            PROFILE_NAME="quick"
            PROFILE_VERIFY_DEPTH="graduated"
            PROFILE_MAX_RETRIES=1
            PROFILE_BUILDER_TIMEOUT=300
            PROFILE_VERIFIER_TIMEOUT=120
            PROFILE_WIRING_PROOF=false
            ;;
        standard)
            PROFILE_NAME="standard"
            PROFILE_VERIFY_DEPTH="full"
            PROFILE_MAX_RETRIES=3
            PROFILE_BUILDER_TIMEOUT=600
            PROFILE_VERIFIER_TIMEOUT=300
            PROFILE_WIRING_PROOF=true
            ;;
        thorough)
            PROFILE_NAME="thorough"
            PROFILE_VERIFY_DEPTH="full"
            PROFILE_MAX_RETRIES=5
            PROFILE_BUILDER_TIMEOUT=900
            PROFILE_VERIFIER_TIMEOUT=600
            PROFILE_WIRING_PROOF=true
            ;;
        *)
            echo "  WARNING: Unknown profile '${requested_profile}', using standard" >&2
            PROFILE_NAME="standard"
            ;;
    esac

    echo "  Runtime profile: ${PROFILE_NAME}"
}

# ══════════════════════════════════════════
# Session Persistence (orchestrator-only)
# ══════════════════════════════════════════
# Persists loop state for resume after interruption.
# NEVER persists builder or verifier context — they are fresh-context by design.

SESSION_FILE=""

_session_file_path() {
    echo "${SPECTRA_DIR}/session.state"
}

save_session_state() {
    local current_batch="${1:-}"
    local current_task_idx="${2:-0}"
    local retry_counts="${3:-}"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    SESSION_FILE=$(_session_file_path)

    cat > "${SESSION_FILE}" <<EOF
# SPECTRA Session State (orchestrator-only)
# This file is for loop resume — builder/verifier start fresh each task.
timestamp=${timestamp}
profile=${PROFILE_NAME}
batch=${current_batch}
task_idx=${current_task_idx}
retry_counts=${retry_counts}
EOF
}

load_session_state() {
    SESSION_FILE=$(_session_file_path)

    if [[ ! -f "${SESSION_FILE}" ]]; then
        return 1
    fi

    # Source the state file to restore variables
    local saved_profile saved_batch saved_task_idx saved_retry_counts
    saved_profile=$(grep -oP '^profile=\K.*' "${SESSION_FILE}" 2>/dev/null || echo "standard")
    saved_batch=$(grep -oP '^batch=\K.*' "${SESSION_FILE}" 2>/dev/null || echo "")
    saved_task_idx=$(grep -oP '^task_idx=\K.*' "${SESSION_FILE}" 2>/dev/null || echo "0")
    saved_retry_counts=$(grep -oP '^retry_counts=\K.*' "${SESSION_FILE}" 2>/dev/null || echo "")

    echo "  Resuming session: profile=${saved_profile}, task_idx=${saved_task_idx}"

    # Export for caller consumption
    SESSION_PROFILE="${saved_profile}"
    SESSION_BATCH="${saved_batch}"
    SESSION_TASK_IDX="${saved_task_idx}"
    SESSION_RETRY_COUNTS="${saved_retry_counts}"

    return 0
}

clear_session_state() {
    SESSION_FILE=$(_session_file_path)
    rm -f "${SESSION_FILE}"
}

# ══════════════════════════════════════════
# Fresh Context Guard
# ══════════════════════════════════════════
# Asserts that builder/verifier agent invocations do NOT carry stale state.
# Call this before spawning agents to verify the fresh-context doctrine.

session_guard_fresh() {
    local agent_type="${1:-builder}"  # "builder" or "verifier"

    # Check for stale agent-specific state files that should not exist
    local stale_files=()

    # Builder should not have leftover context from previous tasks
    if [[ "${agent_type}" == "builder" ]]; then
        [[ -f "${SPECTRA_DIR}/builder-context.cache" ]] && stale_files+=("builder-context.cache")
        [[ -f "${SPECTRA_DIR}/builder-session.state" ]] && stale_files+=("builder-session.state")
    fi

    # Verifier should not have leftover context from previous tasks
    if [[ "${agent_type}" == "verifier" ]]; then
        [[ -f "${SPECTRA_DIR}/verifier-context.cache" ]] && stale_files+=("verifier-context.cache")
        [[ -f "${SPECTRA_DIR}/verifier-session.state" ]] && stale_files+=("verifier-session.state")
    fi

    if [[ ${#stale_files[@]} -gt 0 ]]; then
        echo "  WARNING: Stale ${agent_type} state detected: ${stale_files[*]}" >&2
        echo "  Removing stale state to maintain fresh-context doctrine..." >&2
        for f in "${stale_files[@]}"; do
            rm -f "${SPECTRA_DIR}/${f}"
        done
    fi

    return 0
}
