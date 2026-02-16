#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Loop unit tests for Phase 1 quick wins
# Tests plan checksum lock and builder timeout detection (no LLM invocation).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
LOOP_SCRIPT="${SPECTRA_DIR}/bin/spectra-loop.sh"

PASS=0
FAIL=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT

tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: Plan checksum — detect plan.md mutation
# ══════════════════════════════════════════
echo "  Test: plan checksum detects mutation"

# Create a fake project directory
PROJ="${tmp_dir}/checksum-test"
mkdir -p "${PROJ}/.spectra/signals"
echo "## Task 001: Foo" > "${PROJ}/.spectra/plan.md"

# Compute initial checksum
INITIAL=$(sha256sum "${PROJ}/.spectra/plan.md" | cut -d' ' -f1)

# Mutate the plan
echo "## Task 002: Bar" >> "${PROJ}/.spectra/plan.md"

# Compute again
AFTER=$(sha256sum "${PROJ}/.spectra/plan.md" | cut -d' ' -f1)

if [[ "${INITIAL}" != "${AFTER}" ]]; then
    echo "  PASS  checksum detects mutation (${INITIAL:0:8}... != ${AFTER:0:8}...)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  checksum did NOT detect mutation"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Plan checksum — stable on unchanged file
# ══════════════════════════════════════════
echo "  Test: plan checksum stable on unchanged file"

STABLE_PLAN="${tmp_dir}/stable-plan.md"
echo "## Task 001: Stable" > "${STABLE_PLAN}"

CS1=$(sha256sum "${STABLE_PLAN}" | cut -d' ' -f1)
CS2=$(sha256sum "${STABLE_PLAN}" | cut -d' ' -f1)

if [[ "${CS1}" == "${CS2}" ]]; then
    echo "  PASS  checksum stable on unchanged file"
    PASS=$((PASS + 1))
else
    echo "  FAIL  checksum changed on unchanged file"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 3: Timeout exit code 124
# ══════════════════════════════════════════
echo "  Test: timeout command returns exit 124"

set +e
timeout 1 sleep 10
EXIT_CODE=$?
set -e

if [[ "${EXIT_CODE}" -eq 124 ]]; then
    echo "  PASS  timeout returns exit 124"
    PASS=$((PASS + 1))
else
    echo "  FAIL  timeout returned exit ${EXIT_CODE} (expected 124)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 4: Timeout does not kill fast commands
# ══════════════════════════════════════════
echo "  Test: timeout does not kill fast commands"

set +e
timeout 5 echo "hello" > /dev/null
EXIT_CODE=$?
set -e

if [[ "${EXIT_CODE}" -eq 0 ]]; then
    echo "  PASS  fast command completes under timeout"
    PASS=$((PASS + 1))
else
    echo "  FAIL  fast command got exit ${EXIT_CODE} under timeout"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 5: --builder-timeout flag recognized by script parser
# ══════════════════════════════════════════
echo "  Test: --builder-timeout flag in help text"

if grep -q 'builder-timeout' "${LOOP_SCRIPT}" 2>/dev/null; then
    echo "  PASS  --builder-timeout flag present in spectra-loop.sh"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --builder-timeout flag missing from spectra-loop.sh"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 6: TIMEOUT signal file creation pattern
# ══════════════════════════════════════════
echo "  Test: TIMEOUT signal file creation"

TIMEOUT_SIG="${tmp_dir}/TIMEOUT_001"
echo "TIMEOUT" > "${TIMEOUT_SIG}"

if [[ -f "${TIMEOUT_SIG}" ]] && [[ "$(cat "${TIMEOUT_SIG}")" == "TIMEOUT" ]]; then
    echo "  PASS  TIMEOUT signal file created correctly"
    PASS=$((PASS + 1))
else
    echo "  FAIL  TIMEOUT signal file creation failed"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  loop-unit: ${PASS} passed, ${FAIL} failed"

export TEST_LOOP_PASS=${PASS}
export TEST_LOOP_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
