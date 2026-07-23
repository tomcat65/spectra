#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Post-Project Cleanup — v5.5
# End-of-project hygiene tool. Identifies dead scaffolds, stale fixtures,
# and cleanup candidates. Defaults to DRY-RUN (report only).
#
# Usage: spectra-refactor-clean [OPTIONS] [PROJECT_ROOT]
#   PROJECT_ROOT — project directory (default: .)
#
# This is NOT part of the core execution loop. Run it after a project
# completes to identify artifacts that can be safely removed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"

DRY_RUN=true
VERBOSE=false
PROJECT_ROOT=""

show_help() {
    cat <<EOF
SPECTRA Post-Project Cleanup — End-of-project hygiene tool

Usage: spectra-refactor-clean [OPTIONS] [PROJECT_ROOT]

Options:
  --apply       Actually remove identified files (default: dry-run)
  --verbose     Show detailed reasoning for each candidate
  -h, --help    Show this help

Categories scanned:
  1. Stale signal files     — .spectra/signals/* left from completed runs
  2. Session state files    — .spectra/session.state from interrupted runs
  3. Stale agent caches     — builder/verifier context caches (should not exist)
  4. Empty log directories  — .spectra/logs/ subdirectories with no content
  5. Orphaned plan artifacts — .spectra/plan.md.new, plan.json.bak from failed planning

Defaults to DRY-RUN: reports what it would clean without modifying anything.

This tool is for post-project hygiene. It is NOT a required execution phase
and is never called by the main loop.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   DRY_RUN=false; shift ;;
        --verbose) VERBOSE=true; shift ;;
        -h|--help) show_help ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
        *)
            PROJECT_ROOT="$1"; shift ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-.}"
SPECTRA_DIR="${PROJECT_ROOT}/.spectra"

# Verify we're in a SPECTRA project
if [[ ! -d "${SPECTRA_DIR}" ]]; then
    echo "ERROR: No .spectra directory found in ${PROJECT_ROOT}" >&2
    echo "This command should be run from a SPECTRA project root." >&2
    exit 1
fi

echo "══════════════════════════════════════════"
echo "  SPECTRA Post-Project Cleanup"
echo "  Project: ${PROJECT_ROOT}"
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  Mode: DRY-RUN (use --apply to remove)"
else
    echo "  Mode: APPLY (files will be removed)"
fi
echo "══════════════════════════════════════════"
echo ""

CANDIDATES=0
REMOVED=0

# Helper: report a candidate and optionally remove it
report_candidate() {
    local file_path="$1"
    local category="$2"
    local reason="$3"

    CANDIDATES=$((CANDIDATES + 1))
    echo "  [${category}] ${file_path}"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo "    Reason: ${reason}"
    fi

    if [[ "${DRY_RUN}" == "false" ]]; then
        rm -rf "${file_path}"
        REMOVED=$((REMOVED + 1))
    fi
}

# ── Category 1: Stale signal files ──
echo "Scanning: stale signal files..."
SIGNALS_DIR="${SPECTRA_DIR}/signals"
if [[ -d "${SIGNALS_DIR}" ]]; then
    for sig_file in "${SIGNALS_DIR}"/*; do
        [[ -f "${sig_file}" ]] || continue
        report_candidate "${sig_file}" "signal" "Leftover signal from completed/interrupted run"
    done
fi

# ── Category 2: Session state files ──
echo "Scanning: session state files..."
if [[ -f "${SPECTRA_DIR}/session.state" ]]; then
    report_candidate "${SPECTRA_DIR}/session.state" "session" "Orchestrator session state from interrupted run"
fi

# ── Category 3: Stale agent caches ──
echo "Scanning: stale agent caches..."
for cache_file in \
    "${SPECTRA_DIR}/builder-context.cache" \
    "${SPECTRA_DIR}/builder-session.state" \
    "${SPECTRA_DIR}/verifier-context.cache" \
    "${SPECTRA_DIR}/verifier-session.state"; do
    if [[ -f "${cache_file}" ]]; then
        report_candidate "${cache_file}" "cache" "Stale agent state violating fresh-context doctrine"
    fi
done

# ── Category 4: Empty log directories ──
echo "Scanning: empty log directories..."
LOGS_DIR="${SPECTRA_DIR}/logs"
if [[ -d "${LOGS_DIR}" ]]; then
    for log_sub in "${LOGS_DIR}"/*/; do
        [[ -d "${log_sub}" ]] || continue
        file_count=$(find "${log_sub}" -type f 2>/dev/null | wc -l)
        if [[ "${file_count}" -eq 0 ]]; then
            report_candidate "${log_sub}" "empty-dir" "Empty log subdirectory"
        fi
    done
fi

# ── Category 5: Orphaned plan artifacts ──
echo "Scanning: orphaned plan artifacts..."
for orphan in \
    "${SPECTRA_DIR}/plan.md.new" \
    "${SPECTRA_DIR}/plan.json.bak" \
    "${SPECTRA_DIR}/plan.md.rejected" \
    "${SPECTRA_DIR}/plan-review.md.draft"; do
    if [[ -f "${orphan}" ]]; then
        report_candidate "${orphan}" "orphan" "Leftover from failed or rejected planning pass"
    fi
done

# ── Summary ──
echo ""
echo "══════════════════════════════════════════"
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  Found: ${CANDIDATES} cleanup candidate(s)"
    if [[ ${CANDIDATES} -gt 0 ]]; then
        echo "  Run with --apply to remove them."
    else
        echo "  Project is clean — no stale artifacts found."
    fi
else
    echo "  Removed: ${REMOVED} of ${CANDIDATES} candidate(s)"
fi
echo "══════════════════════════════════════════"

exit 0
