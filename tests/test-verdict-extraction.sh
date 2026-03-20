#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Structured verdict extraction (loop-verdict.sh)
# Validates JSON trailer parsing, regex fallback, and whitelist validation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"

source "${SPECTRA_DIR}/lib/loop-verdict.sh"

PASS=0
FAIL=0

tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

assert() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS  ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  ${desc} (expected '${expected}', got '${actual}')"
        FAIL=$((FAIL + 1))
    fi
}

# ══════════════════════════════════════════
# Test 1: JSON trailer — verifier PASS
# ══════════════════════════════════════════
echo "  Test: JSON trailer — verifier PASS"

cat > "${tmp_dir}/verify-pass.md" <<'EOF'
## Verification Report — Task 001

All 4 steps passed. Tests: 287/287.

```json
{"result": "PASS", "failure_type": null}
```
EOF

assert "JSON trailer result=PASS" "PASS" "$(extract_verdict "${tmp_dir}/verify-pass.md" "result" PASS FAIL)"
assert "JSON trailer failure_type=empty" "" "$(extract_verdict "${tmp_dir}/verify-pass.md" "failure_type" test_failure wiring_gap)"

# ══════════════════════════════════════════
# Test 2: JSON trailer — verifier FAIL with type
# ══════════════════════════════════════════
echo "  Test: JSON trailer — verifier FAIL with failure_type"

cat > "${tmp_dir}/verify-fail.md" <<'EOF'
## Verification Report — Task 002

Step 1 failed. ModuleNotFoundError: No module named 'pipecat'.

```json
{"result": "FAIL", "failure_type": "missing_dependency"}
```
EOF

assert "JSON trailer result=FAIL" "FAIL" "$(extract_verdict "${tmp_dir}/verify-fail.md" "result" PASS FAIL)"
assert "JSON trailer failure_type=missing_dependency" "missing_dependency" "$(extract_verdict "${tmp_dir}/verify-fail.md" "failure_type" test_failure missing_dependency wiring_gap)"

# ══════════════════════════════════════════
# Test 3: JSON trailer — plan review APPROVED
# ══════════════════════════════════════════
echo "  Test: JSON trailer — plan review APPROVED"

cat > "${tmp_dir}/review-approved.md" <<'EOF'
## Plan Review

The plan is well-structured. All tasks have clear ACs.

Verdict: APPROVED

```json
{"verdict": "APPROVED"}
```
EOF

assert "JSON trailer verdict=APPROVED" "APPROVED" "$(extract_verdict "${tmp_dir}/review-approved.md" "verdict" APPROVED APPROVED_WITH_WARNINGS REJECTED)"

# ══════════════════════════════════════════
# Test 4: Regex fallback — no JSON trailer, markdown bold
# ══════════════════════════════════════════
echo "  Test: regex fallback — markdown bold Result"

cat > "${tmp_dir}/verify-bold.md" <<'EOF'
## Verification Report

- **Result:** PASS
- **Failure Type:** N/A

All steps passed.
EOF

assert "regex fallback bold result=PASS" "PASS" "$(extract_verdict "${tmp_dir}/verify-bold.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
# Test 5: Regex fallback — plain text Result
# ══════════════════════════════════════════
echo "  Test: regex fallback — plain text Result"

cat > "${tmp_dir}/verify-plain.md" <<'EOF'
Verification complete.
Result: FAIL
Failure Type: test_failure
EOF

assert "regex fallback plain result=FAIL" "FAIL" "$(extract_verdict "${tmp_dir}/verify-plain.md" "result" PASS FAIL)"
assert "regex fallback plain failure_type" "test_failure" "$(extract_verdict "${tmp_dir}/verify-plain.md" "failure_type" test_failure missing_dependency)"

# ══════════════════════════════════════════
# Test 6: Regex fallback — header-prefixed Result
# ══════════════════════════════════════════
echo "  Test: regex fallback — ## Result: PASS"

cat > "${tmp_dir}/verify-header.md" <<'EOF'
## Result: PASS

Everything looks good.
EOF

assert "regex fallback header result=PASS" "PASS" "$(extract_verdict "${tmp_dir}/verify-header.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
# Test 7: Regex fallback — natural language PASS indicators
# ══════════════════════════════════════════
echo "  Test: regex fallback — natural language 'all passed'"

cat > "${tmp_dir}/verify-natural.md" <<'EOF'
All 4 audit steps passed. Tests: 355/355.
Wiring clean. No issues found.
EOF

assert "regex fallback natural language PASS" "PASS" "$(extract_verdict "${tmp_dir}/verify-natural.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
# Test 8: Whitelist validation rejects invalid values
# ══════════════════════════════════════════
echo "  Test: whitelist validation rejects invalid values"

cat > "${tmp_dir}/verify-garbage.md" <<'EOF'
```json
{"result": "MAYBE", "failure_type": "cosmic_rays"}
```
EOF

assert "whitelist rejects MAYBE" "" "$(extract_verdict "${tmp_dir}/verify-garbage.md" "result" PASS FAIL)"
assert "whitelist rejects cosmic_rays" "" "$(extract_verdict "${tmp_dir}/verify-garbage.md" "failure_type" test_failure wiring_gap)"

# ══════════════════════════════════════════
# Test 9: Missing file returns empty
# ══════════════════════════════════════════
echo "  Test: missing file returns empty"

assert "missing file returns empty" "" "$(extract_verdict "${tmp_dir}/nonexistent.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
# Test 10: Plan review — regex fallback Verdict: with bold
# ══════════════════════════════════════════
echo "  Test: regex fallback — **Verdict:** REJECTED"

cat > "${tmp_dir}/review-rejected.md" <<'EOF'
## Plan Review

Multiple issues found with task ordering.

- **Verdict:** REJECTED

### Issues
- Task 003 depends on 005
EOF

assert "regex fallback bold verdict=REJECTED" "REJECTED" "$(extract_verdict "${tmp_dir}/review-rejected.md" "verdict" APPROVED APPROVED_WITH_WARNINGS REJECTED)"

# ══════════════════════════════════════════
# Test 11: JSON trailer takes priority over conflicting regex
# ══════════════════════════════════════════
echo "  Test: JSON trailer takes priority over conflicting narrative"

cat > "${tmp_dir}/verify-conflict.md" <<'EOF'
## Report

Step 1 initially showed FAIL but was resolved after retry.
Result: FAIL (before fix)

After fixing the import, all tests pass.

```json
{"result": "PASS", "failure_type": null}
```
EOF

assert "JSON overrides conflicting narrative" "PASS" "$(extract_verdict "${tmp_dir}/verify-conflict.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
# Test 12: VERDICT_SYSTEM_PROMPT variable is defined
# ══════════════════════════════════════════
echo "  Test: VERDICT_SYSTEM_PROMPT is defined and non-empty"

if [[ -n "${VERDICT_SYSTEM_PROMPT:-}" ]] && [[ ${#VERDICT_SYSTEM_PROMPT} -gt 100 ]]; then
    echo "  PASS  VERDICT_SYSTEM_PROMPT defined (${#VERDICT_SYSTEM_PROMPT} chars)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  VERDICT_SYSTEM_PROMPT missing or too short"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 13: Negotiate verdict extraction
# ══════════════════════════════════════════
echo "  Test: negotiate verdict — ESCALATE"

cat > "${tmp_dir}/negotiate.md" <<'EOF'
The proposed adaptation conflicts with the constitution.

```json
{"verdict": "ESCALATE"}
```
EOF

assert "negotiate verdict=ESCALATE" "ESCALATE" "$(extract_verdict "${tmp_dir}/negotiate.md" "verdict" APPROVED ESCALATE)"

# ══════════════════════════════════════════
# Test 14: Case-insensitive matching in regex fallback
# ══════════════════════════════════════════
echo "  Test: case-insensitive regex fallback"

cat > "${tmp_dir}/verify-lowercase.md" <<'EOF'
result: pass
failure type: test_failure
EOF

assert "case-insensitive result=PASS" "PASS" "$(extract_verdict "${tmp_dir}/verify-lowercase.md" "result" PASS FAIL)"

# ══════════════════════════════════════════
echo ""
echo "  verdict-extraction: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=verdict-extraction pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

[[ ${FAIL} -eq 0 ]]
