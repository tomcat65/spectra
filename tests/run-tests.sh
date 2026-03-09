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
# Suite 6: Phase 4 CI parity tests
# ══════════════════════════════════════════
echo "=== Suite: phase4-ci ==="
set +e
output=$("${SCRIPT_DIR}/test-phase4-ci.sh" 2>&1)
phase4_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase4_pass=$(echo "${output}" | grep -oP 'phase4-ci: \K[0-9]+(?= passed)' || echo "0")
phase4_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase4_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase4_fail))
[[ ${phase4_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 7: Phase 5 ShellCheck ratchet tests
# ══════════════════════════════════════════
echo "=== Suite: phase5-ratchet ==="
set +e
output=$("${SCRIPT_DIR}/test-phase5-ratchet.sh" 2>&1)
phase5_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase5_pass=$(echo "${output}" | grep -oP 'phase5-ratchet: \K[0-9]+(?= passed)' || echo "0")
phase5_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase5_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase5_fail))
[[ ${phase5_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 8: Phase 6 modularization tests
# ══════════════════════════════════════════
echo "=== Suite: phase6-modular ==="
set +e
output=$("${SCRIPT_DIR}/test-phase6-modular.sh" 2>&1)
phase6_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase6_pass=$(echo "${output}" | grep -oP 'phase6-modular: \K[0-9]+(?= passed)' || echo "0")
phase6_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase6_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase6_fail))
[[ ${phase6_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 9: Phase 7 ShellCheck burn-down tests
# ══════════════════════════════════════════
echo "=== Suite: phase7-shellcheck ==="
set +e
output=$("${SCRIPT_DIR}/test-phase7-shellcheck.sh" 2>&1)
phase7_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase7_pass=$(echo "${output}" | grep -oP 'phase7-shellcheck: \K[0-9]+(?= passed)' || echo "0")
phase7_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase7_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase7_fail))
[[ ${phase7_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 10: Phase 8 behavior parity tests
# ══════════════════════════════════════════
echo "=== Suite: phase8-behavior ==="
set +e
output=$("${SCRIPT_DIR}/test-phase8-behavior.sh" 2>&1)
phase8_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase8_pass=$(echo "${output}" | grep -oP 'phase8-behavior: \K[0-9]+(?= passed)' || echo "0")
phase8_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase8_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase8_fail))
[[ ${phase8_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 11: Phase 9 continuous learning tests
# ══════════════════════════════════════════
echo "=== Suite: phase9-lessons ==="
set +e
output=$("${SCRIPT_DIR}/test-phase9-lessons.sh" 2>&1)
phase9_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
phase9_pass=$(echo "${output}" | grep -oP 'phase9-lessons: \K[0-9]+(?= passed)' || echo "0")
phase9_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + phase9_pass))
TOTAL_FAIL=$((TOTAL_FAIL + phase9_fail))
[[ ${phase9_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 12: Agent routing tests
# ══════════════════════════════════════════
echo "=== Suite: agent-routing ==="
set +e
output=$("${SCRIPT_DIR}/test-agent-routing.sh" 2>&1)
routing_exit=$?
set -e
echo "${output}"
echo ""

# Parse pass/fail counts from the sub-test output
routing_pass=$(echo "${output}" | grep -oP 'agent-routing: \K[0-9]+(?= passed)' || echo "0")
routing_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + routing_pass))
TOTAL_FAIL=$((TOTAL_FAIL + routing_fail))
[[ ${routing_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 13: Phase D STUCK recovery tests
# ══════════════════════════════════════════
echo "=== Suite: phase-d-stuck ==="
set +e
output=$("${SCRIPT_DIR}/test-phase-d-stuck.sh" 2>&1)
stuck_exit=$?
set -e
echo "${output}"
echo ""

stuck_pass=$(echo "${output}" | grep -oP '\K[0-9]+(?= passed)' | tail -1 || echo "0")
stuck_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' | tail -1 || echo "0")
TOTAL_PASS=$((TOTAL_PASS + stuck_pass))
TOTAL_FAIL=$((TOTAL_FAIL + stuck_fail))
[[ ${stuck_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 14: Phase D language profile tests
# ══════════════════════════════════════════
echo "=== Suite: phase-d-langprofile ==="
set +e
output=$("${SCRIPT_DIR}/test-phase-d-langprofile.sh" 2>&1)
langprofile_exit=$?
set -e
echo "${output}"
echo ""

langprofile_pass=$(echo "${output}" | grep -oP '\K[0-9]+(?= passed)' | tail -1 || echo "0")
langprofile_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' | tail -1 || echo "0")
TOTAL_PASS=$((TOTAL_PASS + langprofile_pass))
TOTAL_FAIL=$((TOTAL_FAIL + langprofile_fail))
[[ ${langprofile_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 15: Loop planning delegation tests (Task 001)
# ══════════════════════════════════════════
echo "=== Suite: loop-planning ==="
set +e
output=$("${SCRIPT_DIR}/test-loop-planning.sh" 2>&1)
loopplan_exit=$?
set -e
echo "${output}"
echo ""

loopplan_pass=$(echo "${output}" | grep -oP 'loop-planning: \K[0-9]+(?= passed)' || echo "0")
loopplan_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + loopplan_pass))
TOTAL_FAIL=$((TOTAL_FAIL + loopplan_fail))
[[ ${loopplan_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 16: Plan review gate tests (Task 002)
# ══════════════════════════════════════════
echo "=== Suite: plan-review-gate ==="
set +e
output=$("${SCRIPT_DIR}/test-plan-review-gate.sh" 2>&1)
reviewgate_exit=$?
set -e
echo "${output}"
echo ""

reviewgate_pass=$(echo "${output}" | grep -oP 'plan-review-gate: \K[0-9]+(?= passed)' || echo "0")
reviewgate_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + reviewgate_pass))
TOTAL_FAIL=$((TOTAL_FAIL + reviewgate_fail))
[[ ${reviewgate_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 17: Preflight and RECONCILE tests (Task 003)
# ══════════════════════════════════════════
echo "=== Suite: preflight-reconcile ==="
set +e
output=$("${SCRIPT_DIR}/test-preflight-reconcile.sh" 2>&1)
preflight_exit=$?
set -e
echo "${output}"
echo ""

preflight_pass=$(echo "${output}" | grep -oP 'preflight-reconcile: \K[0-9]+(?= passed)' || echo "0")
preflight_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + preflight_pass))
TOTAL_FAIL=$((TOTAL_FAIL + preflight_fail))
[[ ${preflight_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 18: Init drift and version consistency tests (Task 004)
# ══════════════════════════════════════════
echo "=== Suite: init-drift ==="
set +e
output=$("${SCRIPT_DIR}/test-init-drift.sh" 2>&1)
initdrift_exit=$?
set -e
echo "${output}"
echo ""

initdrift_pass=$(echo "${output}" | grep -oP 'init-drift: \K[0-9]+(?= passed)' || echo "0")
initdrift_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + initdrift_pass))
TOTAL_FAIL=$((TOTAL_FAIL + initdrift_fail))
[[ ${initdrift_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 19: Verify command detection tests (Task 005)
# ══════════════════════════════════════════
echo "=== Suite: verify-command-detection ==="
set +e
output=$("${SCRIPT_DIR}/test-verify-command-detection.sh" 2>&1)
verifycmd_exit=$?
set -e
echo "${output}"
echo ""

verifycmd_pass=$(echo "${output}" | grep -oP 'verify-command-detection: \K[0-9]+(?= passed)' || echo "0")
verifycmd_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + verifycmd_pass))
TOTAL_FAIL=$((TOTAL_FAIL + verifycmd_fail))
[[ ${verifycmd_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 20: Status dashboard tests (Task 006)
# ══════════════════════════════════════════
echo "=== Suite: status ==="
set +e
output=$("${SCRIPT_DIR}/test-status.sh" 2>&1)
status_exit=$?
set -e
echo "${output}"
echo ""

status_pass=$(echo "${output}" | grep -oP 'status: \K[0-9]+(?= passed)' || echo "0")
status_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + status_pass))
TOTAL_FAIL=$((TOTAL_FAIL + status_fail))
[[ ${status_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 21: Quick mode tests (Task 006)
# ══════════════════════════════════════════
echo "=== Suite: quick ==="
set +e
output=$("${SCRIPT_DIR}/test-quick.sh" 2>&1)
quick_exit=$?
set -e
echo "${output}"
echo ""

quick_pass=$(echo "${output}" | grep -oP 'quick: \K[0-9]+(?= passed)' || echo "0")
quick_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + quick_pass))
TOTAL_FAIL=$((TOTAL_FAIL + quick_fail))
[[ ${quick_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 22: Init end-to-end tests (Task 006)
# ══════════════════════════════════════════
echo "=== Suite: init-e2e ==="
set +e
output=$("${SCRIPT_DIR}/test-init-e2e.sh" 2>&1)
inite2e_exit=$?
set -e
echo "${output}"
echo ""

inite2e_pass=$(echo "${output}" | grep -oP 'init-e2e: \K[0-9]+(?= passed)' || echo "0")
inite2e_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + inite2e_pass))
TOTAL_FAIL=$((TOTAL_FAIL + inite2e_fail))
[[ ${inite2e_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 23: Context loading tests (Task 007)
# ══════════════════════════════════════════
echo "=== Suite: phase11-context-loading ==="
set +e
output=$("${SCRIPT_DIR}/test-phase11-context-loading.sh" 2>&1)
ctxload_exit=$?
set -e
echo "${output}"
echo ""

ctxload_pass=$(echo "${output}" | grep -oP 'phase11-context-loading: \K[0-9]+(?= passed)' || echo "0")
ctxload_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + ctxload_pass))
TOTAL_FAIL=$((TOTAL_FAIL + ctxload_fail))
[[ ${ctxload_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 24: Sign candidate discovery tests (Task 008)
# ══════════════════════════════════════════
echo "=== Suite: phase11-sign-candidates ==="
set +e
output=$("${SCRIPT_DIR}/test-phase11-sign-candidates.sh" 2>&1)
signcand_exit=$?
set -e
echo "${output}"
echo ""

signcand_pass=$(echo "${output}" | grep -oP 'phase11-sign-candidates: \K[0-9]+(?= passed)' || echo "0")
signcand_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + signcand_pass))
TOTAL_FAIL=$((TOTAL_FAIL + signcand_fail))
[[ ${signcand_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 25: Quality gate tests (Task 009)
# ══════════════════════════════════════════
echo "=== Suite: phase11-quality-gate ==="
set +e
output=$("${SCRIPT_DIR}/test-phase11-quality-gate.sh" 2>&1)
qualgate_exit=$?
set -e
echo "${output}"
echo ""

qualgate_pass=$(echo "${output}" | grep -oP 'phase11-quality-gate: \K[0-9]+(?= passed)' || echo "0")
qualgate_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + qualgate_pass))
TOTAL_FAIL=$((TOTAL_FAIL + qualgate_fail))
[[ ${qualgate_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 26: Runtime profiles tests (Task 010)
# ══════════════════════════════════════════
echo "=== Suite: phase11-runtime-profiles ==="
set +e
output=$("${SCRIPT_DIR}/test-phase11-runtime-profiles.sh" 2>&1)
rtprofile_exit=$?
set -e
echo "${output}"
echo ""

rtprofile_pass=$(echo "${output}" | grep -oP 'phase11-runtime-profiles: \K[0-9]+(?= passed)' || echo "0")
rtprofile_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + rtprofile_pass))
TOTAL_FAIL=$((TOTAL_FAIL + rtprofile_fail))
[[ ${rtprofile_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

# ══════════════════════════════════════════
# Suite 27: Post-project cleanup tests (Task 011)
# ══════════════════════════════════════════
echo "=== Suite: refactor-clean ==="
set +e
output=$("${SCRIPT_DIR}/test-refactor-clean.sh" 2>&1)
refclean_exit=$?
set -e
echo "${output}"
echo ""

refclean_pass=$(echo "${output}" | grep -oP 'refactor-clean: \K[0-9]+(?= passed)' || echo "0")
refclean_fail=$(echo "${output}" | grep -oP 'passed, \K[0-9]+(?= failed)' || echo "0")
TOTAL_PASS=$((TOTAL_PASS + refclean_pass))
TOTAL_FAIL=$((TOTAL_FAIL + refclean_fail))
[[ ${refclean_exit} -ne 0 ]] && SUITE_FAILURES=$((SUITE_FAILURES + 1))

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
