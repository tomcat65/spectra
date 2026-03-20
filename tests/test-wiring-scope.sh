#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Wiring assertion scope (Bug 2 fix)
# Validates that spectra-verify-wiring.sh evaluates assertions
# scoped to completed/stuck tasks, not globally.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
WIRING_SCRIPT="${SPECTRA_DIR}/bin/spectra-verify-wiring.sh"

PASS=0
FAIL=0
SKIP=0

# ── Fixture setup ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# Create minimal verify.yaml so wiring script doesn't skip
mkdir -p "${tmp_dir}/.spectra"
cat > "${tmp_dir}/.spectra/verify.yaml" <<'YAML'
project:
  source_dirs: ["src/"]
  test_dirs: ["tests/"]
  entry_points: ["src/main.py"]
  language: python
rules:
  wiring:
    enabled: false
  framework_checks: []
  constants: []
  write_guard:
    enabled: false
YAML

# Create a file that exists (for completed task assertion)
mkdir -p "${tmp_dir}/src"
echo 'def existing_fn(): return 42' > "${tmp_dir}/src/existing.py"

# ══════════════════════════════════════════
# Test 1: Future-task assertions skipped (default mode)
# Task 002 is pending [ ] with GREP on nonexistent file.
# Default mode should skip it.
# ══════════════════════════════════════════
echo "  Test: future-task assertions skipped in default mode"

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Task 001: Setup
- [x] 001: Setup
- AC:
  - Project initialized
- Assertions:
  - GREP src/existing.py "existing_fn" EXISTS

## Task 002: Add handler
- [ ] 002: Add handler
- AC:
  - Handler added
- Assertions:
  - GREP src/nonexistent.py "handle" EXISTS
PLAN

set +e
OUT=$("${WIRING_SCRIPT}" "${tmp_dir}" --verbose 2>&1)
EC=$?
set -e

if echo "${OUT}" | grep -q "PASS.*existing_fn" && ! echo "${OUT}" | grep -q "nonexistent"; then
    echo "  PASS  completed task assertion evaluated, pending task assertion skipped"
    PASS=$((PASS + 1))
else
    echo "  FAIL  scope filtering did not work correctly"
    echo "        output: ${OUT}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Completed-task assertions evaluated
# ══════════════════════════════════════════
echo "  Test: completed-task assertions are evaluated and pass"

if echo "${OUT}" | grep -q "PASS.*GREP src/existing.py"; then
    echo "  PASS  completed task assertion evaluated and passed"
    PASS=$((PASS + 1))
else
    echo "  FAIL  completed task assertion not evaluated"
    echo "        output: ${OUT}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Current-task assertions evaluated with --task
# --task 002 should include Task 002's assertions
# ══════════════════════════════════════════
echo "  Test: --task 002 includes pending task assertions"

set +e
OUT_TASK=$("${WIRING_SCRIPT}" "${tmp_dir}" --task 002 --verbose 2>&1)
EC_TASK=$?
set -e

if echo "${OUT_TASK}" | grep -q "nonexistent"; then
    echo "  PASS  --task 002 evaluates Task 002 assertions"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --task 002 did not include Task 002 assertions"
    echo "        output: ${OUT_TASK}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Stuck-task assertions evaluated
# ══════════════════════════════════════════
echo "  Test: stuck-task [!] assertions are evaluated"

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Task 001: Stuck task
- [!] 001: Stuck task
- AC:
  - Something
- Assertions:
  - GREP src/existing.py "existing_fn" EXISTS

## Task 002: Pending
- [ ] 002: Pending
- AC:
  - Something
- Assertions:
  - GREP src/nonexistent.py "handle" EXISTS
PLAN

set +e
OUT_STUCK=$("${WIRING_SCRIPT}" "${tmp_dir}" --verbose 2>&1)
set -e

if echo "${OUT_STUCK}" | grep -q "PASS.*existing_fn"; then
    echo "  PASS  stuck task assertion evaluated"
    PASS=$((PASS + 1))
else
    echo "  FAIL  stuck task assertion not evaluated"
    echo "        output: ${OUT_STUCK}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: --all flag evaluates everything
# ══════════════════════════════════════════
echo "  Test: --all evaluates all task assertions"

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Task 001: Done
- [x] 001: Done
- Assertions:
  - GREP src/existing.py "existing_fn" EXISTS

## Task 002: Pending
- [ ] 002: Pending
- Assertions:
  - GREP src/existing.py "existing_fn" EXISTS
PLAN

set +e
OUT_ALL=$("${WIRING_SCRIPT}" "${tmp_dir}" --all --verbose 2>&1)
set -e

# --all should evaluate both tasks' assertions (2 PASS lines for existing_fn)
ALL_COUNT=$(echo "${OUT_ALL}" | grep -c "PASS.*GREP" || true)
if [[ "${ALL_COUNT}" -ge 2 ]]; then
    echo "  PASS  --all evaluated assertions from all tasks (${ALL_COUNT} matches)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --all did not evaluate all assertions (got ${ALL_COUNT})"
    echo "        output: ${OUT_ALL}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: Header assertions always evaluated
# Assertions before any ## Task block should always be included.
# ══════════════════════════════════════════
echo "  Test: header assertions (before any Task block) always evaluated"

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Project: Test

- Assertions:
  - GREP src/existing.py "existing_fn" EXISTS

## Task 001: Pending
- [ ] 001: Pending
- Assertions:
  - GREP src/nonexistent.py "handle" EXISTS
PLAN

set +e
OUT_HDR=$("${WIRING_SCRIPT}" "${tmp_dir}" --verbose 2>&1)
set -e

if echo "${OUT_HDR}" | grep -q "PASS.*existing_fn" && ! echo "${OUT_HDR}" | grep -q "nonexistent"; then
    echo "  PASS  header assertion evaluated, pending task assertion skipped"
    PASS=$((PASS + 1))
else
    echo "  FAIL  header assertion handling incorrect"
    echo "        output: ${OUT_HDR}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Pre-commit hook invokes spectra-verify-wiring.sh without --task
# ══════════════════════════════════════════
echo "  Test: pre-commit hook runs completed-only mode (no --task flag)"

HOOK="${SPECTRA_DIR}/hooks/pre-commit"
if [[ -f "${HOOK}" ]]; then
    # Check that the exec line calls spectra-verify-wiring.sh but does NOT pass --task
    EXEC_LINE=$(grep -E '^\s*(exec\s+)?".*spectra-verify-wiring' "${HOOK}" || true)
    if [[ -n "${EXEC_LINE}" ]] && ! echo "${EXEC_LINE}" | grep -q "\-\-task"; then
        echo "  PASS  pre-commit hook invokes wiring check without --task (completed-only)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  pre-commit hook does not match expected pattern"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  pre-commit hook not found at ${HOOK}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: loop-wiring.sh passes --task to spectra-verify-wiring.sh
# ══════════════════════════════════════════
echo "  Test: loop-wiring.sh passes --task to spectra-verify-wiring.sh"

LOOP_WIRING="${SPECTRA_DIR}/lib/loop-wiring.sh"
if grep -q 'spectra-verify-wiring.sh.*--task' "${LOOP_WIRING}" 2>/dev/null; then
    echo "  PASS  loop-wiring.sh passes --task flag"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-wiring.sh does not pass --task flag"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: Pre-commit hook is functional (not exit 0 bypass)
# ══════════════════════════════════════════
echo "  Test: pre-commit hook is functional (not bypassed)"

if grep -q "^exit 0" "${HOOK}" 2>/dev/null; then
    echo "  FAIL  pre-commit hook still has exit 0 bypass"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  pre-commit hook is functional (no exit 0 bypass)"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 10: Regex alternation with \| (BRE) auto-converted for grep -E (ERE)
# ══════════════════════════════════════════
echo "  Test: BRE pipe-OR pattern auto-converted for ERE grep"

mkdir -p "${tmp_dir}/src"
cat > "${tmp_dir}/src/multi.py" <<'PYFILE'
from pipecat_flows import FlowConfig
class StateMachine:
    pass
PYFILE

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Task 001: Multi-pattern
- [x] 001: Multi-pattern
- Assertions:
  - GREP src/multi.py "pipecat_flows\|FlowConfig\|StateMachine" EXISTS
PLAN

set +e
OUT_REGEX=$("${WIRING_SCRIPT}" "${tmp_dir}" --verbose 2>&1)
set -e

if echo "${OUT_REGEX}" | grep -q "PASS.*GREP src/multi.py"; then
    echo "  PASS  BRE \\| alternation pattern matched via auto-conversion"
    PASS=$((PASS + 1))
else
    echo "  FAIL  BRE \\| alternation pattern did not match"
    echo "        output: ${OUT_REGEX}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Native ERE alternation with | also works
# ══════════════════════════════════════════
echo "  Test: native ERE pipe-OR pattern works directly"

cat > "${tmp_dir}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Task 001: ERE pattern
- [x] 001: ERE pattern
- Assertions:
  - GREP src/multi.py "pipecat_flows|FlowConfig|StateMachine" EXISTS
PLAN

set +e
OUT_ERE=$("${WIRING_SCRIPT}" "${tmp_dir}" --verbose 2>&1)
set -e

if echo "${OUT_ERE}" | grep -q "PASS.*GREP src/multi.py"; then
    echo "  PASS  native ERE | alternation pattern matched"
    PASS=$((PASS + 1))
else
    echo "  FAIL  native ERE | alternation pattern did not match"
    echo "        output: ${OUT_ERE}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: Self-test passes (includes same-file call case)
# ══════════════════════════════════════════
echo "  Test: self-test passes (same-file call detection)"

set +e
OUT_SELF=$("${WIRING_SCRIPT}" --self-test 2>&1)
EC_SELF=$?
set -e

if [[ ${EC_SELF} -eq 0 ]]; then
    echo "  PASS  self-test passes (includes same-file wiring)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  self-test failed"
    echo "        output: ${OUT_SELF}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  wiring-scope: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=wiring-scope pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_WIRING_SCOPE_PASS=${PASS}
export TEST_WIRING_SCOPE_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
