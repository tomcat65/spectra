#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test Runner
# Runs all test suites and reports aggregate pass/fail counts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITE_FAILURES=0

# ══════════════════════════════════════════
# Suite 0: Bash syntax check on all bin/*.sh scripts
# ══════════════════════════════════════════
echo "=== Suite: bash -n syntax check ==="
SYNTAX_PASS=0
SYNTAX_FAIL=0

for script in "${SPECTRA_DIR}"/bin/*.sh; do
    name="$(basename "${script}")"
    if bash -n "${script}" 2>/dev/null; then
        echo "  PASS  ${name}"
        SYNTAX_PASS=$((SYNTAX_PASS + 1))
    else
        echo "  FAIL  ${name} (syntax error)"
        SYNTAX_FAIL=$((SYNTAX_FAIL + 1))
    fi
done

echo ""
echo "  syntax-check: ${SYNTAX_PASS} passed, ${SYNTAX_FAIL} failed"
echo ""

TOTAL_PASS=$((TOTAL_PASS + SYNTAX_PASS))
TOTAL_FAIL=$((TOTAL_FAIL + SYNTAX_FAIL))
[[ ${SYNTAX_FAIL} -gt 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 1: Plan validation tests
# ══════════════════════════════════════════
echo "=== Suite: plan-validate ==="
set +e
output=$("${SCRIPT_DIR}/test-plan-validate.sh" 2>&1)
plan_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
plan_pass=$(echo "${output}" | grep -oP 'plan-validate: \K[0-9]+(?= passed)' || echo "0")
plan_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + plan_pass))
TOTAL_FAIL=$((TOTAL_FAIL + plan_fail))
[[ ${plan_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 2: Assessment tests
# ══════════════════════════════════════════
echo "=== Suite: assess ==="
set +e
output=$("${SCRIPT_DIR}/test-assess.sh" 2>&1)
assess_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
assess_pass=$(echo "${output}" | grep -oP 'assess: \K[0-9]+(?= passed)' || echo "0")
assess_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + assess_pass))
TOTAL_FAIL=$((TOTAL_FAIL + assess_fail))
[[ ${assess_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 3: Loop unit tests (Phase 1 quick wins)
# ══════════════════════════════════════════
echo "=== Suite: loop-unit ==="
set +e
output=$("${SCRIPT_DIR}/test-loop-unit.sh" 2>&1)
loop_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
loop_pass=$(echo "${output}" | grep -oP 'loop-unit: \K[0-9]+(?= passed)' || echo "0")
loop_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + loop_pass))
TOTAL_FAIL=$((TOTAL_FAIL + loop_fail))
[[ ${loop_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 4: Plan extraction tests (Phase 2)
# ══════════════════════════════════════════
echo "=== Suite: plan-extract ==="
set +e
output=$("${SCRIPT_DIR}/test-plan-extract.sh" 2>&1)
extract_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
extract_pass=$(echo "${output}" | grep -oP 'plan-extract: \K[0-9]+(?= passed)' || echo "0")
extract_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + extract_pass))
TOTAL_FAIL=$((TOTAL_FAIL + extract_fail))
[[ ${extract_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 5: Phase 3 enforcement tests
# ══════════════════════════════════════════
echo "=== Suite: phase3-enforcement ==="
set +e
output=$("${SCRIPT_DIR}/test-phase3-enforcement.sh" 2>&1)
phase3_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase3_pass=$(echo "${output}" | grep -oP 'phase3-enforcement: \K[0-9]+(?= passed)' || echo "0")
phase3_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase3_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase3_fail))
[[ ${phase3_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo "==============================="
echo "TOTAL: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo "==============================="

if [[ ${TOTAL_FAIL} -gt 0 ]]; then
    echo "RESULT: FAIL (${SUITE_FAILURES} suite(s) had failures)"
    exit 1
else
    echo "RESULT: PASS"
    exit 0
fi
