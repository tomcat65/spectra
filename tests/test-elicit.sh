#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Goal/decision elicitation front-end (spectra-elicit.sh)
# Validates scaffolding, completeness gate (--check), idempotent preservation,
# --from pre-fill, and integration reads (init/plan/context).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
ELICIT="${SPECTRA_DIR}/bin/spectra-elicit.sh"
TEMPLATE="${SPECTRA_DIR}/templates/.spectra/goals.md.tmpl"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

tmp_root=""
cleanup() { [[ -n "${tmp_root}" ]] && rm -rf "${tmp_root}"; }
trap cleanup EXIT
tmp_root=$(mktemp -d)

# ── A filled, complete goals.md used by multiple tests ──
write_complete() {
    cat > "$1" <<'FILLED'
# Goals & Decisions — demo
## Primary Goal
Ship a CLI that prints build status.
## Success Criteria
- [ ] `status` exits 0 and prints a table
## Key Decisions
| # | Decision | Choice | Rationale | Status |
|---|----------|--------|-----------|--------|
| 1 | output | table | readable | RESOLVED |
## Constraints & Non-Negotiables
- Bash only
## Explicitly Out of Scope
- No web UI
## Open Questions / Assumptions
- Assume coreutils present
## Requester
Tomas
FILLED
}

# ── Test 1: script exists and is executable ──
echo "  Test: spectra-elicit.sh exists and is executable"
if [[ -x "${ELICIT}" ]]; then pass "exists and executable"; else fail "not found/executable"; fi

# ── Test 2: template exists ──
echo "  Test: goals.md.tmpl template present"
if [[ -f "${TEMPLATE}" ]]; then pass "template present"; else fail "template missing"; fi

# ── Test 3: --help exits 0 with Usage ──
echo "  Test: --help exits 0 with Usage"
set +e; out=$("${ELICIT}" --help 2>&1); rc=$?; set -e
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q 'Usage'; then pass "--help ok"; else fail "--help rc=${rc}"; fi

# ── Test 4: --self-test passes ──
echo "  Test: --self-test passes"
set +e; "${ELICIT}" --self-test >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "self-test passed"; else fail "self-test rc=${rc}"; fi

# ── Test 5: default mode creates goals.md from template ──
echo "  Test: default mode scaffolds .spectra/goals.md"
proj="${tmp_root}/p5"; mkdir -p "${proj}/.spectra"
set +e; "${ELICIT}" "${proj}" >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 && -f "${proj}/.spectra/goals.md" ]]; then pass "scaffolded"; else fail "not scaffolded rc=${rc}"; fi

# ── Test 6: fresh (template) goals.md fails --check (incomplete) ──
echo "  Test: fresh goals.md fails --check"
set +e; "${ELICIT}" "${proj}" --check >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "incomplete -> exit 1"; else fail "expected 1 got ${rc}"; fi

# ── Test 7: completed goals.md passes --check ──
echo "  Test: completed goals.md passes --check"
proj7="${tmp_root}/p7"; mkdir -p "${proj7}/.spectra"
write_complete "${proj7}/.spectra/goals.md"
set +e; "${ELICIT}" "${proj7}" --check >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "complete -> exit 0"; else fail "expected 0 got ${rc}"; fi

# ── Test 8: --check on missing file exits 2 ──
echo "  Test: --check on missing goals.md exits 2"
proj8="${tmp_root}/p8"; mkdir -p "${proj8}/.spectra"
set +e; "${ELICIT}" "${proj8}" --check >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "missing -> exit 2"; else fail "expected 2 got ${rc}"; fi

# ── Test 9: idempotent — existing file is preserved, not clobbered ──
echo "  Test: default mode preserves an existing goals.md"
proj9="${tmp_root}/p9"; mkdir -p "${proj9}/.spectra"
echo "SENTINEL-DO-NOT-CLOBBER" > "${proj9}/.spectra/goals.md"
set +e; "${ELICIT}" "${proj9}" >/dev/null 2>&1; set -e
if grep -q 'SENTINEL-DO-NOT-CLOBBER' "${proj9}/.spectra/goals.md"; then pass "preserved"; else fail "clobbered existing file"; fi

# ── Test 10: --from pre-fills the primary goal on a fresh create ──
echo "  Test: --from pre-fills primary goal"
proj10="${tmp_root}/p10"; mkdir -p "${proj10}/.spectra"
set +e; "${ELICIT}" "${proj10}" --from "ELICITED-GOAL-LINE" >/dev/null 2>&1; set -e
if grep -qF 'ELICITED-GOAL-LINE' "${proj10}/.spectra/goals.md"; then pass "--from pre-filled"; else fail "--from not applied"; fi

# ── Test 11: SPECTRA_HOME auto-detection present ──
echo "  Test: SPECTRA_HOME auto-detection present"
if grep -q 'SPECTRA_HOME=.*dirname.*SCRIPT_DIR' "${ELICIT}"; then pass "auto-detect present"; else fail "missing auto-detect"; fi

# ── Test 12: context loader reads goals.md when present ──
echo "  Test: loop-context.sh references goals.md"
if grep -q 'goals.md' "${SPECTRA_DIR}/lib/loop-context.sh"; then pass "context wired"; else fail "context not wired"; fi

# ── Test 13: planner read-list + scout prompt reference goals.md ──
echo "  Test: spectra-plan.sh references goals.md"
if grep -q 'goals.md' "${SPECTRA_DIR}/bin/spectra-plan.sh"; then pass "planner wired"; else fail "planner not wired"; fi

# ── Test 14: init scaffolds goals.md (preserve-guarded) ──
echo "  Test: spectra-init.sh scaffolds goals.md"
if grep -q 'goals.md' "${SPECTRA_DIR}/bin/spectra-init.sh"; then pass "init wired"; else fail "init not wired"; fi

# ── Test 15: an empty goals file fails even though it has no markers ──
echo "  Test: empty goals.md fails structural completeness"
proj15="${tmp_root}/p15"; mkdir -p "${proj15}/.spectra"
: > "${proj15}/.spectra/goals.md"
set +e; "${ELICIT}" "${proj15}" --check >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "empty -> exit 1"; else fail "empty expected 1 got ${rc}"; fi

# ── Test 16: a required heading cannot be omitted ──
echo "  Test: missing required goals section fails completeness"
proj16="${tmp_root}/p16"; mkdir -p "${proj16}/.spectra"
write_complete "${proj16}/.spectra/goals.md"
sed -i '/^## Requester$/,$d' "${proj16}/.spectra/goals.md"
set +e; "${ELICIT}" "${proj16}" --check >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "missing section -> exit 1"; else fail "missing section expected 1 got ${rc}"; fi

# ── Test 17: planner enforces the goal gate before discovery/planning ──
echo "  Test: spectra-plan.sh blocks on incomplete goals.md"
proj17="${tmp_root}/p17"; mkdir -p "${proj17}/.spectra"
: > "${proj17}/.spectra/goals.md"
set +e
out=$(cd "${proj17}" && SPECTRA_HOME="${SPECTRA_DIR}" bash "${SPECTRA_DIR}/bin/spectra-plan.sh" --skip-discovery --show-prompt 2>&1)
rc=$?
set -e
if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q 'goals.md is incomplete'; then
    pass "planner rejects incomplete goals"
else
    fail "planner gate rc=${rc}"
fi

# ── Test 18: later spec negotiation is evaluated against the goal contract ──
echo "  Test: NEGOTIATE review references goals.md"
if grep -q 'Evaluate against goals.md' "${SPECTRA_DIR}/bin/spectra-loop.sh" \
   && grep -q 'Read `goals.md`' "${SPECTRA_DIR}/agents/spectra-reviewer.md"; then
    pass "negotiation anchored to goals"
else
    fail "negotiation does not reference goals"
fi

# ══════════════════════════════════════════
echo ""
echo "  elicit: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=elicit pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

[[ ${FAIL} -eq 0 ]]
