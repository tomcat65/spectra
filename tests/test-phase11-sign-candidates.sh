#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Sign candidate discovery (Task 008)
# Validates opt-in post-verify Sign candidate proposal generation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_SCRIPT="${SPECTRA_DIR}/hooks/post-verify-learn.sh"
LESSONS_LIB="${SPECTRA_DIR}/lib/loop-lessons.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: post-verify-learn.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: post-verify-learn.sh exists and is executable"

if [[ -x "${HOOK_SCRIPT}" ]]; then
    echo "  PASS  post-verify-learn.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  post-verify-learn.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Hook is disabled by default (SPECTRA_SIGN_DISCOVERY not set)
# ══════════════════════════════════════════
echo "  Test: disabled by default"

(
    cd "${tmp_dir}"
    mkdir -p .spectra/logs
    # Create artifacts that would trigger candidate generation
    echo "Result: PASS" > .spectra/logs/task-001-verify-script.md
    echo "Failure Type: test_failure" > .spectra/logs/task-001-verify.md

    # Run without SPECTRA_SIGN_DISCOVERY — should exit silently
    unset SPECTRA_SIGN_DISCOVERY 2>/dev/null || true
    SPECTRA_HOME="${SPECTRA_DIR}" "${HOOK_SCRIPT}" "001" "test-project" ".spectra" 2>/dev/null

    if [[ ! -f ".spectra/logs/sign-candidates-001.md" ]]; then
        echo "  PASS  no candidates generated when disabled (default)"
    else
        echo "  FAIL  candidates generated despite being disabled"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 3: Hook generates candidates when enabled
# ══════════════════════════════════════════
echo "  Test: generates candidates when enabled"

(
    cd "${tmp_dir}"
    rm -f .spectra/logs/sign-candidates-001.md

    SPECTRA_SIGN_DISCOVERY=1 SPECTRA_HOME="${SPECTRA_DIR}" \
        "${HOOK_SCRIPT}" "001" "test-project" ".spectra" 2>/dev/null

    if [[ -f ".spectra/logs/sign-candidates-001.md" ]]; then
        echo "  PASS  sign-candidates-001.md generated"
    else
        echo "  FAIL  sign-candidates-001.md not generated"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: Candidate file includes failure type
# ══════════════════════════════════════════
echo "  Test: candidate file includes failure type"

(
    cd "${tmp_dir}"
    if grep -q 'test_failure' ".spectra/logs/sign-candidates-001.md" 2>/dev/null; then
        echo "  PASS  candidate file references failure type"
    else
        echo "  FAIL  candidate file missing failure type"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Candidate file includes task ID
# ══════════════════════════════════════════
echo "  Test: candidate file includes task ID"

(
    cd "${tmp_dir}"
    if grep -q 'Task.*001' ".spectra/logs/sign-candidates-001.md" 2>/dev/null; then
        echo "  PASS  candidate file references task 001"
    else
        echo "  FAIL  candidate file missing task ID"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: Candidate file includes audit context (evidence path)
# ══════════════════════════════════════════
echo "  Test: candidate file includes evidence path"

(
    cd "${tmp_dir}"
    if grep -q 'verify.md' ".spectra/logs/sign-candidates-001.md" 2>/dev/null; then
        echo "  PASS  candidate file includes evidence path"
    else
        echo "  FAIL  candidate file missing evidence path"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: Candidate file does NOT modify guardrails
# The hook must be read-only with respect to guardrails.md
# ══════════════════════════════════════════
echo "  Test: guardrails.md not modified"

(
    cd "${tmp_dir}"
    echo "# Guards" > .spectra/guardrails.md
    GUARD_BEFORE=$(md5sum .spectra/guardrails.md | cut -d' ' -f1)

    SPECTRA_SIGN_DISCOVERY=1 SPECTRA_HOME="${SPECTRA_DIR}" \
        "${HOOK_SCRIPT}" "002" "test-project" ".spectra" 2>/dev/null || true

    GUARD_AFTER=$(md5sum .spectra/guardrails.md | cut -d' ' -f1)
    if [[ "${GUARD_BEFORE}" == "${GUARD_AFTER}" ]]; then
        echo "  PASS  guardrails.md unchanged after hook"
    else
        echo "  FAIL  guardrails.md was modified by hook"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: Hook exits silently when no prior failure (no verify log)
# ══════════════════════════════════════════
echo "  Test: exits silently when no prior failure"

(
    nofail_dir=$(mktemp -d)
    cd "${nofail_dir}"
    mkdir -p .spectra/logs

    # No verify.md means no prior failure
    SPECTRA_SIGN_DISCOVERY=1 SPECTRA_HOME="${SPECTRA_DIR}" \
        "${HOOK_SCRIPT}" "099" "test-project" ".spectra" 2>/dev/null

    if [[ ! -f ".spectra/logs/sign-candidates-099.md" ]]; then
        echo "  PASS  no candidates when no prior failure"
    else
        echo "  FAIL  candidates generated without prior failure"
        exit 1
    fi
    rm -rf "${nofail_dir}"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: Hook exits silently when latest result is still FAIL
# ══════════════════════════════════════════
echo "  Test: exits silently when still failing"

(
    stillfail_dir=$(mktemp -d)
    cd "${stillfail_dir}"
    mkdir -p .spectra/logs
    echo "Failure Type: test_failure" > .spectra/logs/task-003-verify.md
    echo "Result: FAIL" > .spectra/logs/task-003-verify-script.md

    SPECTRA_SIGN_DISCOVERY=1 SPECTRA_HOME="${SPECTRA_DIR}" \
        "${HOOK_SCRIPT}" "003" "test-project" ".spectra" 2>/dev/null

    if [[ ! -f ".spectra/logs/sign-candidates-003.md" ]]; then
        echo "  PASS  no candidates when still failing"
    else
        echo "  FAIL  candidates generated while still failing"
        exit 1
    fi
    rm -rf "${stillfail_dir}"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: Hook script references SPECTRA_SIGN_DISCOVERY gate
# ══════════════════════════════════════════
echo "  Test: feature gate uses SPECTRA_SIGN_DISCOVERY"

if grep -q 'SPECTRA_SIGN_DISCOVERY' "${HOOK_SCRIPT}"; then
    echo "  PASS  hook uses SPECTRA_SIGN_DISCOVERY feature gate"
    PASS=$((PASS + 1))
else
    echo "  FAIL  hook missing SPECTRA_SIGN_DISCOVERY gate"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Hook has valid bash syntax
# ══════════════════════════════════════════
echo "  Test: hook has valid syntax"

if bash -n "${HOOK_SCRIPT}" 2>/dev/null; then
    echo "  PASS  post-verify-learn.sh has valid syntax"
    PASS=$((PASS + 1))
else
    echo "  FAIL  post-verify-learn.sh has syntax errors"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: Candidate file includes next steps for human review
# ══════════════════════════════════════════
echo "  Test: candidate file includes next steps"

(
    cd "${tmp_dir}"
    if grep -q 'Next Steps' ".spectra/logs/sign-candidates-001.md" 2>/dev/null; then
        echo "  PASS  candidate file includes review next steps"
    else
        echo "  FAIL  candidate file missing next steps"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: Candidate explicitly states guardrails are NOT modified
# ══════════════════════════════════════════
echo "  Test: candidate states guardrails not modified"

(
    cd "${tmp_dir}"
    if grep -qi 'NOT modified\|not modified\|proposal only' ".spectra/logs/sign-candidates-001.md" 2>/dev/null; then
        echo "  PASS  candidate file states guardrails are not modified"
    else
        echo "  FAIL  candidate file does not disclaim guardrail mutation"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 14: Hook uses SPECTRA_HOME auto-detection
# ══════════════════════════════════════════
echo "  Test: uses SPECTRA_HOME auto-detection"

if grep -q 'SPECTRA_HOME=.*dirname.*SCRIPT_DIR' "${HOOK_SCRIPT}"; then
    echo "  PASS  uses SPECTRA_HOME auto-detection"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing SPECTRA_HOME auto-detection"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  phase11-sign-candidates: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=phase11-sign-candidates pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_PHASE11_SIGN_CANDIDATES_PASS=${PASS}
export TEST_PHASE11_SIGN_CANDIDATES_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
