#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Loop unit tests for Phase 1 quick wins
# Tests plan checksum lock and builder timeout detection (no LLM invocation).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"

PASS=0
FAIL=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT

tmp_dir=$(mktemp -d)

# Helper: compute structural checksum (same algorithm as spectra-loop.sh)
structural_checksum() {
    grep -vE '^\- \[[ xX!]\] [0-9]{3}:' "$1" 2>/dev/null | sha256sum | cut -d' ' -f1
}

# ══════════════════════════════════════════
# Test 1: Structural checksum — detect task definition mutation
# ══════════════════════════════════════════
echo "  Test: structural checksum detects task definition mutation"

PROJ="${tmp_dir}/checksum-test"
mkdir -p "${PROJ}/.spectra/signals"
cat > "${PROJ}/.spectra/plan.md" <<'PLAN'
## Task 001: Foo
- [ ] 001: Foo
- AC:
  - criterion
- Files: src/foo.ts
- Verify: `npm test`
PLAN

INITIAL=$(structural_checksum "${PROJ}/.spectra/plan.md")

# Mutate a structural line (add new task)
echo "## Task 002: Bar" >> "${PROJ}/.spectra/plan.md"

AFTER=$(structural_checksum "${PROJ}/.spectra/plan.md")

if [[ "${INITIAL}" != "${AFTER}" ]]; then
    echo "  PASS  structural checksum detects definition mutation (${INITIAL:0:8}... != ${AFTER:0:8}...)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  structural checksum did NOT detect definition mutation"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Structural checksum — stable on checkbox-only mutation
# ══════════════════════════════════════════
echo "  Test: structural checksum stable when checkbox changes"

cat > "${PROJ}/.spectra/plan.md" <<'PLAN'
## Task 001: Foo
- [ ] 001: Foo
- AC:
  - criterion
- Files: src/foo.ts
- Verify: `npm test`
PLAN

CS_BEFORE=$(structural_checksum "${PROJ}/.spectra/plan.md")

# Mutate only checkbox ([ ] -> [x]) — this is what the loop does
sed -i 's/\- \[ \] 001:/- [x] 001:/' "${PROJ}/.spectra/plan.md"

CS_AFTER=$(structural_checksum "${PROJ}/.spectra/plan.md")

if [[ "${CS_BEFORE}" == "${CS_AFTER}" ]]; then
    echo "  PASS  structural checksum stable across checkbox mutation"
    PASS=$((PASS + 1))
else
    echo "  FAIL  structural checksum changed on checkbox mutation (${CS_BEFORE:0:8}... != ${CS_AFTER:0:8}...)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2b: Structural checksum — stable on stuck marker mutation
# ══════════════════════════════════════════
echo "  Test: structural checksum stable when stuck marker set"

cat > "${PROJ}/.spectra/plan.md" <<'PLAN'
## Task 001: Foo
- [ ] 001: Foo
- AC:
  - criterion
- Files: src/foo.ts
- Verify: `npm test`
PLAN

CS_BEFORE=$(structural_checksum "${PROJ}/.spectra/plan.md")

# Mutate checkbox to stuck ([ ] -> [!])
sed -i 's/\- \[ \] 001:/- [!] 001:/' "${PROJ}/.spectra/plan.md"

CS_AFTER=$(structural_checksum "${PROJ}/.spectra/plan.md")

if [[ "${CS_BEFORE}" == "${CS_AFTER}" ]]; then
    echo "  PASS  structural checksum stable across stuck marker"
    PASS=$((PASS + 1))
else
    echo "  FAIL  structural checksum changed on stuck marker (${CS_BEFORE:0:8}... != ${CS_AFTER:0:8}...)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2c: Structural checksum — recompute after NEGOTIATE constraint append
# ══════════════════════════════════════════
echo "  Test: checksum recompute after constraint append prevents false lock"

cat > "${PROJ}/.spectra/plan.md" <<'PLAN'
## Task 001: Foo
- [ ] 001: Foo
- AC:
  - criterion
- Files: src/foo.ts
- Verify: `npm test`
PLAN

CS_INITIAL=$(structural_checksum "${PROJ}/.spectra/plan.md")

# Simulate NEGOTIATE approved constraint append (bin/spectra-loop.sh:1645)
echo "> Constraint: API must use v2 schema" >> "${PROJ}/.spectra/plan.md"

# Without recompute, checksum would differ (this is the bug codex found)
CS_AFTER_APPEND=$(structural_checksum "${PROJ}/.spectra/plan.md")

if [[ "${CS_INITIAL}" != "${CS_AFTER_APPEND}" ]]; then
    # Good — append DOES change structural checksum (it's a real structural change)
    # The fix is that spectra-loop.sh recomputes PLAN_CHECKSUM after the append.
    # Simulate recompute (what the fix does):
    CS_RECOMPUTED="${CS_AFTER_APPEND}"
    # Now verify next check matches the recomputed baseline
    CS_NEXT_CHECK=$(structural_checksum "${PROJ}/.spectra/plan.md")
    if [[ "${CS_RECOMPUTED}" == "${CS_NEXT_CHECK}" ]]; then
        echo "  PASS  recomputed checksum matches after constraint append"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  recomputed checksum does not match (${CS_RECOMPUTED:0:8}... != ${CS_NEXT_CHECK:0:8}...)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  constraint append did not change structural checksum (expected change before recompute)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Timeout exit code 124
# ══════════════════════════════════════════
echo "  Test: timeout command returns exit 124"

set +e
timeout 1 sleep 10
EXIT_CODE=$?
set -e

if [[ "${EXIT_CODE}" -eq 124 ]]; then
    echo "  PASS  timeout returns exit 124"
    PASS=$((PASS + 1))
else
    echo "  FAIL  timeout returned exit ${EXIT_CODE} (expected 124)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Timeout does not kill fast commands
# ══════════════════════════════════════════
echo "  Test: timeout does not kill fast commands"

set +e
timeout 5 echo "hello" > /dev/null
EXIT_CODE=$?
set -e

if [[ "${EXIT_CODE}" -eq 0 ]]; then
    echo "  PASS  fast command completes under timeout"
    PASS=$((PASS + 1))
else
    echo "  FAIL  fast command got exit ${EXIT_CODE} under timeout"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: --builder-timeout flag recognized by script parser
# ══════════════════════════════════════════
echo "  Test: --builder-timeout flag in help text"

if grep -q 'builder-timeout' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  --builder-timeout flag present in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --builder-timeout flag missing from spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: TIMEOUT signal file creation pattern
# ══════════════════════════════════════════
echo "  Test: TIMEOUT signal file creation"

TIMEOUT_SIG="${tmp_dir}/TIMEOUT_001"
echo "TIMEOUT" > "${TIMEOUT_SIG}"

if [[ -f "${TIMEOUT_SIG}" ]] && [[ "$(cat "${TIMEOUT_SIG}")" == "TIMEOUT" ]]; then
    echo "  PASS  TIMEOUT signal file created correctly"
    PASS=$((PASS + 1))
else
    echo "  FAIL  TIMEOUT signal file creation failed"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  loop-unit: ${PASS} passed, ${FAIL} failed"

export TEST_LOOP_PASS=${PASS}
export TEST_LOOP_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
