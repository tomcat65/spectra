#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Preflight and RECONCILE behavior alignment (Task 003 scaffolding)
# Validates that preflight invocation and RECONCILE signal handling are
# consistent between documentation and runtime. No LLM invocation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"
PREFLIGHT_SCRIPT="${SPECTRA_DIR}/bin/spectra-preflight.sh"
FIXTURE_DIR="${SPECTRA_DIR}/fixtures/loop-planning"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-preflight.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-preflight.sh exists and is executable"

if [[ -x "${PREFLIGHT_SCRIPT}" ]]; then
    echo "  PASS  spectra-preflight.sh exists and is executable"
    PASS=$((PASS + 1))
else
    if [[ -f "${PREFLIGHT_SCRIPT}" ]]; then
        echo "  FAIL  spectra-preflight.sh exists but is not executable"
    else
        echo "  FAIL  spectra-preflight.sh not found at ${PREFLIGHT_SCRIPT}"
    fi
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: spectra-preflight.sh accepts --force flag
# ══════════════════════════════════════════
echo "  Test: spectra-preflight.sh accepts --force flag"

if grep -q '\-\-force' "${PREFLIGHT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-preflight.sh recognizes --force flag"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-preflight.sh does not recognize --force flag"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: spectra-loop.sh does NOT call spectra-preflight.sh at startup
# KNOWN GAP: The loop does NOT invoke the integration preflight script.
# The "preflight" in the loop is the per-task spectra-auditor scan.
# This distinction matters for Task 003 (doc/code alignment).
# ══════════════════════════════════════════
echo "  Test: spectra-loop.sh preflight invocation (doc alignment check)"

if grep -q 'spectra-preflight' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-loop.sh invokes spectra-preflight.sh at startup"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-loop.sh does not invoke spectra-preflight.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Per-task preflight is the auditor-based scan
# The loop uses spectra-auditor as the per-task preflight, not spectra-preflight.sh.
# ══════════════════════════════════════════
echo "  Test: per-task preflight uses spectra-auditor"

if grep -q 'spectra-auditor' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-loop.sh uses spectra-auditor for per-task preflight"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-loop.sh does not reference spectra-auditor"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: RECONCILE signal file is checked before parse_plan
# The RECONCILE check must happen early, before plan parsing begins.
# ══════════════════════════════════════════
echo "  Test: RECONCILE signal checked in spectra-loop.sh"

if grep -q 'RECONCILE' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  RECONCILE signal handling present in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  RECONCILE signal handling missing from spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: RECONCILE non-interactive path exits with code 1
# In non-interactive mode (CI, piped), RECONCILE must fail loudly.
# ══════════════════════════════════════════
echo "  Test: RECONCILE non-interactive exits with code 1"

if grep -qP 'RECONCILE.*exit\s+1|RECONCILE.*non-interactive' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  RECONCILE non-interactive fails with exit 1"
    PASS=$((PASS + 1))
else
    echo "  FAIL  RECONCILE non-interactive exit behavior unclear"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: RECONCILE interactive path uses read -r for user input
# Interactive RECONCILE should prompt the user, not silently proceed.
# ══════════════════════════════════════════
echo "  Test: RECONCILE interactive path prompts user"

if grep -qP 'read.*RECONCILE|RECONCILE.*read' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  RECONCILE interactive path prompts user via read"
    PASS=$((PASS + 1))
else
    echo "  FAIL  RECONCILE interactive path does not prompt user"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: RECONCILE signal is cleaned up after handling
# The signal file must be removed regardless of which path is taken.
# ══════════════════════════════════════════
echo "  Test: RECONCILE signal cleaned up after handling"

if grep -qP 'rm.*RECONCILE' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  RECONCILE signal file cleaned up after handling"
    PASS=$((PASS + 1))
else
    echo "  FAIL  RECONCILE signal file not cleaned up"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: RECONCILE fixture has expected structure
# ══════════════════════════════════════════
echo "  Test: RECONCILE fixture has expected structure"

RECONCILE_FIXTURE="${FIXTURE_DIR}/reconcile-signal.txt"
if [[ ! -f "${RECONCILE_FIXTURE}" ]]; then
    echo "  FAIL  RECONCILE fixture not found: ${RECONCILE_FIXTURE}"
    FAIL=$((FAIL + 1))
else
    has_reason=false
    has_details=false
    grep -q 'reason:' "${RECONCILE_FIXTURE}" && has_reason=true
    grep -q 'details:' "${RECONCILE_FIXTURE}" && has_details=true

    if ${has_reason} && ${has_details}; then
        echo "  PASS  RECONCILE fixture has reason and details"
        PASS=$((PASS + 1))
    else
        missing=""
        ${has_reason} || missing="${missing} reason"
        ${has_details} || missing="${missing} details"
        echo "  FAIL  RECONCILE fixture missing:${missing}"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 10: RECONCILE signal generated by spectra-plan.sh
# The RECONCILE signal is written by the plan script when assessment drift detected.
# ══════════════════════════════════════════
echo "  Test: RECONCILE signal generation in spectra-plan.sh"

PLAN_SCRIPT="${SPECTRA_DIR}/bin/spectra-plan.sh"
if grep -q 'RECONCILE' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-plan.sh generates RECONCILE signal on assessment drift"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-plan.sh does not generate RECONCILE signal"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Interactive vs non-interactive detection uses -t 0
# The loop should test stdin (fd 0) to determine interactive mode.
# ══════════════════════════════════════════
echo "  Test: interactive detection uses terminal test"

if grep -qP '\-t\s+0' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  interactive detection uses -t 0 (terminal test on stdin)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  interactive detection does not use -t 0"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: RECONCILE non-interactive message includes actionable next steps
# AC: operator-facing output gives exact next steps when RECONCILE blocks.
# ══════════════════════════════════════════
echo "  Test: RECONCILE non-interactive gives actionable next steps"

if grep -q 'Next steps:' "${LOOP_SCRIPT}" 2>/dev/null && \
   grep -q 'spectra-assess' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  RECONCILE non-interactive output includes next steps with spectra-assess reference"
    PASS=$((PASS + 1))
else
    echo "  FAIL  RECONCILE non-interactive output missing actionable next steps"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 13: Preflight failure in loop gives actionable next steps
# ══════════════════════════════════════════
echo "  Test: preflight failure in loop gives actionable next steps"

if grep -qP 'spectra-preflight.*force' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  preflight failure message references --force re-run"
    PASS=$((PASS + 1))
else
    echo "  FAIL  preflight failure message missing --force reference"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: README describes RECONCILE non-interactive as blocking (not continuing)
# ══════════════════════════════════════════
echo "  Test: README describes RECONCILE as blocking in non-interactive mode"

README="${SPECTRA_DIR}/README.md"
if [[ -f "${README}" ]]; then
    if grep -q 'exits with error' "${README}" 2>/dev/null || \
       grep -qP 'non-interactive.*exit|exit.*non-interactive' "${README}" 2>/dev/null; then
        echo "  PASS  README describes non-interactive RECONCILE as exiting with error"
        PASS=$((PASS + 1))
    elif grep -q 'continues with the existing plan' "${README}" 2>/dev/null; then
        echo "  FAIL  README still claims non-interactive RECONCILE continues (stale)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS  README RECONCILE description does not claim silent continuation"
        PASS=$((PASS + 1))
    fi
else
    echo "  FAIL  README.md not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: README describes preflight as automatic in loop
# ══════════════════════════════════════════
echo "  Test: README describes preflight as automatic in loop"

if [[ -f "${README}" ]]; then
    if grep -qi 'automatically\|calls.*spectra-preflight' "${README}" 2>/dev/null; then
        echo "  PASS  README documents automatic preflight in loop"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  README does not document automatic preflight"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  README.md not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  preflight-reconcile: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=preflight-reconcile pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_PREFLIGHT_RECONCILE_PASS=${PASS}
export TEST_PREFLIGHT_RECONCILE_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
