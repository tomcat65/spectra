#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: typed structured helper
# Validates plan parsing, status mutation, and generated status snapshots.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME_REAL="$(dirname "${SCRIPT_DIR}")"
HELPER="${SPECTRA_HOME_REAL}/scripts/spectra-structured.py"
FIXTURE_DIR="${SPECTRA_HOME_REAL}/fixtures/plan-bridge"

PASS=0
FAIL=0
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

echo "  Test: helper exists and compiles"
if [[ -f "${HELPER}" ]] && python3 -m py_compile "${HELPER}" 2>/dev/null; then
    echo "  PASS  helper exists and py_compile passes"
    PASS=$((PASS + 1))
else
    echo "  FAIL  helper missing or py_compile failed"
    FAIL=$((FAIL + 1))
fi

echo "  Test: plan extract emits valid JSON payload"
(
    out="${tmp_dir}/plan.json"
    python3 "${HELPER}" plan extract --file "${FIXTURE_DIR}/valid-level0.md" --output "${out}"
    if grep -q '"version": "1.0"' "${out}" && grep -q '"id": "001"' "${out}"; then
        echo "  PASS  plan extract emitted versioned task JSON"
    else
        echo "  FAIL  unexpected plan extract output"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo "  Test: emit-shell prefers fresh plan.json"
(
    proj="${tmp_dir}/emit-shell"
    mkdir -p "${proj}/.spectra"
    cp "${FIXTURE_DIR}/valid-level0.md" "${proj}/.spectra/plan.md"
    python3 "${HELPER}" plan extract --file "${proj}/.spectra/plan.md" --output "${proj}/.spectra/plan.json" >/dev/null
    out=$(python3 "${HELPER}" plan emit-shell --plan-file "${proj}/.spectra/plan.md" --plan-json "${proj}/.spectra/plan.json")
    if echo "${out}" | grep -q "PLAN_PARSE_SOURCE=.*plan_json" && echo "${out}" | grep -q "TASK_IDS+=(001)"; then
        echo "  PASS  emit-shell used plan.json fast path"
    else
        echo "  FAIL  emit-shell did not expose plan_json source"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo "  Test: set-status syncs plan.md and plan.json"
(
    proj="${tmp_dir}/set-status"
    mkdir -p "${proj}/.spectra"
    cp "${FIXTURE_DIR}/valid-level0.md" "${proj}/.spectra/plan.md"
    python3 "${HELPER}" plan extract --file "${proj}/.spectra/plan.md" --output "${proj}/.spectra/plan.json" >/dev/null
    python3 "${HELPER}" plan set-status \
        --plan-file "${proj}/.spectra/plan.md" \
        --plan-json "${proj}/.spectra/plan.json" \
        --task-id "001" \
        --status "complete"
    if grep -q '^- \[x\] 001:' "${proj}/.spectra/plan.md" && grep -q '"status": "complete"' "${proj}/.spectra/plan.json"; then
        echo "  PASS  set-status updated plan.md and plan.json"
    else
        echo "  FAIL  set-status did not keep plan artifacts aligned"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo "  Test: status snapshot JSON includes task counts"
(
    proj="${tmp_dir}/status-json"
    mkdir -p "${proj}/.spectra/signals"
    cp "${FIXTURE_DIR}/valid-level0.md" "${proj}/.spectra/plan.md"
    cat > "${proj}/.spectra/project.yaml" <<'YAML'
name: helper-status
level: 0
YAML
    python3 "${HELPER}" plan extract --file "${proj}/.spectra/plan.md" --output "${proj}/.spectra/plan.json" >/dev/null
    python3 "${HELPER}" plan set-status \
        --plan-file "${proj}/.spectra/plan.md" \
        --plan-json "${proj}/.spectra/plan.json" \
        --task-id "001" \
        --status "complete"
    echo "executing" > "${proj}/.spectra/signals/PHASE"
    echo "builder" > "${proj}/.spectra/signals/AGENT"
    out=$(python3 "${HELPER}" status snapshot --project-root "${proj}" --format json)
    if echo "${out}" | grep -q '"project": "helper-status"' && \
       echo "${out}" | grep -q '"done": 1' && \
       echo "${out}" | grep -q '"remaining": 0'; then
        echo "  PASS  status snapshot JSON reported task counts"
    else
        echo "  FAIL  unexpected status snapshot JSON: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo "  Test: status snapshot progress string is stable"
(
    proj="${tmp_dir}/status-progress"
    mkdir -p "${proj}/.spectra/signals"
    cp "${FIXTURE_DIR}/valid-level0.md" "${proj}/.spectra/plan.md"
    python3 "${HELPER}" plan extract --file "${proj}/.spectra/plan.md" --output "${proj}/.spectra/plan.json" >/dev/null
    out=$(python3 "${HELPER}" status snapshot --project-root "${proj}" --format progress)
    if [[ "${out}" == "0/1 tasks (0 stuck)" ]]; then
        echo "  PASS  progress string matches expected format"
    else
        echo "  FAIL  unexpected progress string: ${out}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo "  Test: status snapshot writes generated status.json"
(
    proj="${tmp_dir}/status-output"
    mkdir -p "${proj}/.spectra/signals"
    cp "${FIXTURE_DIR}/valid-level0.md" "${proj}/.spectra/plan.md"
    python3 "${HELPER}" plan extract --file "${proj}/.spectra/plan.md" --output "${proj}/.spectra/plan.json" >/dev/null
    python3 "${HELPER}" status snapshot --project-root "${proj}" --output "${proj}/.spectra/status.json" --format json >/dev/null
    if [[ -f "${proj}/.spectra/status.json" ]] && grep -q '"tasks"' "${proj}/.spectra/status.json"; then
        echo "  PASS  generated status.json written"
    else
        echo "  FAIL  status.json not generated"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo ""
echo "  structured-helper: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=structured-helper pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

[[ ${FAIL} -eq 0 ]]
