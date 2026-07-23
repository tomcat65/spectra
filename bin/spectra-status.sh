#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Status Dashboard
# Thin wrapper over the typed structured helper.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"
JSON_MODE=false
WATCH_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --watch) WATCH_MODE=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA Status Dashboard

Usage: spectra-status [OPTIONS]

Options:
  --json      Output as JSON (for programmatic consumption)
  --watch     Refresh every 5 seconds (Ctrl+C to stop)
  -h, --help  Show this help
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d ".spectra" ]]; then
    echo "Error: No .spectra/ directory found. Not a SPECTRA project." >&2
    exit 1
fi

render_once() {
    local format="text"
    if [[ "${JSON_MODE}" == true ]]; then
        format="json"
    fi

    python3 "${SPECTRA_HOME}/scripts/spectra-structured.py" status snapshot \
        --project-root "$(pwd)" \
        --output ".spectra/status.json" \
        --format "${format}"
}

if [[ "${WATCH_MODE}" == true ]]; then
    while true; do
        clear
        render_once
        sleep 5
    done
else
    render_once
fi
