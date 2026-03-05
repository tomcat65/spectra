#!/usr/bin/env bash
# SPECTRA lib/loop-stuck-recovery.sh — Party Mode STUCK recovery
#
# Contract:
#   Globals required: SIGNALS_DIR, LOGS_DIR
#
# Exports:
#   classify_stuck(), attempt_recovery(), handle_stuck()

classify_stuck() {
    local stuck_file="$1"
    local reason
    reason=$(grep -i 'Reason:' "$stuck_file" 2>/dev/null | head -1 | sed 's/.*Reason:[[:space:]]*//' || true)
    if [[ -z "$reason" ]]; then
        reason=$(cat "$stuck_file" 2>/dev/null || true)
    fi
    local lower
    lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')

    # dependency_failure: pip, npm, yarn, build, install errors
    if echo "$lower" | grep -qE '(npm.err|pip.*install|yarn.*error|dependency|missing.*package|build.*error|ERESOLVE|module.*not.*found|no matching version|could not resolve)'; then
        echo "dependency_failure"
        return 0
    fi

    # environment_issue: missing tool, wrong version, permission
    if echo "$lower" | grep -qE '(command not found|not installed|permission denied|wrong version|tool.*missing|env.*not set|no such file|EACCES|executable.*not found)'; then
        echo "environment_issue"
        return 0
    fi

    # spec_conflict: contradictory requirements
    if echo "$lower" | grep -qE '(contradict|conflict.*requirement|impossible.*constraint|mutually exclusive|incompatible.*spec|spec.*conflict|cannot satisfy both)'; then
        echo "spec_conflict"
        return 0
    fi

    echo "unknown"
}

attempt_recovery() {
    local classification="$1"
    local task_id="$2"
    local stuck_reason="$3"

    case "$classification" in
        dependency_failure)
            mkdir -p "$(dirname "${SIGNALS_DIR}/RECOVERY_PLAN")"
            cat > "${SIGNALS_DIR}/RECOVERY_PLAN" <<EOF
## Recovery Plan — Task ${task_id}
- Classification: dependency_failure
- Stuck Reason: ${stuck_reason}
- Suggested Fix: Re-run package install with clean cache, check lock file consistency
- Auto-recoverable: yes
EOF
            return 0
            ;;
        environment_issue)
            mkdir -p "$(dirname "${SIGNALS_DIR}/RECOVERY_PLAN")"
            cat > "${SIGNALS_DIR}/RECOVERY_PLAN" <<EOF
## Recovery Plan — Task ${task_id}
- Classification: environment_issue
- Stuck Reason: ${stuck_reason}
- Suggested Fix: Verify tool availability, check PATH, confirm required versions
- Auto-recoverable: yes
EOF
            return 0
            ;;
        spec_conflict|unknown|*)
            return 1
            ;;
    esac
}

handle_stuck() {
    local task_id="$1"
    local stuck_file="${SIGNALS_DIR}/STUCK"

    if [[ ! -f "$stuck_file" ]]; then
        return 1
    fi

    local reason
    reason=$(grep -i 'Reason:' "$stuck_file" 2>/dev/null | head -1 | sed 's/.*Reason:[[:space:]]*//' || true)
    if [[ -z "$reason" ]]; then
        reason=$(head -5 "$stuck_file" 2>/dev/null || true)
    fi

    local classification
    classification=$(classify_stuck "$stuck_file")

    # Always write recovery log
    mkdir -p "${LOGS_DIR}"
    cat > "${LOGS_DIR}/task-${task_id}-recovery.md" <<EOF
## STUCK Recovery Attempt — Task ${task_id}
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Classification: ${classification}
- Reason: ${reason}
- Recovery-Attempted: yes
EOF

    if attempt_recovery "$classification" "$task_id" "$reason"; then
        cat >> "${LOGS_DIR}/task-${task_id}-recovery.md" <<EOF
- Result: RECOVERABLE — clearing STUCK signal
EOF
        rm -f "$stuck_file"
        return 0
    else
        cat >> "${LOGS_DIR}/task-${task_id}-recovery.md" <<EOF
- Result: NOT RECOVERABLE — preserving STUCK signal for human escalation
EOF
        return 1
    fi
}
