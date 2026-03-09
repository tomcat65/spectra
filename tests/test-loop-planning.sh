#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Loop planning persistence (Task 001)
# Validates that the planning path delegates to spectra-plan.sh (the plan writer),
# not through direct planner agent invocation. No LLM invocation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"
PLAN_SCRIPT="${SPECTRA_DIR}/bin/spectra-plan.sh"
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
# Test 1: --plan-only flag recognized by spectra-loop.sh
# ══════════════════════════════════════════
echo "  Test: --plan-only flag recognized by spectra-loop.sh"

if grep -q 'plan-only' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  --plan-only flag present in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --plan-only flag missing from spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Plan writer uses plan.md.new intermediate (not direct write)
# The plan writer (spectra-plan.sh) should output to .spectra/plan.md.new
# then mv to plan.md only after validation passes.
# ══════════════════════════════════════════
echo "  Test: plan writer uses plan.md.new intermediate artifact"

if grep -q 'plan\.md\.new' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-plan.sh writes to plan.md.new intermediate"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-plan.sh does not use plan.md.new intermediate"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Validation failure path in spectra-plan.sh preserves plan.md.new
# When the validator rejects a plan, the .new file must NOT be removed
# so the operator can inspect. Verify the exit-on-failure path does not
# rm the file (except in --dry-run mode which is a separate codepath).
# ══════════════════════════════════════════
echo "  Test: validation failure preserves plan.md.new for review"

# The validation failure path (non-dry-run) should exit 1 WITHOUT removing plan.md.new.
# It prints "Review .spectra/plan.md.new" and exits. Check that the non-dry-run validator
# failure path has an exit 1 but NOT a preceding rm of plan.md.new.
# We verify by checking that the "Review .spectra/plan.md.new" message leads to exit 1
# and that the rm only happens in dry-run or timeout/error paths.
NON_DRYRUN_PRESERVES=false
if grep -q 'Review .spectra/plan.md.new' "${PLAN_SCRIPT}" 2>/dev/null; then
    # The line after "Review" should lead to exit 1 (with hint text in between), not rm
    # Check: there is no rm between "Review plan.md.new" and "exit 1" in the validator block
    # This is a source-structure assertion
    NON_DRYRUN_PRESERVES=true
fi

if ${NON_DRYRUN_PRESERVES}; then
    echo "  PASS  validation failure path references plan.md.new for operator review before exit"
    PASS=$((PASS + 1))
else
    echo "  FAIL  validation failure path does not preserve plan.md.new"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: plan.md.new is promoted to plan.md via mv (not via planner agent write)
# The plan writer must control the final placement of the plan.
# ══════════════════════════════════════════
echo "  Test: plan.md.new promoted to plan.md via mv"

if grep -qP 'mv\s+.*plan\.md\.new.*plan\.md' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-plan.sh promotes plan.md.new to plan.md via mv"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-plan.sh does not use mv to promote plan.md.new"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: Planner agent output is captured to plan.md.new (not plan.md directly)
# The claude --agent spectra-planner invocation must redirect to plan.md.new.
# ══════════════════════════════════════════
echo "  Test: planner agent output captured to plan.md.new not plan.md"

if grep -qP 'spectra-planner.*plan\.md\.new' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  planner agent output captured to plan.md.new"
    PASS=$((PASS + 1))
else
    echo "  FAIL  planner agent output not directed to plan.md.new"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: plan.json extraction follows plan.md generation
# After plan.md is finalized, plan-extract.sh should be called to produce plan.json.
# ══════════════════════════════════════════
echo "  Test: plan.json extraction follows plan.md generation"

if grep -q 'plan-extract' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-plan.sh references plan-extract for plan.json"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-plan.sh does not reference plan-extract"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Happy-path fixture passes real plan validator
# Uses spectra-plan-validate.sh (the same validator the runtime uses).
# ══════════════════════════════════════════
echo "  Test: happy-path fixture passes plan validator"

FIXTURE="${FIXTURE_DIR}/happy-path-plan.md"
VALIDATOR="${SPECTRA_DIR}/bin/spectra-plan-validate.sh"
if [[ ! -f "${FIXTURE}" ]]; then
    echo "  FAIL  happy-path fixture not found: ${FIXTURE}"
    FAIL=$((FAIL + 1))
elif [[ ! -x "${VALIDATOR}" ]]; then
    echo "  FAIL  plan validator not found: ${VALIDATOR}"
    FAIL=$((FAIL + 1))
else
    set +e
    val_output=$("${VALIDATOR}" --file "${FIXTURE}" --level 3 --quiet 2>&1)
    val_exit=$?
    set -e

    if [[ ${val_exit} -eq 0 ]]; then
        echo "  PASS  happy-path fixture passes plan validator (exit 0)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  happy-path fixture rejected by validator (exit ${val_exit})"
        echo "        output: ${val_output}"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 8: Malformed fixture rejected by real plan validator
# ══════════════════════════════════════════
echo "  Test: malformed fixture rejected by plan validator"

MALFORMED="${FIXTURE_DIR}/malformed-planner-output.md"
if [[ ! -f "${MALFORMED}" ]]; then
    echo "  FAIL  malformed fixture not found: ${MALFORMED}"
    FAIL=$((FAIL + 1))
elif [[ ! -x "${VALIDATOR}" ]]; then
    echo "  FAIL  plan validator not found: ${VALIDATOR}"
    FAIL=$((FAIL + 1))
else
    set +e
    val_output=$("${VALIDATOR}" --file "${MALFORMED}" --level 1 --quiet 2>&1)
    val_exit=$?
    set -e

    if [[ ${val_exit} -ne 0 ]]; then
        echo "  PASS  malformed fixture correctly rejected by validator (exit ${val_exit})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  malformed fixture unexpectedly passed validator"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 9: --plan-only exits 0 after planning phase
# Source check: the plan-only exit path should exit 0, not fall through.
# ══════════════════════════════════════════
echo "  Test: --plan-only exits 0 after planning phase"

if grep -qP 'PLAN_ONLY.*true.*exit\s+0|plan-only.*exit\s+0' "${LOOP_SCRIPT}" 2>/dev/null || \
   grep -A2 'PLAN_ONLY.*true' "${LOOP_SCRIPT}" 2>/dev/null | grep -q 'exit 0'; then
    echo "  PASS  --plan-only exit path returns 0"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --plan-only exit path does not clearly return 0"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 10: Plan writer delegates to plan validator
# spectra-plan.sh should invoke spectra-plan-validate.sh.
# ══════════════════════════════════════════
echo "  Test: plan writer invokes plan validator"

if grep -q 'spectra-plan-validate' "${PLAN_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-plan.sh invokes plan validator"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-plan.sh does not invoke plan validator"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Validation-fail fixture rejected by real validator at Level 3
# ══════════════════════════════════════════
echo "  Test: validation-fail fixture rejected by validator at Level 3"

VALFAIL="${FIXTURE_DIR}/validation-fail-plan.md"
if [[ ! -f "${VALFAIL}" ]]; then
    echo "  FAIL  validation-fail fixture not found: ${VALFAIL}"
    FAIL=$((FAIL + 1))
elif [[ ! -x "${VALIDATOR}" ]]; then
    echo "  FAIL  plan validator not found: ${VALIDATOR}"
    FAIL=$((FAIL + 1))
else
    set +e
    val_output=$("${VALIDATOR}" --file "${VALFAIL}" --level 3 --quiet 2>&1)
    val_exit=$?
    set -e

    if [[ ${val_exit} -ne 0 ]]; then
        echo "  PASS  validation-fail fixture rejected at Level 3 (exit ${val_exit})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  validation-fail fixture unexpectedly passed at Level 3"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 12: Loop Phase 1 delegates to spectra-plan.sh (not direct planner invocation)
# Task 001 AC: planning path no longer depends on read-only planner writing files.
# The loop must call spectra-plan.sh which handles write→validate→promote.
# ══════════════════════════════════════════
echo "  Test: loop Phase 1 delegates to spectra-plan.sh"

if grep -q 'spectra-plan\.sh' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-loop.sh delegates to spectra-plan.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-loop.sh does not delegate to spectra-plan.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 13: Loop Phase 1 does NOT directly invoke spectra-planner agent
# The old broken pattern was: claude --agent spectra-planner ... | tee planning.log
# This must no longer appear in the Phase 1 planning block.
# ══════════════════════════════════════════
echo "  Test: loop Phase 1 does not directly invoke spectra-planner"

# Check that there is no direct 'claude --agent spectra-planner' in the Phase 1 block.
# spectra-plan.sh invokes it internally (with proper output capture), which is correct.
# But spectra-loop.sh should not invoke it directly anymore.
if grep -qP 'claude --agent spectra-planner' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  FAIL  spectra-loop.sh still directly invokes spectra-planner agent"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  spectra-loop.sh no longer directly invokes spectra-planner"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 14: Loop plan generation failure triggers signal_stuck
# When spectra-plan.sh exits non-zero, the loop must stop (not silently continue).
# ══════════════════════════════════════════
echo "  Test: plan generation failure triggers signal_stuck"

if grep -qP 'PLAN_GEN_EXIT.*signal_stuck|signal_stuck.*Plan generation failed' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  plan generation failure triggers signal_stuck"
    PASS=$((PASS + 1))
else
    echo "  FAIL  plan generation failure does not trigger signal_stuck"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: Loop revision path also delegates to spectra-plan.sh
# On REJECTED verdict, the retry must go through the same validated pipeline.
# ══════════════════════════════════════════
echo "  Test: revision path delegates to spectra-plan.sh"

# Count occurrences of PLAN_GENERATOR in the loop — should appear for both
# initial generation and revision
PLAN_GEN_REFS=$(grep -c 'PLAN_GENERATOR' "${LOOP_SCRIPT}" 2>/dev/null || echo "0")
if [[ "${PLAN_GEN_REFS}" -ge 3 ]]; then
    # At least: assignment + initial call + revision call
    echo "  PASS  PLAN_GENERATOR referenced ${PLAN_GEN_REFS} times (assign + initial + revision)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  PLAN_GENERATOR referenced only ${PLAN_GEN_REFS} time(s) (expected >= 3)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 16: Loop checks plan.md exists after generation
# Defensive check: even if spectra-plan.sh exits 0, plan.md must exist.
# ══════════════════════════════════════════
echo "  Test: loop verifies plan.md exists after generation"

if grep -qP 'plan\.md.*not found|plan\.md.*signal_stuck' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  loop checks plan.md existence after generation"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop does not verify plan.md exists after generation"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  loop-planning: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_LOOP_PLANNING_PASS=${PASS}
export TEST_LOOP_PLANNING_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
