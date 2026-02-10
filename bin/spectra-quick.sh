#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA Quick Mode — Ad-Hoc Task Execution                      ║
# ║  Skips planning. Builder implements + self-verifies in one shot.  ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-quick "description of change"

SPECTRA_HOME="${HOME}/.spectra"
SPECTRA_DIR=".spectra"
LOGS_DIR="${SPECTRA_DIR}/logs"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# ── Parse arguments ──
if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    cat <<EOF
SPECTRA Quick Mode — Ad-Hoc Task Execution

Usage: spectra-quick "description of change"

Skips planning entirely. Builder implements + self-verifies in one session.
Commits with 'quick: description' convention.

Options:
  -h, --help    Show this help

Guard:
  If a previous quick task ran < 1 hour ago, warns that you should
  consider using Level 1 planning instead (spectra-loop).
EOF
    exit 0
fi

DESCRIPTION="$1"

# ── Source env ──
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# ── Quick chain guard ──
if [[ -f "${SIGNALS_DIR}/QUICK_CHAIN" ]]; then
    LAST_QUICK=$(cat "${SIGNALS_DIR}/QUICK_CHAIN" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST_QUICK ))
    if [[ $ELAPSED -lt 3600 ]]; then
        MINS_AGO=$(( ELAPSED / 60 ))
        echo ""
        echo "  Warning: Previous quick task ran ${MINS_AGO} minutes ago."
        echo "  If you're chaining multiple changes, consider using Level 1 planning:"
        echo "    spectra-init --name \"feature\" --level 1"
        echo "    spectra-loop"
        echo ""
    fi
fi

# ── Ensure directories ──
mkdir -p "${LOGS_DIR}" "${SIGNALS_DIR}"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA Quick Mode                       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Task: ${DESCRIPTION}"
echo "  Time: ${TIMESTAMP}"
echo ""

# ── Build prompt ──
QUICK_PROMPT="You are in SPECTRA Quick Mode — a single-session ad-hoc task.

## Task
${DESCRIPTION}

## Rules
1. Implement the change described above.
2. Run tests to self-verify your work. If tests exist, they must all pass.
3. If no test framework exists, verify manually via CLI commands.
4. Commit with message: quick: ${DESCRIPTION}
5. Write a 5-line report to .spectra/logs/quick-${TIMESTAMP}.md:
   - What was changed
   - Files modified
   - Tests run (command + result)
   - Any risks or follow-up needed
   - Duration estimate

## Constraints
- ONE session, ONE task. Do not scope-creep.
- If the task is too large for a single session, write STUCK signal and exit.
- Read existing code before modifying.
- Follow existing code conventions."

# ── Read guardrails if available ──
if [[ -f "${SPECTRA_DIR}/guardrails.md" ]]; then
    QUICK_PROMPT="${QUICK_PROMPT}

## Active Signs
Read .spectra/guardrails.md for Sign patterns to avoid."
elif [[ -f "${SPECTRA_HOME}/guardrails-global.md" ]]; then
    QUICK_PROMPT="${QUICK_PROMPT}

## Global Signs
Read ${SPECTRA_HOME}/guardrails-global.md for Sign patterns to avoid."
fi

# ── Execute ──
echo "  Spawning builder (Opus, single session)..."
set +e
claude --agent spectra-builder -p --permission-mode acceptEdits \
    --prompt "${QUICK_PROMPT}" \
    --max-turns 30 2>&1 | tail -15
QUICK_EXIT=$?
set -e

# ── Record quick chain timestamp ──
date +%s > "${SIGNALS_DIR}/QUICK_CHAIN"

# ── Report ──
if [[ -f "${LOGS_DIR}/quick-${TIMESTAMP}.md" ]]; then
    echo ""
    echo "  Report: ${LOGS_DIR}/quick-${TIMESTAMP}.md"
fi

if [[ $QUICK_EXIT -eq 0 ]]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Quick Mode complete                      ║"
    echo "╚══════════════════════════════════════════╝"
else
    echo ""
    echo "  Quick Mode exited with code ${QUICK_EXIT}."
    echo "  Check ${LOGS_DIR}/quick-${TIMESTAMP}.md for details."
fi
