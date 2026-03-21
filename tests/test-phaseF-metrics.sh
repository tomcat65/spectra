#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Phase F per-task execution metrics (F-003, F-005, F-006)
# Tests: record_task_metric(), aggregate_metrics(), read_metrics(),
#        generate_retrospective(), _suggest_profile_from_metrics()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR_REAL="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# Set up minimal environment for sourcing
export SPECTRA_HOME="${SPECTRA_DIR_REAL}"
SPECTRA_DIR="${tmp_dir}/.spectra"
mkdir -p "${SPECTRA_DIR}"
LOGS_DIR="${SPECTRA_DIR}/logs"
mkdir -p "${LOGS_DIR}"
SPECTRA_RUN_ID="test-run-001"

# Source dependencies
source "${SPECTRA_DIR_REAL}/lib/loop-metrics.sh"

# ══════════════════════════════════════════
# Test 1: _ensure_metrics_dir creates directory
# ══════════════════════════════════════════
echo "  Test: _ensure_metrics_dir creates metrics directory"

_ensure_metrics_dir
if [[ -d "${SPECTRA_DIR}/metrics" ]]; then
    echo "  PASS  metrics directory created"
    PASS=$((PASS + 1))
else
    echo "  FAIL  metrics directory not created"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: record_task_metric writes valid JSONL
# ══════════════════════════════════════════
echo "  Test: record_task_metric writes valid JSONL"

(
    cd "${tmp_dir}"
    record_task_metric "001" "PASS" "1" "" "120" "45" "test-run-001"

    if [[ -f "${SPECTRA_DIR}/metrics/tasks.jsonl" ]]; then
        line=$(cat "${SPECTRA_DIR}/metrics/tasks.jsonl")
        if echo "${line}" | grep -q '"task_id":"001"' && \
           echo "${line}" | grep -q '"result":"PASS"' && \
           echo "${line}" | grep -q '"iterations":1' && \
           echo "${line}" | grep -q '"build_secs":120' && \
           echo "${line}" | grep -q '"verify_secs":45'; then
            echo "  PASS  JSONL record has correct fields"
        else
            echo "  FAIL  JSONL record missing expected fields: ${line}"
            exit 1
        fi
    else
        echo "  FAIL  metrics file not created"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 3: record_task_metric includes timestamp
# ══════════════════════════════════════════
echo "  Test: record_task_metric includes timestamp"

(
    cd "${tmp_dir}"
    line=$(cat "${SPECTRA_DIR}/metrics/tasks.jsonl" | head -1)
    if echo "${line}" | grep -qP '"timestamp":"\d{4}-\d{2}-\d{2}T'; then
        echo "  PASS  timestamp present in metric"
    else
        echo "  FAIL  timestamp missing: ${line}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: record_task_metric includes project name
# ══════════════════════════════════════════
echo "  Test: record_task_metric includes project name"

(
    cd "${tmp_dir}"
    line=$(cat "${SPECTRA_DIR}/metrics/tasks.jsonl" | head -1)
    if echo "${line}" | grep -q '"project":"'; then
        echo "  PASS  project name present"
    else
        echo "  FAIL  project name missing"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Multiple records append (not overwrite)
# ══════════════════════════════════════════
echo "  Test: multiple records append to JSONL"

(
    cd "${tmp_dir}"
    record_task_metric "002" "FAIL" "3" "test_failure" "300" "90" "test-run-001"
    record_task_metric "003" "PASS" "1" "" "100" "30" "test-run-001"

    count=$(wc -l < "${SPECTRA_DIR}/metrics/tasks.jsonl")
    if [[ "${count}" -eq 3 ]]; then
        echo "  PASS  3 records appended"
    else
        echo "  FAIL  expected 3 records, got ${count}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: aggregate_metrics on empty file
# ══════════════════════════════════════════
echo "  Test: aggregate_metrics handles empty file"

(
    cd "${tmp_dir}"
    # Use a fresh metrics dir
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"

    out=$(aggregate_metrics)
    if echo "${out}" | grep -q "total_tasks=0"; then
        echo "  PASS  empty file returns total_tasks=0"
    else
        echo "  FAIL  unexpected output: ${out}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: aggregate_metrics computes pass_rate
# ══════════════════════════════════════════
echo "  Test: aggregate_metrics computes pass_rate"

(
    cd "${tmp_dir}"
    out=$(aggregate_metrics)
    if echo "${out}" | grep -q "pass_rate=66"; then
        echo "  PASS  pass_rate=66 (2/3)"
    else
        echo "  FAIL  unexpected pass_rate: $(echo "${out}" | grep pass_rate)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: aggregate_metrics computes first_pass_rate
# ══════════════════════════════════════════
echo "  Test: aggregate_metrics computes first_pass_rate"

(
    cd "${tmp_dir}"
    out=$(aggregate_metrics)
    # 2 tasks with iterations=1 and PASS out of 3 total = 66%
    if echo "${out}" | grep -q "first_pass_rate=66"; then
        echo "  PASS  first_pass_rate correct"
    else
        # Task 001: PASS iter=1 (first pass), Task 002: FAIL iter=3 (not first pass), Task 003: PASS iter=1 (first pass)
        echo "  FAIL  unexpected first_pass_rate: $(echo "${out}" | grep first_pass_rate)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: aggregate_metrics counts stuck
# ══════════════════════════════════════════
echo "  Test: aggregate_metrics counts stuck tasks"

(
    cd "${tmp_dir}"
    record_task_metric "004" "STUCK" "3" "architecture_mismatch" "500" "0" "test-run-001"
    out=$(aggregate_metrics)
    if echo "${out}" | grep -q "stuck_count=1"; then
        echo "  PASS  stuck_count=1"
    else
        echo "  FAIL  unexpected stuck_count: $(echo "${out}" | grep stuck)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: read_metrics returns all lines
# ══════════════════════════════════════════
echo "  Test: read_metrics returns all lines"

(
    cd "${tmp_dir}"
    out=$(read_metrics)
    count=$(echo "${out}" | wc -l)
    if [[ "${count}" -eq 4 ]]; then
        echo "  PASS  read_metrics returns all 4 lines"
    else
        echo "  FAIL  expected 4 lines, got ${count}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: read_metrics with max_lines limit
# ══════════════════════════════════════════
echo "  Test: read_metrics respects max_lines"

(
    cd "${tmp_dir}"
    out=$(read_metrics 2)
    count=$(echo "${out}" | wc -l)
    if [[ "${count}" -eq 2 ]]; then
        echo "  PASS  read_metrics returned exactly 2 lines"
    else
        echo "  FAIL  expected 2 lines, got ${count}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: record_task_metric sanitizes failure_type
# ══════════════════════════════════════════
echo "  Test: record_task_metric sanitizes failure_type"

(
    cd "${tmp_dir}"
    record_task_metric "005" "FAIL" "1" 'test "injection' "60" "30" "test-run-001"
    last_line=$(tail -1 "${SPECTRA_DIR}/metrics/tasks.jsonl")
    if echo "${last_line}" | grep -q '"failure_type":"test_injection'; then
        echo "  PASS  quotes stripped and spaces normalized in failure_type"
    else
        echo "  FAIL  sanitization issue: ${last_line}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 13: record_task_metric uses SPECTRA_RUN_ID default
# ══════════════════════════════════════════
echo "  Test: record_task_metric uses SPECTRA_RUN_ID when run_id omitted"

(
    cd "${tmp_dir}"
    SPECTRA_RUN_ID="auto-run-42"
    record_task_metric "006" "PASS" "1" "" "60" "30"
    last_line=$(tail -1 "${SPECTRA_DIR}/metrics/tasks.jsonl")
    if echo "${last_line}" | grep -q '"run_id":"auto-run-42"'; then
        echo "  PASS  SPECTRA_RUN_ID used as default"
    else
        echo "  FAIL  run_id not defaulted: ${last_line}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 14: generate_retrospective produces markdown
# ══════════════════════════════════════════
echo "  Test: generate_retrospective produces markdown"

(
    cd "${tmp_dir}"
    out=$(generate_retrospective "test-run-001")
    if echo "${out}" | grep -q "## Run Retrospective" && \
       echo "${out}" | grep -q "Run ID.*test-run-001"; then
        echo "  PASS  retrospective has header and run_id"
    else
        echo "  FAIL  unexpected retrospective: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 15: generate_retrospective includes task counts
# ══════════════════════════════════════════
echo "  Test: generate_retrospective includes task counts"

(
    cd "${tmp_dir}"
    out=$(generate_retrospective "test-run-001")
    # Should have counts for tasks with run_id=test-run-001
    if echo "${out}" | grep -q "passed" && echo "${out}" | grep -q "stuck"; then
        echo "  PASS  retrospective includes pass/stuck counts"
    else
        echo "  FAIL  missing counts: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 16: generate_retrospective on empty metrics
# ══════════════════════════════════════════
echo "  Test: generate_retrospective handles no metrics"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"

    out=$(generate_retrospective "nonexistent-run")
    if echo "${out}" | grep -q "No metrics"; then
        echo "  PASS  graceful empty response"
    else
        echo "  FAIL  unexpected output: ${out}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 17: _suggest_profile_from_metrics returns standard on empty
# ══════════════════════════════════════════
echo "  Test: _suggest_profile_from_metrics defaults to standard"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"

    suggestion=$(_suggest_profile_from_metrics)
    if [[ "${suggestion}" == "standard" ]]; then
        echo "  PASS  default is standard"
    else
        echo "  FAIL  expected standard, got ${suggestion}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 18: _suggest_profile suggests quick for high pass rate
# ══════════════════════════════════════════
echo "  Test: _suggest_profile suggests quick for 100% first-pass"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # Write 5 perfect first-pass results
    for i in 1 2 3 4 5; do
        printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"%03d","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' "$i" >> "${METRICS_FILE}"
    done

    suggestion=$(_suggest_profile_from_metrics)
    if [[ "${suggestion}" == "quick" ]]; then
        echo "  PASS  suggests quick for perfect history"
    else
        echo "  FAIL  expected quick, got ${suggestion}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 19: _suggest_profile suggests thorough for high stuck rate
# ══════════════════════════════════════════
echo "  Test: _suggest_profile suggests thorough for high stuck rate"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # 3 pass + 2 stuck = 40% stuck rate
    for i in 1 2 3; do
        printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"%03d","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' "$i" >> "${METRICS_FILE}"
    done
    for i in 4 5; do
        printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"%03d","result":"STUCK","iterations":3,"failure_type":"arch","build_secs":500,"verify_secs":0}\n' "$i" >> "${METRICS_FILE}"
    done

    suggestion=$(_suggest_profile_from_metrics)
    if [[ "${suggestion}" == "thorough" ]]; then
        echo "  PASS  suggests thorough for high stuck rate"
    else
        echo "  FAIL  expected thorough, got ${suggestion}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 20: _suggest_profile returns standard with < 3 tasks
# ══════════════════════════════════════════
echo "  Test: _suggest_profile returns standard with insufficient data"

(
    local_spec=$(mktemp -d)/.spectra
    mkdir -p "${local_spec}/metrics"
    SPECTRA_DIR="${local_spec}"
    METRICS_DIR="${local_spec}/metrics"
    METRICS_FILE="${METRICS_DIR}/tasks.jsonl"

    # Only 2 tasks — not enough for suggestion
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"001","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' >> "${METRICS_FILE}"
    printf '{"timestamp":"2026-01-01","project":"test","run_id":"r1","task_id":"002","result":"PASS","iterations":1,"failure_type":"","build_secs":100,"verify_secs":30}\n' >> "${METRICS_FILE}"

    suggestion=$(_suggest_profile_from_metrics)
    if [[ "${suggestion}" == "standard" ]]; then
        echo "  PASS  standard with insufficient data"
    else
        echo "  FAIL  expected standard, got ${suggestion}"
        exit 1
    fi
    rm -rf "$(dirname "${local_spec}")"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 21: generate_retrospective includes failure breakdown
# ══════════════════════════════════════════
echo "  Test: generate_retrospective includes failure breakdown"

(
    cd "${tmp_dir}"
    out=$(generate_retrospective "test-run-001")
    if echo "${out}" | grep -q "Failure Breakdown"; then
        echo "  PASS  failure breakdown section present"
    else
        echo "  FAIL  no failure breakdown in retrospective"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 22: metrics file is plain JSONL (one JSON object per line)
# ══════════════════════════════════════════
echo "  Test: metrics file is valid JSONL format"

(
    cd "${tmp_dir}"
    valid=true
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        # Check basic JSON structure: starts with { ends with }
        if [[ "${line}" != "{"* ]] || [[ "${line}" != *"}" ]]; then
            valid=false
            break
        fi
    done < "${SPECTRA_DIR}/metrics/tasks.jsonl"

    if [[ "${valid}" == true ]]; then
        echo "  PASS  all lines are JSON objects"
    else
        echo "  FAIL  invalid JSONL format"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  phaseF-metrics: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=phaseF-metrics pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

[[ ${FAIL} -eq 0 ]]
