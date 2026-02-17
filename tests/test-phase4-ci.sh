#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 4 Tests — CI Parity
# Tests that CI workflow, fixtures, and break-glass doc are properly configured.

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
# Test 1: Workflow file exists
# ══════════════════════════════════════════
WORKFLOW="${SPECTRA_HOME}/.github/workflows/spectra-ci.yml"
if [[ -f "$WORKFLOW" ]]; then
    assert_pass "workflow file exists"
else
    assert_fail "workflow file exists"
fi

# ══════════════════════════════════════════
# Test 2: Workflow contains 3 required job names
# ══════════════════════════════════════════
JOBS_OK=true
for job in "lint:" "tests:" "wiring:"; do
    if ! grep -q "^  ${job}" "$WORKFLOW" 2>/dev/null; then
        JOBS_OK=false
    fi
done
if [[ "$JOBS_OK" == true ]]; then
    assert_pass "workflow contains lint, tests, wiring jobs"
else
    assert_fail "workflow contains lint, tests, wiring jobs"
fi

# ══════════════════════════════════════════
# Test 3: Workflow contains anti-bypass guard
# ══════════════════════════════════════════
if grep -q 'SPECTRA_SKIP_WIRING' "$WORKFLOW" 2>/dev/null \
   && grep -q 'not allowed in CI' "$WORKFLOW" 2>/dev/null; then
    assert_pass "workflow contains anti-bypass guard"
else
    assert_fail "workflow contains anti-bypass guard"
fi

# ══════════════════════════════════════════
# Test 4: Workflow contains shellcheck step
# ══════════════════════════════════════════
if grep -q 'shellcheck' "$WORKFLOW" 2>/dev/null; then
    assert_pass "workflow contains shellcheck step"
else
    assert_fail "workflow contains shellcheck step"
fi

# ══════════════════════════════════════════
# Test 5: Workflow contains actionlint step
# ══════════════════════════════════════════
if grep -q 'actionlint' "$WORKFLOW" 2>/dev/null; then
    assert_pass "workflow contains actionlint step"
else
    assert_fail "workflow contains actionlint step"
fi

# ══════════════════════════════════════════
# Test 6: Workflow is hardened (timeout, concurrency, permissions)
# ══════════════════════════════════════════
HARDENED=true
grep -q 'timeout-minutes' "$WORKFLOW" 2>/dev/null || HARDENED=false
grep -q 'cancel-in-progress' "$WORKFLOW" 2>/dev/null || HARDENED=false
grep -q 'permissions' "$WORKFLOW" 2>/dev/null || HARDENED=false
grep -q 'actions/checkout@v4' "$WORKFLOW" 2>/dev/null || HARDENED=false
if [[ "$HARDENED" == true ]]; then
    assert_pass "workflow is hardened (timeout, concurrency, permissions, pinned actions)"
else
    assert_fail "workflow is hardened (timeout, concurrency, permissions, pinned actions)"
fi

# ── Ensure fixture git repos exist (wiring script uses git-scoped detection) ──
for fixture_dir in "${SPECTRA_HOME}/fixtures/ci-wiring-pass" "${SPECTRA_HOME}/fixtures/ci-wiring-fail"; do
    if [[ -d "$fixture_dir" ]] && [[ ! -d "$fixture_dir/.git" ]]; then
        (cd "$fixture_dir" && git init && git add -A && git commit -m "fixture" --quiet) > /dev/null 2>&1
    fi
done

# ══════════════════════════════════════════
# Test 7: Pass fixture exists and wiring exits 0
# ══════════════════════════════════════════
PASS_FIXTURE="${SPECTRA_HOME}/fixtures/ci-wiring-pass"
if [[ -d "$PASS_FIXTURE" ]] && [[ -f "$PASS_FIXTURE/.spectra/verify.yaml" ]]; then
    set +e
    "${SPECTRA_HOME}/bin/spectra-verify-wiring.sh" "$PASS_FIXTURE" > /dev/null 2>&1
    PF_EXIT=$?
    set -e
    if [[ $PF_EXIT -eq 0 ]]; then
        assert_pass "pass fixture exists and wiring exits 0"
    else
        assert_fail "pass fixture exists and wiring exits 0 (got exit $PF_EXIT)"
    fi
else
    assert_fail "pass fixture exists and wiring exits 0 (fixture missing)"
fi

# ══════════════════════════════════════════
# Test 8: Fail fixture exists and wiring exits 1
# ══════════════════════════════════════════
FAIL_FIXTURE="${SPECTRA_HOME}/fixtures/ci-wiring-fail"
if [[ -d "$FAIL_FIXTURE" ]] && [[ -f "$FAIL_FIXTURE/.spectra/verify.yaml" ]]; then
    set +e
    "${SPECTRA_HOME}/bin/spectra-verify-wiring.sh" "$FAIL_FIXTURE" > /dev/null 2>&1
    FF_EXIT=$?
    set -e
    if [[ $FF_EXIT -eq 1 ]]; then
        assert_pass "fail fixture exists and wiring exits 1"
    else
        assert_fail "fail fixture exists and wiring exits 1 (got exit $FF_EXIT)"
    fi
else
    assert_fail "fail fixture exists and wiring exits 1 (fixture missing)"
fi

# ══════════════════════════════════════════
# Test 9: Break-glass document exists with required sections
# ══════════════════════════════════════════
BREAKGLASS="${SPECTRA_HOME}/docs/ci-break-glass.md"
if [[ -f "$BREAKGLASS" ]]; then
    BG_OK=true
    grep -qi 'owner' "$BREAKGLASS" 2>/dev/null || BG_OK=false
    grep -qi 'disable.*protection\|disable branch' "$BREAKGLASS" 2>/dev/null || BG_OK=false
    grep -qi 're-enable\|reenable' "$BREAKGLASS" 2>/dev/null || BG_OK=false
    grep -qi 'post-incident\|incident log' "$BREAKGLASS" 2>/dev/null || BG_OK=false
    if [[ "$BG_OK" == true ]]; then
        assert_pass "break-glass doc exists with required sections"
    else
        assert_fail "break-glass doc exists with required sections (missing sections)"
    fi
else
    assert_fail "break-glass doc exists with required sections (file missing)"
fi

# ══════════════════════════════════════════
# Test 10: Workflow uploads artifacts on failure
# ══════════════════════════════════════════
if grep -q 'upload-artifact' "$WORKFLOW" 2>/dev/null; then
    assert_pass "workflow uploads artifacts on failure"
else
    assert_fail "workflow uploads artifacts on failure"
fi

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase4-ci: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
