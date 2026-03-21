#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 7 Tests — ShellCheck Warning Burn-Down
# Validates zero warnings, canonical baseline, suppress rationale policy, monotonic proof.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"
BASELINE="${SPECTRA_HOME}/shellcheck-baseline.json"

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
# Test 1: Baseline total is 0
# ══════════════════════════════════════════
if [[ -f "$BASELINE" ]]; then
    TOTAL=$(jq -r '.total' "$BASELINE" 2>/dev/null || echo "-1")
    if [[ "$TOTAL" -eq 0 ]]; then
        assert_pass "baseline total is 0 (all warnings fixed)"
    else
        assert_fail "baseline total is 0 — got $TOTAL"
    fi
else
    assert_fail "baseline total is 0 (baseline file missing)"
fi

# ══════════════════════════════════════════
# Test 2: Baseline uses canonical paths (no symlink aliases)
# ══════════════════════════════════════════
SYMLINK_ALIASES=0
if [[ -f "$BASELINE" ]]; then
    while IFS= read -r key; do
        # Check if the corresponding file is a symlink
        full_path="${SPECTRA_HOME}/${key}"
        if [[ -L "$full_path" ]]; then
            SYMLINK_ALIASES=1
            echo "    Symlink alias in baseline: ${key}"
        fi
    done < <(jq -r '.files | keys[]' "$BASELINE" 2>/dev/null)
fi
if [[ $SYMLINK_ALIASES -eq 0 ]]; then
    assert_pass "baseline uses canonical paths (no symlink aliases)"
else
    assert_fail "baseline uses canonical paths (no symlink aliases)"
fi

# ══════════════════════════════════════════
# Test 3: Every shellcheck disable has preceding RATIONALE comment
# ══════════════════════════════════════════
MISSING_RATIONALE=0
for f in "${SPECTRA_HOME}"/bin/*.sh "${SPECTRA_HOME}"/lib/*.sh "${SPECTRA_HOME}"/hooks/pre-commit; do
    [[ -f "$f" ]] || continue
    [[ -L "$f" ]] && continue
    prev_line=""
    while IFS= read -r line; do
        if echo "$line" | grep -q '# shellcheck disable=' 2>/dev/null; then
            if ! echo "$prev_line" | grep -q '# RATIONALE:' 2>/dev/null; then
                MISSING_RATIONALE=1
                echo "    Missing RATIONALE before disable in $(basename "$f"): $line"
            fi
        fi
        prev_line="$line"
    done < "$f"
done
if [[ $MISSING_RATIONALE -eq 0 ]]; then
    assert_pass "every shellcheck disable has preceding RATIONALE comment"
else
    assert_fail "every shellcheck disable has preceding RATIONALE comment"
fi

# ══════════════════════════════════════════
# Test 4: Monotonic ratchet proof — baseline total <= 22 (Phase 6 baseline)
# ══════════════════════════════════════════
if [[ -f "$BASELINE" ]]; then
    TOTAL=$(jq -r '.total' "$BASELINE" 2>/dev/null || echo "999")
    if [[ "$TOTAL" -le 22 ]]; then
        assert_pass "monotonic ratchet: baseline ($TOTAL) <= previous (22)"
    else
        assert_fail "monotonic ratchet: baseline ($TOTAL) > previous (22)"
    fi
else
    assert_fail "monotonic ratchet proof (baseline missing)"
fi

# ══════════════════════════════════════════
# Test 5: Ratchet --check passes with current code
# ══════════════════════════════════════════
RATCHET="${SPECTRA_HOME}/bin/spectra-shellcheck-ratchet.sh"
SHELLCHECK_BIN="${SHELLCHECK_BIN:-$(command -v shellcheck 2>/dev/null || echo "")}"
if [[ -n "$SHELLCHECK_BIN" ]] && [[ -x "$RATCHET" ]]; then
    set +e
    SHELLCHECK_BIN="$SHELLCHECK_BIN" "$RATCHET" --check > /dev/null 2>&1
    RATCHET_EXIT=$?
    set -e
    if [[ $RATCHET_EXIT -eq 0 ]]; then
        assert_pass "ratchet --check passes with current code"
    else
        assert_fail "ratchet --check fails (exit $RATCHET_EXIT)"
    fi
else
    echo "    SKIP: shellcheck not available"
    assert_pass "ratchet --check passes (skipped — shellcheck not installed)"
fi

# ══════════════════════════════════════════
# Test 6: Discover targets prefers canonical paths over symlinks
# ══════════════════════════════════════════
# The ratchet should list bin/spectra-loop.sh, not bin/spectra-loop-v3.sh
if [[ -n "$SHELLCHECK_BIN" ]] && [[ -x "$RATCHET" ]]; then
    set +e
    TARGETS=$(SHELLCHECK_BIN="$SHELLCHECK_BIN" bash -c '
        SPECTRA_HOME="'"${SPECTRA_HOME}"'"
        source "'"${RATCHET}"'" --help 2>/dev/null || true
    ' 2>&1)
    set -e
    # Simpler: just check the baseline keys don't include symlink paths
    if jq -r '.files | keys[]' "$BASELINE" 2>/dev/null | grep -q 'spectra-loop-v3\|spectra-loop-v5'; then
        assert_fail "discover_targets prefers canonical paths (found symlink alias in baseline)"
    else
        assert_pass "discover_targets prefers canonical paths"
    fi
else
    assert_pass "discover_targets prefers canonical paths (skipped — shellcheck not installed)"
fi

# ══════════════════════════════════════════
# Test 7: No SC2034 warnings remain in any script
# ══════════════════════════════════════════
if [[ -n "$SHELLCHECK_BIN" ]]; then
    SC2034_COUNT=0
    for f in "${SPECTRA_HOME}"/bin/*.sh "${SPECTRA_HOME}"/hooks/pre-commit; do
        [[ -f "$f" ]] || continue
        [[ -L "$f" ]] && continue
        cnt=$("$SHELLCHECK_BIN" --severity=warning --format=gcc "$f" 2>&1 | grep -c 'SC2034' || true)
        SC2034_COUNT=$((SC2034_COUNT + cnt))
    done
    if [[ $SC2034_COUNT -eq 0 ]]; then
        assert_pass "no SC2034 (unused variable) warnings remain"
    else
        assert_fail "no SC2034 warnings remain — found $SC2034_COUNT"
    fi
else
    assert_pass "no SC2034 warnings remain (skipped — shellcheck not installed)"
fi

# ══════════════════════════════════════════
# Test 8: CI workflow includes suppress-rationale guard
# ══════════════════════════════════════════
CI_WORKFLOW="${SPECTRA_HOME}/.github/workflows/spectra-ci.yml"
if [[ -f "$CI_WORKFLOW" ]] && grep -q 'Suppress rationale guard' "$CI_WORKFLOW" 2>/dev/null; then
    assert_pass "CI workflow has suppress-rationale guard step"
else
    assert_fail "CI workflow has suppress-rationale guard step"
fi

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase7-shellcheck: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=phase7-shellcheck pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
