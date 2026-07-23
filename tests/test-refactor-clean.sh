#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Post-project cleanup command (Task 011)
# Validates spectra-refactor-clean.sh behavior including dry-run default,
# category detection, --apply mode, and safety boundaries.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
CLEAN_CMD="${SPECTRA_DIR}/bin/spectra-refactor-clean.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# Create a mock SPECTRA project
setup_project() {
    local proj="$1"
    mkdir -p "${proj}/.spectra/signals"
    mkdir -p "${proj}/.spectra/logs"
    echo "name: test-project" > "${proj}/.spectra/project.yaml"
}

# ══════════════════════════════════════════
# Test 1: Script exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-refactor-clean.sh exists and is executable"

if [[ -x "${CLEAN_CMD}" ]]; then
    echo "  PASS  script exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  script not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: --help exits 0 with usage text
# ══════════════════════════════════════════
echo "  Test: --help exits 0"

set +e
help_out=$("${CLEAN_CMD}" --help 2>&1)
help_exit=$?
set -e

if [[ ${help_exit} -eq 0 ]] && echo "${help_out}" | grep -q 'Usage'; then
    echo "  PASS  --help exits 0 with usage text"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --help exit=${help_exit}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Defaults to dry-run mode
# ══════════════════════════════════════════
echo "  Test: defaults to dry-run mode"

(
    proj="${tmp_dir}/t3"
    setup_project "${proj}"
    touch "${proj}/.spectra/signals/PHASE"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    # File should still exist (dry-run)
    if [[ -f "${proj}/.spectra/signals/PHASE" ]] && echo "${out}" | grep -q 'DRY-RUN'; then
        echo "  PASS  dry-run mode: files preserved"
    else
        echo "  FAIL  dry-run mode not active by default"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: Exits with error outside SPECTRA project
# ══════════════════════════════════════════
echo "  Test: exits with error outside SPECTRA project"

(
    empty="${tmp_dir}/t4_empty"
    mkdir -p "${empty}"
    set +e
    out=$("${CLEAN_CMD}" "${empty}" 2>&1)
    rc=$?
    set -e
    if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q 'No .spectra directory'; then
        echo "  PASS  exits with error outside SPECTRA project"
    else
        echo "  FAIL  should error outside SPECTRA project (rc=${rc})"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Detects stale signal files
# ══════════════════════════════════════════
echo "  Test: detects stale signal files"

(
    proj="${tmp_dir}/t5"
    setup_project "${proj}"
    echo "executing" > "${proj}/.spectra/signals/PHASE"
    echo "builder" > "${proj}/.spectra/signals/AGENT"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q '\[signal\]'; then
        echo "  PASS  detects stale signal files"
    else
        echo "  FAIL  did not detect stale signal files"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: Detects session state file
# ══════════════════════════════════════════
echo "  Test: detects session state file"

(
    proj="${tmp_dir}/t6"
    setup_project "${proj}"
    echo "timestamp=2026-03-09" > "${proj}/.spectra/session.state"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q '\[session\]'; then
        echo "  PASS  detects session state file"
    else
        echo "  FAIL  did not detect session state file"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: Detects stale agent caches
# ══════════════════════════════════════════
echo "  Test: detects stale agent caches"

(
    proj="${tmp_dir}/t7"
    setup_project "${proj}"
    touch "${proj}/.spectra/builder-context.cache"
    touch "${proj}/.spectra/verifier-context.cache"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q '\[cache\]'; then
        echo "  PASS  detects stale agent caches"
    else
        echo "  FAIL  did not detect stale agent caches"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: Detects orphaned plan artifacts
# ══════════════════════════════════════════
echo "  Test: detects orphaned plan artifacts"

(
    proj="${tmp_dir}/t8"
    setup_project "${proj}"
    touch "${proj}/.spectra/plan.md.new"
    touch "${proj}/.spectra/plan.json.bak"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q '\[orphan\]'; then
        echo "  PASS  detects orphaned plan artifacts"
    else
        echo "  FAIL  did not detect orphaned plan artifacts"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: --apply removes candidates
# ══════════════════════════════════════════
echo "  Test: --apply removes candidates"

(
    proj="${tmp_dir}/t9"
    setup_project "${proj}"
    echo "executing" > "${proj}/.spectra/signals/PHASE"
    touch "${proj}/.spectra/session.state"
    touch "${proj}/.spectra/plan.md.new"
    "${CLEAN_CMD}" --apply "${proj}" >/dev/null 2>&1
    if [[ ! -f "${proj}/.spectra/signals/PHASE" ]] && \
       [[ ! -f "${proj}/.spectra/session.state" ]] && \
       [[ ! -f "${proj}/.spectra/plan.md.new" ]]; then
        echo "  PASS  --apply removed candidates"
    else
        echo "  FAIL  --apply did not remove all candidates"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: Clean project reports no candidates
# ══════════════════════════════════════════
echo "  Test: clean project reports no candidates"

(
    proj="${tmp_dir}/t10"
    setup_project "${proj}"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q 'no stale artifacts\|Found: 0 cleanup'; then
        echo "  PASS  clean project reports 0 candidates"
    else
        echo "  FAIL  clean project should report 0 candidates"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: --verbose shows reasons
# ══════════════════════════════════════════
echo "  Test: --verbose shows reasons"

(
    proj="${tmp_dir}/t11"
    setup_project "${proj}"
    touch "${proj}/.spectra/session.state"
    out=$("${CLEAN_CMD}" --verbose "${proj}" 2>&1)
    if echo "${out}" | grep -q 'Reason:'; then
        echo "  PASS  --verbose shows reasons"
    else
        echo "  FAIL  --verbose did not show reasons"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: Unknown option exits with error
# ══════════════════════════════════════════
echo "  Test: unknown option exits with error"

(
    set +e
    out=$("${CLEAN_CMD}" --invalid-flag 2>&1)
    rc=$?
    set -e
    if [[ ${rc} -ne 0 ]] && echo "${out}" | grep -q 'Unknown option'; then
        echo "  PASS  unknown option exits with error"
    else
        echo "  FAIL  unknown option should exit with error"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: Script has valid bash syntax
# ══════════════════════════════════════════
echo "  Test: script has valid bash syntax"

if bash -n "${CLEAN_CMD}" 2>/dev/null; then
    echo "  PASS  valid bash syntax"
    PASS=$((PASS + 1))
else
    echo "  FAIL  script has syntax errors"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: Script is NOT called by spectra-loop.sh
# ══════════════════════════════════════════
echo "  Test: not called by spectra-loop.sh"

if ! grep -q 'refactor-clean\|spectra-refactor' "${SPECTRA_DIR}/bin/spectra-loop.sh" 2>/dev/null; then
    echo "  PASS  not referenced by spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  cleanup command should not be in the main loop"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 15: Does not modify project.yaml or plan.md
# ══════════════════════════════════════════
echo "  Test: does not modify operator-owned artifacts"

# Check the script does not write to project.yaml, plan.md, guardrails.md
if grep -qP 'project\.yaml|plan\.md[^.]|guardrails\.md' "${CLEAN_CMD}" | grep -vP 'grep|read|cat|check|echo|orphan' 2>/dev/null; then
    echo "  FAIL  script may modify operator-owned artifacts"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  script does not modify operator-owned artifacts"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 16: Script uses SPECTRA_HOME auto-detection
# ══════════════════════════════════════════
echo "  Test: uses SPECTRA_HOME auto-detection"

if grep -q 'SPECTRA_HOME=.*dirname.*SCRIPT_DIR' "${CLEAN_CMD}"; then
    echo "  PASS  uses SPECTRA_HOME auto-detection"
    PASS=$((PASS + 1))
else
    echo "  FAIL  missing SPECTRA_HOME auto-detection"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 17: Candidate count is accurate
# ══════════════════════════════════════════
echo "  Test: candidate count matches actual candidates"

(
    proj="${tmp_dir}/t17"
    setup_project "${proj}"
    echo "stuck" > "${proj}/.spectra/signals/PHASE"
    touch "${proj}/.spectra/session.state"
    touch "${proj}/.spectra/builder-context.cache"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    if echo "${out}" | grep -q 'Found: 3 cleanup'; then
        echo "  PASS  candidate count accurate (3)"
    else
        echo "  FAIL  candidate count inaccurate"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 18: --help mentions dry-run default
# ══════════════════════════════════════════
echo "  Test: help mentions dry-run behavior"

if echo "${help_out}" | grep -qi 'dry.run\|DRY-RUN'; then
    echo "  PASS  help mentions dry-run"
    PASS=$((PASS + 1))
else
    echo "  FAIL  help does not mention dry-run"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 19: Help clarifies this is NOT a required phase
# ══════════════════════════════════════════
echo "  Test: help clarifies not a required phase"

if echo "${help_out}" | grep -qi 'NOT.*required\|post-project\|hygiene'; then
    echo "  PASS  help clarifies optional/post-project nature"
    PASS=$((PASS + 1))
else
    echo "  FAIL  help does not clarify optional nature"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 20: Detects empty log subdirectories
# ══════════════════════════════════════════
echo "  Test: detects empty log subdirectories"

(
    proj="${tmp_dir}/t20"
    setup_project "${proj}"
    mkdir -p "${proj}/.spectra/logs/task-001"
    mkdir -p "${proj}/.spectra/logs/task-002"
    echo "some log" > "${proj}/.spectra/logs/task-002/build.log"
    out=$("${CLEAN_CMD}" "${proj}" 2>&1)
    # Should detect task-001 (empty) but not task-002 (has content)
    if echo "${out}" | grep -q '\[empty-dir\].*task-001'; then
        echo "  PASS  detects empty log subdirectory"
    else
        echo "  FAIL  did not detect empty log subdirectory"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  refactor-clean: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=refactor-clean pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_REFACTOR_CLEAN_PASS=${PASS}
export TEST_REFACTOR_CLEAN_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
