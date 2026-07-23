#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Plan Validation against fixtures
# Runs spectra-plan-validate.sh against each fixture defined in the plan-bridge manifest.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
FIXTURE_DIR="${SPECTRA_DIR}/fixtures/plan-bridge"
VALIDATOR="${SPECTRA_DIR}/bin/spectra-plan-validate.sh"
MANIFEST="${FIXTURE_DIR}/manifest.json"

PASS=0
FAIL=0

if [[ ! -f "${MANIFEST}" ]]; then
    echo "FAIL: manifest not found: ${MANIFEST}" >&2
    exit 1
fi

if [[ ! -f "${VALIDATOR}" ]]; then
    echo "FAIL: validator not found: ${VALIDATOR}" >&2
    exit 1
fi

# Parse fixture entries from manifest.json using grep/sed (no jq dependency)
# Extract each fixture block: id, file, projectLevel, expected
mapfile -t IDS < <(grep '"id"' "${MANIFEST}" | sed 's/.*"id": *"//;s/".*//')
mapfile -t FILES < <(grep '"file"' "${MANIFEST}" | sed 's/.*"file": *"//;s/".*//')
mapfile -t LEVELS < <(grep '"projectLevel"' "${MANIFEST}" | sed 's/.*"projectLevel": *//;s/[, ].*//')
mapfile -t EXPECTED < <(grep '"expected"' "${MANIFEST}" | sed 's/.*"expected": *"//;s/".*//')

for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    file="${FILES[$i]}"
    level="${LEVELS[$i]}"
    expected="${EXPECTED[$i]}"
    fixture_path="${FIXTURE_DIR}/${file}"

    if [[ ! -f "${fixture_path}" ]]; then
        echo "  FAIL  ${id}: fixture file not found: ${fixture_path}"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Run validator with --file and --level flags, capture exit code
    set +e
    output=$("${VALIDATOR}" --file "${fixture_path}" --level "${level}" --quiet 2>&1)
    exit_code=$?
    set -e

    if [[ "${expected}" == "pass" ]]; then
        if [[ ${exit_code} -eq 0 ]]; then
            echo "  PASS  ${id} (expected pass, got exit 0)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL  ${id} (expected pass, got exit ${exit_code})"
            echo "        output: ${output}"
            FAIL=$((FAIL + 1))
        fi
    elif [[ "${expected}" == "fail" ]]; then
        if [[ ${exit_code} -ne 0 ]]; then
            echo "  PASS  ${id} (expected fail, got exit ${exit_code})"
            PASS=$((PASS + 1))
        else
            echo "  FAIL  ${id} (expected fail, got exit 0)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL  ${id}: unknown expected value '${expected}'"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "  plan-validate: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=plan-validate pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

# Export counts for runner aggregation
export TEST_PLAN_PASS=${PASS}
export TEST_PLAN_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
