#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  SPECTRA v3.1 — TeammateIdle Hook for Agent Teams            ║
# ║  Simplified safety net. Task assignment is the lead's job.   ║
# ║  Exit 0 = allow idle, Exit 2 = reject (don't idle yet).     ║
# ╚══════════════════════════════════════════════════════════════╝

SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"

# If COMPLETE or STUCK signal exists, allow idle (run is done)
if [[ -f "${SIGNALS_DIR}/COMPLETE" ]] || [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
    exit 0
fi

# If uncommitted changes exist, reject idle (don't idle with dirty state)
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        echo "{\"rejection_reason\": \"Uncommitted changes detected. Commit or stash before idling.\"}"
        exit 2
    fi
fi

# Otherwise, allow idle — the lead handles task assignment via SendMessage
exit 0
