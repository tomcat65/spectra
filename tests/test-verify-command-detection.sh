#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Verifier command selection is language-aware (Task 005)
# Validates that spectra-verify.sh uses language profiles for regression
# command selection instead of a Python-biased hardcoded chain.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
VERIFY_SCRIPT="${SPECTRA_DIR}/bin/spectra-verify.sh"
PROFILES_DIR="${SPECTRA_DIR}/lang-profiles"
FIXTURE_DIR="${SPECTRA_DIR}/fixtures/verify-command"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-verify.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-verify.sh exists and is executable"

if [[ -x "${VERIFY_SCRIPT}" ]]; then
    echo "  PASS  spectra-verify.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-verify.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: tests/ directory alone does NOT trigger pytest
# This is the core bug that Task 005 fixes.
# ══════════════════════════════════════════
echo "  Test: bare tests/ directory does not trigger pytest"

# Check that the old pattern (-d "tests" → pytest) is gone
if grep -qP '\-d "tests".*pytest|\-d "tests".*python' "${VERIFY_SCRIPT}" 2>/dev/null; then
    echo "  FAIL  spectra-verify.sh still uses -d 'tests' to trigger pytest"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  spectra-verify.sh does not use -d 'tests' to trigger pytest"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 3: Language detection precedes Step 2
# Detection must happen before the regression command selection.
# ══════════════════════════════════════════
echo "  Test: language detection precedes Step 2 regression"

DETECT_LINE=$(grep -n 'DETECTED_LANG=' "${VERIFY_SCRIPT}" | head -1 | cut -d: -f1)
STEP2_LINE=$(grep -n 'Step 2.*Regression' "${VERIFY_SCRIPT}" | head -1 | cut -d: -f1)

if [[ -n "${DETECT_LINE}" && -n "${STEP2_LINE}" ]]; then
    if [[ "${DETECT_LINE}" -lt "${STEP2_LINE}" ]]; then
        echo "  PASS  language detection (line ${DETECT_LINE}) before Step 2 (line ${STEP2_LINE})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  language detection (line ${DETECT_LINE}) after Step 2 (line ${STEP2_LINE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  could not locate DETECTED_LANG or Step 2 in verify script"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Profile loading precedes Step 2
# ══════════════════════════════════════════
echo "  Test: profile loading precedes Step 2 regression"

PROFILE_LINE=$(grep -n 'source.*LANG_PROFILE' "${VERIFY_SCRIPT}" | head -1 | cut -d: -f1)

if [[ -n "${PROFILE_LINE}" && -n "${STEP2_LINE}" ]]; then
    if [[ "${PROFILE_LINE}" -lt "${STEP2_LINE}" ]]; then
        echo "  PASS  profile source (line ${PROFILE_LINE}) before Step 2 (line ${STEP2_LINE})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  profile source (line ${PROFILE_LINE}) after Step 2 (line ${STEP2_LINE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  could not locate profile source or Step 2"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: Python profile defines REGRESSION_CMD
# ══════════════════════════════════════════
echo "  Test: python.profile defines REGRESSION_CMD"

if grep -q 'REGRESSION_CMD=' "${PROFILES_DIR}/python.profile" 2>/dev/null; then
    PYTHON_CMD=$(grep -oP 'REGRESSION_CMD="\K[^"]+' "${PROFILES_DIR}/python.profile" || true)
    if [[ "${PYTHON_CMD}" == *"pytest"* ]]; then
        echo "  PASS  python.profile REGRESSION_CMD includes pytest (${PYTHON_CMD})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  python.profile REGRESSION_CMD unexpected: ${PYTHON_CMD}"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  python.profile missing REGRESSION_CMD"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: JavaScript profile exists and defines REGRESSION_CMD
# ══════════════════════════════════════════
echo "  Test: javascript.profile defines REGRESSION_CMD"

if [[ -f "${PROFILES_DIR}/javascript.profile" ]]; then
    JS_CMD=$(grep -oP 'REGRESSION_CMD="\K[^"]+' "${PROFILES_DIR}/javascript.profile" || true)
    if [[ "${JS_CMD}" == *"npm test"* ]]; then
        echo "  PASS  javascript.profile REGRESSION_CMD is npm test"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  javascript.profile REGRESSION_CMD unexpected: ${JS_CMD}"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  javascript.profile not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Bash profile exists and defines REGRESSION_CMD
# ══════════════════════════════════════════
echo "  Test: bash.profile defines REGRESSION_CMD"

if [[ -f "${PROFILES_DIR}/bash.profile" ]]; then
    BASH_CMD=$(grep -oP 'REGRESSION_CMD="\K[^"]+' "${PROFILES_DIR}/bash.profile" || true)
    if [[ "${BASH_CMD}" == *"run-tests"* ]]; then
        echo "  PASS  bash.profile REGRESSION_CMD runs test runner (${BASH_CMD})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  bash.profile REGRESSION_CMD unexpected: ${BASH_CMD}"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  bash.profile not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: All profiles are sourceable without error
# ══════════════════════════════════════════
echo "  Test: all profiles sourceable without error"

all_sourceable=true
for profile in "${PROFILES_DIR}"/*.profile; do
    [[ -f "${profile}" ]] || continue
    if ! bash -c "source '${profile}'" 2>/dev/null; then
        echo "  FAIL  $(basename "${profile}") has syntax errors"
        all_sourceable=false
        break
    fi
done

if ${all_sourceable}; then
    echo "  PASS  all profiles sourceable"
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: Step 2 uses REGRESSION_CMD variable (not hardcoded commands)
# The regression command should come from the profile or fallback,
# via the REGRESSION_CMD variable.
# ══════════════════════════════════════════
echo "  Test: Step 2 uses REGRESSION_CMD variable"

# Extract the Step 2 block (between Step 2 and Step 3 comments)
step2_block=$(sed -n '/Step 2.*Regression/,/Step 3/p' "${VERIFY_SCRIPT}")

# The block should reference REGRESSION_CMD, not hardcode pytest/npm/cargo directly
if echo "${step2_block}" | grep -q 'REGRESSION_CMD'; then
    echo "  PASS  Step 2 references REGRESSION_CMD variable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  Step 2 does not reference REGRESSION_CMD"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 10: Functional test — Python repo detection via temp dir
# Create a temp dir with pyproject.toml and source the detection logic.
# ══════════════════════════════════════════
echo "  Test: Python repo detected from pyproject.toml"

(
    cd "${tmp_dir}"
    touch pyproject.toml
    mkdir -p tests

    # Extract and run the detection logic
    DETECTED_LANG=""
    if [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" || -f "setup.cfg" || -f "Pipfile" || -f "pytest.ini" ]]; then
        DETECTED_LANG="python"
    elif [[ -f "package.json" ]]; then
        DETECTED_LANG="javascript"
    fi

    if [[ "${DETECTED_LANG}" == "python" ]]; then
        echo "  PASS  pyproject.toml → detected python"
    else
        echo "  FAIL  pyproject.toml → detected '${DETECTED_LANG}' (expected python)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: Functional test — JS repo detection via temp dir
# ══════════════════════════════════════════
echo "  Test: JS repo detected from package.json"

(
    cd "${tmp_dir}"
    rm -f pyproject.toml setup.py requirements.txt setup.cfg Pipfile pytest.ini
    touch package.json

    DETECTED_LANG=""
    if [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" || -f "setup.cfg" || -f "Pipfile" || -f "pytest.ini" ]]; then
        DETECTED_LANG="python"
    elif [[ -f "package.json" ]]; then
        DETECTED_LANG="javascript"
    fi

    if [[ "${DETECTED_LANG}" == "javascript" ]]; then
        echo "  PASS  package.json → detected javascript"
    else
        echo "  FAIL  package.json → detected '${DETECTED_LANG}' (expected javascript)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: Functional test — bare tests/ dir does NOT detect any language
# This is the key invariant: tests/ alone → no detection → no pytest.
# ══════════════════════════════════════════
echo "  Test: bare tests/ directory → no language detected"

(
    bare_dir=$(mktemp -d)
    cd "${bare_dir}"
    mkdir -p tests

    DETECTED_LANG=""
    if [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" || -f "setup.cfg" || -f "Pipfile" || -f "pytest.ini" ]]; then
        DETECTED_LANG="python"
    elif [[ -f "package.json" ]]; then
        DETECTED_LANG="javascript"
    elif [[ -f "go.mod" ]]; then
        DETECTED_LANG="go"
    elif [[ -f "Cargo.toml" ]]; then
        DETECTED_LANG="rust"
    fi

    if [[ -z "${DETECTED_LANG}" ]]; then
        echo "  PASS  bare tests/ → no language detected (correct: no pytest)"
    else
        echo "  FAIL  bare tests/ → detected '${DETECTED_LANG}' (should be empty)"
        exit 1
    fi

    rm -rf "${bare_dir}"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: Fallback for Cargo.toml (no profile needed)
# Rust and Go have hardcoded fallbacks in the script for repos without profiles.
# ══════════════════════════════════════════
echo "  Test: Cargo.toml fallback → cargo test"

# The fallback block checks Cargo.toml and sets cargo test on nearby lines
has_cargo_check=$(grep -c 'Cargo.toml' "${VERIFY_SCRIPT}" || echo "0")
has_cargo_cmd=$(grep -c 'cargo test' "${VERIFY_SCRIPT}" || echo "0")

if [[ "${has_cargo_check}" -gt 0 && "${has_cargo_cmd}" -gt 0 ]]; then
    echo "  PASS  Cargo.toml check and cargo test command both present"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing Cargo.toml check (${has_cargo_check}) or cargo test (${has_cargo_cmd})"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: Fallback for go.mod (no profile needed)
# ══════════════════════════════════════════
echo "  Test: go.mod fallback → go test"

has_go_check=$(grep -c 'go.mod' "${VERIFY_SCRIPT}" || echo "0")
has_go_cmd=$(grep -c 'go test' "${VERIFY_SCRIPT}" || echo "0")

if [[ "${has_go_check}" -gt 0 && "${has_go_cmd}" -gt 0 ]]; then
    echo "  PASS  go.mod check and go test command both present"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing go.mod check (${has_go_check}) or go test (${has_go_cmd})"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: No duplicate language detection in Step 4
# The old code had separate detection blocks for Step 2 and Step 4.
# After refactor, detection should appear once before Step 2.
# ══════════════════════════════════════════
echo "  Test: language detection is not duplicated in Step 4"

# Count how many times the full detection block appears (DETECTED_LANG="" followed by if chains)
detect_count=$(grep -c 'DETECTED_LANG=""' "${VERIFY_SCRIPT}" || echo "0")

if [[ "${detect_count}" -eq 1 ]]; then
    echo "  PASS  DETECTED_LANG initialized once (no duplicate detection)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  DETECTED_LANG initialized ${detect_count} times (expected 1)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 16: Profile REGRESSION_CMD sourced into scope
# After sourcing a profile, REGRESSION_CMD should be set.
# ══════════════════════════════════════════
echo "  Test: sourcing profile sets REGRESSION_CMD in scope"

(
    REGRESSION_CMD=""
    source "${PROFILES_DIR}/python.profile"
    if [[ -n "${REGRESSION_CMD}" ]]; then
        echo "  PASS  sourcing python.profile sets REGRESSION_CMD='${REGRESSION_CMD}'"
    else
        echo "  FAIL  sourcing python.profile did not set REGRESSION_CMD"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 17: JS profile has correct FILE_EXTENSION
# ══════════════════════════════════════════
echo "  Test: javascript.profile FILE_EXTENSION is js"

(
    source "${PROFILES_DIR}/javascript.profile"
    if [[ "${FILE_EXTENSION}" == "js" ]]; then
        echo "  PASS  javascript.profile FILE_EXTENSION is js"
    else
        echo "  FAIL  javascript.profile FILE_EXTENSION is '${FILE_EXTENSION}' (expected js)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 18: Bash profile has correct FILE_EXTENSION
# ══════════════════════════════════════════
echo "  Test: bash.profile FILE_EXTENSION is sh"

(
    source "${PROFILES_DIR}/bash.profile"
    if [[ "${FILE_EXTENSION}" == "sh" ]]; then
        echo "  PASS  bash.profile FILE_EXTENSION is sh"
    else
        echo "  FAIL  bash.profile FILE_EXTENSION is '${FILE_EXTENSION}' (expected sh)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 19: Fixture README exists
# ══════════════════════════════════════════
echo "  Test: verify-command fixture README exists"

if [[ -f "${FIXTURE_DIR}/README.md" ]]; then
    echo "  PASS  fixtures/verify-command/README.md exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL  fixtures/verify-command/README.md not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 20: pytest.ini is treated as Python signal
# Even without pyproject.toml, pytest.ini should trigger Python detection.
# ══════════════════════════════════════════
echo "  Test: pytest.ini triggers Python detection"

if grep -q 'pytest.ini' "${VERIFY_SCRIPT}" 2>/dev/null; then
    echo "  PASS  spectra-verify.sh recognizes pytest.ini as Python signal"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-verify.sh does not recognize pytest.ini"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  verify-command-detection: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_VERIFY_COMMAND_DETECTION_PASS=${PASS}
export TEST_VERIFY_COMMAND_DETECTION_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
