#!/usr/bin/env bash
# agents/scripts/builder-self-audit.sh
# Builder's 4-step self-audit — executable version
# Called before commit to verify code quality
#
# Usage: builder-self-audit.sh [TASK_FILE] [PROJECT_ROOT]
#   TASK_FILE    — path to the task description (plan.md section or task file)
#   PROJECT_ROOT — project root directory (default: .)
#
# Exits 0 if all 4 checks pass, 1 if any fail.
set -euo pipefail

TASK_FILE="${1:-}"
PROJECT_ROOT="${2:-.}"
FAILURES=0

# Detect project language
detect_language() {
    if [[ -f "${PROJECT_ROOT}/pyproject.toml" ]] || [[ -f "${PROJECT_ROOT}/requirements.txt" ]] || [[ -f "${PROJECT_ROOT}/setup.py" ]]; then
        echo "python"
    elif [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        echo "javascript"
    elif [[ -f "${PROJECT_ROOT}/go.mod" ]]; then
        echo "go"
    elif [[ -f "${PROJECT_ROOT}/Cargo.toml" ]]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

# Map language to file extensions for grep --include
lang_includes() {
    case "$1" in
        python)     echo '--include=*.py' ;;
        javascript) echo '--include=*.js --include=*.ts --include=*.tsx --include=*.jsx' ;;
        go)         echo '--include=*.go' ;;
        rust)       echo '--include=*.rs' ;;
        *)          echo '' ;;
    esac
}

# ── Check A: REACHABILITY ──
# For every public function/class created or modified, find at least one
# callsite in EXISTING runtime code (not test files, not the defining file).
check_reachability() {
    local lang
    lang=$(detect_language)

    if [[ -z "${TASK_FILE}" ]] || [[ ! -f "${TASK_FILE}" ]]; then
        echo "SKIP: REACHABILITY — no task file provided"
        return 0
    fi

    # Extract file paths from task description (Files: field)
    local files_line
    files_line=$(grep -i '^- Files:' "${TASK_FILE}" 2>/dev/null || true)
    if [[ -z "${files_line}" ]]; then
        echo "SKIP: REACHABILITY — no Files field in task"
        return 0
    fi

    local fail_count=0
    local checked=0
    local file_list
    file_list=$(echo "${files_line}" | sed 's/^- Files:\s*//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    local includes
    includes=$(lang_includes "${lang}")

    while IFS= read -r file_path; do
        [[ -z "${file_path}" ]] && continue
        local full_path="${PROJECT_ROOT}/${file_path}"
        if [[ ! -f "${full_path}" ]]; then
            echo "  REACHABILITY: File not found: ${file_path}"
            ((fail_count++))
            continue
        fi

        # Extract public function/class names from this file and check for callsites
        local symbols=""
        case "${lang}" in
            python)
                symbols=$(grep -oP '^(?:def|class)\s+\K[a-zA-Z_][a-zA-Z0-9_]*' "${full_path}" 2>/dev/null | grep -v '^_' || true)
                ;;
            javascript)
                symbols=$(grep -oP '(?:export\s+(?:default\s+)?(?:function|class|const|let|var)\s+)\K[a-zA-Z_][a-zA-Z0-9_]*' "${full_path}" 2>/dev/null || true)
                ;;
            go)
                symbols=$(grep -oP '^func\s+\K[A-Z][a-zA-Z0-9_]*' "${full_path}" 2>/dev/null || true)
                ;;
        esac

        if [[ -z "${symbols}" ]]; then
            continue
        fi

        while IFS= read -r sym; do
            [[ -z "${sym}" ]] && continue
            checked=$((checked + 1))
            # Search for callsite in project, excluding the defining file and test files
            local callsites
            # shellcheck disable=SC2086
            callsites=$(grep -rn "${sym}" "${PROJECT_ROOT}" ${includes} 2>/dev/null \
                | grep -v "test_\|_test\.\|\.test\.\|\.spec\." \
                | grep -v "${file_path}" \
                | grep -vc "^\s*#\|^\s*//\|^\s*/\*\|def ${sym}\|class ${sym}\|func ${sym}\|function ${sym}" || true)
            if [[ "${callsites}" -eq 0 ]]; then
                echo "  REACHABILITY: No external callsite for '${sym}' (defined in ${file_path})"
                ((fail_count++))
            fi
        done <<< "${symbols}"
    done <<< "${file_list}"

    if [[ "${fail_count}" -gt 0 ]]; then
        echo "FAIL: REACHABILITY — ${fail_count} symbol(s) have no external callsite"
        return 1
    fi
    if [[ "${checked}" -eq 0 ]]; then
        echo "SKIP: REACHABILITY — no public symbols found to check"
        return 0
    fi
    echo "PASS: REACHABILITY — ${checked} symbol(s) verified with external callsites"
    return 0
}

# ── Check B: SPEC FIDELITY ──
# Re-read the task spec and verify specific literal values (model names, field
# counts, status codes, collection names, endpoint paths, enum values) appear
# in the codebase. Also run any Assertions block from plan.md.
check_spec_fidelity() {
    if [[ -z "${TASK_FILE}" ]] || [[ ! -f "${TASK_FILE}" ]]; then
        echo "SKIP: SPEC FIDELITY — no task file provided"
        return 0
    fi

    local fail_count=0
    local checked=0

    # Extract quoted literal values from task spec (strings in quotes, backticks)
    local literals
    # shellcheck disable=SC2016
    literals=$(grep -oP '(?<=")[^"]{2,50}(?=")|(?<=`)[^`]{2,50}(?=`)' "${TASK_FILE}" 2>/dev/null || true)

    # Also extract values after colons in AC lines (e.g., "- Status code: 200")
    # Exclude plan.md metadata fields (Files, Verify, Risk, Max-iterations, AC)
    local ac_values
    ac_values=$(grep -vE '^\s*-\s+(Files|Verify|Risk|Max-iterations|AC):' "${TASK_FILE}" 2>/dev/null \
        | grep -oP '^\s*-\s+.*?:\s*\K\S+' || true)

    # Combine and deduplicate
    local all_values
    all_values=$(printf '%s\n%s' "${literals}" "${ac_values}" | sort -u | grep -v '^$' || true)

    if [[ -n "${all_values}" ]]; then
        # Extract file paths from Files: field for targeted search
        local files_line
        files_line=$(grep -i '^- Files:' "${TASK_FILE}" 2>/dev/null || true)
        local search_dir="${PROJECT_ROOT}"

        while IFS= read -r value; do
            [[ -z "${value}" ]] && continue
            # Skip common non-spec words
            [[ "${value}" =~ ^(the|and|or|for|with|from|this|that|should|must|can|will)$ ]] && continue
            checked=$((checked + 1))
            local found
            found=$(grep -r --include="*.py" --include="*.js" --include="*.ts" --include="*.go" --include="*.rs" --include="*.sh" -l "${value}" "${search_dir}" 2>/dev/null | head -1 || true)
            if [[ -z "${found}" ]]; then
                echo "  SPEC FIDELITY: Literal '${value}' from spec not found in codebase"
                ((fail_count++))
            fi
        done <<< "${all_values}"
    fi

    # Run Assertions block if present in plan.md
    local plan_file="${PROJECT_ROOT}/.spectra/plan.md"
    if [[ -f "${plan_file}" ]]; then
        local assertions
        assertions=$(sed -n '/^- Assertions:/,/^- [A-Z]/{ /^- Assertions:/d; /^- [A-Z]/d; p; }' "${plan_file}" 2>/dev/null || true)
        if [[ -n "${assertions}" ]]; then
            while IFS= read -r assertion_cmd; do
                assertion_cmd=$(echo "${assertion_cmd}" | sed 's/^\s*-\s*//' | sed 's/`//g')
                [[ -z "${assertion_cmd}" ]] && continue
                checked=$((checked + 1))
                if ! eval "${assertion_cmd}" > /dev/null 2>&1; then
                    echo "  SPEC FIDELITY: Assertion failed: ${assertion_cmd}"
                    ((fail_count++))
                fi
            done <<< "${assertions}"
        fi
    fi

    if [[ "${fail_count}" -gt 0 ]]; then
        echo "FAIL: SPEC FIDELITY — ${fail_count} spec value(s) not found or assertion(s) failed"
        return 1
    fi
    if [[ "${checked}" -eq 0 ]]; then
        echo "SKIP: SPEC FIDELITY — no literal values or assertions to check"
        return 0
    fi
    echo "PASS: SPEC FIDELITY — ${checked} spec value(s) verified"
    return 0
}

# ── Check C: INTEGRATION TEST ──
# Verify at least one test exercises real wiring (not just unit mocks).
check_integration_test() {
    local lang
    lang=$(detect_language)
    local test_dir="${PROJECT_ROOT}/tests"

    if [[ ! -d "${test_dir}" ]]; then
        test_dir="${PROJECT_ROOT}/test"
    fi

    if [[ ! -d "${test_dir}" ]]; then
        # Check for test files in other common locations
        local test_count
        test_count=$(find "${PROJECT_ROOT}" -name "test_*" -o -name "*_test.*" -o -name "*.test.*" 2>/dev/null | grep -vc node_modules)
        if [[ "${test_count}" -eq 0 ]]; then
            echo "FAIL: INTEGRATION TEST — no test files found"
            return 1
        fi
    fi

    # Check for integration test indicators
    local integration_indicators=0

    case "${lang}" in
        python)
            # Look for subprocess calls or real imports (not mock) in test files
            integration_indicators=$(grep -rl 'subprocess\|integration\|e2e\|end.to.end' "${PROJECT_ROOT}" --include="test_*" --include="*_test.py" 2>/dev/null | grep -vc __pycache__)
            ;;
        javascript)
            integration_indicators=$(grep -rl 'integration\|e2e\|supertest\|end.to.end' "${PROJECT_ROOT}" --include="*.test.*" --include="*.spec.*" 2>/dev/null | grep -vc node_modules)
            ;;
        *)
            # For unknown languages, check for any test files
            integration_indicators=$(find "${PROJECT_ROOT}" -name "*integration*" -o -name "*e2e*" 2>/dev/null | grep -c .)
            ;;
    esac

    if [[ "${integration_indicators}" -eq 0 ]]; then
        echo "WARN: INTEGRATION TEST — no obvious integration test markers found (subprocess, e2e, integration)"
        # Warn but don't fail — not all projects use these markers
        return 0
    fi

    echo "PASS: INTEGRATION TEST — ${integration_indicators} integration test indicator(s) found"
    return 0
}

# ── Check D: SINGLE SOURCE OF TRUTH ──
# If code generates an ID, timestamp, config value, or computed value used in
# multiple places: verify it's generated ONCE and passed through.
# Flags duplicate generation of the same concept in new/modified files.
check_single_source_of_truth() {
    if [[ -z "${TASK_FILE}" ]] || [[ ! -f "${TASK_FILE}" ]]; then
        echo "SKIP: SINGLE SOURCE OF TRUTH — no task file provided"
        return 0
    fi

    # Extract file paths from task description
    local files_line
    files_line=$(grep -i '^- Files:' "${TASK_FILE}" 2>/dev/null || true)
    if [[ -z "${files_line}" ]]; then
        echo "SKIP: SINGLE SOURCE OF TRUTH — no Files field in task"
        return 0
    fi

    local file_list
    file_list=$(echo "${files_line}" | sed 's/^- Files:\s*//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Patterns that indicate value generation (not consumption)
    local generation_patterns='uuid\.\|uuid4\|uuidv4\|generate_id\|nanoid\|datetime\.now\|Date\.now\|time\.Now\|Utc::now\|random\.\|Math\.random\|rand::'
    local fail_count=0
    local checked=0

    # Collect all generation sites across task files
    local -A gen_concepts
    while IFS= read -r file_path; do
        [[ -z "${file_path}" ]] && continue
        local full_path="${PROJECT_ROOT}/${file_path}"
        [[ ! -f "${full_path}" ]] && continue

        local hits
        hits=$(grep -n "${generation_patterns}" "${full_path}" 2>/dev/null || true)
        [[ -z "${hits}" ]] && continue

        while IFS= read -r hit; do
            [[ -z "${hit}" ]] && continue
            checked=$((checked + 1))
            # Extract the generation concept (uuid, datetime, random, etc.)
            local concept
            concept=$(echo "${hit}" | grep -oP 'uuid|generate_id|nanoid|datetime\.now|Date\.now|time\.Now|Utc::now|random|Math\.random|rand' | head -1 || true)
            [[ -z "${concept}" ]] && continue

            local key="${concept}"
            if [[ -n "${gen_concepts[${key}]+x}" ]]; then
                # Same concept generated in multiple files
                echo "  SINGLE SOURCE: '${concept}' generated in multiple files: ${gen_concepts[${key}]} AND ${file_path}"
                ((fail_count++))
            else
                gen_concepts["${key}"]="${file_path}"
            fi
        done <<< "${hits}"
    done <<< "${file_list}"

    if [[ "${fail_count}" -gt 0 ]]; then
        echo "FAIL: SINGLE SOURCE OF TRUTH — ${fail_count} concept(s) generated in multiple files"
        return 1
    fi
    if [[ "${checked}" -eq 0 ]]; then
        echo "SKIP: SINGLE SOURCE OF TRUTH — no generation patterns found"
        return 0
    fi
    echo "PASS: SINGLE SOURCE OF TRUTH — ${checked} generation site(s), no duplicates"
    return 0
}

# ── Quality Gate (pre-audit, language-aware) ──
# Runs cheap lint/format checks before the 4-step audit.
# Quality gate is advisory: failures are reported but don't block the audit.
run_quality_gate() {
    local quality_gate="${SPECTRA_HOME:-${HOME}/.spectra}/scripts/spectra-quality-gate.sh"
    if [[ -x "${quality_gate}" ]]; then
        echo "  [pre] Running quality gate..."
        set +e
        "${quality_gate}" "${PROJECT_ROOT}" 2>&1 | sed 's/^/    /'
        local gate_exit=$?
        set -e
        if [[ ${gate_exit} -eq 0 ]]; then
            echo "  [pre] Quality gate: PASS"
        elif [[ ${gate_exit} -eq 2 ]]; then
            echo "  [pre] Quality gate: SKIP (no tools available)"
        else
            echo "  [pre] Quality gate: ISSUES found (advisory, continuing audit)"
        fi
    fi
}

# ── Main ──
main() {
    echo "══════════════════════════════════════════"
    echo "  SPECTRA Builder Self-Audit"
    echo "  Task: ${TASK_FILE:-<none>}"
    echo "  Root: ${PROJECT_ROOT}"
    echo "══════════════════════════════════════════"
    echo ""

    run_quality_gate

    check_reachability         || ((FAILURES++))
    check_spec_fidelity        || ((FAILURES++))
    check_integration_test     || ((FAILURES++))
    check_single_source_of_truth || ((FAILURES++))

    echo ""
    if [[ "${FAILURES}" -eq 0 ]]; then
        echo "══ PASS: All 4 builder self-audit checks passed ══"
        exit 0
    else
        echo "══ FAIL: ${FAILURES} check(s) failed ══"
        exit 1
    fi
}

main "$@"
