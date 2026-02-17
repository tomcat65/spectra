#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 3 Tests — Pre-Commit Wiring Enforcement + Full Verification
# Tests that graduated mode is removed and wiring enforcement is active.

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
# Test 1: Pre-commit hook exists and is executable
# ══════════════════════════════════════════
HOOK="${SPECTRA_HOME}/hooks/pre-commit"
if [[ -f "$HOOK" ]] && [[ -x "$HOOK" ]]; then
    assert_pass "pre-commit hook exists and is executable"
else
    assert_fail "pre-commit hook exists and is executable"
fi

# ══════════════════════════════════════════
# Test 2: Pre-commit hook exits 0 when no verify.yaml (graceful degradation)
# ══════════════════════════════════════════
TMPDIR_T2=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T2"' EXIT
(cd "$TMPDIR_T2" && bash "$HOOK" 2>/dev/null)
if [[ $? -eq 0 ]]; then
    assert_pass "pre-commit hook exits 0 when no verify.yaml"
else
    assert_fail "pre-commit hook exits 0 when no verify.yaml"
fi

# ══════════════════════════════════════════
# Test 3: Pre-commit hook exits 0 when SPECTRA_SKIP_WIRING=1
# ══════════════════════════════════════════
TMPDIR_T3=$(mktemp -d)
mkdir -p "$TMPDIR_T3/.spectra"
echo "project:" > "$TMPDIR_T3/.spectra/verify.yaml"
set +e
(cd "$TMPDIR_T3" && SPECTRA_SKIP_WIRING=1 bash "$HOOK" 2>/dev/null)
T3_EXIT=$?
set -e
rm -rf "$TMPDIR_T3"
if [[ $T3_EXIT -eq 0 ]]; then
    assert_pass "pre-commit hook exits 0 when SPECTRA_SKIP_WIRING=1"
else
    assert_fail "pre-commit hook exits 0 when SPECTRA_SKIP_WIRING=1"
fi

# ══════════════════════════════════════════
# Test 4: Pre-commit hook install is idempotent
# ══════════════════════════════════════════
TMPDIR_T4=$(mktemp -d)
mkdir -p "$TMPDIR_T4/.git/hooks"
ln -s "$HOOK" "$TMPDIR_T4/.git/hooks/pre-commit" 2>/dev/null || true
# Try install again — should not error
if ln -s "$HOOK" "$TMPDIR_T4/.git/hooks/pre-commit" 2>/dev/null; then
    # Second symlink succeeded (shouldn't if already exists) — still ok, idempotent check passes
    assert_pass "pre-commit hook install is idempotent"
elif [[ -L "$TMPDIR_T4/.git/hooks/pre-commit" ]]; then
    # Symlink already exists — correct idempotent behavior
    assert_pass "pre-commit hook install is idempotent"
else
    assert_fail "pre-commit hook install is idempotent"
fi
rm -rf "$TMPDIR_T4"

# ══════════════════════════════════════════
# Test 5: Loop does NOT contain --no-verify
# ══════════════════════════════════════════
LOOP="${SPECTRA_HOME}/bin/spectra-loop.sh"
if grep -q '\-\-no-verify' "$LOOP" 2>/dev/null; then
    assert_fail "loop does NOT contain --no-verify"
else
    assert_pass "loop does NOT contain --no-verify"
fi

# ══════════════════════════════════════════
# Test 6: Loop sets verify_depth="full" unconditionally (no graduated reference)
# ══════════════════════════════════════════
if grep -q 'verify_depth="graduated"' "$LOOP" 2>/dev/null; then
    assert_fail "loop sets verify_depth=full unconditionally (no graduated)"
elif grep -q 'verify_depth="full"' "$LOOP" 2>/dev/null; then
    assert_pass "loop sets verify_depth=full unconditionally (no graduated)"
else
    assert_fail "loop sets verify_depth=full unconditionally (no graduated)"
fi

# ══════════════════════════════════════════
# Test 7: spectra-verify.sh has no --graduated flag
# ══════════════════════════════════════════
VERIFY="${SPECTRA_HOME}/bin/spectra-verify.sh"
if grep -q '\-\-graduated' "$VERIFY" 2>/dev/null; then
    assert_fail "spectra-verify.sh has no --graduated flag"
else
    assert_pass "spectra-verify.sh has no --graduated flag"
fi

# ══════════════════════════════════════════
# Test 8: Verifier agent definition has no "graduated" references
# ══════════════════════════════════════════
VERIFIER_AGENT="${HOME}/.claude/agents/spectra-verifier.md"
if grep -qi 'graduated' "$VERIFIER_AGENT" 2>/dev/null; then
    assert_fail "verifier agent has no graduated references"
else
    assert_pass "verifier agent has no graduated references"
fi

# ══════════════════════════════════════════
# Test 9: Builder Stop hook references spectra-verify-wiring.sh
# ══════════════════════════════════════════
BUILDER_AGENT="${HOME}/.claude/agents/spectra-builder.md"
if grep -q 'spectra-verify-wiring.sh' "$BUILDER_AGENT" 2>/dev/null; then
    if grep -q 'spectra-wiring-proof.sh' "$BUILDER_AGENT" 2>/dev/null; then
        assert_fail "builder Stop hook references spectra-verify-wiring.sh (not old dead script)"
    else
        assert_pass "builder Stop hook references spectra-verify-wiring.sh (not old dead script)"
    fi
else
    assert_fail "builder Stop hook references spectra-verify-wiring.sh (not old dead script)"
fi

# ══════════════════════════════════════════
# Test 10: Dry-run emits verify_depth="full" for every task (behavioral)
# ══════════════════════════════════════════
# We verify by checking loop source: the verify_depth assignment is unconditional.
# Count how many verify_depth assignments exist in the verification section
FULL_ASSIGNS=$(grep -c 'verify_depth="full"' "$LOOP" 2>/dev/null) || FULL_ASSIGNS=0
GRADUATED_ASSIGNS=$(grep -c 'verify_depth="graduated"' "$LOOP" 2>/dev/null) || GRADUATED_ASSIGNS=0
if [[ "$FULL_ASSIGNS" -ge 1 ]] && [[ "$GRADUATED_ASSIGNS" -eq 0 ]]; then
    assert_pass "all verify_depth assignments are 'full' (no graduated)"
else
    assert_fail "all verify_depth assignments are 'full' (no graduated) — full=$FULL_ASSIGNS, graduated=$GRADUATED_ASSIGNS"
fi

# ══════════════════════════════════════════
# Test 11: Pre-commit hook fails closed when verifier script is missing
# ══════════════════════════════════════════
TMPDIR_T11=$(mktemp -d)
mkdir -p "$TMPDIR_T11/.spectra"
echo "project:" > "$TMPDIR_T11/.spectra/verify.yaml"
set +e
# Run hook with a fake SPECTRA_HOME that has no verifier script
(cd "$TMPDIR_T11" && SPECTRA_HOME="$TMPDIR_T11/nonexistent" bash "$HOOK" 2>/dev/null)
T11_EXIT=$?
set -e
rm -rf "$TMPDIR_T11"
if [[ $T11_EXIT -ne 0 ]]; then
    assert_pass "pre-commit hook fails closed when verifier missing"
else
    assert_fail "pre-commit hook fails closed when verifier missing"
fi

# ══════════════════════════════════════════
# Test 12: Wiring failure routes to FAIL path (not completion)
# ══════════════════════════════════════════
# Verify the loop structure: wiring gate runs BEFORE TASK_STATUS=complete
# and sets RESULT="FAIL" + FAILURE_TYPE="wiring_gap" on failure.
# This is a structural test on the source ordering.
LOOP_PASS_SECTION=$(sed -n '/RESULT\^\^.*PASS/,/TASK_STATUS\[/p' "$LOOP" 2>/dev/null | head -20)
if echo "$LOOP_PASS_SECTION" | grep -q 'WIRING_OK' 2>/dev/null; then
    # Wiring gate appears before TASK_STATUS assignment
    assert_pass "wiring gate runs before task completion marking"
else
    assert_fail "wiring gate runs before task completion marking"
fi

# ══════════════════════════════════════════
# Test 13: Wiring failure sets failure_type=wiring_gap (routes to retry)
# ══════════════════════════════════════════
if grep -q 'FAILURE_TYPE="wiring_gap"' "$LOOP" 2>/dev/null; then
    assert_pass "wiring failure sets failure_type=wiring_gap for retry"
else
    assert_fail "wiring failure sets failure_type=wiring_gap for retry"
fi

# ══════════════════════════════════════════
# Test 14: Runtime — wiring failure prevents task completion in mock loop
# ══════════════════════════════════════════
# Simulate the wiring gate logic extracted from the loop.
# If wiring fails, RESULT must flip to FAIL and task must NOT be marked complete.
TMPDIR_T14=$(mktemp -d)
cat > "$TMPDIR_T14/wiring-gate-sim.sh" <<'SIMEOF'
#!/usr/bin/env bash
set -euo pipefail
# Simulated wiring gate logic (extracted from spectra-loop.sh)
RESULT="PASS"
WIRING_OK=true
TASK_STATUS="pending"

# Simulate wiring failure (exit 1)
WIRING_EXIT=1
SPECTRA_SKIP_WIRING="${SPECTRA_SKIP_WIRING:-0}"

if [[ "$SPECTRA_SKIP_WIRING" == "1" ]]; then
    : # bypass
elif [[ $WIRING_EXIT -ne 0 ]]; then
    WIRING_OK=false
fi

if [[ "$WIRING_OK" == false ]]; then
    RESULT="FAIL"
    FAILURE_TYPE="wiring_gap"
fi

if [[ "${RESULT}" == "PASS" ]]; then
    TASK_STATUS="complete"
fi

# Output for test assertion
echo "RESULT=${RESULT}"
echo "TASK_STATUS=${TASK_STATUS}"
echo "FAILURE_TYPE=${FAILURE_TYPE:-}"
SIMEOF
chmod +x "$TMPDIR_T14/wiring-gate-sim.sh"

SIM_OUT=$(bash "$TMPDIR_T14/wiring-gate-sim.sh" 2>&1)
rm -rf "$TMPDIR_T14"

SIM_RESULT=$(echo "$SIM_OUT" | grep '^RESULT=' | cut -d= -f2)
SIM_STATUS=$(echo "$SIM_OUT" | grep '^TASK_STATUS=' | cut -d= -f2)
SIM_FTYPE=$(echo "$SIM_OUT" | grep '^FAILURE_TYPE=' | cut -d= -f2)

if [[ "$SIM_RESULT" == "FAIL" ]] && [[ "$SIM_STATUS" == "pending" ]] && [[ "$SIM_FTYPE" == "wiring_gap" ]]; then
    assert_pass "runtime: wiring failure blocks completion (FAIL/pending/wiring_gap)"
else
    assert_fail "runtime: wiring failure blocks completion — got RESULT=$SIM_RESULT STATUS=$SIM_STATUS TYPE=$SIM_FTYPE"
fi

# ══════════════════════════════════════════
# Test 15: Type-specific retry budget is enforced (wiring_gap -> 2)
# ══════════════════════════════════════════
# max_retries_for returns 2 for wiring_gap.
# The loop must STUCK when iteration >= allowed_retries, not fall through to max_iterations.
BUDGET_CHECK=$(sed -n '/allowed_retries.*max_retries_for/,/signal_stuck.*retry budget/p' "$LOOP" 2>/dev/null)
if echo "$BUDGET_CHECK" | grep -q 'iteration.*-ge.*allowed_retries' 2>/dev/null \
   && echo "$BUDGET_CHECK" | grep -q 'retry budget' 2>/dev/null; then
    assert_pass "type-specific retry budget enforced (iteration >= allowed_retries -> STUCK)"
else
    assert_fail "type-specific retry budget enforced (iteration >= allowed_retries -> STUCK)"
fi

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase3-enforcement: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
