#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test Runner
# Runs all test suites and reports aggregate pass/fail counts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITE_FAILURES=0

# Force automated suites down non-interactive code paths even when the
# operator launches the runner from a PTY. This prevents nested scripts
# like spectra-init.sh from prompting and stalling the aggregate run.
exec </dev/null

parse_suite_result() {
    local expected_suite="$1"
    local output_file="$2"
    local result_line=""
    local result_suite=""
    local result_pass=""
    local result_fail=""
    local result_skip=""
    local result_total=""
    local token=""
    local key=""
    local value=""

    result_line=$(grep '^SPECTRA_TEST_RESULT ' "${output_file}" | tail -1 || true)
    if [[ -z "${result_line}" ]]; then
        return 1
    fi

    for token in ${result_line#SPECTRA_TEST_RESULT }; do
        key="${token%%=*}"
        value="${token#*=}"
        case "${key}" in
            suite) result_suite="${value}" ;;
            pass) result_pass="${value}" ;;
            fail) result_fail="${value}" ;;
            skip) result_skip="${value}" ;;
            total) result_total="${value}" ;;
        esac
    done

    if [[ "${result_suite}" != "${expected_suite}" ]]; then
        return 1
    fi

    if ! [[ "${result_pass}" =~ ^[0-9]+$ && "${result_fail}" =~ ^[0-9]+$ && "${result_skip}" =~ ^[0-9]+$ && "${result_total}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [[ $((result_pass + result_fail + result_skip)) -ne ${result_total} ]]; then
        return 1
    fi

    printf '%s %s %s %s\n' "${result_pass}" "${result_fail}" "${result_skip}" "${result_total}"
}

run_script_suite() {
    local suite_name="$1"
    local script_name="$2"
    local output_file=""
    local suite_exit=0
    local suite_pass=0
    local suite_fail=0
    local suite_skip=0
    local suite_total=0
    local suite_result=""

    output_file=$(mktemp)
    echo "=== Suite: ${suite_name} ==="

    set +e
    "${SCRIPT_DIR}/${script_name}" 2>&1 | tee "${output_file}"
    suite_exit=${PIPESTATUS[0]}
    set -e
    echo ""

    suite_result=$(parse_suite_result "${suite_name}" "${output_file}" || true)
    rm -f "${output_file}"

    if [[ -n "${suite_result}" ]]; then
        read -r suite_pass suite_fail suite_skip suite_total <<< "${suite_result}"
    else
        echo "  FAIL  ${suite_name}: missing or malformed SPECTRA_TEST_RESULT contract"
        suite_fail=1
    fi

    if [[ ${suite_exit} -ne 0 ]]; then
        SUITE_FAILURES=$((SUITE_FAILURES + 1))
        if [[ ${suite_fail} -eq 0 ]]; then
            echo "  FAIL  ${suite_name}: suite exited ${suite_exit} with zero recorded failures"
            suite_fail=1
        fi
    fi

    TOTAL_PASS=$((TOTAL_PASS + suite_pass))
    TOTAL_FAIL=$((TOTAL_FAIL + suite_fail))
}

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

run_script_suite "plan-validate" "test-plan-validate.sh"
run_script_suite "assess" "test-assess.sh"
run_script_suite "loop-unit" "test-loop-unit.sh"
run_script_suite "plan-extract" "test-plan-extract.sh"
run_script_suite "phase3-enforcement" "test-phase3-enforcement.sh"
run_script_suite "phase4-ci" "test-phase4-ci.sh"
run_script_suite "phase5-ratchet" "test-phase5-ratchet.sh"
run_script_suite "phase6-modular" "test-phase6-modular.sh"
run_script_suite "phase7-shellcheck" "test-phase7-shellcheck.sh"
run_script_suite "phase8-behavior" "test-phase8-behavior.sh"
run_script_suite "phase9-lessons" "test-phase9-lessons.sh"
run_script_suite "agent-routing" "test-agent-routing.sh"
run_script_suite "phase-d-stuck" "test-phase-d-stuck.sh"
run_script_suite "phase-d-langprofile" "test-phase-d-langprofile.sh"
run_script_suite "loop-planning" "test-loop-planning.sh"
run_script_suite "plan-review-gate" "test-plan-review-gate.sh"
run_script_suite "preflight-reconcile" "test-preflight-reconcile.sh"
run_script_suite "init-drift" "test-init-drift.sh"
run_script_suite "verify-command-detection" "test-verify-command-detection.sh"
run_script_suite "status" "test-status.sh"
run_script_suite "quick" "test-quick.sh"
run_script_suite "init-e2e" "test-init-e2e.sh"
run_script_suite "phase11-context-loading" "test-phase11-context-loading.sh"
run_script_suite "phase11-sign-candidates" "test-phase11-sign-candidates.sh"
run_script_suite "phase11-quality-gate" "test-phase11-quality-gate.sh"
run_script_suite "phase11-runtime-profiles" "test-phase11-runtime-profiles.sh"
run_script_suite "refactor-clean" "test-refactor-clean.sh"
run_script_suite "phaseF-metrics" "test-phaseF-metrics.sh"
run_script_suite "phaseF-feedback-loops" "test-phaseF-feedback-loops.sh"
run_script_suite "structured-helper" "test-structured-helper.sh"
run_script_suite "verify-project-trials" "test-verify-project-trials.sh"
run_script_suite "verdict-extraction" "test-verdict-extraction.sh"
run_script_suite "wiring-scope" "test-wiring-scope.sh"
run_script_suite "elicit" "test-elicit.sh"
run_script_suite "runtime-probe" "test-runtime-probe.sh"
run_script_suite "ci-parity" "test-ci-parity.sh"
run_script_suite "doctor" "test-doctor.sh"

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo "==============================="
echo "TOTAL: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo "==============================="

if [[ ${TOTAL_FAIL} -gt 0 || ${SUITE_FAILURES} -gt 0 ]]; then
    echo "RESULT: FAIL (${SUITE_FAILURES} suite(s) had failures)"
    exit 1
else
    echo "RESULT: PASS"
    exit 0
fi
