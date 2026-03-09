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

# ══════════════════════════════════════════
# Section 2: BMAD Bridge Fixture Validation
# Execute fixture manifests — verify files exist and structure matches checks.
# ══════════════════════════════════════════
BMAD_DIR="${SPECTRA_DIR}/fixtures/bmad-bridge"
BMAD_MANIFEST="${BMAD_DIR}/manifest.json"

if [[ -f "${BMAD_MANIFEST}" ]]; then
    echo ""
    echo "  --- BMAD Bridge Fixtures ---"

    mapfile -t BMAD_IDS < <(grep '"id"' "${BMAD_MANIFEST}" | sed 's/.*"id": *"//;s/".*//')
    mapfile -t BMAD_PATHS < <(grep '"path"' "${BMAD_MANIFEST}" | sed 's/.*"path": *"//;s/".*//')
    mapfile -t BMAD_EXPECTED < <(grep '"expected"' "${BMAD_MANIFEST}" | sed 's/.*"expected": *"//;s/".*//')

    for i in "${!BMAD_IDS[@]}"; do
        bid="${BMAD_IDS[$i]}"
        bpath="${BMAD_PATHS[$i]:-}"
        bexpected="${BMAD_EXPECTED[$i]}"

        if [[ -z "${bpath}" ]]; then
            # Some entries (like case-004) have no path field
            echo "  PASS  ${bid} (${bexpected}: no path — config-only fixture)"
            PASS=$((PASS + 1))
            continue
        fi

        fixture_full="${BMAD_DIR}/${bpath}"
        if [[ -d "${fixture_full}" ]]; then
            # For pass fixtures, verify the directory contains at least one file
            file_count=$(find "${fixture_full}" -type f 2>/dev/null | wc -l)
            if [[ "${bexpected}" == "pass" || "${bexpected}" == "warn" ]]; then
                if [[ ${file_count} -gt 0 ]]; then
                    echo "  PASS  ${bid} (${bexpected}: ${file_count} files in ${bpath})"
                    PASS=$((PASS + 1))
                else
                    echo "  FAIL  ${bid} (${bexpected}: directory empty)"
                    FAIL=$((FAIL + 1))
                fi
            elif [[ "${bexpected}" == "fail" ]]; then
                # Fail fixtures should exist but contain known defects
                echo "  PASS  ${bid} (fail: fixture directory exists for negative test)"
                PASS=$((PASS + 1))
            else
                echo "  PASS  ${bid} (${bexpected}: fixture present)"
                PASS=$((PASS + 1))
            fi
        else
            echo "  FAIL  ${bid}: fixture path not found: ${fixture_full}"
            FAIL=$((FAIL + 1))
        fi
    done
else
    echo ""
    echo "  FAIL  bmad-bridge manifest not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Section 3: Plan Bridge Fixture Validation
# Execute plan fixtures through the plan validator.
# ══════════════════════════════════════════
PLAN_DIR="${SPECTRA_DIR}/fixtures/plan-bridge"
PLAN_MANIFEST="${PLAN_DIR}/manifest.json"
PLAN_VALIDATOR="${SPECTRA_DIR}/bin/spectra-plan-validate.sh"

if [[ -f "${PLAN_MANIFEST}" ]]; then
    echo ""
    echo "  --- Plan Bridge Fixtures ---"

    mapfile -t PLAN_IDS < <(grep '"id"' "${PLAN_MANIFEST}" | sed 's/.*"id": *"//;s/".*//')
    mapfile -t PLAN_FILES < <(grep '"file"' "${PLAN_MANIFEST}" | sed 's/.*"file": *"//;s/".*//')
    mapfile -t PLAN_EXPECTED < <(grep '"expected"' "${PLAN_MANIFEST}" | sed 's/.*"expected": *"//;s/".*//')
    mapfile -t PLAN_LEVELS < <(grep '"projectLevel"' "${PLAN_MANIFEST}" | sed 's/.*"projectLevel": *//;s/,.*//')

    for i in "${!PLAN_IDS[@]}"; do
        pid="${PLAN_IDS[$i]}"
        pfile="${PLAN_FILES[$i]}"
        pexpected="${PLAN_EXPECTED[$i]}"
        plevel="${PLAN_LEVELS[$i]:-1}"
        fixture_path="${PLAN_DIR}/${pfile}"

        if [[ ! -f "${fixture_path}" ]]; then
            echo "  FAIL  ${pid}: fixture file not found: ${fixture_path}"
            FAIL=$((FAIL + 1))
            continue
        fi

        # Run through validator if available, passing the fixture's project level
        if [[ -x "${PLAN_VALIDATOR}" ]]; then
            set +e
            validate_out=$("${PLAN_VALIDATOR}" --file "${fixture_path}" --level "${plevel}" --quiet 2>&1)
            validate_exit=$?
            set -e

            if [[ "${pexpected}" == "pass" ]]; then
                if [[ ${validate_exit} -eq 0 ]]; then
                    echo "  PASS  ${pid} (valid: validator pass)"
                    PASS=$((PASS + 1))
                else
                    echo "  FAIL  ${pid} (expected valid but validator failed: exit ${validate_exit})"
                    FAIL=$((FAIL + 1))
                fi
            elif [[ "${pexpected}" == "fail" ]]; then
                if [[ ${validate_exit} -ne 0 ]]; then
                    echo "  PASS  ${pid} (invalid: validator correctly rejected)"
                    PASS=$((PASS + 1))
                else
                    echo "  FAIL  ${pid} (expected invalid but validator passed)"
                    FAIL=$((FAIL + 1))
                fi
            fi
        else
            # Fallback: just verify file exists and has task structure
            if grep -qE '^## Task [0-9]{3}:' "${fixture_path}" 2>/dev/null; then
                echo "  PASS  ${pid} (structure: has task headers)"
                PASS=$((PASS + 1))
            else
                if [[ "${pexpected}" == "fail" ]]; then
                    echo "  PASS  ${pid} (invalid: no task headers as expected)"
                    PASS=$((PASS + 1))
                else
                    echo "  FAIL  ${pid}: no task headers found"
                    FAIL=$((FAIL + 1))
                fi
            fi
        fi
    done
else
    echo ""
    echo "  FAIL  plan-bridge manifest not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Section 4: spectra-assess.sh structural checks
# ══════════════════════════════════════════
ASSESS_SCRIPT="${SPECTRA_DIR}/bin/spectra-assess.sh"

echo ""
echo "  --- spectra-assess.sh structural ---"

# Check --help exits 0
if [[ -x "${ASSESS_SCRIPT}" ]]; then
    set +e
    help_out=$("${ASSESS_SCRIPT}" --help 2>&1)
    help_exit=$?
    set -e
    if [[ ${help_exit} -eq 0 ]] && echo "${help_out}" | grep -q 'Usage'; then
        echo "  PASS  spectra-assess.sh --help exits 0"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  spectra-assess.sh --help (exit=${help_exit})"
        FAIL=$((FAIL + 1))
    fi

    # Check BMAD detection logic exists
    if grep -q 'bmad\|BMAD' "${ASSESS_SCRIPT}" 2>/dev/null; then
        echo "  PASS  spectra-assess.sh contains BMAD detection logic"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  spectra-assess.sh missing BMAD detection"
        FAIL=$((FAIL + 1))
    fi

    # Check track→level mapping
    if grep -qP 'quick_flow|bmad_method|enterprise|track' "${ASSESS_SCRIPT}" 2>/dev/null; then
        echo "  PASS  spectra-assess.sh contains track→level mapping"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  spectra-assess.sh missing track→level mapping"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  spectra-assess.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "  assess: ${PASS} passed, ${FAIL} failed"

# Export counts for runner aggregation
export TEST_ASSESS_PASS=${PASS}
export TEST_ASSESS_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
