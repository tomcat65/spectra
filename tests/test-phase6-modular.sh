#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 6 Tests — Loop Modularization
# Validates module extraction, source ordering, anti-drift, and golden behavior.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"
LOOP="${SPECTRA_HOME}/bin/spectra-loop.sh"

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
# Test 1: All lib/loop-*.sh modules exist
# ══════════════════════════════════════════
EXPECTED_MODULES=(loop-signals loop-retry loop-wiring loop-git loop-checkpoint loop-build loop-verify)
MISSING=0
for mod in "${EXPECTED_MODULES[@]}"; do
    if [[ ! -f "${SPECTRA_HOME}/lib/${mod}.sh" ]]; then
        MISSING=1
        echo "    Missing: lib/${mod}.sh"
    fi
done
if [[ $MISSING -eq 0 ]]; then
    assert_pass "all expected lib/loop-*.sh modules exist"
else
    assert_fail "all expected lib/loop-*.sh modules exist"
fi

# ══════════════════════════════════════════
# Test 2: All modules pass bash -n syntax check
# ══════════════════════════════════════════
SYNTAX_OK=0
SYNTAX_ERR=0
for mod_file in "${SPECTRA_HOME}"/lib/loop-*.sh; do
    if bash -n "$mod_file" 2>/dev/null; then
        SYNTAX_OK=$((SYNTAX_OK + 1))
    else
        SYNTAX_ERR=$((SYNTAX_ERR + 1))
        echo "    Syntax error: $(basename "$mod_file")"
    fi
done
if [[ $SYNTAX_ERR -eq 0 ]] && [[ $SYNTAX_OK -ge 7 ]]; then
    assert_pass "all lib/loop-*.sh modules pass bash -n ($SYNTAX_OK files)"
else
    assert_fail "all lib/loop-*.sh modules pass bash -n ($SYNTAX_ERR errors)"
fi

# ══════════════════════════════════════════
# Test 3: Every lib/loop-*.sh file is sourced in spectra-loop.sh (anti-drift)
# ══════════════════════════════════════════
UNSOURCED=0
for mod_file in "${SPECTRA_HOME}"/lib/loop-*.sh; do
    mod_name=$(basename "$mod_file")
    if ! grep -q "source.*lib/${mod_name}" "$LOOP" 2>/dev/null; then
        UNSOURCED=1
        echo "    Unsourced: ${mod_name}"
    fi
done
if [[ $UNSOURCED -eq 0 ]]; then
    assert_pass "every lib/loop-*.sh is sourced in spectra-loop.sh"
else
    assert_fail "every lib/loop-*.sh is sourced in spectra-loop.sh"
fi

# ══════════════════════════════════════════
# Test 4: No duplicate source lines in spectra-loop.sh
# ══════════════════════════════════════════
DUPS=$(grep -E '^source.*lib/loop-' "$LOOP" 2>/dev/null | sort | uniq -d)
if [[ -z "$DUPS" ]]; then
    assert_pass "no duplicate source lines for lib modules"
else
    assert_fail "no duplicate source lines for lib modules — duplicates: $DUPS"
fi

# ══════════════════════════════════════════
# Test 5: Source lines use explicit list (no wildcard glob)
# ══════════════════════════════════════════
if grep -qE 'source.*lib/loop-\*' "$LOOP" 2>/dev/null; then
    assert_fail "source lines use explicit list (no wildcard glob)"
else
    assert_pass "source lines use explicit list (no wildcard glob)"
fi

# ══════════════════════════════════════════
# Test 6: Each module has a Contract header comment
# ══════════════════════════════════════════
MISSING_CONTRACT=0
for mod_file in "${SPECTRA_HOME}"/lib/loop-*.sh; do
    if ! grep -q '# Contract:' "$mod_file" 2>/dev/null; then
        MISSING_CONTRACT=1
        echo "    Missing Contract header: $(basename "$mod_file")"
    fi
done
if [[ $MISSING_CONTRACT -eq 0 ]]; then
    assert_pass "all modules have Contract header comment"
else
    assert_fail "all modules have Contract header comment"
fi

# ══════════════════════════════════════════
# Test 7: Each module has an Exports header comment
# ══════════════════════════════════════════
MISSING_EXPORTS=0
for mod_file in "${SPECTRA_HOME}"/lib/loop-*.sh; do
    if ! grep -q '# Exports:' "$mod_file" 2>/dev/null; then
        MISSING_EXPORTS=1
        echo "    Missing Exports header: $(basename "$mod_file")"
    fi
done
if [[ $MISSING_EXPORTS -eq 0 ]]; then
    assert_pass "all modules have Exports header comment"
else
    assert_fail "all modules have Exports header comment"
fi

# ══════════════════════════════════════════
# Test 8: Extracted functions are NOT duplicated in spectra-loop.sh
# ══════════════════════════════════════════
# These functions should exist ONLY in their modules, not in the main loop.
EXTRACTED_FUNCS=(write_signal write_progress write_status write_batch_status
                 signal_stuck signal_complete write_final_report
                 max_retries_for generate_task_summary propagate_signs
                 run_wiring_gate
                 setup_branch commit_task install_precommit_hook
                 write_checkpoint restore_checkpoint
                 compute_plan_structure_checksum verify_plan_checksum
                 build_prompt preflight_prompt parallel_build
                 verify_prompt oracle_classify)

DUPED=0
for func in "${EXTRACTED_FUNCS[@]}"; do
    # Check if the function is defined (function name() { or name() {) in spectra-loop.sh
    if grep -qE "^${func}\(\)|^function ${func}" "$LOOP" 2>/dev/null; then
        DUPED=1
        echo "    Duplicated in loop: ${func}()"
    fi
done
if [[ $DUPED -eq 0 ]]; then
    assert_pass "extracted functions not duplicated in spectra-loop.sh"
else
    assert_fail "extracted functions not duplicated in spectra-loop.sh"
fi

# ══════════════════════════════════════════
# Test 9: Source order correctness — signals before checkpoint, build before verify
# ══════════════════════════════════════════
# loop-checkpoint.sh calls write_signal(), so loop-signals.sh must be sourced first.
# loop-build.sh should come before loop-verify.sh (build runs first in loop).
SIGNALS_LINE=$(grep -n 'source.*loop-signals.sh' "$LOOP" 2>/dev/null | head -1 | cut -d: -f1)
CHECKPOINT_LINE=$(grep -n 'source.*loop-checkpoint.sh' "$LOOP" 2>/dev/null | head -1 | cut -d: -f1)
BUILD_LINE=$(grep -n 'source.*loop-build.sh' "$LOOP" 2>/dev/null | head -1 | cut -d: -f1)
VERIFY_LINE=$(grep -n 'source.*loop-verify.sh' "$LOOP" 2>/dev/null | head -1 | cut -d: -f1)
ORDER_OK=true
if [[ -z "$SIGNALS_LINE" ]] || [[ -z "$CHECKPOINT_LINE" ]] || [[ "$SIGNALS_LINE" -ge "$CHECKPOINT_LINE" ]]; then
    ORDER_OK=false
fi
if [[ -z "$BUILD_LINE" ]] || [[ -z "$VERIFY_LINE" ]] || [[ "$BUILD_LINE" -ge "$VERIFY_LINE" ]]; then
    ORDER_OK=false
fi
if [[ "$ORDER_OK" == true ]]; then
    assert_pass "source order: signals before checkpoint, build before verify"
else
    assert_fail "source order: signals=$SIGNALS_LINE, checkpoint=$CHECKPOINT_LINE, build=$BUILD_LINE, verify=$VERIFY_LINE"
fi

# ══════════════════════════════════════════
# Test 10: Loop still uses extracted function calls (not inline code)
# ══════════════════════════════════════════
CALLS_FOUND=0
CALLS_MISSING=""
for call in "setup_branch" "install_precommit_hook" "run_wiring_gate" "commit_task" "write_checkpoint"; do
    if grep -q "$call" "$LOOP" 2>/dev/null; then
        CALLS_FOUND=$((CALLS_FOUND + 1))
    else
        CALLS_MISSING="${CALLS_MISSING} ${call}"
    fi
done
if [[ $CALLS_FOUND -ge 5 ]]; then
    assert_pass "loop uses extracted function calls ($CALLS_FOUND/5)"
else
    assert_fail "loop uses extracted function calls ($CALLS_FOUND/5, missing:$CALLS_MISSING)"
fi

# ══════════════════════════════════════════
# Test 11: Golden behavior — dry-run sourcing works end-to-end
# ══════════════════════════════════════════
# Source the loop modules in a subshell with required globals and verify functions exist.
set +e
GOLDEN_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
LOGS_DIR="${SPECTRA_DIR}/logs"
BRANCH_NAME=""
DRY_RUN=true
RESUME=false
FRESH_BRANCH=false
PASS_HISTORY=""
CHECKPOINT_FILE="/dev/null"
PLAN_CHECKSUM=""
ELAPSED_OFFSET=0
SLACK_WEBHOOK_URL=""
START_TIME=$(date +%s)
declare -a TASK_IDS=() TASK_STATUS=() RETRY_COUNTS=() FAILURE_TYPES=()

elapsed() { echo "0m00s"; }
elapsed_seconds() { echo "0"; }

source "${SPECTRA_HOME}/lib/loop-signals.sh"
source "${SPECTRA_HOME}/lib/loop-retry.sh"
source "${SPECTRA_HOME}/lib/loop-wiring.sh"
source "${SPECTRA_HOME}/lib/loop-git.sh"
source "${SPECTRA_HOME}/lib/loop-checkpoint.sh"
source "${SPECTRA_HOME}/lib/loop-build.sh"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

# Verify all exported functions are callable
type write_signal >/dev/null 2>&1 && echo "OK:write_signal"
type write_progress >/dev/null 2>&1 && echo "OK:write_progress"
type max_retries_for >/dev/null 2>&1 && echo "OK:max_retries_for"
type run_wiring_gate >/dev/null 2>&1 && echo "OK:run_wiring_gate"
type setup_branch >/dev/null 2>&1 && echo "OK:setup_branch"
type commit_task >/dev/null 2>&1 && echo "OK:commit_task"
type write_checkpoint >/dev/null 2>&1 && echo "OK:write_checkpoint"
type restore_checkpoint >/dev/null 2>&1 && echo "OK:restore_checkpoint"
type verify_plan_checksum >/dev/null 2>&1 && echo "OK:verify_plan_checksum"
type propagate_signs >/dev/null 2>&1 && echo "OK:propagate_signs"
type build_prompt >/dev/null 2>&1 && echo "OK:build_prompt"
type preflight_prompt >/dev/null 2>&1 && echo "OK:preflight_prompt"
type parallel_build >/dev/null 2>&1 && echo "OK:parallel_build"
type verify_prompt >/dev/null 2>&1 && echo "OK:verify_prompt"
type oracle_classify >/dev/null 2>&1 && echo "OK:oracle_classify"
' 2>&1)
GOLDEN_EXIT=$?
set -e

OK_COUNT=$(echo "$GOLDEN_OUT" | grep -c '^OK:' || echo "0")
if [[ $GOLDEN_EXIT -eq 0 ]] && [[ $OK_COUNT -ge 15 ]]; then
    assert_pass "golden behavior: all modules source and export functions ($OK_COUNT/15)"
else
    assert_fail "golden behavior: modules source failed (exit=$GOLDEN_EXIT, funcs=$OK_COUNT/15)"
fi

# ══════════════════════════════════════════
# Test 12: Golden behavior — max_retries_for returns correct budgets
# ══════════════════════════════════════════
set +e
BUDGET_OUT=$(bash -c '
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
SPECTRA_DIR=".spectra"
source "${SPECTRA_HOME}/lib/loop-retry.sh"
echo "test_failure:$(max_retries_for test_failure)"
echo "wiring_gap:$(max_retries_for wiring_gap)"
echo "ambiguous_spec:$(max_retries_for ambiguous_spec)"
' 2>&1)
set -e

TF_BUDGET=$(echo "$BUDGET_OUT" | grep '^test_failure:' | cut -d: -f2)
WG_BUDGET=$(echo "$BUDGET_OUT" | grep '^wiring_gap:' | cut -d: -f2)
AS_BUDGET=$(echo "$BUDGET_OUT" | grep '^ambiguous_spec:' | cut -d: -f2)
if [[ "$TF_BUDGET" == "3" ]] && [[ "$WG_BUDGET" == "2" ]] && [[ "$AS_BUDGET" == "0" ]]; then
    assert_pass "golden behavior: retry budgets correct (tf=3, wg=2, stuck=0)"
else
    assert_fail "golden behavior: retry budgets wrong (tf=$TF_BUDGET, wg=$WG_BUDGET, as=$AS_BUDGET)"
fi

# ══════════════════════════════════════════
# Test 13: CI and local checks use the canonical module inventory implementation
# ══════════════════════════════════════════
CI_WORKFLOW="${SPECTRA_HOME}/.github/workflows/spectra-ci.yml"
if [[ -f "$CI_WORKFLOW" ]] \
   && grep -q 'Module anti-drift' "$CI_WORKFLOW" 2>/dev/null \
   && grep -q 'spectra-ci-lint.sh --modules' "$CI_WORKFLOW" 2>/dev/null \
   && "${SPECTRA_HOME}/scripts/spectra-ci-lint.sh" --modules >/dev/null 2>&1; then
    assert_pass "CI anti-drift delegates to the canonical module inventory gate"
else
    assert_fail "CI anti-drift delegates to the canonical module inventory gate"
fi

# ══════════════════════════════════════════
# Test 14: Non-dry-run golden behavior — write_signal produces signal file
# ══════════════════════════════════════════
TMPDIR_T14=$(mktemp -d)
set +e
SIG_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
SIGNALS_DIR="'"${TMPDIR_T14}"'/signals"
SPECTRA_DIR="'"${TMPDIR_T14}"'"
BRANCH_NAME="test-branch"
PASS_HISTORY=""
LOGS_DIR="'"${TMPDIR_T14}"'/logs"
SLACK_WEBHOOK_URL=""
START_TIME=$(date +%s)

elapsed() { echo "0m00s"; }
elapsed_seconds() { echo "0"; }

mkdir -p "$SIGNALS_DIR" "$LOGS_DIR"
source "${SPECTRA_HOME}/lib/loop-signals.sh"

# Actually write a signal (non-dry-run behavior)
write_signal "TEST_SIGNAL" "golden behavior test"

# Verify signal file was created with correct content
if [[ -f "${SIGNALS_DIR}/TEST_SIGNAL" ]]; then
    content=$(cat "${SIGNALS_DIR}/TEST_SIGNAL")
    echo "SIGNAL_EXISTS=true"
    echo "SIGNAL_CONTENT=${content}"
else
    echo "SIGNAL_EXISTS=false"
fi
' 2>&1)
SIG_EXIT=$?
set -e

if [[ $SIG_EXIT -eq 0 ]] && echo "$SIG_OUT" | grep -q 'SIGNAL_EXISTS=true'; then
    assert_pass "non-dry-run: write_signal produces signal file"
else
    assert_fail "non-dry-run: write_signal produces signal file (exit=$SIG_EXIT)"
fi
rm -rf "$TMPDIR_T14"

# ══════════════════════════════════════════
# Test 15: Non-dry-run golden behavior — write_checkpoint produces valid JSON
# ══════════════════════════════════════════
TMPDIR_T15=$(mktemp -d)
set +e
CKPT_OUT=$(bash -c '
set -euo pipefail
SPECTRA_HOME="'"${SPECTRA_HOME}"'"
SIGNALS_DIR="'"${TMPDIR_T15}"'/signals"
SPECTRA_DIR="'"${TMPDIR_T15}"'"
BRANCH_NAME="test-branch"
PASS_HISTORY="001"
LOGS_DIR="'"${TMPDIR_T15}"'/logs"
CHECKPOINT_FILE="'"${TMPDIR_T15}"'/signals/CHECKPOINT"
PLAN_CHECKSUM=""
ELAPSED_OFFSET=0
SLACK_WEBHOOK_URL=""
START_TIME=$(date +%s)

elapsed() { echo "0m00s"; }
elapsed_seconds() { echo "0"; }

declare -a TASK_IDS=("001" "002")
declare -a TASK_STATUS=("complete" "pending")
declare -a RETRY_COUNTS=(0 1)
declare -a FAILURE_TYPES=("" "test_failure")

mkdir -p "$SIGNALS_DIR" "$LOGS_DIR"
source "${SPECTRA_HOME}/lib/loop-signals.sh"
source "${SPECTRA_HOME}/lib/loop-checkpoint.sh"

# Actually write checkpoint (non-dry-run behavior)
write_checkpoint

# Verify checkpoint was created and is valid JSON
if [[ -f "$CHECKPOINT_FILE" ]]; then
    echo "CKPT_EXISTS=true"
    if command -v jq &>/dev/null; then
        version=$(jq -r ".version" "$CHECKPOINT_FILE" 2>/dev/null || echo "")
        completed=$(jq -r ".completed[0]" "$CHECKPOINT_FILE" 2>/dev/null || echo "")
        branch=$(jq -r ".branch" "$CHECKPOINT_FILE" 2>/dev/null || echo "")
        echo "VERSION=${version}"
        echo "COMPLETED=${completed}"
        echo "BRANCH=${branch}"
    else
        echo "VERSION=skip"
        echo "COMPLETED=skip"
        echo "BRANCH=skip"
    fi
else
    echo "CKPT_EXISTS=false"
fi
' 2>&1)
CKPT_EXIT=$?
set -e

CKPT_EXISTS=$(echo "$CKPT_OUT" | grep '^CKPT_EXISTS=' | cut -d= -f2)
CKPT_VERSION=$(echo "$CKPT_OUT" | grep '^VERSION=' | cut -d= -f2)
CKPT_COMPLETED=$(echo "$CKPT_OUT" | grep '^COMPLETED=' | cut -d= -f2)
CKPT_BRANCH=$(echo "$CKPT_OUT" | grep '^BRANCH=' | cut -d= -f2)

if [[ $CKPT_EXIT -eq 0 ]] && [[ "$CKPT_EXISTS" == "true" ]]; then
    if [[ "$CKPT_VERSION" == "skip" ]] || \
       ( [[ "$CKPT_VERSION" == "5.0" ]] && [[ "$CKPT_COMPLETED" == "001" ]] && [[ "$CKPT_BRANCH" == "test-branch" ]] ); then
        assert_pass "non-dry-run: write_checkpoint produces valid JSON (v=$CKPT_VERSION, completed=$CKPT_COMPLETED)"
    else
        assert_fail "non-dry-run: checkpoint content wrong (v=$CKPT_VERSION, completed=$CKPT_COMPLETED, branch=$CKPT_BRANCH)"
    fi
else
    assert_fail "non-dry-run: write_checkpoint failed (exit=$CKPT_EXIT, exists=$CKPT_EXISTS)"
fi
rm -rf "$TMPDIR_T15"

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase6-modular: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=phase6-modular pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
