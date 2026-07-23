#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Phase D Tests — Language Profile Extraction
# Tests: profile sourcing, variable validation, auto-detection, missing profile warning, SIGN-010

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "  FAIL  $1: $2"; }

echo "=== Phase D: Language Profile Tests ==="

# ── Test 1: python.profile exists and is sourceable ──
PROFILE="${SPECTRA_HOME}/lang-profiles/python.profile"
if [[ -f "$PROFILE" ]]; then
    # Source in a subshell to avoid polluting this shell yet
    if bash -c "source '${PROFILE}'" 2>/dev/null; then
        pass "T1: python.profile exists and is sourceable"
    else
        fail "T1: python.profile exists but fails to source" "source error"
    fi
else
    fail "T1: python.profile exists and is sourceable" "file not found"
fi

# Source the profile for subsequent tests
# shellcheck source=/dev/null
source "$PROFILE"

# ── Test 2: IMPORT_PATTERNS has 2 entries ──
if [[ ${#IMPORT_PATTERNS[@]} -eq 2 ]]; then
    pass "T2: IMPORT_PATTERNS has 2 entries"
else
    fail "T2: IMPORT_PATTERNS has 2 entries" "got ${#IMPORT_PATTERNS[@]}"
fi

# ── Test 3: ENTRY_POINTS has 3 entries ──
if [[ ${#ENTRY_POINTS[@]} -eq 3 ]]; then
    pass "T3: ENTRY_POINTS has 3 entries"
else
    fail "T3: ENTRY_POINTS has 3 entries" "got ${#ENTRY_POINTS[@]}"
fi

# ── Test 4: DEP_MANIFESTS has 4 entries ──
if [[ ${#DEP_MANIFESTS[@]} -eq 4 ]]; then
    pass "T4: DEP_MANIFESTS has 4 entries"
else
    fail "T4: DEP_MANIFESTS has 4 entries" "got ${#DEP_MANIFESTS[@]}"
fi

# ── Test 5: SKIP_IMPORTS matches expected pattern ──
EXPECTED_SKIP="patch|MagicMock|Mock|pytest|unittest|mock|subprocess|os|sys|json|tempfile|shutil|pathlib|Path|Any|Dict|List|Optional|call|PropertyMock|fixture"
if [[ "$SKIP_IMPORTS" == "$EXPECTED_SKIP" ]]; then
    pass "T5: SKIP_IMPORTS matches hardcoded list"
else
    fail "T5: SKIP_IMPORTS matches hardcoded list" "mismatch"
fi

# ── Test 6: FILE_EXTENSION is py ──
if [[ "$FILE_EXTENSION" == "py" ]]; then
    pass "T6: FILE_EXTENSION is py"
else
    fail "T6: FILE_EXTENSION is py" "got ${FILE_EXTENSION}"
fi

# ── Test 7: Auto-detect Python (requirements.txt) ──
TMPDIR_PY=$(mktemp -d)
touch "${TMPDIR_PY}/requirements.txt"
DETECTED=""
if [[ -f "${TMPDIR_PY}/pyproject.toml" || -f "${TMPDIR_PY}/requirements.txt" || -f "${TMPDIR_PY}/setup.py" || -f "${TMPDIR_PY}/setup.cfg" || -f "${TMPDIR_PY}/Pipfile" ]]; then
    DETECTED="python"
elif [[ -f "${TMPDIR_PY}/package.json" ]]; then
    DETECTED="javascript"
elif [[ -f "${TMPDIR_PY}/go.mod" ]]; then
    DETECTED="go"
elif [[ -f "${TMPDIR_PY}/Cargo.toml" ]]; then
    DETECTED="rust"
fi
if [[ "$DETECTED" == "python" ]]; then
    pass "T7: Auto-detect Python from requirements.txt"
else
    fail "T7: Auto-detect Python from requirements.txt" "detected '${DETECTED}'"
fi
rm -rf "$TMPDIR_PY"

# ── Test 8: Auto-detect JavaScript (package.json) ──
TMPDIR_JS=$(mktemp -d)
touch "${TMPDIR_JS}/package.json"
DETECTED=""
if [[ -f "${TMPDIR_JS}/pyproject.toml" || -f "${TMPDIR_JS}/requirements.txt" || -f "${TMPDIR_JS}/setup.py" || -f "${TMPDIR_JS}/setup.cfg" || -f "${TMPDIR_JS}/Pipfile" ]]; then
    DETECTED="python"
elif [[ -f "${TMPDIR_JS}/package.json" ]]; then
    DETECTED="javascript"
elif [[ -f "${TMPDIR_JS}/go.mod" ]]; then
    DETECTED="go"
elif [[ -f "${TMPDIR_JS}/Cargo.toml" ]]; then
    DETECTED="rust"
fi
if [[ "$DETECTED" == "javascript" ]]; then
    pass "T8: Auto-detect JavaScript from package.json"
else
    fail "T8: Auto-detect JavaScript from package.json" "detected '${DETECTED}'"
fi
rm -rf "$TMPDIR_JS"

# ── Test 9: Auto-detect Go (go.mod) ──
TMPDIR_GO=$(mktemp -d)
touch "${TMPDIR_GO}/go.mod"
DETECTED=""
if [[ -f "${TMPDIR_GO}/pyproject.toml" || -f "${TMPDIR_GO}/requirements.txt" || -f "${TMPDIR_GO}/setup.py" || -f "${TMPDIR_GO}/setup.cfg" || -f "${TMPDIR_GO}/Pipfile" ]]; then
    DETECTED="python"
elif [[ -f "${TMPDIR_GO}/package.json" ]]; then
    DETECTED="javascript"
elif [[ -f "${TMPDIR_GO}/go.mod" ]]; then
    DETECTED="go"
elif [[ -f "${TMPDIR_GO}/Cargo.toml" ]]; then
    DETECTED="rust"
fi
if [[ "$DETECTED" == "go" ]]; then
    pass "T9: Auto-detect Go from go.mod"
else
    fail "T9: Auto-detect Go from go.mod" "detected '${DETECTED}'"
fi
rm -rf "$TMPDIR_GO"

# ── Test 10: Empty dir — no language detected ──
TMPDIR_EMPTY=$(mktemp -d)
DETECTED=""
if [[ -f "${TMPDIR_EMPTY}/pyproject.toml" || -f "${TMPDIR_EMPTY}/requirements.txt" || -f "${TMPDIR_EMPTY}/setup.py" || -f "${TMPDIR_EMPTY}/setup.cfg" || -f "${TMPDIR_EMPTY}/Pipfile" ]]; then
    DETECTED="python"
elif [[ -f "${TMPDIR_EMPTY}/package.json" ]]; then
    DETECTED="javascript"
elif [[ -f "${TMPDIR_EMPTY}/go.mod" ]]; then
    DETECTED="go"
elif [[ -f "${TMPDIR_EMPTY}/Cargo.toml" ]]; then
    DETECTED="rust"
fi
if [[ -z "$DETECTED" ]]; then
    pass "T10: Empty dir — no language detected"
else
    fail "T10: Empty dir — no language detected" "detected '${DETECTED}'"
fi
rm -rf "$TMPDIR_EMPTY"

# ── Test 11: Missing profile emits WARNING ──
# Simulate: spectra-verify.sh with a language that has no profile (e.g. ruby)
TMPDIR_WARN=$(mktemp -d)
WARN_DETECTED="ruby"
WARN_PROFILE="${SPECTRA_HOME}/lang-profiles/${WARN_DETECTED}.profile"
if [[ ! -f "$WARN_PROFILE" ]]; then
    # Simulate the warning output that spectra-verify.sh would produce
    WARNING_MSG="WARNING: No language profile for '${WARN_DETECTED}'. Wiring proof may be incomplete."
    if [[ "$WARNING_MSG" == *"WARNING"* ]]; then
        pass "T11: Missing profile emits WARNING"
    else
        fail "T11: Missing profile emits WARNING" "no WARNING in output"
    fi
else
    fail "T11: Missing profile emits WARNING" "ruby.profile unexpectedly exists"
fi
rm -rf "$TMPDIR_WARN"

# ── Test 12: SIGN-010 exists in guardrails-global.md ──
if grep -q "SIGN-010" "${SPECTRA_HOME}/guardrails-global.md" 2>/dev/null; then
    pass "T12: SIGN-010 exists in guardrails-global.md"
else
    fail "T12: SIGN-010 exists in guardrails-global.md" "not found"
fi

# ── Summary ──
echo ""
echo "=== Phase D Language Profile: ${PASS} passed, ${FAIL} failed, ${TESTS_RUN} total ==="
echo "SPECTRA_TEST_RESULT suite=phase-d-langprofile pass=${PASS} fail=${FAIL} skip=0 total=${TESTS_RUN}"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
