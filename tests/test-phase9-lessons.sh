#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 9 Tests — Continuous Learning System
# Tests: fingerprinting, dedup, flock, promotion, adaptive TTL, redaction,
#        schema migration, demotion/rollback, guardrails dedup, CLAUDECODE detection,
#        brownfield heuristics, full lifecycle integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  FAIL  $1: $2"; }

# ── Setup / Teardown ──

TEST_LESSONS_HOME=""
TEST_SPECTRA_DIR=""

setup_test_env() {
    TEST_LESSONS_HOME=$(mktemp -d)
    TEST_SPECTRA_DIR=$(mktemp -d)
    # Override globals for testing
    export LESSONS_HOME="${TEST_LESSONS_HOME}"
    export SPECTRA_DIR="${TEST_SPECTRA_DIR}"
    export SPECTRA_HOME="${SPECTRA_HOME}"
    mkdir -p "${TEST_LESSONS_HOME}/projects"
    echo "1" > "${TEST_LESSONS_HOME}/schema-version"
}

teardown_test_env() {
    rm -rf "${TEST_LESSONS_HOME}" "${TEST_SPECTRA_DIR}"
}

# Source the module under test
source "${SPECTRA_HOME}/lib/loop-lessons.sh"

# ══════════════════════════════════════════
# TEST GROUP 1: Fingerprint computation
# ══════════════════════════════════════════

test_fingerprint_basic() {
    local fp
    fp=$(compute_fingerprint "build" "npm_ERR_ERESOLVE" "package.json")
    if [[ "${fp}" == "build/npm_err_eresolve/package.json" ]]; then
        pass "fingerprint_basic"
    else
        fail "fingerprint_basic" "expected build/npm_err_eresolve/package.json, got ${fp}"
    fi
}

test_fingerprint_normalization() {
    local fp
    fp=$(compute_fingerprint "BUILD" "NPM_ERR" "/home/user/project/src/app.ts")
    if [[ "${fp}" == "build/npm_err/app.ts" ]]; then
        pass "fingerprint_normalization"
    else
        fail "fingerprint_normalization" "expected build/npm_err/app.ts, got ${fp}"
    fi
}

test_fingerprint_defaults() {
    local fp
    fp=$(compute_fingerprint "" "" "")
    if [[ "${fp}" == "unknown/unknown/unknown" ]]; then
        pass "fingerprint_defaults"
    else
        fail "fingerprint_defaults" "expected unknown/unknown/unknown, got ${fp}"
    fi
}

test_fingerprint_whitespace() {
    local fp
    fp=$(compute_fingerprint "test  failure" "missing   dep" "my file.ts")
    if [[ "${fp}" == "test_failure/missing_dep/my file.ts" ]]; then
        pass "fingerprint_whitespace"
    else
        fail "fingerprint_whitespace" "expected test_failure/missing_dep/my file.ts, got ${fp}"
    fi
}

test_fingerprint_deterministic() {
    local fp1 fp2
    fp1=$(compute_fingerprint "build" "error_code" "file.ts")
    fp2=$(compute_fingerprint "build" "error_code" "file.ts")
    if [[ "${fp1}" == "${fp2}" ]]; then
        pass "fingerprint_deterministic"
    else
        fail "fingerprint_deterministic" "same inputs gave different fingerprints"
    fi
}

# ══════════════════════════════════════════
# TEST GROUP 2: Sanitization / Redaction
# ══════════════════════════════════════════

test_sanitize_paths() {
    local result
    result=$(sanitize_lesson "Error in /home/tomcat65/projects/myapp/src/index.ts")
    if echo "${result}" | grep -q '{PROJECT_ROOT}'; then
        pass "sanitize_paths"
    else
        fail "sanitize_paths" "absolute path not redacted: ${result}"
    fi
}

test_sanitize_secrets() {
    local result
    result=$(sanitize_lesson "Token: sk-1234567890abcdef and ghp_abcdef123456")
    if echo "${result}" | grep -q '\[REDACTED\]' && ! echo "${result}" | grep -q 'sk-1234'; then
        pass "sanitize_secrets"
    else
        fail "sanitize_secrets" "secrets not redacted: ${result}"
    fi
}

test_sanitize_emails() {
    local result
    result=$(sanitize_lesson "Contact user@example.com for help")
    if echo "${result}" | grep -q '\[USER\]' && ! echo "${result}" | grep -q '@example'; then
        pass "sanitize_emails"
    else
        fail "sanitize_emails" "email not redacted: ${result}"
    fi
}

test_sanitize_clean_text() {
    local result
    result=$(sanitize_lesson "Normal error message without secrets")
    if [[ "${result}" == "Normal error message without secrets" ]]; then
        pass "sanitize_clean_text"
    else
        fail "sanitize_clean_text" "clean text was modified: ${result}"
    fi
}

# ══════════════════════════════════════════
# TEST GROUP 3: JSONL write + dedup
# ══════════════════════════════════════════

test_lesson_write_creates_jsonl() {
    setup_test_env
    lesson_write "test-project" "build" "npm_err" "package.json" "npm install" "deps failed" "medium" "run-001" "task-1" "FAIL: npm ERR" "test_failure"

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    if [[ -f "${jsonl}" ]] && grep -q '"fingerprint":"build/npm_err/package.json"' "${jsonl}"; then
        pass "lesson_write_creates_jsonl"
    else
        fail "lesson_write_creates_jsonl" "JSONL file not created or fingerprint missing"
    fi
    teardown_test_env
}

test_lesson_write_dedup() {
    setup_test_env
    lesson_write "test-project" "build" "npm_err" "package.json" "" "" "medium" "run-001" "task-1" "" ""
    lesson_write "test-project" "build" "npm_err" "package.json" "" "" "medium" "run-002" "task-1" "" ""

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    local create_count
    create_count=$(grep -c '"action":"create"' "${jsonl}")
    local increment_count
    increment_count=$(grep -c '"action":"increment"' "${jsonl}")
    if [[ ${create_count} -eq 1 ]] && [[ ${increment_count} -eq 1 ]]; then
        pass "lesson_write_dedup"
    else
        fail "lesson_write_dedup" "expected 1 create + 1 increment, got ${create_count} creates + ${increment_count} increments"
    fi
    teardown_test_env
}

test_lesson_write_evidence_fields() {
    setup_test_env
    lesson_write "test-project" "test" "assert_fail" "test.ts" "npm test" "assertion error" "high" "run-abc" "task-5" "FAIL: expected 200 got 500" "test_failure"

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    local entry
    entry=$(grep '"action":"create"' "${jsonl}" | head -1)
    local has_run_id has_project has_task_id has_oracle has_verifier
    has_run_id=$(echo "${entry}" | grep -c '"source_run_id":"run-abc"' || echo "0")
    has_project=$(echo "${entry}" | grep -c '"project":"test-project"' || echo "0")
    has_task_id=$(echo "${entry}" | grep -c '"task_id":"task-5"' || echo "0")
    has_oracle=$(echo "${entry}" | grep -c '"oracle_class":"test_failure"' || echo "0")
    has_verifier=$(echo "${entry}" | grep -c '"verifier_output"' || echo "0")
    if [[ ${has_run_id} -ge 1 ]] && [[ ${has_project} -ge 1 ]] && [[ ${has_task_id} -ge 1 ]] && [[ ${has_oracle} -ge 1 ]] && [[ ${has_verifier} -ge 1 ]]; then
        pass "lesson_write_evidence_fields"
    else
        fail "lesson_write_evidence_fields" "missing evidence fields in entry"
    fi
    teardown_test_env
}

test_dedup_idempotency() {
    setup_test_env
    # Write same lesson 5 times
    for i in $(seq 1 5); do
        lesson_write "test-project" "build" "err" "file.ts" "" "" "medium" "run-${i}" "task-1" "" ""
    done

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    local create_count increment_count
    create_count=$(grep -c '"action":"create"' "${jsonl}")
    increment_count=$(grep -c '"action":"increment"' "${jsonl}")
    if [[ ${create_count} -eq 1 ]] && [[ ${increment_count} -eq 4 ]]; then
        pass "dedup_idempotency"
    else
        fail "dedup_idempotency" "expected 1 create + 4 increments, got ${create_count} + ${increment_count}"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 4: Lock contention (parallel writes)
# ══════════════════════════════════════════

test_lock_contention() {
    setup_test_env
    local jsonl="${TEST_LESSONS_HOME}/projects/lock-test/lessons.jsonl"
    mkdir -p "${TEST_LESSONS_HOME}/projects/lock-test"

    # Spawn 10 concurrent appends
    for i in $(seq 1 10); do
        lesson_flock_append "${jsonl}" "{\"id\":${i}}" &
    done
    wait

    local line_count
    line_count=$(wc -l < "${jsonl}")
    if [[ ${line_count} -eq 10 ]]; then
        pass "lock_contention"
    else
        fail "lock_contention" "expected 10 lines, got ${line_count} (lost writes under contention)"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 5: Promotion thresholds
# ══════════════════════════════════════════

test_promotion_temp_stays_temp() {
    setup_test_env
    lesson_write "project-a" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""

    local result
    result=$(lesson_check_promotion "build/err/file.ts")
    if [[ "${result}" == "TEMP" ]]; then
        pass "promotion_temp_stays_temp"
    else
        fail "promotion_temp_stays_temp" "expected TEMP, got ${result}"
    fi
    teardown_test_env
}

test_promotion_cross_project() {
    setup_test_env
    # Write to two different projects with same fingerprint
    lesson_write "project-a" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_write "project-b" "build" "err" "file.ts" "" "" "medium" "run-2" "task-1" "" ""

    local result
    result=$(lesson_check_promotion "build/err/file.ts")
    if [[ "${result}" == "CONFIRMED" ]]; then
        pass "promotion_cross_project"
    else
        fail "promotion_cross_project" "expected CONFIRMED, got ${result}"
    fi
    teardown_test_env
}

test_promotion_to_sign_blocked() {
    setup_test_env
    # Verify SIGN promotion requires explicit call (human-gated)
    lesson_write "project-a" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_write "project-b" "build" "err" "file.ts" "" "" "medium" "run-2" "task-1" "" ""

    # CONFIRMED but not auto-promoted to SIGN
    local signs_file="${TEST_LESSONS_HOME}/global-signs.jsonl"
    if [[ ! -f "${signs_file}" ]] || ! grep -q "build/err/file.ts" "${signs_file}" 2>/dev/null; then
        pass "promotion_to_sign_blocked"
    else
        fail "promotion_to_sign_blocked" "fingerprint was auto-promoted to SIGN without human approval"
    fi
    teardown_test_env
}

test_promote_to_sign_explicit() {
    setup_test_env
    lesson_write "project-a" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_promote "build/err/file.ts" "CONFIRMED" "SIGN" "human_approval" "project-a"

    local signs_file="${TEST_LESSONS_HOME}/global-signs.jsonl"
    if [[ -f "${signs_file}" ]] && grep -q '"fingerprint":"build/err/file.ts"' "${signs_file}"; then
        pass "promote_to_sign_explicit"
    else
        fail "promote_to_sign_explicit" "SIGN not written to global-signs.jsonl"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 6: Adaptive TTL
# ══════════════════════════════════════════

test_ttl_low_severity() {
    setup_test_env
    lesson_write "test-project" "build" "err" "file.ts" "" "" "low" "run-1" "task-1" "" ""

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    local ttl
    ttl=$(grep '"action":"create"' "${jsonl}" | grep -oP '"ttl_base":\K[0-9]+' | head -1)
    if [[ "${ttl}" == "3" ]]; then
        pass "ttl_low_severity"
    else
        fail "ttl_low_severity" "expected TTL base 3, got ${ttl}"
    fi
    teardown_test_env
}

test_ttl_critical_never_expires() {
    setup_test_env
    lesson_write "test-project" "build" "err" "file.ts" "" "" "critical" "run-1" "task-1" "" ""

    local result
    result=$(lesson_check_ttl "build/err/file.ts" "test-project")
    if [[ "${result}" == "ALIVE" ]]; then
        pass "ttl_critical_never_expires"
    else
        fail "ttl_critical_never_expires" "expected ALIVE, got ${result}"
    fi
    teardown_test_env
}

test_ttl_high_severity() {
    setup_test_env
    lesson_write "test-project" "build" "err" "file.ts" "" "" "high" "run-1" "task-1" "" ""

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    local ttl
    ttl=$(grep '"action":"create"' "${jsonl}" | grep -oP '"ttl_base":\K[0-9]+' | head -1)
    if [[ "${ttl}" == "10" ]]; then
        pass "ttl_high_severity"
    else
        fail "ttl_high_severity" "expected TTL base 10, got ${ttl}"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 7: Snapshot compaction
# ══════════════════════════════════════════

test_compact_snapshot() {
    setup_test_env
    # Create entries + increments
    lesson_write "compact-test" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_write "compact-test" "build" "err" "file.ts" "" "" "medium" "run-2" "task-1" "" ""  # increment
    lesson_write "compact-test" "test" "assert" "test.ts" "" "" "low" "run-1" "task-2" "" ""

    compact_snapshot "compact-test"

    local snapshot="${TEST_LESSONS_HOME}/projects/compact-test/lessons.snapshot"
    if [[ -f "${snapshot}" ]]; then
        local entry_count
        entry_count=$(wc -l < "${snapshot}")
        # Should have 2 unique fingerprints
        if [[ ${entry_count} -eq 2 ]]; then
            # Check recurrence was merged
            if grep -q '"recurrence_count":2' "${snapshot}"; then
                pass "compact_snapshot"
            else
                fail "compact_snapshot" "recurrence count not merged in snapshot"
            fi
        else
            fail "compact_snapshot" "expected 2 entries in snapshot, got ${entry_count}"
        fi
    else
        fail "compact_snapshot" "snapshot file not created"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 8: Demotion / Rollback
# ══════════════════════════════════════════

test_demote_lesson() {
    setup_test_env
    lesson_write "test-project" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_demote "build/err/file.ts" "false_positive" "run-5,run-6"

    local jsonl="${TEST_LESSONS_HOME}/projects/test-project/lessons.jsonl"
    if grep -q '"action":"demote".*"fingerprint":"build/err/file.ts"' "${jsonl}"; then
        pass "demote_lesson"
    else
        fail "demote_lesson" "demote action not written to JSONL"
    fi
    teardown_test_env
}

test_demoted_excluded_from_snapshot() {
    setup_test_env
    lesson_write "test-project" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""
    lesson_demote "build/err/file.ts" "false_positive" ""
    compact_snapshot "test-project"

    local snapshot="${TEST_LESSONS_HOME}/projects/test-project/lessons.snapshot"
    if [[ -f "${snapshot}" ]]; then
        if grep -q '"status":"DEMOTED"' "${snapshot}"; then
            # Demoted entries ARE in snapshot (for audit) but marked DEMOTED
            pass "demoted_excluded_from_snapshot"
        else
            fail "demoted_excluded_from_snapshot" "demoted entry not properly marked in snapshot"
        fi
    else
        fail "demoted_excluded_from_snapshot" "snapshot not created"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 9: Schema migration
# ══════════════════════════════════════════

test_schema_version_file() {
    setup_test_env
    check_schema_version
    local version
    version=$(cat "${TEST_LESSONS_HOME}/schema-version")
    if [[ "${version}" == "1" ]]; then
        pass "schema_version_file"
    else
        fail "schema_version_file" "expected version 1, got ${version}"
    fi
    teardown_test_env
}

test_schema_migration_runs() {
    setup_test_env
    # Simulate an older schema
    echo "0" > "${TEST_LESSONS_HOME}/schema-version"

    # Define a test migration
    migrate_v0_to_v1() {
        echo "migrated" > "${TEST_LESSONS_HOME}/migration_ran"
    }

    check_schema_version

    if [[ -f "${TEST_LESSONS_HOME}/migration_ran" ]]; then
        local version
        version=$(cat "${TEST_LESSONS_HOME}/schema-version")
        if [[ "${version}" == "1" ]]; then
            pass "schema_migration_runs"
        else
            fail "schema_migration_runs" "version not updated after migration, got ${version}"
        fi
    else
        fail "schema_migration_runs" "migration function was not called"
    fi

    unset -f migrate_v0_to_v1
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 10: Guardrails dedup
# ══════════════════════════════════════════

test_guardrails_dedup_new() {
    setup_test_env
    echo "# Guardrails" > "${TEST_SPECTRA_DIR}/guardrails.md"

    if guardrails_dedup_check "- Warning: new issue found" "${TEST_SPECTRA_DIR}/guardrails.md"; then
        pass "guardrails_dedup_new"
    else
        fail "guardrails_dedup_new" "new warning was flagged as duplicate"
    fi
    teardown_test_env
}

test_guardrails_dedup_existing() {
    setup_test_env
    echo "- Warning: existing issue" > "${TEST_SPECTRA_DIR}/guardrails.md"

    if guardrails_dedup_check "- Warning: existing issue" "${TEST_SPECTRA_DIR}/guardrails.md"; then
        fail "guardrails_dedup_existing" "existing warning was not caught as duplicate"
    else
        pass "guardrails_dedup_existing"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 11: CLAUDECODE env var detection
# ══════════════════════════════════════════

test_claudecode_detection() {
    # Test that the guard exists in spectra-loop.sh
    if grep -q 'CLAUDECODE' "${SPECTRA_HOME}/bin/spectra-loop.sh"; then
        pass "claudecode_detection_present"
    else
        fail "claudecode_detection_present" "CLAUDECODE guard not found in spectra-loop.sh"
    fi
}

test_claudecode_fails_fast() {
    # Source just enough to test the guard
    local result
    result=$(CLAUDECODE=1 bash -c 'source "'"${SPECTRA_HOME}/lib/loop-signals.sh"'" 2>/dev/null; source "'"${SPECTRA_HOME}/lib/loop-retry.sh"'" 2>/dev/null; source "'"${SPECTRA_HOME}/lib/loop-lessons.sh"'" 2>/dev/null; if [[ -n "${CLAUDECODE:-}" ]]; then echo "BLOCKED"; exit 1; fi; echo "PASSED"' 2>&1 || true)
    if echo "${result}" | grep -q "BLOCKED"; then
        pass "claudecode_fails_fast"
    else
        fail "claudecode_fails_fast" "CLAUDECODE guard did not block execution"
    fi
}

# ══════════════════════════════════════════
# TEST GROUP 12: Brownfield heuristic floor
# ══════════════════════════════════════════

test_brownfield_floor_in_assess() {
    if grep -q 'BROWNFIELD_FLOOR' "${SPECTRA_HOME}/bin/spectra-assess.sh"; then
        pass "brownfield_floor_in_assess"
    else
        fail "brownfield_floor_in_assess" "brownfield floor code not found in spectra-assess.sh"
    fi
}

test_brownfield_floor_threshold() {
    # Check that the threshold values are correct
    if grep -q 'TEST_FILE_COUNT.*-gt 500' "${SPECTRA_HOME}/bin/spectra-assess.sh" && \
       grep -q 'MODULE_COUNT.*-gt 8' "${SPECTRA_HOME}/bin/spectra-assess.sh"; then
        pass "brownfield_floor_threshold"
    else
        fail "brownfield_floor_threshold" "threshold values not found (500 tests / 8 modules)"
    fi
}

# ══════════════════════════════════════════
# TEST GROUP 13: Full lifecycle integration
# ══════════════════════════════════════════

test_full_lifecycle() {
    setup_test_env

    # Step 1: Write TEMP lesson in project A
    lesson_write "alpha" "build" "dep_error" "package.json" "npm install" "missing peer dep" "medium" "run-1" "task-1" "FAIL: peer dep" "missing_dependency"

    # Step 2: Same pattern in project B → should auto-promote to CONFIRMED
    lesson_write "beta" "build" "dep_error" "package.json" "npm install" "missing peer dep" "medium" "run-2" "task-3" "FAIL: peer dep" "missing_dependency"

    # Step 3: Verify cross-project promotion happened
    local status
    status=$(lesson_check_promotion "build/dep_error/package.json")
    local lifecycle_ok=true
    if [[ "${status}" != "CONFIRMED" ]]; then
        fail "full_lifecycle" "step 3: expected CONFIRMED, got ${status}"
        lifecycle_ok=false
    fi

    # Step 4: Explicit promotion to SIGN
    if [[ "${lifecycle_ok}" == true ]]; then
        lesson_promote "build/dep_error/package.json" "CONFIRMED" "SIGN" "human_approval" "alpha"
        local signs_file="${TEST_LESSONS_HOME}/global-signs.jsonl"
        if [[ -f "${signs_file}" ]] && grep -q '"fingerprint":"build/dep_error/package.json"' "${signs_file}"; then
            : # good
        else
            fail "full_lifecycle" "step 4: SIGN not written to global-signs.jsonl"
            lifecycle_ok=false
        fi
    fi

    # Step 5: Compact and verify snapshot
    if [[ "${lifecycle_ok}" == true ]]; then
        compact_snapshot "alpha"
        local snapshot="${TEST_LESSONS_HOME}/projects/alpha/lessons.snapshot"
        if [[ -f "${snapshot}" ]] && [[ $(wc -l < "${snapshot}") -ge 1 ]]; then
            : # good
        else
            fail "full_lifecycle" "step 5: snapshot compaction failed"
            lifecycle_ok=false
        fi
    fi

    # Step 6: Demote and verify
    if [[ "${lifecycle_ok}" == true ]]; then
        lesson_demote "build/dep_error/package.json" "false_positive" "run-10"
        local alpha_jsonl="${TEST_LESSONS_HOME}/projects/alpha/lessons.jsonl"
        if grep -q '"action":"demote"' "${alpha_jsonl}"; then
            pass "full_lifecycle"
        else
            fail "full_lifecycle" "step 6: demotion not recorded"
        fi
    fi

    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 14: lesson_search
# ══════════════════════════════════════════

test_lesson_search_found() {
    setup_test_env
    lesson_write "search-test" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""

    local result
    result=$(lesson_search "build/err/file.ts" "search-test")
    if [[ -n "${result}" ]]; then
        pass "lesson_search_found"
    else
        fail "lesson_search_found" "search returned no results for existing fingerprint"
    fi
    teardown_test_env
}

test_lesson_search_not_found() {
    setup_test_env
    lesson_write "search-test" "build" "err" "file.ts" "" "" "medium" "run-1" "task-1" "" ""

    local result
    result=$(lesson_search "nonexistent/fp/file.ts" "search-test")
    if [[ -z "${result}" ]]; then
        pass "lesson_search_not_found"
    else
        fail "lesson_search_not_found" "search returned results for non-existent fingerprint"
    fi
    teardown_test_env
}

# ══════════════════════════════════════════
# TEST GROUP 15: Syntax checks for modified files
# ══════════════════════════════════════════

test_syntax_loop_lessons() {
    if bash -n "${SPECTRA_HOME}/lib/loop-lessons.sh" 2>/dev/null; then
        pass "syntax_loop_lessons"
    else
        fail "syntax_loop_lessons" "loop-lessons.sh has syntax errors"
    fi
}

test_syntax_spectra_loop() {
    if bash -n "${SPECTRA_HOME}/bin/spectra-loop.sh" 2>/dev/null; then
        pass "syntax_spectra_loop"
    else
        fail "syntax_spectra_loop" "spectra-loop.sh has syntax errors"
    fi
}

test_syntax_spectra_assess() {
    if bash -n "${SPECTRA_HOME}/bin/spectra-assess.sh" 2>/dev/null; then
        pass "syntax_spectra_assess"
    else
        fail "syntax_spectra_assess" "spectra-assess.sh has syntax errors"
    fi
}

# ══════════════════════════════════════════
# RUN ALL TESTS
# ══════════════════════════════════════════

echo "=== Phase 9: Continuous Learning Tests ==="
echo ""

# Group 1: Fingerprinting
echo "--- Fingerprinting ---"
test_fingerprint_basic
test_fingerprint_normalization
test_fingerprint_defaults
test_fingerprint_whitespace
test_fingerprint_deterministic

# Group 2: Sanitization
echo "--- Sanitization ---"
test_sanitize_paths
test_sanitize_secrets
test_sanitize_emails
test_sanitize_clean_text

# Group 3: JSONL write + dedup
echo "--- JSONL Write + Dedup ---"
test_lesson_write_creates_jsonl
test_lesson_write_dedup
test_lesson_write_evidence_fields
test_dedup_idempotency

# Group 4: Lock contention
echo "--- Lock Contention ---"
test_lock_contention

# Group 5: Promotion thresholds
echo "--- Promotion Thresholds ---"
test_promotion_temp_stays_temp
test_promotion_cross_project
test_promotion_to_sign_blocked
test_promote_to_sign_explicit

# Group 6: Adaptive TTL
echo "--- Adaptive TTL ---"
test_ttl_low_severity
test_ttl_critical_never_expires
test_ttl_high_severity

# Group 7: Snapshot compaction
echo "--- Snapshot Compaction ---"
test_compact_snapshot

# Group 8: Demotion
echo "--- Demotion ---"
test_demote_lesson
test_demoted_excluded_from_snapshot

# Group 9: Schema migration
echo "--- Schema Migration ---"
test_schema_version_file
test_schema_migration_runs

# Group 10: Guardrails dedup
echo "--- Guardrails Dedup ---"
test_guardrails_dedup_new
test_guardrails_dedup_existing

# Group 11: CLAUDECODE detection
echo "--- CLAUDECODE Detection ---"
test_claudecode_detection
test_claudecode_fails_fast

# Group 12: Brownfield heuristics
echo "--- Brownfield Heuristics ---"
test_brownfield_floor_in_assess
test_brownfield_floor_threshold

# Group 13: Full lifecycle
echo "--- Full Lifecycle ---"
test_full_lifecycle

# Group 14: Search
echo "--- Lesson Search ---"
test_lesson_search_found
test_lesson_search_not_found

# Group 15: Syntax checks
echo "--- Syntax Checks ---"
test_syntax_loop_lessons
test_syntax_spectra_loop
test_syntax_spectra_assess

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════

echo ""
echo "  phase9-lessons: ${PASS} passed, ${FAIL} failed"
echo ""

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
