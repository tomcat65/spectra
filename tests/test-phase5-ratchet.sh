#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase 5 Tests — ShellCheck Ratchet
# Tests that the ratchet script enforces per-file/per-rule baselines correctly.

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

# ── Check if shellcheck is available ──
SHELLCHECK_BIN="${SHELLCHECK_BIN:-shellcheck}"
if ! command -v "$SHELLCHECK_BIN" > /dev/null 2>&1; then
    # Try common locations
    for candidate in ~/.local/bin/shellcheck /usr/local/bin/shellcheck /usr/bin/shellcheck; do
        if [[ -x "$candidate" ]]; then
            SHELLCHECK_BIN="$candidate"
            break
        fi
    done
fi

if ! command -v "$SHELLCHECK_BIN" > /dev/null 2>&1 && [[ ! -x "$SHELLCHECK_BIN" ]]; then
    echo "  SKIP  shellcheck not found — skipping ratchet tests"
    echo ""
    echo "  phase5-ratchet: 0 passed, 0 failed"
    echo "SPECTRA_TEST_RESULT suite=phase5-ratchet pass=0 fail=0 skip=0 total=0"
    exit 0
fi

export SHELLCHECK_BIN

RATCHET="${SPECTRA_HOME}/bin/spectra-shellcheck-ratchet.sh"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ══════════════════════════════════════════
# Test 1: Ratchet script exists and is executable
# ══════════════════════════════════════════
if [[ -x "$RATCHET" ]]; then
    assert_pass "ratchet script exists and is executable"
else
    assert_fail "ratchet script exists and is executable"
fi

# ══════════════════════════════════════════
# Test 2: --check exits 0 when warnings match baseline
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test2"
mkdir -p "${TMPDIR}/bin" "${TMPDIR}/hooks"

# Create a clean script with no warnings
cat > "${TMPDIR}/bin/clean.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
SCRIPT

# Create a matching baseline
SC_VERSION=$("$SHELLCHECK_BIN" --version | grep '^version:' | awk '{print $2}')
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/clean.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

# Override SPECTRA_HOME so ratchet scopes to our temp dir
set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --check > /dev/null 2>&1
CHECK_EXIT=$?
set -e

if [[ $CHECK_EXIT -eq 0 ]]; then
    assert_pass "--check exits 0 when warnings match baseline"
else
    assert_fail "--check exits 0 when warnings match baseline (got exit $CHECK_EXIT)"
fi

# ══════════════════════════════════════════
# Test 3: --check exits 1 when a file has more warnings than baseline
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test3"
mkdir -p "${TMPDIR}/bin"

# Create a script with an unused variable (SC2034 warning)
cat > "${TMPDIR}/bin/warn.sh" <<'SCRIPT'
#!/usr/bin/env bash
UNUSED_VAR=$(echo hello)
SCRIPT

# Baseline claims 0 warnings for this file
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/warn.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --check > /dev/null 2>&1
CHECK_EXIT=$?
set -e

if [[ $CHECK_EXIT -eq 1 ]]; then
    assert_pass "--check exits 1 when file has more warnings than baseline"
else
    assert_fail "--check exits 1 when file has more warnings than baseline (got exit $CHECK_EXIT)"
fi

# ══════════════════════════════════════════
# Test 4: --check exits 1 when a new rule appears not in baseline
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test4"
mkdir -p "${TMPDIR}/bin"

# SC2034 unused variable
cat > "${TMPDIR}/bin/warn.sh" <<'SCRIPT'
#!/usr/bin/env bash
UNUSED_VAR=$(echo hello)
SCRIPT

# Baseline has 1 warning total but for a different rule
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/warn.sh": { "total": 1, "rules": { "SC9999": 1 } }
  },
  "total": 1
}
BASELINE

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --check > /dev/null 2>&1
CHECK_EXIT=$?
set -e

if [[ $CHECK_EXIT -eq 1 ]]; then
    assert_pass "--check exits 1 when new rule appears not in baseline"
else
    assert_fail "--check exits 1 when new rule appears not in baseline (got exit $CHECK_EXIT)"
fi

# ══════════════════════════════════════════
# Test 5: --update-baseline produces valid JSON with required fields
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test5"
mkdir -p "${TMPDIR}/bin"

cat > "${TMPDIR}/bin/sample.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ok"
SCRIPT

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --update-baseline > /dev/null 2>&1
UPDATE_EXIT=$?
set -e

if [[ $UPDATE_EXIT -eq 0 ]] && [[ -f "${TMPDIR}/shellcheck-baseline.json" ]]; then
    HAS_FIELDS=true
    jq -e '.shellcheck_version' "${TMPDIR}/shellcheck-baseline.json" > /dev/null 2>&1 || HAS_FIELDS=false
    jq -e '.generated_at' "${TMPDIR}/shellcheck-baseline.json" > /dev/null 2>&1 || HAS_FIELDS=false
    jq -e '.files' "${TMPDIR}/shellcheck-baseline.json" > /dev/null 2>&1 || HAS_FIELDS=false
    jq -e '.total' "${TMPDIR}/shellcheck-baseline.json" > /dev/null 2>&1 || HAS_FIELDS=false
    if [[ "$HAS_FIELDS" == true ]]; then
        assert_pass "--update-baseline produces valid JSON with required fields"
    else
        assert_fail "--update-baseline produces valid JSON with required fields (missing fields)"
    fi
else
    assert_fail "--update-baseline produces valid JSON with required fields (exit $UPDATE_EXIT)"
fi

# ══════════════════════════════════════════
# Test 6: --update-baseline fails if any file count increased (no --allow-increase)
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test6"
mkdir -p "${TMPDIR}/bin"

# Script with an unused variable warning (SC2034)
cat > "${TMPDIR}/bin/warn.sh" <<'SCRIPT'
#!/usr/bin/env bash
UNUSED_VAR=$(echo hello)
SCRIPT

# Old baseline claims 0 warnings
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/warn.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --update-baseline > /dev/null 2>&1
UPDATE_EXIT=$?
set -e

if [[ $UPDATE_EXIT -eq 1 ]]; then
    assert_pass "--update-baseline fails if file count increased (no --allow-increase)"
else
    assert_fail "--update-baseline fails if file count increased (got exit $UPDATE_EXIT)"
fi

# ══════════════════════════════════════════
# Test 7: --update-baseline --allow-increase succeeds with rationale
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test7"
mkdir -p "${TMPDIR}/bin"

# Script with an unused variable warning (SC2034)
cat > "${TMPDIR}/bin/warn.sh" <<'SCRIPT'
#!/usr/bin/env bash
UNUSED_VAR=$(echo hello)
SCRIPT

# Old baseline claims 0
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/warn.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

set +e
output=$(SPECTRA_HOME="$TMPDIR" "$RATCHET" --update-baseline --allow-increase "adding unused var for test" 2>&1)
UPDATE_EXIT=$?
set -e

if [[ $UPDATE_EXIT -eq 0 ]] && echo "$output" | grep -q "adding unused var for test"; then
    assert_pass "--update-baseline --allow-increase succeeds and emits rationale"
else
    assert_fail "--update-baseline --allow-increase succeeds and emits rationale (exit $UPDATE_EXIT)"
fi

# ══════════════════════════════════════════
# Test 7b: --allow-increase rejects empty rationale
# ══════════════════════════════════════════
set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --update-baseline --allow-increase "" > /dev/null 2>&1
EMPTY_EXIT=$?
set -e

if [[ $EMPTY_EXIT -eq 1 ]]; then
    assert_pass "--allow-increase rejects empty rationale string"
else
    assert_fail "--allow-increase rejects empty rationale string (got exit $EMPTY_EXIT)"
fi

# ══════════════════════════════════════════
# Test 8: Version mismatch between runtime and baseline fails --check
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test8"
mkdir -p "${TMPDIR}/bin"

cat > "${TMPDIR}/bin/clean.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
SCRIPT

# Baseline with wrong version
cat > "${TMPDIR}/shellcheck-baseline.json" <<'BASELINE'
{
  "shellcheck_version": "99.99.99",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/clean.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --check > /dev/null 2>&1
CHECK_EXIT=$?
set -e

if [[ $CHECK_EXIT -eq 1 ]]; then
    assert_pass "version mismatch between runtime and baseline fails --check"
else
    assert_fail "version mismatch between runtime and baseline fails --check (got exit $CHECK_EXIT)"
fi

# ══════════════════════════════════════════
# Test 9: --check fails on file missing from baseline (new file)
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test9"
mkdir -p "${TMPDIR}/bin"

cat > "${TMPDIR}/bin/old.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "old"
SCRIPT

cat > "${TMPDIR}/bin/new.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "new"
SCRIPT

# Baseline only knows about old.sh
cat > "${TMPDIR}/shellcheck-baseline.json" <<BASELINE
{
  "shellcheck_version": "${SC_VERSION}",
  "generated_at": "2026-01-01T00:00:00Z",
  "files": {
    "bin/old.sh": { "total": 0, "rules": {} }
  },
  "total": 0
}
BASELINE

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --check > /dev/null 2>&1
CHECK_EXIT=$?
set -e

if [[ $CHECK_EXIT -eq 1 ]]; then
    assert_pass "--check fails on file missing from baseline (new file requires update)"
else
    assert_fail "--check fails on file missing from baseline (got exit $CHECK_EXIT)"
fi

# ══════════════════════════════════════════
# Test 10: --allow-increase requires non-empty rationale
# ══════════════════════════════════════════
TMPDIR="${TMPDIR_BASE}/test10"
mkdir -p "${TMPDIR}/bin"

cat > "${TMPDIR}/bin/sample.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ok"
SCRIPT

set +e
SPECTRA_HOME="$TMPDIR" "$RATCHET" --update-baseline --allow-increase > /dev/null 2>&1
NOARG_EXIT=$?
set -e

if [[ $NOARG_EXIT -eq 1 ]]; then
    assert_pass "--allow-increase requires non-empty rationale string"
else
    assert_fail "--allow-increase requires non-empty rationale string (got exit $NOARG_EXIT)"
fi

# ══════════════════════════════════════════
# Test 11: Baseline JSON exists in repo
# ══════════════════════════════════════════
if [[ -f "${SPECTRA_HOME}/shellcheck-baseline.json" ]]; then
    VALID=true
    jq -e '.shellcheck_version' "${SPECTRA_HOME}/shellcheck-baseline.json" > /dev/null 2>&1 || VALID=false
    jq -e '.files' "${SPECTRA_HOME}/shellcheck-baseline.json" > /dev/null 2>&1 || VALID=false
    if [[ "$VALID" == true ]]; then
        assert_pass "shellcheck-baseline.json exists in repo with valid structure"
    else
        assert_fail "shellcheck-baseline.json exists in repo with valid structure (invalid JSON)"
    fi
else
    assert_fail "shellcheck-baseline.json exists in repo with valid structure (file missing)"
fi

# ══════════════════════════════════════════
# Test 12: CI workflow contains ratchet step
# ══════════════════════════════════════════
WORKFLOW="${SPECTRA_HOME}/.github/workflows/spectra-ci.yml"
if grep -q 'spectra-ci-lint.sh --ratchet' "$WORKFLOW" 2>/dev/null; then
    assert_pass "CI workflow contains ratchet step"
else
    assert_fail "CI workflow contains ratchet step"
fi

# ══════════════════════════════════════════
# Test 13: CI workflow pins ShellCheck version (not apt-get)
# ══════════════════════════════════════════
if grep -q 'shellcheck.*releases/download' "$WORKFLOW" 2>/dev/null \
   && ! grep -q 'apt-get.*shellcheck' "$WORKFLOW" 2>/dev/null; then
    assert_pass "CI workflow pins ShellCheck version (not apt-get)"
else
    assert_fail "CI workflow pins ShellCheck version (not apt-get)"
fi

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  phase5-ratchet: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=phase5-ratchet pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
exit 0
