#!/usr/bin/env bash
# SPECTRA install.sh — Set up SPECTRA CLI tools
set -euo pipefail

SPECTRA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing SPECTRA from ${SPECTRA_HOME}..."

# Ensure bin directory exists
if [[ ! -d "${SPECTRA_HOME}/bin" ]]; then
    echo "ERROR: ${SPECTRA_HOME}/bin not found. Is this a valid SPECTRA installation?" >&2
    exit 1
fi

# Add to PATH in shell RC
SHELL_RC="${HOME}/.bashrc"
PATH_ENTRY="export PATH=\"${SPECTRA_HOME}/bin:\${PATH}\""
if ! grep -qF "${SPECTRA_HOME}/bin" "${SHELL_RC}" 2>/dev/null; then
    {
        echo ''
        echo '# SPECTRA CLI tools'
        echo "${PATH_ENTRY}"
    } >> "${SHELL_RC}"
    echo "Added ${SPECTRA_HOME}/bin to PATH in ${SHELL_RC}. Run: source ${SHELL_RC}"
else
    echo "PATH already configured in ${SHELL_RC}."
fi

echo "SPECTRA installation complete."
