#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  SPECTRA v3.1 — TaskCompleted Hook for Agent Teams           ║
# ║  Pure gate check — no external process spawning.             ║
# ║  Verification is the lead's job, not the hook's.             ║
# ║  Exit 0 = allow, Exit 2 = reject with feedback.             ║
# ╚══════════════════════════════════════════════════════════════╝

SPECTRA_DIR=".spectra"
LOGS_DIR="${SPECTRA_DIR}/logs"

# Read task context from stdin (JSON)
TASK_CONTEXT=$(cat)

# Extract task number from context
TASK_NUM=$(echo "$TASK_CONTEXT" | grep -oP '"taskNumber"\s*:\s*\K\d+' 2>/dev/null || echo "")
if [[ -z "$TASK_NUM" ]]; then
    TASK_NUM=$(echo "$TASK_CONTEXT" | grep -oP '"task_id"\s*:\s*\K\d+' 2>/dev/null || echo "")
fi

# Extract task subject to determine task type
TASK_SUBJECT=$(echo "$TASK_CONTEXT" | grep -oP '"subject"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")

# If we can't identify the task, allow completion
if [[ -z "$TASK_NUM" && -z "$TASK_SUBJECT" ]]; then
    exit 0
fi

# If this is a verify/audit/review task, always allow completion
if echo "$TASK_SUBJECT" | grep -qiE '(verify|audit|review|pre-flight|preflight)'; then
    exit 0
fi

# For build tasks: check if verify report exists and shows PASS
VERIFY_REPORT="${LOGS_DIR}/task-${TASK_NUM}-verify.md"

if [[ -f "$VERIFY_REPORT" ]]; then
    RESULT=$(grep -oiP 'Result:\s*\K\S+' "$VERIFY_REPORT" 2>/dev/null | head -1 || echo "")
    if [[ "${RESULT^^}" == "PASS" ]]; then
        exit 0
    else
        FAILURE_TYPE=$(grep -oiP 'Failure Type:\s*\K\S+' "$VERIFY_REPORT" 2>/dev/null | head -1 || echo "unknown")
        echo "{\"rejection_reason\": \"Verification FAILED for Task ${TASK_NUM} (type: ${FAILURE_TYPE}). See ${VERIFY_REPORT} for details.\"}"
        exit 2
    fi
fi

# No verify report yet — allow completion (lead handles verification spawning)
exit 0
