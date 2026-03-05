#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase D Tests — Party Mode STUCK Recovery
# Tests: classify_stuck, attempt_recovery, handle_stuck

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  FAIL  $1: $2"; }

# ── Setup / Teardown ──

TEST_SIGNALS_DIR=""
TEST_LOGS_DIR=""

setup_test_env() {
    TEST_SIGNALS_DIR=$(mktemp -d)
    TEST_LOGS_DIR=$(mktemp -d)
    export SIGNALS_DIR="${TEST_SIGNALS_DIR}"
    export LOGS_DIR="${TEST_LOGS_DIR}"
}

teardown_test_env() {
    rm -rf "${TEST_SIGNALS_DIR}" "${TEST_LOGS_DIR}"
}

# Source the module under test
source "${SPECTRA_HOME}/lib/loop-stuck-recovery.sh"

# ══════════════════════════════════════════
# TEST GROUP 1: classify_stuck
# ══════════════════════════════════════════

test_classify_dependency_failure() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: npm ERR! ERESOLVE unable to resolve dependency tree
EOF
    local result
    result=$(classify_stuck "${SIGNALS_DIR}/STUCK")
    if [[ "$result" == "dependency_failure" ]]; then
        pass "classify_dependency_failure"
    else
        fail "classify_dependency_failure" "expected dependency_failure, got ${result}"
    fi
    teardown_test_env
}

test_classify_dependency_pip() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: pip install failed: could not resolve dependencies
EOF
    local result
    result=$(classify_stuck "${SIGNALS_DIR}/STUCK")
    if [[ "$result" == "dependency_failure" ]]; then
        pass "classify_dependency_pip"
    else
        fail "classify_dependency_pip" "expected dependency_failure, got ${result}"
    fi
    teardown_test_env
}

test_classify_environment_issue() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: docker: command not found
EOF
    local result
    result=$(classify_stuck "${SIGNALS_DIR}/STUCK")
    if [[ "$result" == "environment_issue" ]]; then
        pass "classify_environment_issue"
    else
        fail "classify_environment_issue" "expected environment_issue, got ${result}"
    fi
    teardown_test_env
}

test_classify_spec_conflict() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: contradictory requirements: must use both ESM and CJS simultaneously
EOF
    local result
    result=$(classify_stuck "${SIGNALS_DIR}/STUCK")
    if [[ "$result" == "spec_conflict" ]]; then
        pass "classify_spec_conflict"
    else
        fail "classify_spec_conflict" "expected spec_conflict, got ${result}"
    fi
    teardown_test_env
}

test_classify_unknown() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: something entirely opaque happened
EOF
    local result
    result=$(classify_stuck "${SIGNALS_DIR}/STUCK")
    if [[ "$result" == "unknown" ]]; then
        pass "classify_unknown"
    else
        fail "classify_unknown" "expected unknown, got ${result}"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 2: attempt_recovery
# ══════════════════════════════════════════

test_attempt_recovery_dependency() {
    setup_test_env
    if attempt_recovery "dependency_failure" "101" "npm failed"; then
        pass "attempt_recovery_dependency"
    else
        fail "attempt_recovery_dependency" "expected return 0"
    fi
    teardown_test_env
}

test_attempt_recovery_environment() {
    setup_test_env
    if attempt_recovery "environment_issue" "102" "tool missing"; then
        pass "attempt_recovery_environment"
    else
        fail "attempt_recovery_environment" "expected return 0"
    fi
    teardown_test_env
}

test_attempt_recovery_spec_conflict() {
    setup_test_env
    if attempt_recovery "spec_conflict" "103" "contradictory"; then
        fail "attempt_recovery_spec_conflict" "expected return 1"
    else
        pass "attempt_recovery_spec_conflict"
    fi
    teardown_test_env
}

test_attempt_recovery_unknown() {
    setup_test_env
    if attempt_recovery "unknown" "104" "no idea"; then
        fail "attempt_recovery_unknown" "expected return 1"
    else
        pass "attempt_recovery_unknown"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 3: handle_stuck
# ══════════════════════════════════════════

test_handle_stuck_clears_recoverable() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: npm ERR! ERESOLVE unable to resolve dependency tree
EOF
    if handle_stuck "201"; then
        if [[ ! -f "${SIGNALS_DIR}/STUCK" ]]; then
            pass "handle_stuck_clears_recoverable"
        else
            fail "handle_stuck_clears_recoverable" "STUCK file still exists"
        fi
    else
        fail "handle_stuck_clears_recoverable" "handle_stuck returned 1"
    fi
    teardown_test_env
}

test_handle_stuck_preserves_non_recoverable() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: something entirely opaque happened
EOF
    if handle_stuck "202"; then
        fail "handle_stuck_preserves_non_recoverable" "expected return 1"
    else
        if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
            pass "handle_stuck_preserves_non_recoverable"
        else
            fail "handle_stuck_preserves_non_recoverable" "STUCK file was removed"
        fi
    fi
    teardown_test_env
}

test_recovery_log_written() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: pip install failed: could not resolve dependencies
EOF
    handle_stuck "301" || true
    if [[ -f "${LOGS_DIR}/task-301-recovery.md" ]]; then
        pass "recovery_log_written"
    else
        fail "recovery_log_written" "recovery log not found at ${LOGS_DIR}/task-301-recovery.md"
    fi
    teardown_test_env
}

test_recovery_plan_created() {
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: npm ERR! module not found
EOF
    handle_stuck "401" || true
    if [[ -f "${SIGNALS_DIR}/RECOVERY_PLAN" ]]; then
        pass "recovery_plan_created"
    else
        fail "recovery_plan_created" "RECOVERY_PLAN file not found"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 4: compound recovery state restoration
# ══════════════════════════════════════════

test_compound_recovery_clears_failure_history() {
    # Simulates the loop logic: on successful compound recovery,
    # STUCK is removed and failure history is cleared for retry.
    setup_test_env
    # Simulate a recoverable compound STUCK
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: pip install failed: could not resolve dependencies
EOF
    local task_failure_history="test_failure,dependency_failure"

    # Simulate the fixed loop logic: try recovery BEFORE marking stuck
    if handle_stuck "501"; then
        # Recovery succeeded — clear STUCK, reset failure history
        rm -f "${SIGNALS_DIR}/STUCK"
        task_failure_history=""
        if [[ ! -f "${SIGNALS_DIR}/STUCK" ]] && [[ -z "$task_failure_history" ]]; then
            pass "compound_recovery_clears_failure_history"
        else
            fail "compound_recovery_clears_failure_history" "state not fully restored"
        fi
    else
        fail "compound_recovery_clears_failure_history" "recovery should have succeeded"
    fi
    teardown_test_env
}

test_compound_non_recoverable_preserves_stuck() {
    # On non-recoverable compound failure, STUCK remains and task stays stuck.
    setup_test_env
    cat > "${SIGNALS_DIR}/STUCK" <<'EOF'
## SPECTRA STUCK Signal
- Reason: contradictory requirements in spec
EOF
    if handle_stuck "502"; then
        fail "compound_non_recoverable_preserves_stuck" "expected failure"
    else
        if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
            pass "compound_non_recoverable_preserves_stuck"
        else
            fail "compound_non_recoverable_preserves_stuck" "STUCK was removed"
        fi
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# Run all tests
# ══════════════════════════════════════════

echo "Phase D: Party Mode STUCK Recovery"
echo "════════════════════════════════════"

# Group 1: classify_stuck
test_classify_dependency_failure
test_classify_dependency_pip
test_classify_environment_issue
test_classify_spec_conflict
test_classify_unknown

# Group 2: attempt_recovery
test_attempt_recovery_dependency
test_attempt_recovery_environment
test_attempt_recovery_spec_conflict
test_attempt_recovery_unknown

# Group 3: handle_stuck
test_handle_stuck_clears_recoverable
test_handle_stuck_preserves_non_recoverable
test_recovery_log_written
test_recovery_plan_created

# Group 4: compound recovery state restoration
test_compound_recovery_clears_failure_history
test_compound_non_recoverable_preserves_stuck

echo ""
echo "════════════════════════════════════"
echo "Results: ${PASS} passed, ${FAIL} failed (${TESTS_RUN} total)"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
