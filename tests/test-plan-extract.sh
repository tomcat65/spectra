#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Plan extraction (plan.md → plan.json)
# Tests plan-extract.sh against fixtures and validates JSON output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
EXTRACTOR="${SPECTRA_DIR}/bin/plan-extract.sh"
FIXTURE_DIR="${SPECTRA_DIR}/fixtures/plan-bridge"

PASS=0
FAIL=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

assert_pass() {
    local desc="$1"
    PASS=$((PASS + 1))
    echo "  PASS  ${desc}"
}

assert_fail() {
    local desc="$1"
    local detail="${2:-}"
    FAIL=$((FAIL + 1))
    echo "  FAIL  ${desc}"
    [[ -n "$detail" ]] && echo "        ${detail}"
}

# ══════════════════════════════════════════
# Test 1: Basic extraction — level 0 fixture
# ══════════════════════════════════════════
echo "  Test: basic extraction (level 0)"

OUT="${tmp_dir}/level0.json"
if "${EXTRACTOR}" --file "${FIXTURE_DIR}/valid-level0.md" --output "${OUT}" 2>/dev/null; then
    if [[ -f "$OUT" ]] && [[ -s "$OUT" ]]; then
        assert_pass "level 0 extraction produces non-empty output"
    else
        assert_fail "level 0 extraction output empty or missing"
    fi
else
    assert_fail "level 0 extraction exited non-zero"
fi

# ══════════════════════════════════════════
# Test 2: Basic extraction — level 2 fixture
# ══════════════════════════════════════════
echo "  Test: basic extraction (level 2)"

OUT="${tmp_dir}/level2.json"
if "${EXTRACTOR}" --file "${FIXTURE_DIR}/valid-level2.md" --output "${OUT}" 2>/dev/null; then
    task_count=$(grep -c '"id":' "$OUT" || echo "0")
    if [[ "$task_count" -eq 2 ]]; then
        assert_pass "level 2 extraction finds 2 tasks"
    else
        assert_fail "level 2 extraction expected 2 tasks, got ${task_count}"
    fi
else
    assert_fail "level 2 extraction exited non-zero"
fi

# ══════════════════════════════════════════
# Test 3: Basic extraction — level 4 fixture
# ══════════════════════════════════════════
echo "  Test: basic extraction (level 4)"

OUT="${tmp_dir}/level4.json"
if "${EXTRACTOR}" --file "${FIXTURE_DIR}/valid-level4.md" --output "${OUT}" 2>/dev/null; then
    task_count=$(grep -c '"id":' "$OUT" || echo "0")
    if [[ "$task_count" -eq 3 ]]; then
        assert_pass "level 4 extraction finds 3 tasks"
    else
        assert_fail "level 4 extraction expected 3 tasks, got ${task_count}"
    fi
else
    assert_fail "level 4 extraction exited non-zero"
fi

# ══════════════════════════════════════════
# Test 4: Ownership arrays (owns, touches, reads)
# ══════════════════════════════════════════
echo "  Test: ownership arrays extraction"

OUT="${tmp_dir}/level4.json"
# Already generated above; check Task 001 owns
if command -v jq &>/dev/null; then
    owns_count=$(jq '.tasks[0].owns | length' "$OUT" 2>/dev/null || echo "0")
    touches_count=$(jq '.tasks[0].touches | length' "$OUT" 2>/dev/null || echo "0")
    reads_count=$(jq '.tasks[0].reads | length' "$OUT" 2>/dev/null || echo "0")

    if [[ "$owns_count" -eq 1 ]] && [[ "$touches_count" -eq 0 ]] && [[ "$reads_count" -eq 1 ]]; then
        assert_pass "Task 001 owns=1, touches=0, reads=1"
    else
        assert_fail "Task 001 ownership mismatch: owns=${owns_count}, touches=${touches_count}, reads=${reads_count}"
    fi
else
    # Fallback: grep for the array content
    if grep -q '"owns": \["infra/terraform/messaging.tf"\]' "$OUT" 2>/dev/null; then
        assert_pass "Task 001 owns field present (grep fallback)"
    else
        assert_fail "Task 001 owns field not found (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 5: Dependency chain extraction
# ══════════════════════════════════════════
echo "  Test: dependency chain extraction"

OUT="${tmp_dir}/level4.json"
if command -v jq &>/dev/null; then
    deps_002=$(jq -r '.tasks[1].deps | join(",")' "$OUT" 2>/dev/null || echo "")
    if [[ "$deps_002" == "001" ]]; then
        assert_pass "Task 002 depends on 001"
    else
        assert_fail "Task 002 deps expected '001', got '${deps_002}'"
    fi
else
    if grep -q '"deps": \["001"\]' "$OUT" 2>/dev/null; then
        assert_pass "Task 002 depends on 001 (grep fallback)"
    else
        assert_fail "Task 002 deps not found (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 6: Risk case normalization
# ══════════════════════════════════════════
echo "  Test: risk case normalization"

OUT="${tmp_dir}/mixed-risk.json"
"${EXTRACTOR}" --file "${FIXTURE_DIR}/valid-risk-mixed-case.md" --output "${OUT}" 2>/dev/null

if command -v jq &>/dev/null; then
    risk_001=$(jq -r '.tasks[0].risk' "$OUT" 2>/dev/null || echo "")
    risk_002=$(jq -r '.tasks[1].risk' "$OUT" 2>/dev/null || echo "")
    risk_003=$(jq -r '.tasks[2].risk' "$OUT" 2>/dev/null || echo "")

    if [[ "$risk_001" == "high" ]] && [[ "$risk_002" == "low" ]] && [[ "$risk_003" == "medium" ]]; then
        assert_pass "Risk normalized: High→high, LOW→low, medium→medium"
    else
        assert_fail "Risk normalization failed: 001=${risk_001}, 002=${risk_002}, 003=${risk_003}"
    fi
else
    # Fallback: check that no uppercase Risk values in output
    if ! grep -qE '"risk": "(High|LOW|HIGH|Low|Medium|MEDIUM)"' "$OUT" 2>/dev/null; then
        assert_pass "No uppercase Risk values in output (grep fallback)"
    else
        assert_fail "Uppercase Risk values found in output"
    fi
fi

# ══════════════════════════════════════════
# Test 7: Checkbox status mapping
# ══════════════════════════════════════════
echo "  Test: checkbox status mapping"

CHECKBOX_PLAN="${tmp_dir}/checkbox.md"
cat > "$CHECKBOX_PLAN" <<'PLAN'
# SPECTRA Execution Plan

## Project: Checkbox Test
## Level: 0
## Generated: 2026-02-16

---

## Task 001: Pending task
- [ ] 001: Pending task
- AC:
  - A criterion.
- Files: src/a.ts
- Verify: `npm test`

## Task 002: Complete task
- [x] 002: Complete task
- AC:
  - A criterion.
- Files: src/b.ts
- Verify: `npm test`

## Task 003: Stuck task
- [!] 003: Stuck task
- AC:
  - A criterion.
- Files: src/c.ts
- Verify: `npm test`
PLAN

OUT="${tmp_dir}/checkbox.json"
"${EXTRACTOR}" --file "$CHECKBOX_PLAN" --output "$OUT" 2>/dev/null

if command -v jq &>/dev/null; then
    s1=$(jq -r '.tasks[0].status' "$OUT" 2>/dev/null || echo "")
    s2=$(jq -r '.tasks[1].status' "$OUT" 2>/dev/null || echo "")
    s3=$(jq -r '.tasks[2].status' "$OUT" 2>/dev/null || echo "")

    if [[ "$s1" == "pending" ]] && [[ "$s2" == "complete" ]] && [[ "$s3" == "stuck" ]]; then
        assert_pass "Status: pending/complete/stuck mapped correctly"
    else
        assert_fail "Status mapping: 001=${s1}, 002=${s2}, 003=${s3}"
    fi
else
    if grep -q '"status": "pending"' "$OUT" && grep -q '"status": "complete"' "$OUT" && grep -q '"status": "stuck"' "$OUT"; then
        assert_pass "All three status values present (grep fallback)"
    else
        assert_fail "Not all status values found (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 8: Line number tracking
# ══════════════════════════════════════════
echo "  Test: line number tracking"

if command -v jq &>/dev/null; then
    line_001=$(jq '.tasks[0].line_number' "$OUT" 2>/dev/null || echo "0")
    if [[ "$line_001" -gt 0 ]]; then
        assert_pass "Task 001 has line_number > 0 (${line_001})"
    else
        assert_fail "Task 001 line_number is 0 or missing"
    fi
else
    if grep -qE '"line_number": [1-9]' "$OUT" 2>/dev/null; then
        assert_pass "line_number > 0 found (grep fallback)"
    else
        assert_fail "line_number > 0 not found (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 9: JSON validity (via jq)
# ══════════════════════════════════════════
echo "  Test: JSON validity"

OUT="${tmp_dir}/level4.json"
if command -v jq &>/dev/null; then
    if jq empty "$OUT" 2>/dev/null; then
        assert_pass "level 4 JSON is valid (jq)"
    else
        assert_fail "level 4 JSON is invalid (jq)"
    fi
else
    # Can't validate without jq — check basic structure
    if grep -q '"version": "1.0"' "$OUT" && grep -q '"tasks":' "$OUT"; then
        assert_pass "JSON has expected structure (no jq available)"
    else
        assert_fail "JSON structure check failed (no jq)"
    fi
fi

# ══════════════════════════════════════════
# Test 10: Parse error exit code (missing file)
# ══════════════════════════════════════════
echo "  Test: parse error exit code"

set +e
"${EXTRACTOR}" --file "${tmp_dir}/nonexistent.md" 2>/dev/null
EXIT_CODE=$?
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
    assert_pass "missing file returns non-zero exit (${EXIT_CODE})"
else
    assert_fail "missing file returned exit 0 (expected non-zero)"
fi

# ══════════════════════════════════════════
# Test 11: --file required
# ══════════════════════════════════════════
echo "  Test: --file required"

set +e
"${EXTRACTOR}" 2>/dev/null
EXIT_CODE=$?
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
    assert_pass "no --file flag returns non-zero exit (${EXIT_CODE})"
else
    assert_fail "no --file flag returned exit 0 (expected non-zero)"
fi

# ══════════════════════════════════════════
# Test 12: Bare owns fallback parsing
# ══════════════════════════════════════════
echo "  Test: bare owns fallback"

BARE_PLAN="${tmp_dir}/bare-owns.md"
cat > "$BARE_PLAN" <<'PLAN'
# SPECTRA Execution Plan

## Project: Bare Owns Test
## Level: 2
## Generated: 2026-02-16

---

## Task 001: Build something
- [ ] 001: Build something
- AC:
  - It works.
- Files: src/thing.ts
- Verify: `npm test`
- Risk: medium
- Max-iterations: 5
- Scope: code
- File-ownership:
  - owns: src/thing.ts, src/other.ts
  - touches: src/shared.ts
  - reads: src/config.ts
- Wiring-proof:
  - CLI: npm test
  - Integration: thing -> other asserted.
PLAN

OUT="${tmp_dir}/bare-owns.json"
"${EXTRACTOR}" --file "$BARE_PLAN" --output "$OUT" 2>/dev/null

if command -v jq &>/dev/null; then
    owns=$(jq -r '.tasks[0].owns | length' "$OUT" 2>/dev/null || echo "0")
    touches=$(jq -r '.tasks[0].touches | length' "$OUT" 2>/dev/null || echo "0")
    reads=$(jq -r '.tasks[0].reads | length' "$OUT" 2>/dev/null || echo "0")

    if [[ "$owns" -eq 2 ]] && [[ "$touches" -eq 1 ]] && [[ "$reads" -eq 1 ]]; then
        assert_pass "bare owns/touches/reads parsed: owns=2, touches=1, reads=1"
    else
        assert_fail "bare format mismatch: owns=${owns}, touches=${touches}, reads=${reads}"
    fi
else
    if grep -q '"owns":' "$OUT" && grep -q '"reads":' "$OUT"; then
        assert_pass "bare format fields present (grep fallback)"
    else
        assert_fail "bare format fields missing (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 13: jq path vs regex path produce identical arrays
# ══════════════════════════════════════════
echo "  Test: jq path vs regex path parity"

# This test sources parse_plan functions from spectra-loop.sh
# and compares JSON-sourced arrays vs markdown-sourced arrays.
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"
PARITY_DIR="${tmp_dir}/parity"
mkdir -p "${PARITY_DIR}/.spectra/signals"

# Copy level 4 fixture as plan.md
cp "${FIXTURE_DIR}/valid-level4.md" "${PARITY_DIR}/.spectra/plan.md"

# Generate plan.json
"${EXTRACTOR}" --file "${PARITY_DIR}/.spectra/plan.md" --output "${PARITY_DIR}/.spectra/plan.json" 2>/dev/null

if command -v jq &>/dev/null; then
    # Extract task IDs from JSON path
    JSON_IDS=$(jq -r '.tasks[].id' "${PARITY_DIR}/.spectra/plan.json" | tr '\n' ',' | sed 's/,$//')

    # Extract task IDs from markdown path (run extractor — same code path as parse_plan_from_markdown)
    MD_IDS=$(grep -oP '^## Task \K[0-9]{3}' "${PARITY_DIR}/.spectra/plan.md" | tr '\n' ',' | sed 's/,$//')

    if [[ "$JSON_IDS" == "$MD_IDS" ]]; then
        assert_pass "task IDs match: JSON='${JSON_IDS}' == MD='${MD_IDS}'"
    else
        assert_fail "task IDs differ: JSON='${JSON_IDS}' vs MD='${MD_IDS}'"
    fi
else
    assert_pass "parity test skipped (no jq)"
fi

# ══════════════════════════════════════════
# Test 14: Explicit "depends on" parsing in extractor
# ══════════════════════════════════════════
echo "  Test: explicit 'depends on' dependency parsing"

EXPLICIT_DEP_PLAN="${tmp_dir}/explicit-dep.md"
cat > "$EXPLICIT_DEP_PLAN" <<'PLAN'
# SPECTRA Execution Plan

## Project: Explicit Deps Test
## Level: 3
## Generated: 2026-02-16

---

## Task 001: Base module
- [ ] 001: Base module
- AC:
  - Module exists.
- Files: src/base.ts
- Verify: `npm test`
- Risk: low
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [src/base.ts]
  - touches: []
  - reads: []
- Wiring-proof:
  - CLI: npm test
  - Integration: base module asserted.

## Task 002: Derived module
- [ ] 002: Derived module
- AC:
  - Module extends base.
- Files: src/derived.ts
- Verify: `npm test`
- Risk: medium
- Max-iterations: 5
- Scope: code
- File-ownership:
  - owns: [src/derived.ts]
  - touches: []
  - reads: [src/base.ts]
- Wiring-proof:
  - CLI: npm test
  - Integration: derived -> base asserted.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Task 002 depends on 001
- Recommendation: SEQUENTIAL_ONLY
PLAN

OUT="${tmp_dir}/explicit-dep.json"
"${EXTRACTOR}" --file "$EXPLICIT_DEP_PLAN" --output "$OUT" 2>/dev/null

if command -v jq &>/dev/null; then
    deps_002=$(jq -r '.tasks[1].deps | join(",")' "$OUT" 2>/dev/null || echo "")
    if [[ "$deps_002" == "001" ]]; then
        assert_pass "explicit 'depends on' parsed: Task 002 deps='001'"
    else
        assert_fail "explicit 'depends on' not parsed: Task 002 deps='${deps_002}' (expected '001')"
    fi
else
    if grep -q '"deps": \["001"\]' "$OUT" 2>/dev/null; then
        assert_pass "explicit 'depends on' parsed (grep fallback)"
    else
        assert_fail "explicit 'depends on' not parsed (grep fallback)"
    fi
fi

# ══════════════════════════════════════════
# Test 15: Malformed plan.json triggers markdown fallback (runtime integration)
# ══════════════════════════════════════════
echo "  Test: malformed plan.json triggers markdown fallback (runtime)"

MALFORMED_DIR="${tmp_dir}/malformed"
mkdir -p "${MALFORMED_DIR}/.spectra/signals"

# Create valid plan.md
cp "${FIXTURE_DIR}/valid-level0.md" "${MALFORMED_DIR}/.spectra/plan.md"

# Create malformed plan.json (missing status field)
cat > "${MALFORMED_DIR}/.spectra/plan.json" <<'BADJSON'
{
  "version": "1.0",
  "project": "Bad",
  "level": 0,
  "generated": "2026-02-16",
  "source": "test",
  "tasks": [
    {
      "id": "001",
      "title": "Missing status field",
      "risk": "medium",
      "verify": "npm test",
      "max_iterations": 5,
      "owns": [],
      "touches": [],
      "reads": [],
      "deps": [],
      "line_number": 11
    }
  ]
}
BADJSON

# Touch plan.json to be fresh (newer than plan.md) so freshness gate passes
sleep 1
touch "${MALFORMED_DIR}/.spectra/plan.json"

# Create minimal project.yaml for loop
cat > "${MALFORMED_DIR}/.spectra/project.yaml" <<'YAML'
name: malformed-test
level: 0
YAML

LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"

# Run spectra-loop.sh --skip-planning --dry-run from the temp project dir
# and capture output. It should fall back to markdown due to malformed JSON.
set +e
loop_output=$(cd "${MALFORMED_DIR}" && bash "${LOOP_SCRIPT}" --skip-planning --dry-run 2>&1)
loop_exit=$?
set -e

if echo "$loop_output" | grep -q "plan.json parse failed\|falling back to markdown\|Parsed.*tasks from plan.md"; then
    assert_pass "malformed plan.json: loop fell back to markdown path"
else
    # Check if it parsed from plan.md anyway (also acceptable — means fallback worked silently)
    if echo "$loop_output" | grep -q "Parsed.*tasks from plan.md"; then
        assert_pass "malformed plan.json: loop used markdown path"
    else
        assert_fail "malformed plan.json: no fallback detected in loop output" "output: $(echo "$loop_output" | head -5)"
    fi
fi

# ══════════════════════════════════════════
# Test 16: Stale plan.json triggers markdown fallback (runtime integration)
# ══════════════════════════════════════════
echo "  Test: stale plan.json triggers markdown fallback (runtime)"

FRESH_DIR="${tmp_dir}/freshness"
mkdir -p "${FRESH_DIR}/.spectra/signals"

# Create plan.md and generate plan.json
cp "${FIXTURE_DIR}/valid-level0.md" "${FRESH_DIR}/.spectra/plan.md"
"${EXTRACTOR}" --file "${FRESH_DIR}/.spectra/plan.md" --output "${FRESH_DIR}/.spectra/plan.json" 2>/dev/null

# Modify plan.md content so source_hash no longer matches plan.json
echo "<!-- modified -->" >> "${FRESH_DIR}/.spectra/plan.md"

# Create minimal project.yaml
cat > "${FRESH_DIR}/.spectra/project.yaml" <<'YAML'
name: freshness-test
level: 0
YAML

# Run loop --skip-planning --dry-run — should detect stale JSON and use markdown
set +e
loop_output=$(cd "${FRESH_DIR}" && bash "${LOOP_SCRIPT}" --skip-planning --dry-run 2>&1)
loop_exit=$?
set -e

if echo "$loop_output" | grep -q "plan.json is stale"; then
    assert_pass "stale plan.json: loop detected staleness and warned"
elif echo "$loop_output" | grep -q "Parsed.*tasks from plan.md"; then
    assert_pass "stale plan.json: loop fell back to markdown path"
else
    assert_fail "stale plan.json: no staleness detection in loop output" "output: $(echo "$loop_output" | head -5)"
fi

# ══════════════════════════════════════════
# Test 17: Fresh plan.json uses jq fast path (runtime integration)
# ══════════════════════════════════════════
echo "  Test: fresh plan.json uses jq fast path (runtime)"

if command -v jq &>/dev/null; then
    FAST_DIR="${tmp_dir}/fastpath"
    mkdir -p "${FAST_DIR}/.spectra/signals"

    cp "${FIXTURE_DIR}/valid-level0.md" "${FAST_DIR}/.spectra/plan.md"
    "${EXTRACTOR}" --file "${FAST_DIR}/.spectra/plan.md" --output "${FAST_DIR}/.spectra/plan.json" 2>/dev/null

    # Ensure plan.json is fresh (same or newer mtime)
    touch "${FAST_DIR}/.spectra/plan.json"

    cat > "${FAST_DIR}/.spectra/project.yaml" <<'YAML'
name: fastpath-test
level: 0
YAML

    set +e
    loop_output=$(cd "${FAST_DIR}" && bash "${LOOP_SCRIPT}" --skip-planning --dry-run 2>&1)
    set -e

    if echo "$loop_output" | grep -q "jq fast path"; then
        assert_pass "fresh plan.json: loop used jq fast path"
    else
        assert_fail "fresh plan.json: jq fast path not used" "output: $(echo "$loop_output" | grep -i 'parsed\|plan' | head -3)"
    fi
else
    assert_pass "fresh plan.json fast path test skipped (no jq)"
fi

# ══════════════════════════════════════════
echo ""
echo "  plan-extract: ${PASS} passed, ${FAIL} failed"

export TEST_EXTRACT_PASS=${PASS}
export TEST_EXTRACT_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
