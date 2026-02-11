#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Status Dashboard
# Reads observability signal files and displays current execution state.
# Usage: spectra-status [--json] [--watch]

SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
JSON_MODE=false
WATCH_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)  JSON_MODE=true; shift ;;
        --watch) WATCH_MODE=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA Status Dashboard

Usage: spectra-status [OPTIONS]

Options:
  --json    Output as JSON (for programmatic consumption)
  --watch   Refresh every 5 seconds (Ctrl+C to stop)
  -h, --help  Show this help

Reads signal files from .spectra/signals/:
  PHASE     Current phase (planning|executing|verifying|complete|stuck)
  AGENT     Active agent name
  PROGRESS  Task completion status
  COMPLETE  Completion marker (with timestamp)
  STUCK     Stuck marker (with reason)
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Guard: must be in a SPECTRA project ──
if [[ ! -d "${SPECTRA_DIR}" ]]; then
    echo "Error: No .spectra/ directory found. Not a SPECTRA project." >&2
    exit 1
fi

display_status() {
    local phase agent progress project_name project_level
    local total=0 done=0 stuck=0 remaining=0

    # Read signal files
    phase=$(cat "${SIGNALS_DIR}/PHASE" 2>/dev/null || echo "unknown")
    agent=$(cat "${SIGNALS_DIR}/AGENT" 2>/dev/null || echo "unknown")
    progress=$(cat "${SIGNALS_DIR}/PROGRESS" 2>/dev/null || echo "no data")

    # Read project info
    project_name="unknown"
    project_level="unknown"
    if [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
        project_name=$(grep -oP '^name:\s*\K.*' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 || echo "unknown")
        project_level=$(grep -oP '^level:\s*\K\d+' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 || echo "unknown")
    fi

    # Count tasks from plan.md directly for fresh numbers
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        total=${total:-0}
        done=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        done=${done:-0}
        stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        stuck=${stuck:-0}
        if [[ "$total" -eq 0 ]]; then
            total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            total=${total:-0}
            done=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            done=${done:-0}
            stuck=0
        fi
        remaining=$((total - done - stuck))
    fi

    # Check for terminal signals
    local complete_info="" stuck_info=""
    if [[ -f "${SIGNALS_DIR}/COMPLETE" ]]; then
        complete_info=$(grep -oP 'Elapsed:\s*\K.*' "${SIGNALS_DIR}/COMPLETE" 2>/dev/null | head -1 || echo "")
    fi
    if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
        stuck_info=$(grep -oP 'Reason:\s*\K.*' "${SIGNALS_DIR}/STUCK" 2>/dev/null | head -1 || echo "unknown reason")
    fi

    # Get branch
    local branch="unknown"
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    fi

    if [[ "${JSON_MODE}" == true ]]; then
        cat <<EOF
{
  "project": "${project_name}",
  "level": ${project_level},
  "phase": "${phase}",
  "agent": "${agent}",
  "branch": "${branch}",
  "tasks": {
    "total": ${total},
    "done": ${done},
    "stuck": ${stuck},
    "remaining": ${remaining}
  },
  "complete": $(if [[ -f "${SIGNALS_DIR}/COMPLETE" ]]; then echo "true"; else echo "false"; fi),
  "stuck_signal": $(if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then echo "\"${stuck_info}\""; else echo "null"; fi),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    else
        echo ""
        echo "  SPECTRA Status"
        echo "  ────────────────────────────────────"
        echo "  Project:  ${project_name}"
        echo "  Level:    ${project_level}"
        echo "  Branch:   ${branch}"
        echo "  Phase:    ${phase}"
        echo "  Agent:    ${agent}"
        echo "  ────────────────────────────────────"
        echo "  Tasks:    ${done}/${total} complete"
        echo "  Remaining: ${remaining}"
        echo "  Stuck:    ${stuck}"
        echo "  Progress: ${done}/${total} tasks (${stuck} stuck)"

        if [[ -n "${complete_info}" ]]; then
            echo "  ────────────────────────────────────"
            echo "  COMPLETE (elapsed: ${complete_info})"
        elif [[ -n "${stuck_info}" ]]; then
            echo "  ────────────────────────────────────"
            echo "  STUCK: ${stuck_info}"
        fi
        echo ""
    fi
}

if [[ "${WATCH_MODE}" == true ]]; then
    while true; do
        clear
        display_status
        sleep 5
    done
else
    display_status
fi
