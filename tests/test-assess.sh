#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Assessment fixture validation
# Validates assessment fixture YAML files contain required fields and structure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
FIXTURE_DIR="${SPECTRA_DIR}/fixtures/assessment"
MANIFEST="${FIXTURE_DIR}/manifest.json"

PASS=0
FAIL=0

if [[ ! -f "${MANIFEST}" ]]; then
    echo "FAIL: manifest not found: ${MANIFEST}" >&2
    exit 1
fi

# Parse fixture entries from manifest.json
mapfile -t IDS < <(grep '"id"' "${MANIFEST}" | sed 's/.*"id": *"//;s/".*//')
mapfile -t FILES < <(grep '"file"' "${MANIFEST}" | sed 's/.*"file": *"//;s/".*//')
mapfile -t EXPECTED < <(grep '"expected"' "${MANIFEST}" | sed 's/.*"expected": *"//;s/".*//')

# Required top-level fields for a valid assessment.yaml
REQUIRED_FIELDS=("spectra:" "execution_mode:")

for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    file="${FILES[$i]}"
    expected="${EXPECTED[$i]}"
    fixture_path="${FIXTURE_DIR}/${file}"

    if [[ ! -f "${fixture_path}" ]]; then
        echo "  FAIL  ${id}: fixture file not found: ${fixture_path}"
        FAIL=$((FAIL + 1))
        continue
    fi

    if [[ "${expected}" == "pass" ]]; then
        # Verify required fields exist: spectra.level and spectra.execution_mode
        has_level=false
        has_exec_mode=false

        if grep -qE '^\s*level:\s*[0-9]+' "${fixture_path}"; then
            has_level=true
        fi
        if grep -qE '^\s*execution_mode:\s*.+' "${fixture_path}"; then
            has_exec_mode=true
        fi

        if ${has_level} && ${has_exec_mode}; then
            echo "  PASS  ${id} (valid: has level and execution_mode)"
            PASS=$((PASS + 1))
        else
            missing=""
            ${has_level} || missing="${missing} level"
            ${has_exec_mode} || missing="${missing} execution_mode"
            echo "  FAIL  ${id} (expected valid but missing:${missing})"
            FAIL=$((FAIL + 1))
        fi

    elif [[ "${expected}" == "fail" ]]; then
        # For malformed fixtures, verify the specific defect exists
        # The malformed-missing-level fixture should lack spectra.level
        is_malformed=false

        # Check if spectra.level is missing (the known malformed case)
        if ! grep -qE '^\s*level:\s*[0-9]+' "${fixture_path}"; then
            is_malformed=true
        fi

        if ${is_malformed}; then
            echo "  PASS  ${id} (malformed: missing required field as expected)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL  ${id} (expected malformed but all required fields present)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL  ${id}: unknown expected value '${expected}'"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "  assess: ${PASS} passed, ${FAIL} failed"

# Export counts for runner aggregation
export TEST_ASSESS_PASS=${PASS}
export TEST_ASSESS_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
