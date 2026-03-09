#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Progressive context loading (Task 007)
# Validates centralized context loading via lib/loop-context.sh.
# Builder and verifier should use shared context functions instead of
# duplicating file references.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
CONTEXT_LIB="${SPECTRA_DIR}/lib/loop-context.sh"
BUILD_LIB="${SPECTRA_DIR}/lib/loop-build.sh"
VERIFY_LIB="${SPECTRA_DIR}/lib/loop-verify.sh"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: loop-context.sh exists
# ══════════════════════════════════════════
echo "  Test: loop-context.sh exists"

if [[ -f "${CONTEXT_LIB}" ]]; then
    echo "  PASS  loop-context.sh exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-context.sh not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: loop-context.sh is sourceable
# ══════════════════════════════════════════
echo "  Test: loop-context.sh is sourceable"

if bash -n "${CONTEXT_LIB}" 2>/dev/null; then
    echo "  PASS  loop-context.sh has valid syntax"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-context.sh has syntax errors"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: context_files_for_build function exists after sourcing
# ══════════════════════════════════════════
echo "  Test: context_files_for_build function exported"

(
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    if declare -f context_files_for_build >/dev/null 2>&1; then
        echo "  PASS  context_files_for_build function available"
    else
        echo "  FAIL  context_files_for_build not defined"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: context_files_for_verify function exists after sourcing
# ══════════════════════════════════════════
echo "  Test: context_files_for_verify function exported"

(
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    if declare -f context_files_for_verify >/dev/null 2>&1; then
        echo "  PASS  context_files_for_verify function available"
    else
        echo "  FAIL  context_files_for_verify not defined"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Build context includes CLAUDE.md reference
# ══════════════════════════════════════════
echo "  Test: build context includes CLAUDE.md"

(
    cd "${tmp_dir}"
    mkdir -p .spectra/logs
    touch .spectra/guardrails.md
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "1" "")
    if echo "${ctx}" | grep -q 'CLAUDE.md'; then
        echo "  PASS  build context references CLAUDE.md"
    else
        echo "  FAIL  build context missing CLAUDE.md reference"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: Build context includes plan.md task section
# ══════════════════════════════════════════
echo "  Test: build context includes plan.md task section"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "042" "1" "")
    if echo "${ctx}" | grep -q 'Task 042'; then
        echo "  PASS  build context includes task-specific plan.md section"
    else
        echo "  FAIL  build context missing task-specific plan.md reference"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: Build context includes guardrails reference
# ══════════════════════════════════════════
echo "  Test: build context includes guardrails"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "1" "")
    if echo "${ctx}" | grep -q 'guardrails'; then
        echo "  PASS  build context references guardrails"
    else
        echo "  FAIL  build context missing guardrails reference"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: Build context retry includes verify log reference
# ══════════════════════════════════════════
echo "  Test: build context retry includes verify log"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "3" "")
    if echo "${ctx}" | grep -q 'retry 3' && echo "${ctx}" | grep -q 'verify.md'; then
        echo "  PASS  retry context includes iteration number and verify log"
    else
        echo "  FAIL  retry context incomplete"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: Verify context includes failure-types reference
# ══════════════════════════════════════════
echo "  Test: verify context includes failure-types reference"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    # Create the reference file so it's found
    mkdir -p "${SPECTRA_DIR}/agents/references"
    touch "${SPECTRA_DIR}/agents/references/failure-types.md"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_verify "001" "full")
    if echo "${ctx}" | grep -q 'failure-types'; then
        echo "  PASS  verify context references failure-types.md"
    else
        echo "  FAIL  verify context missing failure-types reference"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: Verify context includes depth parameter
# ══════════════════════════════════════════
echo "  Test: verify context includes depth"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_verify "001" "graduated")
    if echo "${ctx}" | grep -q 'graduated'; then
        echo "  PASS  verify context includes depth: graduated"
    else
        echo "  FAIL  verify context missing depth parameter"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: Lessons context included when lessons-active.md exists
# ══════════════════════════════════════════
echo "  Test: lessons context included when file exists"

(
    cd "${tmp_dir}"
    touch .spectra/lessons-active.md
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "1" "")
    if echo "${ctx}" | grep -q 'lessons-active'; then
        echo "  PASS  lessons context included when file exists"
    else
        echo "  FAIL  lessons context not included despite file existing"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: Lessons context excluded when file missing
# ══════════════════════════════════════════
echo "  Test: lessons context excluded when file missing"

(
    cd "${tmp_dir}"
    rm -f .spectra/lessons-active.md
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "1" "")
    if echo "${ctx}" | grep -q 'lessons-active'; then
        echo "  FAIL  lessons context included despite file missing"
        exit 1
    else
        echo "  PASS  lessons context correctly excluded when file missing"
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: loop-build.sh calls context_files_for_build
# ══════════════════════════════════════════
echo "  Test: loop-build.sh uses centralized context"

if grep -q 'context_files_for_build' "${BUILD_LIB}"; then
    echo "  PASS  loop-build.sh references context_files_for_build"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-build.sh does not use centralized context"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: loop-verify.sh calls context_files_for_verify
# ══════════════════════════════════════════
echo "  Test: loop-verify.sh uses centralized context"

if grep -q 'context_files_for_verify' "${VERIFY_LIB}"; then
    echo "  PASS  loop-verify.sh references context_files_for_verify"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-verify.sh does not use centralized context"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: spectra-loop.sh sources loop-context.sh
# ══════════════════════════════════════════
echo "  Test: spectra-loop.sh sources loop-context.sh"

if grep -q 'loop-context.sh' "${LOOP_SCRIPT}"; then
    echo "  PASS  spectra-loop.sh sources loop-context.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-loop.sh does not source loop-context.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 16: loop-context.sh sourced before loop-build.sh
# ══════════════════════════════════════════
echo "  Test: loop-context.sh sourced before loop-build.sh"

CTX_LINE=$(grep -n 'loop-context.sh' "${LOOP_SCRIPT}" | head -1 | cut -d: -f1)
BUILD_LINE=$(grep -n 'loop-build.sh' "${LOOP_SCRIPT}" | head -1 | cut -d: -f1)

if [[ -n "${CTX_LINE}" && -n "${BUILD_LINE}" ]]; then
    if [[ "${CTX_LINE}" -lt "${BUILD_LINE}" ]]; then
        echo "  PASS  loop-context.sh (line ${CTX_LINE}) sourced before loop-build.sh (line ${BUILD_LINE})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  loop-context.sh (line ${CTX_LINE}) after loop-build.sh (line ${BUILD_LINE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL  could not find source lines"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 17: Fallback exists if loop-context.sh not sourced
# Both build and verify should still work without context lib.
# ══════════════════════════════════════════
echo "  Test: build_prompt has fallback if context not sourced"

if grep -q 'Fallback.*inline context' "${BUILD_LIB}" 2>/dev/null || \
   grep -q 'declare -f context_files_for_build' "${BUILD_LIB}" 2>/dev/null; then
    echo "  PASS  loop-build.sh has fallback for missing context lib"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-build.sh has no fallback"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 18: Verify prompt has fallback if context not sourced
# ══════════════════════════════════════════
echo "  Test: verify_prompt has fallback if context not sourced"

if grep -q 'Fallback.*inline context' "${VERIFY_LIB}" 2>/dev/null || \
   grep -q 'declare -f context_files_for_verify' "${VERIFY_LIB}" 2>/dev/null; then
    echo "  PASS  loop-verify.sh has fallback for missing context lib"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-verify.sh has no fallback"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 19: Build prompt still enforces <500 byte budget
# ══════════════════════════════════════════
echo "  Test: build prompt enforces budget"

if grep -q '480' "${BUILD_LIB}" 2>/dev/null; then
    echo "  PASS  loop-build.sh enforces 480-byte prompt budget"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-build.sh missing prompt budget enforcement"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 20: Preflight advisory flows through context
# ══════════════════════════════════════════
echo "  Test: preflight advisory flows through context"

(
    cd "${tmp_dir}"
    SPECTRA_HOME="${SPECTRA_DIR}"
    SPECTRA_DIR=".spectra"
    LOGS_DIR=".spectra/logs"
    source "${CONTEXT_LIB}"
    ctx=$(context_files_for_build "001" "1" "SIGN-005 collision risk on config.ts")
    if echo "${ctx}" | grep -q 'SIGN-005'; then
        echo "  PASS  preflight advisory passed through context"
    else
        echo "  FAIL  preflight advisory lost in context"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  phase11-context-loading: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_PHASE11_CONTEXT_LOADING_PASS=${PASS}
export TEST_PHASE11_CONTEXT_LOADING_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
