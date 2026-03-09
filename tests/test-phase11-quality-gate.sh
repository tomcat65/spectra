#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Language-aware quality gates (Task 009)
# Validates the quality gate script's language detection, tool selection,
# and integration with builder self-audit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
QUALITY_GATE="${SPECTRA_DIR}/scripts/spectra-quality-gate.sh"
SELF_AUDIT="${SPECTRA_DIR}/agents/scripts/builder-self-audit.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-quality-gate.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-quality-gate.sh exists and is executable"

if [[ -x "${QUALITY_GATE}" ]]; then
    echo "  PASS  spectra-quality-gate.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-quality-gate.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: --help exits 0
# ══════════════════════════════════════════
echo "  Test: --help exits 0"

set +e
help_out=$("${QUALITY_GATE}" --help 2>&1)
help_exit=$?
set -e

if [[ ${help_exit} -eq 0 ]] && echo "${help_out}" | grep -q 'Usage'; then
    echo "  PASS  --help exits 0 with usage text"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --help exit=${help_exit}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Exit code 2 when no language detected
# ══════════════════════════════════════════
echo "  Test: exit code 2 when no language detected"

(
    empty_dir=$(mktemp -d)
    set +e
    "${QUALITY_GATE}" "${empty_dir}" 2>/dev/null
    exit_code=$?
    set -e
    rm -rf "${empty_dir}"
    if [[ ${exit_code} -eq 2 ]]; then
        echo "  PASS  exits 2 when no language detected"
    else
        echo "  FAIL  expected exit 2, got ${exit_code}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: Detects Python from pyproject.toml
# ══════════════════════════════════════════
echo "  Test: detects Python from pyproject.toml"

(
    cd "${tmp_dir}"
    touch pyproject.toml
    set +e
    out=$("${QUALITY_GATE}" "${tmp_dir}" 2>&1)
    set -e
    if echo "${out}" | grep -q 'language=python'; then
        echo "  PASS  detected Python from pyproject.toml"
    else
        echo "  FAIL  did not detect Python"
        exit 1
    fi
    rm -f pyproject.toml
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Detects JavaScript from package.json
# ══════════════════════════════════════════
echo "  Test: detects JavaScript from package.json"

(
    cd "${tmp_dir}"
    touch package.json
    set +e
    out=$("${QUALITY_GATE}" "${tmp_dir}" 2>&1)
    set -e
    if echo "${out}" | grep -q 'language=javascript'; then
        echo "  PASS  detected JavaScript from package.json"
    else
        echo "  FAIL  did not detect JavaScript"
        exit 1
    fi
    rm -f package.json
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: Detects Bash from shell scripts
# ══════════════════════════════════════════
echo "  Test: detects Bash from shell scripts"

(
    cd "${tmp_dir}"
    mkdir -p bin lib
    touch bin/foo.sh lib/bar.sh
    set +e
    out=$("${QUALITY_GATE}" "${tmp_dir}" 2>&1)
    set -e
    if echo "${out}" | grep -q 'language=bash'; then
        echo "  PASS  detected Bash from shell scripts"
    else
        echo "  FAIL  did not detect Bash"
        exit 1
    fi
    rm -rf bin lib
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: --language override works
# ══════════════════════════════════════════
echo "  Test: --language override works"

(
    set +e
    out=$("${QUALITY_GATE}" --language python "${tmp_dir}" 2>&1)
    set -e
    if echo "${out}" | grep -q 'language=python'; then
        echo "  PASS  --language python override works"
    else
        echo "  FAIL  --language override not honored"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: --auto-fix flag accepted
# ══════════════════════════════════════════
echo "  Test: --auto-fix flag accepted"

if grep -q 'auto-fix\|AUTO_FIX' "${QUALITY_GATE}"; then
    echo "  PASS  --auto-fix flag recognized"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --auto-fix not recognized"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: Script supports all 5 languages (python, javascript, bash, go, rust)
# ══════════════════════════════════════════
echo "  Test: supports 5 languages"

missing_langs=""
for lang in python javascript bash go rust; do
    if ! grep -q "${lang})" "${QUALITY_GATE}" 2>/dev/null; then
        missing_langs="${missing_langs} ${lang}"
    fi
done

if [[ -z "${missing_langs}" ]]; then
    echo "  PASS  supports all 5 languages"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing language support:${missing_langs}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 10: Auto-fix is limited to safe operations (format, lint fix)
# Script should NOT run arbitrary commands with --auto-fix.
# ══════════════════════════════════════════
echo "  Test: auto-fix limited to safe operations"

# Check that auto-fix only calls known safe tools (black, ruff --fix, gofmt -w, prettier --write)
unsafe_patterns=$(grep -P 'AUTO_FIX.*true' "${QUALITY_GATE}" -A3 | grep -P 'rm |mv |curl |wget |eval ' || true)
if [[ -z "${unsafe_patterns}" ]]; then
    echo "  PASS  auto-fix only uses safe formatting tools"
    PASS=$((PASS + 1))
else
    echo "  FAIL  auto-fix uses potentially unsafe commands"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: builder-self-audit.sh references quality gate
# ══════════════════════════════════════════
echo "  Test: builder-self-audit.sh references quality gate"

if grep -q 'quality.gate\|spectra-quality-gate' "${SELF_AUDIT}" 2>/dev/null; then
    echo "  PASS  builder-self-audit.sh references quality gate"
    PASS=$((PASS + 1))
else
    echo "  FAIL  builder-self-audit.sh does not reference quality gate"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: Quality gate does not bypass verifier
# The script must NOT write any verifier signals or mark tasks as verified.
# ══════════════════════════════════════════
echo "  Test: quality gate does not bypass verifier"

if grep -qP 'PASS.*Task.*verified|mark.*complete|signal.*COMPLETE' "${QUALITY_GATE}" 2>/dev/null; then
    echo "  FAIL  quality gate appears to bypass verifier"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  quality gate does not bypass verifier authority"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 13: Script has valid bash syntax
# ══════════════════════════════════════════
echo "  Test: quality gate has valid syntax"

if bash -n "${QUALITY_GATE}" 2>/dev/null; then
    echo "  PASS  spectra-quality-gate.sh has valid syntax"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-quality-gate.sh has syntax errors"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: builder-self-audit.sh quality gate is advisory (non-blocking)
# ══════════════════════════════════════════
echo "  Test: quality gate in self-audit is advisory"

if grep -qP 'advisory|continuing audit' "${SELF_AUDIT}" 2>/dev/null; then
    echo "  PASS  quality gate is advisory in builder self-audit"
    PASS=$((PASS + 1))
else
    echo "  FAIL  quality gate may be blocking in builder self-audit"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: SPECTRA_HOME auto-detection
# ══════════════════════════════════════════
echo "  Test: uses SPECTRA_HOME auto-detection"

if grep -q 'SPECTRA_HOME=.*dirname.*SCRIPT_DIR' "${QUALITY_GATE}"; then
    echo "  PASS  uses SPECTRA_HOME auto-detection"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing SPECTRA_HOME auto-detection"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  phase11-quality-gate: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_PHASE11_QUALITY_GATE_PASS=${PASS}
export TEST_PHASE11_QUALITY_GATE_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
