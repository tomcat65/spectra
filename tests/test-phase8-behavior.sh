#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 8 Tests — Behavior Parity for Extracted Functions
# Validates runtime behavior of loop-build.sh and loop-verify.sh with stubs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0

assert_pass() {
    PASS=$((PASS + 1))
    echo "  PASS  $1"
}

assert_fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL  $1"
}

# ══════════════════════════════════════════
# Test 1: build_prompt truncation at 480 bytes
# ══════════════════════════════════════════
set +e
TRUNC_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

declare -a TASK_IDS=("001")
declare -a TASK_TITLES=("'"$(printf 'X%.0s' {1..500})"'")

prompt=$(build_prompt 0 1 "")
echo "LEN=${#prompt}"
' 2>&1)
TRUNC_EXIT=$?
set -e

PROMPT_LEN=$(echo "$TRUNC_OUT" | grep '^LEN=' | cut -d= -f2)
if [[ $TRUNC_EXIT -eq 0 ]] && [[ -n "$PROMPT_LEN" ]] && [[ "$PROMPT_LEN" -le 480 ]]; then
    assert_pass "build_prompt truncates at 480 bytes (got ${PROMPT_LEN})"
else
    assert_fail "build_prompt truncation (exit=$TRUNC_EXIT, len=$PROMPT_LEN)"
fi

# ══════════════════════════════════════════
# Test 2: verify_prompt truncation at 480 bytes
# ══════════════════════════════════════════
set +e
VTRUNC_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

declare -a TASK_IDS=("001")

# Normal-length task should produce prompt under 480
prompt=$(verify_prompt 0 "full")
echo "LEN=${#prompt}"
# Verify it contains expected content
if echo "$prompt" | grep -q "Verify Task 001"; then
    echo "CONTAINS_TASK=true"
else
    echo "CONTAINS_TASK=false"
fi
' 2>&1)
VTRUNC_EXIT=$?
set -e

VPROMPT_LEN=$(echo "$VTRUNC_OUT" | grep '^LEN=' | cut -d= -f2)
VCONTAINS=$(echo "$VTRUNC_OUT" | grep '^CONTAINS_TASK=' | cut -d= -f2)
if [[ $VTRUNC_EXIT -eq 0 ]] && [[ "$VPROMPT_LEN" -le 480 ]] && [[ "$VCONTAINS" == "true" ]]; then
    assert_pass "verify_prompt under budget and contains task ID (${VPROMPT_LEN} bytes)"
else
    assert_fail "verify_prompt (exit=$VTRUNC_EXIT, len=$VPROMPT_LEN, contains=$VCONTAINS)"
fi

# ══════════════════════════════════════════
# Test 3: preflight_prompt truncation at 480 bytes
# ══════════════════════════════════════════
set +e
PTRUNC_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

prompt=$(preflight_prompt "001")
echo "LEN=${#prompt}"
if echo "$prompt" | grep -q "Sign violations"; then
    echo "CONTAINS_SIGN=true"
else
    echo "CONTAINS_SIGN=false"
fi
' 2>&1)
PTRUNC_EXIT=$?
set -e

PPROMPT_LEN=$(echo "$PTRUNC_OUT" | grep '^LEN=' | cut -d= -f2)
PCONTAINS=$(echo "$PTRUNC_OUT" | grep '^CONTAINS_SIGN=' | cut -d= -f2)
if [[ $PTRUNC_EXIT -eq 0 ]] && [[ "$PPROMPT_LEN" -le 480 ]] && [[ "$PCONTAINS" == "true" ]]; then
    assert_pass "preflight_prompt under budget and contains Sign reference (${PPROMPT_LEN} bytes)"
else
    assert_fail "preflight_prompt (exit=$PTRUNC_EXIT, len=$PPROMPT_LEN, contains=$PCONTAINS)"
fi

# ══════════════════════════════════════════
# Test 4: build_prompt retry context on iteration > 1
# ══════════════════════════════════════════
set +e
RETRY_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

declare -a TASK_IDS=("002")
declare -a TASK_TITLES=("Fix authentication")

prompt=$(build_prompt 0 3 "")
if echo "$prompt" | grep -q "retry 3"; then
    echo "HAS_RETRY=true"
else
    echo "HAS_RETRY=false"
fi
if echo "$prompt" | grep -q "task-002-verify.md"; then
    echo "HAS_VERIFY_REF=true"
else
    echo "HAS_VERIFY_REF=false"
fi
' 2>&1)
RETRY_EXIT=$?
set -e

HAS_RETRY=$(echo "$RETRY_OUT" | grep '^HAS_RETRY=' | cut -d= -f2)
HAS_VERIFY_REF=$(echo "$RETRY_OUT" | grep '^HAS_VERIFY_REF=' | cut -d= -f2)
if [[ $RETRY_EXIT -eq 0 ]] && [[ "$HAS_RETRY" == "true" ]] && [[ "$HAS_VERIFY_REF" == "true" ]]; then
    assert_pass "build_prompt includes retry context on iteration > 1"
else
    assert_fail "build_prompt retry (exit=$RETRY_EXIT, retry=$HAS_RETRY, verify_ref=$HAS_VERIFY_REF)"
fi

# ══════════════════════════════════════════
# Test 5: parallel_build dry-run produces DRY RUN output
# ══════════════════════════════════════════
set +e
DRYRUN_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

declare -a TASK_IDS=("001" "002")
declare -a TASK_TITLES=("Build feature" "Fix bug")
declare -a RETRY_COUNTS=(1 1)
LOGS_DIR="/tmp/spectra-test-$$"
SIGNALS_DIR="/tmp/spectra-test-$$-sig"
DRY_RUN=true
BUILDER_TIMEOUT=300

mkdir -p "$LOGS_DIR" "$SIGNALS_DIR"

parallel_build 0 1
echo "EXIT=$?"

# Check for DRY RUN marker
' 2>&1)
DRYRUN_EXIT=$?
set -e

if [[ $DRYRUN_EXIT -eq 0 ]] && echo "$DRYRUN_OUT" | grep -q '\[DRY RUN\]'; then
    assert_pass "parallel_build dry-run produces DRY RUN output"
else
    assert_fail "parallel_build dry-run (exit=$DRYRUN_EXIT)"
fi

# ══════════════════════════════════════════
# Test 6: parallel_build timeout path writes TIMEOUT signal
# ══════════════════════════════════════════
TMPDIR_T6=$(mktemp -d)
set +e
TIMEOUT_OUT=$(timeout 15 bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

declare -a TASK_IDS=("099")
declare -a TASK_TITLES=("Slow task")
declare -a RETRY_COUNTS=(1)
LOGS_DIR="'"${TMPDIR_T6}"'/logs"
SIGNALS_DIR="'"${TMPDIR_T6}"'/signals"
DRY_RUN=false
BUILDER_TIMEOUT=2

mkdir -p "$LOGS_DIR" "$SIGNALS_DIR"

# Stub claude with a sleep that will be killed by timeout
export PATH="'"${TMPDIR_T6}"'/bin:$PATH"
mkdir -p "'"${TMPDIR_T6}"'/bin"
cat > "'"${TMPDIR_T6}"'/bin/claude" <<STUB
#!/usr/bin/env bash
sleep 60
STUB
chmod +x "'"${TMPDIR_T6}"'/bin/claude"

set +e
parallel_build 0
BUILD_RC=$?
set -e
echo "BUILD_RC=$BUILD_RC"

if [[ -f "$SIGNALS_DIR/TIMEOUT_099" ]]; then
    echo "TIMEOUT_SIGNAL=true"
else
    echo "TIMEOUT_SIGNAL=false"
fi
' 2>&1)
TIMEOUT_EXIT=$?
set -e

TIMEOUT_SIGNAL=$(echo "$TIMEOUT_OUT" | grep '^TIMEOUT_SIGNAL=' | cut -d= -f2)
BUILD_RC=$(echo "$TIMEOUT_OUT" | grep '^BUILD_RC=' | cut -d= -f2)
if [[ "$TIMEOUT_SIGNAL" == "true" ]] && [[ "$BUILD_RC" != "0" ]]; then
    assert_pass "parallel_build timeout writes TIMEOUT signal and returns failure"
else
    assert_fail "parallel_build timeout (signal=$TIMEOUT_SIGNAL, rc=$BUILD_RC, exit=$TIMEOUT_EXIT)"
fi
rm -rf "$TMPDIR_T6"

# ══════════════════════════════════════════
# Test 7: parallel_build infra-failure path writes INFRA_FAIL signal
# ══════════════════════════════════════════
TMPDIR_T7=$(mktemp -d)
set +e
INFRA_OUT=$(timeout 15 bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-build.sh"

declare -a TASK_IDS=("098")
declare -a TASK_TITLES=("Infra test")
declare -a RETRY_COUNTS=(1)
LOGS_DIR="'"${TMPDIR_T7}"'/logs"
SIGNALS_DIR="'"${TMPDIR_T7}"'/signals"
DRY_RUN=false
BUILDER_TIMEOUT=10

mkdir -p "$LOGS_DIR" "$SIGNALS_DIR"

# Stub claude that exits non-zero with infra error in log
export PATH="'"${TMPDIR_T7}"'/bin:$PATH"
mkdir -p "'"${TMPDIR_T7}"'/bin"
cat > "'"${TMPDIR_T7}"'/bin/claude" <<STUB
#!/usr/bin/env bash
echo "error: unknown option --bad-flag"
exit 1
STUB
chmod +x "'"${TMPDIR_T7}"'/bin/claude"

set +e
parallel_build 0
BUILD_RC=$?
set -e
echo "BUILD_RC=$BUILD_RC"

if [[ -f "$SIGNALS_DIR/INFRA_FAIL_098" ]]; then
    echo "INFRA_SIGNAL=true"
else
    echo "INFRA_SIGNAL=false"
fi
' 2>&1)
INFRA_EXIT=$?
set -e

INFRA_SIGNAL=$(echo "$INFRA_OUT" | grep '^INFRA_SIGNAL=' | cut -d= -f2)
INFRA_RC=$(echo "$INFRA_OUT" | grep '^BUILD_RC=' | cut -d= -f2)
if [[ "$INFRA_SIGNAL" == "true" ]] && [[ "$INFRA_RC" != "0" ]]; then
    assert_pass "parallel_build infra-failure writes INFRA_FAIL signal and returns failure"
else
    assert_fail "parallel_build infra-failure (signal=$INFRA_SIGNAL, rc=$INFRA_RC, exit=$INFRA_EXIT)"
fi
rm -rf "$TMPDIR_T7"

# ══════════════════════════════════════════
# Test 8: oracle_classify dry-run returns test_failure
# ══════════════════════════════════════════
set +e
ORACLE_DRY_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

DRY_RUN=true
LOGS_DIR="/tmp/spectra-test-$$"

result=$(oracle_classify "001")
echo "RESULT=$result"
' 2>&1)
ORACLE_DRY_EXIT=$?
set -e

ORACLE_RESULT=$(echo "$ORACLE_DRY_OUT" | grep '^RESULT=' | cut -d= -f2)
if [[ $ORACLE_DRY_EXIT -eq 0 ]] && [[ "$ORACLE_RESULT" == "test_failure" ]]; then
    assert_pass "oracle_classify dry-run returns test_failure"
else
    assert_fail "oracle_classify dry-run (exit=$ORACLE_DRY_EXIT, result=$ORACLE_RESULT)"
fi

# ══════════════════════════════════════════
# Test 9: oracle_classify fallback on invalid oracle output
# ══════════════════════════════════════════
TMPDIR_T9=$(mktemp -d)
set +e
ORACLE_FALLBACK_OUT=$(timeout 15 bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

DRY_RUN=false
LOGS_DIR="'"${TMPDIR_T9}"'/logs"
mkdir -p "$LOGS_DIR"

# Create a verify log with a known failure type
echo "Result: FAIL" > "$LOGS_DIR/task-077-verify.md"
echo "Failure Type: wiring_gap" >> "$LOGS_DIR/task-077-verify.md"

# Stub claude that returns garbage
export PATH="'"${TMPDIR_T9}"'/bin:$PATH"
mkdir -p "'"${TMPDIR_T9}"'/bin"
cat > "'"${TMPDIR_T9}"'/bin/claude" <<STUB
#!/usr/bin/env bash
echo "I do not understand the question"
STUB
chmod +x "'"${TMPDIR_T9}"'/bin/claude"

result=$(oracle_classify "077")
echo "RESULT=$result"
' 2>&1)
ORACLE_FALLBACK_EXIT=$?
set -e

FALLBACK_RESULT=$(echo "$ORACLE_FALLBACK_OUT" | grep '^RESULT=' | cut -d= -f2)
if [[ $ORACLE_FALLBACK_EXIT -eq 0 ]] && [[ "$FALLBACK_RESULT" == "wiring_gap" ]]; then
    assert_pass "oracle_classify falls back to verifier's Failure Type on invalid oracle output"
else
    assert_fail "oracle_classify fallback (exit=$ORACLE_FALLBACK_EXIT, result=$FALLBACK_RESULT)"
fi
rm -rf "$TMPDIR_T9"

# ══════════════════════════════════════════
# Test 10: oracle_classify fallback to test_failure when verify log missing
# ══════════════════════════════════════════
TMPDIR_T10=$(mktemp -d)
set +e
ORACLE_MISSING_OUT=$(timeout 15 bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

DRY_RUN=false
LOGS_DIR="'"${TMPDIR_T10}"'/logs"
mkdir -p "$LOGS_DIR"
# No verify log created — simulates missing log

# Stub claude that returns garbage
export PATH="'"${TMPDIR_T10}"'/bin:$PATH"
mkdir -p "'"${TMPDIR_T10}"'/bin"
cat > "'"${TMPDIR_T10}"'/bin/claude" <<STUB
#!/usr/bin/env bash
echo "garbage_output_here"
STUB
chmod +x "'"${TMPDIR_T10}"'/bin/claude"

result=$(oracle_classify "088")
echo "RESULT=$result"
' 2>&1)
ORACLE_MISSING_EXIT=$?
set -e

MISSING_RESULT=$(echo "$ORACLE_MISSING_OUT" | grep '^RESULT=' | cut -d= -f2)
if [[ $ORACLE_MISSING_EXIT -eq 0 ]] && [[ "$MISSING_RESULT" == "test_failure" ]]; then
    assert_pass "oracle_classify falls back to test_failure when verify log missing"
else
    assert_fail "oracle_classify missing log (exit=$ORACLE_MISSING_EXIT, result=$MISSING_RESULT)"
fi
rm -rf "$TMPDIR_T10"

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase8-behavior: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
