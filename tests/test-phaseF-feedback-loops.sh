#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Phase F feedback loops (F-001, F-002, F-004, F-006)
# Tests: _prior_failure_context(), should_fast_escalate(), --fallback-model usage,
#        auto-profile selection from metrics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR_REAL="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

export SPECTRA_HOME="${SPECTRA_DIR_REAL}"
SPECTRA_DIR="${tmp_dir}/.spectra"
mkdir -p "${SPECTRA_DIR}/metrics" "${SPECTRA_DIR}/logs" "${SPECTRA_DIR}/signals"
LOGS_DIR="${SPECTRA_DIR}/logs"
SPECTRA_RUN_ID="test-f-run"

# Source modules
source "${SPECTRA_DIR_REAL}/lib/loop-context.sh"
source "${SPECTRA_DIR_REAL}/lib/loop-retry.sh"
source "${SPECTRA_DIR_REAL}/lib/loop-metrics.sh"
source "${SPECTRA_DIR_REAL}/lib/loop-session.sh"

# ══════════════════════════════════════════
# F-001 Tests: Prior failure context
# ══════════════════════════════════════════
echo "  Test: _prior_failure_context returns empty when no metrics"

(
    out=$(_prior_failure_context "001")
    if [[ -z "${out}" ]]; then
        echo "  PASS  empty when no metrics file"
    else
        echo "  FAIL  expected empty, got: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ──────────────────────
echo "  Test: _prior_failure_context returns warning when failures exist"

(
    cd "${tmp_dir}"
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"001","result":"FAIL","iterations":2,"failure_type":"test_failure","build_secs":100,"verify_secs":30}\n' > "${SPECTRA_DIR}/metrics/tasks.jsonl"
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"002","result":"FAIL","iterations":1,"failure_type":"test_failure","build_secs":100,"verify_secs":30}\n' >> "${SPECTRA_DIR}/metrics/tasks.jsonl"

    out=$(_prior_failure_context "003")
    if echo "${out}" | grep -q "WARNING.*test_failure"; then
        echo "  PASS  warning includes failure type"
    else
        echo "  FAIL  unexpected: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ──────────────────────
echo "  Test: context_files_for_build includes prior failure warning"

(
    cd "${tmp_dir}"
    # TASK_IDS and TASK_TITLES arrays needed by build_prompt
    TASK_IDS=("001")
    TASK_TITLES=("Test task")

    out=$(context_files_for_build "001" "1" "")
    if echo "${out}" | grep -q "WARNING"; then
        echo "  PASS  prior failure warning injected into build context"
    else
        echo "  FAIL  no warning in build context: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ──────────────────────
echo "  Test: context_files_for_build omits warning when no metrics"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}"
    SPECTRA_DIR="${local_spec}"

    out=$(context_files_for_build "001" "1" "")
    if echo "${out}" | grep -q "WARNING"; then
        echo "  FAIL  should not have warning with no metrics"
        exit 1
    else
        echo "  PASS  no warning when no metrics"
    fi
    rm -rf "$(dirname "${local_spec}")"
    SPECTRA_DIR="${tmp_dir}/.spectra"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# F-002 Tests: Adaptive retry (should_fast_escalate)
# ══════════════════════════════════════════
echo "  Test: should_fast_escalate returns 1 with empty history"

if should_fast_escalate "001" "test_failure" "" 2>/dev/null; then
    echo "  FAIL  should not escalate with empty history"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  does not escalate with empty history"
    PASS=$((PASS + 1))
fi

# ──────────────────────
echo "  Test: should_fast_escalate returns 1 with single failure"

if should_fast_escalate "001" "test_failure" "test_failure" 2>/dev/null; then
    echo "  FAIL  should not escalate after single failure"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  does not escalate after single failure"
    PASS=$((PASS + 1))
fi

# ──────────────────────
echo "  Test: should_fast_escalate returns 0 with 2 consecutive same type"

if should_fast_escalate "001" "test_failure" "test_failure,test_failure" 2>/dev/null; then
    echo "  PASS  escalates on 2 consecutive identical failures"
    PASS=$((PASS + 1))
else
    echo "  FAIL  should escalate"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: should_fast_escalate returns 1 with different types"

if should_fast_escalate "001" "wiring_gap" "test_failure,wiring_gap" 2>/dev/null; then
    echo "  FAIL  should not escalate with different types"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  does not escalate with mixed failure types"
    PASS=$((PASS + 1))
fi

# ──────────────────────
echo "  Test: should_fast_escalate returns 0 with 3 consecutive"

if should_fast_escalate "001" "wiring_gap" "wiring_gap,wiring_gap,wiring_gap" 2>/dev/null; then
    echo "  PASS  escalates on 3 consecutive identical failures"
    PASS=$((PASS + 1))
else
    echo "  FAIL  should escalate"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: should_fast_escalate returns 1 with no failure type"

if should_fast_escalate "001" "" "test_failure" 2>/dev/null; then
    echo "  FAIL  should not escalate with empty current type"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  does not escalate with empty current type"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# F-004 Tests: --fallback-model in agent invocations
# ══════════════════════════════════════════
echo "  Test: loop-build.sh uses --fallback-model on builder"

if grep -q '\-\-fallback-model sonnet' "${SPECTRA_DIR_REAL}/lib/loop-build.sh"; then
    echo "  PASS  builder uses --fallback-model sonnet"
    PASS=$((PASS + 1))
else
    echo "  FAIL  builder missing --fallback-model"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: spectra-loop.sh uses --fallback-model on verifier"

if grep -A1 'spectra-verifier' "${SPECTRA_DIR_REAL}/bin/spectra-loop.sh" | grep -q '\-\-fallback-model sonnet'; then
    echo "  PASS  verifier uses --fallback-model sonnet"
    PASS=$((PASS + 1))
else
    echo "  FAIL  verifier missing --fallback-model"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: loop-verify.sh uses --fallback-model on oracle"

if grep -q '\-\-fallback-model sonnet' "${SPECTRA_DIR_REAL}/lib/loop-verify.sh"; then
    echo "  PASS  oracle uses --fallback-model sonnet"
    PASS=$((PASS + 1))
else
    echo "  FAIL  oracle missing --fallback-model"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: spectra-loop.sh uses --fallback-model on reviewer"

if grep -q 'spectra-reviewer.*--fallback-model haiku' "${SPECTRA_DIR_REAL}/bin/spectra-loop.sh"; then
    echo "  PASS  reviewer uses --fallback-model haiku"
    PASS=$((PASS + 1))
else
    echo "  FAIL  reviewer missing --fallback-model"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────
echo "  Test: spectra-loop.sh uses --fallback-model on auditor"

if grep -q 'spectra-auditor.*--fallback-model sonnet' "${SPECTRA_DIR_REAL}/bin/spectra-loop.sh"; then
    echo "  PASS  auditor uses --fallback-model sonnet"
    PASS=$((PASS + 1))
else
    echo "  FAIL  auditor missing --fallback-model"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# F-006 Tests: Auto-profile from metrics
# ══════════════════════════════════════════
echo "  Test: load_runtime_profile uses auto-suggest when no explicit profile"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # Write 5 perfect first-pass results to trigger "quick" suggestion
    for i in 1 2 3 4 5; do
        printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"%03d","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' "$i" >> "${METRICS_FILE}"
    done

    unset SPECTRA_PROFILE
    out=$(load_runtime_profile 2>&1)
    if echo "${out}" | grep -q "Auto-selected.*quick"; then
        echo "  PASS  auto-selected quick from perfect history"
    else
        # Check if profile was set to quick
        if [[ "${PROFILE_NAME}" == "quick" ]]; then
            echo "  PASS  profile set to quick from metrics"
        else
            echo "  FAIL  expected quick, got ${PROFILE_NAME}. Output: ${out}"
            exit 1
        fi
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ──────────────────────
echo "  Test: SPECTRA_PROFILE env var overrides auto-suggest"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # Write metrics that would suggest "quick"
    for i in 1 2 3 4 5; do
        printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"%03d","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' "$i" >> "${METRICS_FILE}"
    done

    SPECTRA_PROFILE="thorough"
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "thorough" ]]; then
        echo "  PASS  env var overrides auto-suggest"
    else
        echo "  FAIL  expected thorough, got ${PROFILE_NAME}"
        exit 1
    fi
    unset SPECTRA_PROFILE
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ──────────────────────
echo "  Test: load_runtime_profile standard when auto-suggest is standard"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # Only 2 tasks — not enough for suggestion, should stay standard
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"001","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' >> "${METRICS_FILE}"
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"002","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' >> "${METRICS_FILE}"

    unset SPECTRA_PROFILE
    load_runtime_profile >/dev/null 2>&1
    if [[ "${PROFILE_NAME}" == "standard" ]]; then
        echo "  PASS  standard when metrics insufficient"
    else
        echo "  FAIL  expected standard, got ${PROFILE_NAME}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  phaseF-feedback-loops: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=phaseF-feedback-loops pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

[[ ${FAIL} -eq 0 ]]
