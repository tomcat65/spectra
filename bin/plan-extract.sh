#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Extractor — plan.md → plan.json
# Thin wrapper over the typed structured helper.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"

exec python3 "${SPECTRA_HOME}/scripts/spectra-structured.py" plan extract "$@"
