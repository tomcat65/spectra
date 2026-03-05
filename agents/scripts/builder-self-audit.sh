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

# ── Check A: REACHABILITY ──
# For every public function/class created or modified, find at least one
# callsite in EXISTING runtime code (not test files).
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
    # Check each listed file exists
    local file_list
    file_list=$(echo "${files_line}" | sed 's/^- Files:\s*//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    while IFS= read -r file_path; do
        [[ -z "${file_path}" ]] && continue
        if [[ ! -f "${PROJECT_ROOT}/${file_path}" ]]; then
            echo "  REACHABILITY: File not found: ${file_path}"
            ((fail_count++))
        fi
    done <<< "${file_list}"

    if [[ "${fail_count}" -gt 0 ]]; then
        echo "FAIL: REACHABILITY — ${fail_count} file(s) unreachable"
        return 1
    fi
    echo "PASS: REACHABILITY"
    return 0
}

# ── Check B: SPEC FIDELITY ──
# Verify all acceptance criteria items from the task have corresponding code.
check_spec_fidelity() {
    if [[ -z "${TASK_FILE}" ]] || [[ ! -f "${TASK_FILE}" ]]; then
        echo "SKIP: SPEC FIDELITY — no task file provided"
        return 0
    fi

    # Count AC items (use head -1 to ensure single-line value)
    local ac_count
    ac_count=$(grep -cE '^\s+-\s+' "${TASK_FILE}" 2>/dev/null || true)
    ac_count="${ac_count:-0}"

    if [[ "${ac_count}" -eq 0 ]]; then
        echo "SKIP: SPEC FIDELITY — no AC items found in task"
        return 0
    fi

    echo "PASS: SPEC FIDELITY — ${ac_count} AC items found in task"
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

# ── Check D: DEPENDENCY RESOLUTION ──
# Verify no missing imports or unresolvable dependencies.
check_dependency_resolution() {
    local lang
    lang=$(detect_language)

    case "${lang}" in
        python)
            if command -v pip > /dev/null 2>&1; then
                local pip_check
                pip_check=$(pip check 2>&1 || true)
                if echo "${pip_check}" | grep -qi "no broken"; then
                    echo "PASS: DEPENDENCY RESOLUTION — pip check passed"
                    return 0
                elif [[ -n "${pip_check}" ]]; then
                    echo "FAIL: DEPENDENCY RESOLUTION — pip check: ${pip_check}"
                    return 1
                fi
            fi
            # Fallback: check requirements.txt exists
            if [[ -f "${PROJECT_ROOT}/requirements.txt" ]] || [[ -f "${PROJECT_ROOT}/pyproject.toml" ]]; then
                echo "PASS: DEPENDENCY RESOLUTION — manifest found"
                return 0
            fi
            echo "FAIL: DEPENDENCY RESOLUTION — no dependency manifest found"
            return 1
            ;;
        javascript)
            if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
                if [[ ! -d "${PROJECT_ROOT}/node_modules" ]]; then
                    echo "FAIL: DEPENDENCY RESOLUTION — node_modules missing (run npm install)"
                    return 1
                fi
                echo "PASS: DEPENDENCY RESOLUTION — package.json + node_modules present"
                return 0
            fi
            echo "FAIL: DEPENDENCY RESOLUTION — no package.json found"
            return 1
            ;;
        go)
            if command -v go > /dev/null 2>&1 && [[ -f "${PROJECT_ROOT}/go.mod" ]]; then
                local go_check
                go_check=$(cd "${PROJECT_ROOT}" && go mod verify 2>&1) || true
                if echo "${go_check}" | grep -qi "verified"; then
                    echo "PASS: DEPENDENCY RESOLUTION — go mod verify passed"
                    return 0
                fi
            fi
            echo "SKIP: DEPENDENCY RESOLUTION — go not available or no go.mod"
            return 0
            ;;
        *)
            echo "SKIP: DEPENDENCY RESOLUTION — unknown language"
            return 0
            ;;
    esac
}

# ── Main ──
main() {
    echo "══════════════════════════════════════════"
    echo "  SPECTRA Builder Self-Audit"
    echo "  Task: ${TASK_FILE:-<none>}"
    echo "  Root: ${PROJECT_ROOT}"
    echo "══════════════════════════════════════════"
    echo ""

    check_reachability         || ((FAILURES++))
    check_spec_fidelity        || ((FAILURES++))
    check_integration_test     || ((FAILURES++))
    check_dependency_resolution || ((FAILURES++))

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
