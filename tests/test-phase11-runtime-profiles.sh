#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Runtime profiles and session persistence (Task 010)
# Validates load_runtime_profile(), session state persistence,
# and fresh-context guard behavior.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
SESSION_LIB="${SPECTRA_DIR}/lib/loop-session.sh"
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
# Test 1: loop-session.sh exists and has valid syntax
# ══════════════════════════════════════════
echo "  Test: loop-session.sh exists and has valid syntax"

if [[ -f "${SESSION_LIB}" ]] && bash -n "${SESSION_LIB}" 2>/dev/null; then
    echo "  PASS  loop-session.sh exists and has valid syntax"
    PASS=$((PASS + 1))
else
    echo "  FAIL  loop-session.sh missing or has syntax errors"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Exports load_runtime_profile function
# ══════════════════════════════════════════
echo "  Test: exports load_runtime_profile"

if grep -q '^load_runtime_profile()' "${SESSION_LIB}"; then
    echo "  PASS  load_runtime_profile() defined"
    PASS=$((PASS + 1))
else
    echo "  FAIL  load_runtime_profile() not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Exports save_session_state function
# ══════════════════════════════════════════
echo "  Test: exports save_session_state"

if grep -q '^save_session_state()' "${SESSION_LIB}"; then
    echo "  PASS  save_session_state() defined"
    PASS=$((PASS + 1))
else
    echo "  FAIL  save_session_state() not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Exports load_session_state function
# ══════════════════════════════════════════
echo "  Test: exports load_session_state"

if grep -q '^load_session_state()' "${SESSION_LIB}"; then
    echo "  PASS  load_session_state() defined"
    PASS=$((PASS + 1))
else
    echo "  FAIL  load_session_state() not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: Exports clear_session_state function
# ══════════════════════════════════════════
echo "  Test: exports clear_session_state"

if grep -q '^clear_session_state()' "${SESSION_LIB}"; then
    echo "  PASS  clear_session_state() defined"
    PASS=$((PASS + 1))
else
    echo "  FAIL  clear_session_state() not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: Exports session_guard_fresh function
# ══════════════════════════════════════════
echo "  Test: exports session_guard_fresh"

if grep -q '^session_guard_fresh()' "${SESSION_LIB}"; then
    echo "  PASS  session_guard_fresh() defined"
    PASS=$((PASS + 1))
else
    echo "  FAIL  session_guard_fresh() not found"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Default profile is "standard"
# ══════════════════════════════════════════
echo "  Test: default profile is standard"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    unset SPECTRA_PROFILE
    source "${SESSION_LIB}"
    out=$(load_runtime_profile 2>&1)
    if [[ "${PROFILE_NAME}" == "standard" ]]; then
        echo "  PASS  default profile is standard"
    else
        echo "  FAIL  default profile is '${PROFILE_NAME}', expected 'standard'"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: SPECTRA_PROFILE=quick sets quick profile
# ══════════════════════════════════════════
echo "  Test: SPECTRA_PROFILE=quick selects quick profile"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="quick"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "quick" ]] && [[ "${PROFILE_MAX_RETRIES}" -eq 1 ]]; then
        echo "  PASS  quick profile: retries=1"
    else
        echo "  FAIL  quick profile not applied correctly (name=${PROFILE_NAME}, retries=${PROFILE_MAX_RETRIES})"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: SPECTRA_PROFILE=thorough sets thorough profile
# ══════════════════════════════════════════
echo "  Test: SPECTRA_PROFILE=thorough selects thorough profile"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="thorough"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "thorough" ]] && [[ "${PROFILE_MAX_RETRIES}" -eq 5 ]]; then
        echo "  PASS  thorough profile: retries=5"
    else
        echo "  FAIL  thorough profile not applied correctly (name=${PROFILE_NAME}, retries=${PROFILE_MAX_RETRIES})"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: Unknown profile falls back to standard with warning
# ══════════════════════════════════════════
echo "  Test: unknown profile falls back to standard"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="nonexistent"
    source "${SESSION_LIB}"
    warn_out=$(load_runtime_profile 2>&1)
    if [[ "${PROFILE_NAME}" == "standard" ]] && echo "${warn_out}" | grep -q 'WARNING'; then
        echo "  PASS  unknown profile falls back to standard with warning"
    else
        echo "  FAIL  unknown profile did not fallback correctly"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: project.yaml profile field is read
# ══════════════════════════════════════════
echo "  Test: project.yaml profile field is read"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    unset SPECTRA_PROFILE
    echo "profile: thorough" > "${tmp_dir}/project.yaml"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "thorough" ]]; then
        echo "  PASS  project.yaml profile: thorough read correctly"
    else
        echo "  FAIL  project.yaml profile not read (got ${PROFILE_NAME})"
        exit 1
    fi
    rm -f "${tmp_dir}/project.yaml"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: SPECTRA_PROFILE env overrides project.yaml
# ══════════════════════════════════════════
echo "  Test: env var overrides project.yaml"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="quick"
    echo "profile: thorough" > "${tmp_dir}/project.yaml"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "quick" ]]; then
        echo "  PASS  env var overrides project.yaml"
    else
        echo "  FAIL  env var did not override project.yaml (got ${PROFILE_NAME})"
        exit 1
    fi
    rm -f "${tmp_dir}/project.yaml"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: save_session_state creates session.state file
# ══════════════════════════════════════════
echo "  Test: save_session_state creates session.state"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    save_session_state "task-001,task-002" 1 "0,0"
    if [[ -f "${tmp_dir}/session.state" ]]; then
        echo "  PASS  session.state created"
    else
        echo "  FAIL  session.state not created"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 14: load_session_state restores saved values
# ══════════════════════════════════════════
echo "  Test: load_session_state restores values"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    PROFILE_NAME="thorough"
    save_session_state "task-001,task-002" 1 "0,0"
    # Reset to verify restore
    PROFILE_NAME="standard"
    load_session_state >/dev/null 2>&1
    if [[ "${SESSION_BATCH}" == "task-001,task-002" ]] && [[ "${SESSION_TASK_IDX}" == "1" ]]; then
        echo "  PASS  session state restored correctly"
    else
        echo "  FAIL  session state not restored (batch=${SESSION_BATCH:-}, idx=${SESSION_TASK_IDX:-})"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 15: load_session_state returns 1 when no file
# ══════════════════════════════════════════
echo "  Test: load_session_state returns 1 when no file"

(
    SPECTRA_DIR="${tmp_dir}/empty_session_dir"
    mkdir -p "${SPECTRA_DIR}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    set +e
    load_session_state 2>/dev/null
    rc=$?
    set -e
    if [[ ${rc} -eq 1 ]]; then
        echo "  PASS  returns 1 when no session file"
    else
        echo "  FAIL  expected return 1, got ${rc}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 16: clear_session_state removes the file
# ══════════════════════════════════════════
echo "  Test: clear_session_state removes the file"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    save_session_state "task-001" 0 "0"
    [[ -f "${tmp_dir}/session.state" ]] || { echo "  FAIL  state not saved"; exit 1; }
    clear_session_state
    if [[ ! -f "${tmp_dir}/session.state" ]]; then
        echo "  PASS  session.state removed"
    else
        echo "  FAIL  session.state still exists after clear"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 17: session_guard_fresh removes stale builder state
# ══════════════════════════════════════════
echo "  Test: session_guard_fresh removes stale builder state"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    # Create stale files
    touch "${tmp_dir}/builder-context.cache"
    touch "${tmp_dir}/builder-session.state"
    source "${SESSION_LIB}"
    out=$(session_guard_fresh builder 2>&1)
    if [[ ! -f "${tmp_dir}/builder-context.cache" ]] && [[ ! -f "${tmp_dir}/builder-session.state" ]]; then
        echo "  PASS  stale builder state removed"
    else
        echo "  FAIL  stale builder state not removed"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 18: session_guard_fresh removes stale verifier state
# ══════════════════════════════════════════
echo "  Test: session_guard_fresh removes stale verifier state"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    touch "${tmp_dir}/verifier-context.cache"
    touch "${tmp_dir}/verifier-session.state"
    source "${SESSION_LIB}"
    out=$(session_guard_fresh verifier 2>&1)
    if [[ ! -f "${tmp_dir}/verifier-context.cache" ]] && [[ ! -f "${tmp_dir}/verifier-session.state" ]]; then
        echo "  PASS  stale verifier state removed"
    else
        echo "  FAIL  stale verifier state not removed"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 19: session_guard_fresh is silent when no stale state
# ══════════════════════════════════════════
echo "  Test: session_guard_fresh silent when clean"

(
    SPECTRA_DIR="${tmp_dir}/clean_guard_dir"
    mkdir -p "${SPECTRA_DIR}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    out=$(session_guard_fresh builder 2>&1)
    if ! echo "${out}" | grep -q 'WARNING'; then
        echo "  PASS  no warning when state is clean"
    else
        echo "  FAIL  unexpected warning on clean state"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 20: Quick profile disables wiring proof
# ══════════════════════════════════════════
echo "  Test: quick profile disables wiring proof"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="quick"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_WIRING_PROOF}" == "false" ]]; then
        echo "  PASS  quick profile: wiring_proof=false"
    else
        echo "  FAIL  quick profile should disable wiring proof"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 21: Standard profile enables wiring proof
# ══════════════════════════════════════════
echo "  Test: standard profile enables wiring proof"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    export SPECTRA_PROFILE="standard"
    source "${SESSION_LIB}"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_WIRING_PROOF}" == "true" ]]; then
        echo "  PASS  standard profile: wiring_proof=true"
    else
        echo "  FAIL  standard profile should enable wiring proof"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 22: Session state includes timestamp
# ══════════════════════════════════════════
echo "  Test: session state includes timestamp"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    save_session_state "task-001" 0 "0"
    if grep -q '^timestamp=' "${tmp_dir}/session.state"; then
        echo "  PASS  session.state has timestamp"
    else
        echo "  FAIL  session.state missing timestamp"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 23: Session file is orchestrator-only (comment present)
# ══════════════════════════════════════════
echo "  Test: session file marks orchestrator-only"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"
    save_session_state "task-001" 0 "0"
    if grep -q 'orchestrator-only' "${tmp_dir}/session.state"; then
        echo "  PASS  session.state marked orchestrator-only"
    else
        echo "  FAIL  session.state missing orchestrator-only marker"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 24: spectra-loop.sh sources loop-session.sh
# ══════════════════════════════════════════
echo "  Test: spectra-loop.sh sources loop-session.sh"

if grep -q 'source.*loop-session\.sh' "${LOOP_SCRIPT}"; then
    echo "  PASS  spectra-loop.sh sources loop-session.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-loop.sh does not source loop-session.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 25: Profile timeout values are sane
# ══════════════════════════════════════════
echo "  Test: profile timeout values are sane"

(
    SPECTRA_DIR="${tmp_dir}"
    LOGS_DIR="${tmp_dir}/logs"
    mkdir -p "${LOGS_DIR}"
    source "${SESSION_LIB}"

    # Check quick < standard < thorough for builder timeout
    export SPECTRA_PROFILE="quick"
    load_runtime_profile >/dev/null 2>&1
    quick_bt="${PROFILE_BUILDER_TIMEOUT}"

    export SPECTRA_PROFILE="standard"
    load_runtime_profile >/dev/null 2>&1
    standard_bt="${PROFILE_BUILDER_TIMEOUT}"

    export SPECTRA_PROFILE="thorough"
    load_runtime_profile >/dev/null 2>&1
    thorough_bt="${PROFILE_BUILDER_TIMEOUT}"

    if [[ ${quick_bt} -lt ${standard_bt} ]] && [[ ${standard_bt} -lt ${thorough_bt} ]]; then
        echo "  PASS  timeout ordering: quick(${quick_bt}) < standard(${standard_bt}) < thorough(${thorough_bt})"
    else
        echo "  FAIL  timeout ordering violated: ${quick_bt}, ${standard_bt}, ${thorough_bt}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 26: Session persistence does NOT persist builder/verifier state
# ══════════════════════════════════════════
echo "  Test: session persistence excludes builder/verifier context"

# The lib should never write builder/verifier context files (comments are OK)
# Check for actual code lines (not comments) that create builder/verifier state
code_lines=$(grep -v '^\s*#' "${SESSION_LIB}" | grep -P 'save.*builder-context|save.*verifier-context|cat.*builder-context|cat.*verifier-context' || true)
if [[ -z "${code_lines}" ]]; then
    echo "  PASS  session lib does not persist builder/verifier state"
    PASS=$((PASS + 1))
else
    echo "  FAIL  session lib references builder/verifier persistence in code"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  phase11-runtime-profiles: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_PHASE11_RUNTIME_PROFILES_PASS=${PASS}
export TEST_PHASE11_RUNTIME_PROFILES_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
