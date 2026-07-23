#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: spectra-status.sh operational coverage (Task 006)
# Validates the status dashboard reads signals correctly and produces
# expected output in both text and JSON modes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
STATUS_SCRIPT="${SPECTRA_DIR}/bin/spectra-status.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-status.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-status.sh exists and is executable"

if [[ -x "${STATUS_SCRIPT}" ]]; then
    echo "  PASS  spectra-status.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-status.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: --help exits 0 and shows usage
# ══════════════════════════════════════════
echo "  Test: --help exits 0"

set +e
help_out=$("${STATUS_SCRIPT}" --help 2>&1)
help_exit=$?
set -e

if [[ ${help_exit} -eq 0 ]] && echo "${help_out}" | grep -q 'Usage'; then
    echo "  PASS  --help exits 0 with usage text"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --help exit=${help_exit} or missing Usage text"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Exits with error when no .spectra/ directory
# ══════════════════════════════════════════
echo "  Test: exits with error outside SPECTRA project"

(
    cd "${tmp_dir}"
    set +e
    out=$("${STATUS_SCRIPT}" 2>&1)
    exit_code=$?
    set -e
    if [[ ${exit_code} -ne 0 ]] && echo "${out}" | grep -qi 'error.*not a spectra'; then
        echo "  PASS  exits with error when no .spectra/ directory"
    else
        echo "  FAIL  should error without .spectra/ (exit=${exit_code})"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: Reads PHASE signal file
# ══════════════════════════════════════════
echo "  Test: reads PHASE signal file"

(
    cd "${tmp_dir}"
    mkdir -p .spectra/signals
    echo "executing" > .spectra/signals/PHASE
    # Need git for branch detection — init a temp repo
    git init -q .
    out=$("${STATUS_SCRIPT}" 2>&1)
    if echo "${out}" | grep -q 'executing'; then
        echo "  PASS  status output includes PHASE value 'executing'"
    else
        echo "  FAIL  status output missing PHASE value"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Reads project.yaml for project name
# ══════════════════════════════════════════
echo "  Test: reads project.yaml for project name"

(
    cd "${tmp_dir}"
    cat > .spectra/project.yaml <<EOF
name: test-project
level: 2
EOF
    out=$("${STATUS_SCRIPT}" 2>&1)
    if echo "${out}" | grep -q 'test-project'; then
        echo "  PASS  status output includes project name"
    else
        echo "  FAIL  status output missing project name"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: --json produces valid JSON structure
# ══════════════════════════════════════════
echo "  Test: --json produces JSON with expected keys"

(
    cd "${tmp_dir}"
    out=$("${STATUS_SCRIPT}" --json 2>&1)
    # Check for JSON keys
    has_project=$(echo "${out}" | grep -c '"project"' || echo "0")
    has_tasks=$(echo "${out}" | grep -c '"tasks"' || echo "0")
    has_phase=$(echo "${out}" | grep -c '"phase"' || echo "0")
    if [[ ${has_project} -gt 0 && ${has_tasks} -gt 0 && ${has_phase} -gt 0 ]]; then
        echo "  PASS  --json output has project, tasks, phase keys"
    else
        echo "  FAIL  --json output missing expected keys"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: Counts tasks from plan.md
# ══════════════════════════════════════════
echo "  Test: counts tasks from plan.md"

(
    cd "${tmp_dir}"
    cat > .spectra/plan.md <<'EOF'
# Plan
- [x] 001: Done task
- [ ] 002: Open task
- [!] 003: Stuck task
EOF
    out=$("${STATUS_SCRIPT}" --json 2>&1)
    # total should be 3, done 1, stuck 1, remaining 1
    if echo "${out}" | grep -q '"total": 3'; then
        echo "  PASS  task count parsed correctly from plan.md"
    else
        echo "  FAIL  task count incorrect"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: STUCK signal shown in output
# ══════════════════════════════════════════
echo "  Test: STUCK signal shown in output"

(
    cd "${tmp_dir}"
    echo "Reason: test failure in module X" > .spectra/signals/STUCK
    out=$("${STATUS_SCRIPT}" 2>&1)
    if echo "${out}" | grep -q 'STUCK'; then
        echo "  PASS  STUCK signal visible in status output"
    else
        echo "  FAIL  STUCK signal not shown"
        exit 1
    fi
    rm -f .spectra/signals/STUCK
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: COMPLETE signal shown in output
# ══════════════════════════════════════════
echo "  Test: COMPLETE signal shown in output"

(
    cd "${tmp_dir}"
    echo "Elapsed: 45m" > .spectra/signals/COMPLETE
    out=$("${STATUS_SCRIPT}" 2>&1)
    if echo "${out}" | grep -q 'COMPLETE'; then
        echo "  PASS  COMPLETE signal visible in status output"
    else
        echo "  FAIL  COMPLETE signal not shown"
        exit 1
    fi
    rm -f .spectra/signals/COMPLETE
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: Unknown option exits with error
# ══════════════════════════════════════════
echo "  Test: unknown option exits with error"

(
    cd "${tmp_dir}"
    set +e
    out=$("${STATUS_SCRIPT}" --bogus 2>&1)
    exit_code=$?
    set -e
    if [[ ${exit_code} -ne 0 ]]; then
        echo "  PASS  unknown option exits non-zero"
    else
        echo "  FAIL  unknown option should exit non-zero"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  status: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=status pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_STATUS_PASS=${PASS}
export TEST_STATUS_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
