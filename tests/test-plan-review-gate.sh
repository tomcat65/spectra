#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Plan review gate enforcement (Task 002 scaffolding)
# Validates that the reviewer gate blocks on missing artifacts,
# bounds retries, and parses verdicts correctly. No LLM invocation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"
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
# Test 1: Verdict parsing pattern matches expected format
# The loop uses: grep -oP 'Verdict:\s*\K\S+' to extract verdicts.
# Verify this pattern works against fixture files.
# ══════════════════════════════════════════
echo "  Test: verdict parsing pattern against APPROVED fixture"

APPROVED_FIXTURE="${FIXTURE_DIR}/review-approved.md"
if [[ ! -f "${APPROVED_FIXTURE}" ]]; then
    echo "  FAIL  review-approved fixture not found"
    FAIL=$((FAIL + 1))
else
    VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${APPROVED_FIXTURE}" | head -1 || echo "NONE")
    if [[ "${VERDICT}" == "APPROVED" ]]; then
        echo "  PASS  verdict parsing extracts APPROVED correctly"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  verdict parsing got '${VERDICT}' instead of 'APPROVED'"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 2: Verdict parsing against APPROVED_WITH_WARNINGS fixture
# ══════════════════════════════════════════
echo "  Test: verdict parsing pattern against APPROVED_WITH_WARNINGS fixture"

WARNINGS_FIXTURE="${FIXTURE_DIR}/review-approved-warnings.md"
if [[ ! -f "${WARNINGS_FIXTURE}" ]]; then
    echo "  FAIL  review-approved-warnings fixture not found"
    FAIL=$((FAIL + 1))
else
    VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${WARNINGS_FIXTURE}" | head -1 || echo "NONE")
    if [[ "${VERDICT}" == "APPROVED_WITH_WARNINGS" ]]; then
        echo "  PASS  verdict parsing extracts APPROVED_WITH_WARNINGS correctly"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  verdict parsing got '${VERDICT}' instead of 'APPROVED_WITH_WARNINGS'"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 3: Verdict parsing against REJECTED fixture
# ══════════════════════════════════════════
echo "  Test: verdict parsing pattern against REJECTED fixture"

REJECTED_FIXTURE="${FIXTURE_DIR}/review-rejected.md"
if [[ ! -f "${REJECTED_FIXTURE}" ]]; then
    echo "  FAIL  review-rejected fixture not found"
    FAIL=$((FAIL + 1))
else
    VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${REJECTED_FIXTURE}" | head -1 || echo "NONE")
    if [[ "${VERDICT}" == "REJECTED" ]]; then
        echo "  PASS  verdict parsing extracts REJECTED correctly"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  verdict parsing got '${VERDICT}' instead of 'REJECTED'"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 4: Runtime case statement handles all three verdict values
# The spectra-loop.sh case block must have branches for
# APPROVED, APPROVED_WITH_WARNINGS, and REJECTED.
# ══════════════════════════════════════════
echo "  Test: runtime handles APPROVED verdict"
if grep -qP '^\s+APPROVED\)' "${LOOP_SCRIPT}" 2>/dev/null || \
   grep -qP 'APPROVED\s*\)' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  APPROVED case branch present in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  APPROVED case branch missing from spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

echo "  Test: runtime handles APPROVED_WITH_WARNINGS verdict"
if grep -q 'APPROVED_WITH_WARNINGS' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  APPROVED_WITH_WARNINGS case branch present"
    PASS=$((PASS + 1))
else
    echo "  FAIL  APPROVED_WITH_WARNINGS case branch missing"
    FAIL=$((FAIL + 1))
fi

echo "  Test: runtime handles REJECTED verdict"
if grep -q 'REJECTED' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  REJECTED case branch present"
    PASS=$((PASS + 1))
else
    echo "  FAIL  REJECTED case branch missing"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: Missing plan-review.md behavior — current vs expected
# CURRENT BUG: missing plan-review.md is NOT treated as blocking.
# The loop prints "No plan-review.md generated. Proceeding without formal review."
# Task 002 AC requires this to be a blocking condition.
# This test documents the expected behavior so the runtime fix has a target.
# ══════════════════════════════════════════
echo "  Test: missing plan-review.md path exists in source (placeholder for blocking gate)"

# Verify the current behavior is documented in source
if grep -q 'plan-review.md' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  plan-review.md path referenced in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  plan-review.md not referenced in spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

# Verify missing plan-review.md triggers signal_stuck (blocking behavior).
if grep -q 'Proceeding without formal review' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  FAIL  missing review still proceeds without blocking"
    FAIL=$((FAIL + 1))
else
    if grep -qP 'signal_stuck.*plan-review|No plan-review.*signal_stuck' "${LOOP_SCRIPT}" 2>/dev/null; then
        echo "  PASS  missing review triggers signal_stuck (blocking)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  missing review behavior is ambiguous in source"
        FAIL=$((FAIL + 1))
    fi
fi

# ══════════════════════════════════════════
# Test 6: Rejected plan gets exactly one revision attempt
# The retry logic should attempt one re-plan + re-review, then STUCK.
# ══════════════════════════════════════════
echo "  Test: rejected plan gets bounded retry (one revision)"

# Check for the revision attempt prompt
if grep -q 'ONE revision attempt' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  revision attempt is explicitly bounded to ONE"
    PASS=$((PASS + 1))
else
    echo "  FAIL  revision attempt bound not explicit in source"
    FAIL=$((FAIL + 1))
fi

# Check for the double-rejection STUCK signal
if grep -q 'Plan rejected twice' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  double rejection triggers STUCK signal"
    PASS=$((PASS + 1))
else
    echo "  FAIL  double rejection STUCK signal not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Reviewer verdict parsing uses consistent regex
# Both the initial review and re-review should use the same parsing pattern.
# ══════════════════════════════════════════
echo "  Test: verdict parsing pattern is consistent across initial and re-review"

# extract_verdict should be used for all verdict parsing (replaces raw grep patterns)
VERDICT_PATTERNS=$(grep -c "extract_verdict" "${LOOP_SCRIPT}" 2>/dev/null || echo "0")
if [[ "${VERDICT_PATTERNS}" -ge 2 ]]; then
    echo "  PASS  extract_verdict used ${VERDICT_PATTERNS} times (initial + re-review + verifier)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  extract_verdict used only ${VERDICT_PATTERNS} time(s) (expected >= 2)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: Reviewer signal file path is consistent
# plan-review.md should be written to ${SIGNALS_DIR}/plan-review.md.
# ══════════════════════════════════════════
echo "  Test: reviewer signal file path references SIGNALS_DIR"

if grep -qP 'SIGNALS_DIR.*plan-review\.md' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  plan-review.md stored under SIGNALS_DIR"
    PASS=$((PASS + 1))
else
    echo "  FAIL  plan-review.md path does not reference SIGNALS_DIR"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: APPROVED_WITH_WARNINGS branch appends warnings with dedup
# The branch at ~line 818-827 must: extract warnings from plan-review.md,
# run guardrails_dedup_check, and append to guardrails.md.
# ══════════════════════════════════════════
echo "  Test: APPROVED_WITH_WARNINGS branch has dedup append logic"

# Check for the actual branch-specific pattern: dedup check + append to guardrails.md
if grep -q 'guardrails_dedup_check' "${LOOP_SCRIPT}" 2>/dev/null && \
   grep -q '>> .*guardrails\.md' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  warning promotion uses guardrails_dedup_check + append"
    PASS=$((PASS + 1))
else
    echo "  FAIL  warning promotion branch missing dedup or append logic"
    FAIL=$((FAIL + 1))
fi

echo "  Test: warning extraction parses from plan-review.md Warnings section"

# Check the sed pattern that extracts warning lines from the reviewer output
if grep -qP "sed.*Warnings.*plan-review" "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  warnings extracted from plan-review.md via sed section parse"
    PASS=$((PASS + 1))
else
    echo "  FAIL  warning extraction pattern not found in source"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Verdict regex handles bold markdown format from reviewer
# The reviewer agent may output **Verdict:** APPROVED (bold markdown).
# The loop regex must extract the verdict value, not the bold markers.
# ══════════════════════════════════════════
echo "  Test: verdict regex handles bold markdown format"

BOLD_RESULT=$(echo '- **Verdict:** APPROVED' | grep -oP 'Verdict:\*{0,2}\s*\K[A-Z_]+' | head -1 || echo "NONE")
if [[ "${BOLD_RESULT}" == "APPROVED" ]]; then
    echo "  PASS  bold markdown verdict parsed correctly (${BOLD_RESULT})"
    PASS=$((PASS + 1))
else
    echo "  FAIL  bold markdown verdict parsed as '${BOLD_RESULT}' (expected APPROVED)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: Verdict regex handles plain text format
# ══════════════════════════════════════════
echo "  Test: verdict regex handles plain text format"

PLAIN_RESULT=$(echo 'Verdict: REJECTED' | grep -oP 'Verdict:\*{0,2}\s*\K[A-Z_]+' | head -1 || echo "NONE")
if [[ "${PLAIN_RESULT}" == "REJECTED" ]]; then
    echo "  PASS  plain text verdict parsed correctly (${PLAIN_RESULT})"
    PASS=$((PASS + 1))
else
    echo "  FAIL  plain text verdict parsed as '${PLAIN_RESULT}' (expected REJECTED)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 13: Loop uses extract_verdict for structured verdict parsing
# extract_verdict handles JSON trailers + regex fallback (replaces brittle regexes)
# ══════════════════════════════════════════
echo "  Test: loop uses extract_verdict for structured parsing"

if grep -q 'extract_verdict.*verdict.*APPROVED' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  loop uses extract_verdict with whitelist validation"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop does not use extract_verdict for verdict parsing"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: Reviewer agent instructions use plain Verdict: format
# The reviewer agent template should use machine-readable plain text,
# not bold markdown, for the verdict line.
# ══════════════════════════════════════════
echo "  Test: reviewer agent uses plain Verdict: format"

REVIEWER_AGENT="${HOME}/.claude/agents/spectra-reviewer.md"
if [[ -f "${REVIEWER_AGENT}" ]]; then
    # Check that at least one example uses plain "Verdict:" not "**Verdict:**"
    if grep -q '^Verdict:' "${REVIEWER_AGENT}" 2>/dev/null; then
        echo "  PASS  reviewer agent instructions use plain Verdict: format"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  reviewer agent instructions still use bold **Verdict:** format"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  reviewer agent definition not found at ${REVIEWER_AGENT}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  plan-review-gate: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=plan-review-gate pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_PLAN_REVIEW_GATE_PASS=${PASS}
export TEST_PLAN_REVIEW_GATE_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
