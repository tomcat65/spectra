#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: spectra-quick.sh operational coverage (Task 006)
# Validates the quick-mode script's argument handling, guard behavior,
# and prompt construction WITHOUT invoking the LLM.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
QUICK_SCRIPT="${SPECTRA_DIR}/bin/spectra-quick.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-quick.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-quick.sh exists and is executable"

if [[ -x "${QUICK_SCRIPT}" ]]; then
    echo "  PASS  spectra-quick.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-quick.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: --help exits 0 and shows usage
# ══════════════════════════════════════════
echo "  Test: --help exits 0"

set +e
help_out=$("${QUICK_SCRIPT}" --help 2>&1)
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
# Test 3: No arguments exits 0 (shows help)
# ══════════════════════════════════════════
echo "  Test: no arguments shows help"

set +e
no_arg_out=$("${QUICK_SCRIPT}" 2>&1)
no_arg_exit=$?
set -e

if [[ ${no_arg_exit} -eq 0 ]] && echo "${no_arg_out}" | grep -q 'Usage'; then
    echo "  PASS  no arguments shows help and exits 0"
    PASS=$((PASS + 1))
else
    echo "  FAIL  no arguments exit=${no_arg_exit}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Script references spectra-builder agent
# ══════════════════════════════════════════
echo "  Test: uses spectra-builder agent"

if grep -q 'spectra-builder' "${QUICK_SCRIPT}"; then
    echo "  PASS  references spectra-builder agent"
    PASS=$((PASS + 1))
else
    echo "  FAIL  does not reference spectra-builder"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: Script uses acceptEdits permission mode
# ══════════════════════════════════════════
echo "  Test: uses acceptEdits permission mode"

if grep -q 'acceptEdits' "${QUICK_SCRIPT}"; then
    echo "  PASS  uses acceptEdits permission mode"
    PASS=$((PASS + 1))
else
    echo "  FAIL  does not use acceptEdits"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: QUICK_CHAIN guard uses 1-hour threshold
# ══════════════════════════════════════════
echo "  Test: QUICK_CHAIN guard uses 1-hour threshold"

if grep -q '3600' "${QUICK_SCRIPT}"; then
    echo "  PASS  quick chain guard uses 3600s (1 hour) threshold"
    PASS=$((PASS + 1))
else
    echo "  FAIL  quick chain guard missing 3600s threshold"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Prompt includes guardrails reference
# ══════════════════════════════════════════
echo "  Test: prompt references guardrails"

if grep -q 'guardrails' "${QUICK_SCRIPT}"; then
    echo "  PASS  prompt references guardrails"
    PASS=$((PASS + 1))
else
    echo "  FAIL  prompt missing guardrails reference"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: Creates signals/ and logs/ directories
# ══════════════════════════════════════════
echo "  Test: creates signals/ and logs/ directories"

if grep -q 'mkdir -p.*LOGS_DIR.*SIGNALS_DIR\|mkdir -p.*SIGNALS_DIR.*LOGS_DIR' "${QUICK_SCRIPT}" 2>/dev/null || \
   grep -q 'mkdir.*logs.*signals\|mkdir.*signals.*logs' "${QUICK_SCRIPT}" 2>/dev/null; then
    echo "  PASS  creates required directories"
    PASS=$((PASS + 1))
else
    # Check for mkdir with the variable names on separate lines or same line
    if grep -q 'mkdir' "${QUICK_SCRIPT}" && grep -q 'LOGS_DIR' "${QUICK_SCRIPT}" && grep -q 'SIGNALS_DIR' "${QUICK_SCRIPT}"; then
        echo "  PASS  creates required directories (variable references present)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  missing directory creation"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 9: Writes quick report to logs/
# ══════════════════════════════════════════
echo "  Test: generates quick report to logs/"

if grep -q 'quick-.*\.md' "${QUICK_SCRIPT}"; then
    echo "  PASS  generates timestamped quick report"
    PASS=$((PASS + 1))
else
    echo "  FAIL  no quick report generation"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 10: Uses SPECTRA_HOME auto-detection pattern
# ══════════════════════════════════════════
echo "  Test: uses SPECTRA_HOME auto-detection"

if grep -q 'SPECTRA_HOME=.*dirname.*SCRIPT_DIR' "${QUICK_SCRIPT}"; then
    echo "  PASS  uses SPECTRA_HOME auto-detection"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing SPECTRA_HOME auto-detection"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  quick: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=quick pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_QUICK_PASS=${PASS}
export TEST_QUICK_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
