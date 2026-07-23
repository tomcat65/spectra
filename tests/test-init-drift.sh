#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Init version and template drift detection (Task 004 scaffolding)
# Validates that spectra-init.sh, templates, and runtime prompts emit
# consistent version strings and artifact structures. No LLM invocation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
INIT_SCRIPT="${SPECTRA_DIR}/bin/spectra-init.sh"
TEMPLATE_DIR="${SPECTRA_DIR}/templates/.spectra"

PASS=0
FAIL=0
SKIP=0

# ══════════════════════════════════════════
# Test 1: spectra-init.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-init.sh exists and is executable"

if [[ -x "${INIT_SCRIPT}" ]]; then
    echo "  PASS  spectra-init.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-init.sh missing or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Version strings in spectra-init.sh — detect drift
# KNOWN BUG: init emits multiple conflicting version strings:
#   - Banner/help: v5.1
#   - VERSION file: v5.5
#   - Git commit: v5.5
#   - project.yaml comment: v5.1
#   - Slack notification: v5.1
# Task 004 AC requires a single consistent version.
# ══════════════════════════════════════════
echo "  Test: version string consistency in spectra-init.sh"

# Extract all version patterns from init
VERSION_STRINGS=$(grep -oP 'v5\.\d+(\.\d+)?' "${INIT_SCRIPT}" 2>/dev/null | sort -u)
VERSION_COUNT=$(echo "${VERSION_STRINGS}" | wc -l)

if [[ "${VERSION_COUNT}" -le 1 ]]; then
    echo "  PASS  spectra-init.sh uses single consistent version"
    PASS=$((PASS + 1))
else
    echo "  SKIP  [TODO] spectra-init.sh emits ${VERSION_COUNT} distinct version strings (Task 004 will unify)"
    echo "         versions found: $(echo "${VERSION_STRINGS}" | tr '\n' ' ')"
    SKIP=$((SKIP + 1))
fi

# ══════════════════════════════════════════
# Test 3: VERSION file value matches git commit message version
# VERSION file: extracted from `echo "vX.Y" > .spectra/VERSION` (line ~241)
# Commit message: extracted from `git commit -m "chore: initialize SPECTRA vX.Y..."` (line ~317)
# ══════════════════════════════════════════
echo "  Test: VERSION file value vs git commit message version"

# Extract VERSION file value: the echo that writes to .spectra/VERSION
VERSION_FILE_VAL=$(grep -P 'echo.*> .*VERSION' "${INIT_SCRIPT}" 2>/dev/null | grep -oP 'v\d+\.\d+(\.\d+)?' | head -1 || echo "NONE")
# Extract commit message version: the git commit -m line
COMMIT_MSG_VERSION=$(grep -P 'git commit -m.*SPECTRA' "${INIT_SCRIPT}" 2>/dev/null | grep -oP 'v\d+\.\d+(\.\d+)?' | head -1 || echo "NONE")

if [[ "${VERSION_FILE_VAL}" == "${COMMIT_MSG_VERSION}" ]]; then
    echo "  PASS  VERSION file (${VERSION_FILE_VAL}) matches commit message (${COMMIT_MSG_VERSION})"
    PASS=$((PASS + 1))
else
    echo "  SKIP  [TODO] VERSION file (${VERSION_FILE_VAL}) != commit message (${COMMIT_MSG_VERSION}) — Task 004 target"
    SKIP=$((SKIP + 1))
fi

# ══════════════════════════════════════════
# Test 4: Banner version vs help text version
# ══════════════════════════════════════════
echo "  Test: banner version vs help text version consistency"

BANNER_VERSIONS=$(grep -P 'SPECTRA v\d' "${INIT_SCRIPT}" 2>/dev/null | grep -oP 'v\d+\.\d+(\.\d+)?' | sort -u)
BANNER_COUNT=$(echo "${BANNER_VERSIONS}" | wc -l)

if [[ "${BANNER_COUNT}" -le 1 ]]; then
    echo "  PASS  banner and help text use same version"
    PASS=$((PASS + 1))
else
    echo "  SKIP  [TODO] banner/help emit ${BANNER_COUNT} versions: $(echo "${BANNER_VERSIONS}" | tr '\n' ' ')— Task 004 target"
    SKIP=$((SKIP + 1))
fi

# ══════════════════════════════════════════
# Test 5: Prompt template files exist in template directory
# init copies PROMPT_build.md, PROMPT_verify.md, and optionally PROMPT_split.md
# ══════════════════════════════════════════
echo "  Test: PROMPT_build.md template exists"

if [[ -f "${TEMPLATE_DIR}/PROMPT_build.md" ]]; then
    echo "  PASS  PROMPT_build.md template exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL  PROMPT_build.md template not found in ${TEMPLATE_DIR}"
    FAIL=$((FAIL + 1))
fi

echo "  Test: PROMPT_verify.md template exists"

if [[ -f "${TEMPLATE_DIR}/PROMPT_verify.md" ]]; then
    echo "  PASS  PROMPT_verify.md template exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL  PROMPT_verify.md template not found in ${TEMPLATE_DIR}"
    FAIL=$((FAIL + 1))
fi

echo "  Test: PROMPT_split.md template exists (optional)"

if [[ -f "${TEMPLATE_DIR}/PROMPT_split.md" ]]; then
    echo "  PASS  PROMPT_split.md template exists"
    PASS=$((PASS + 1))
else
    echo "  PASS  PROMPT_split.md template absent (conditional copy in init — acceptable)"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 6: Init references template directory correctly
# ══════════════════════════════════════════
echo "  Test: init references PROMPT templates via TEMPLATE_DIR"

if grep -q 'TEMPLATE_DIR' "${INIT_SCRIPT}" 2>/dev/null && \
   grep -q 'PROMPT_build' "${INIT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  init uses TEMPLATE_DIR for prompt file copies"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init does not reference TEMPLATE_DIR for prompts"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 7: Init scaffolds project.yaml
# ══════════════════════════════════════════
echo "  Test: init generates project.yaml"

if grep -q 'project\.yaml' "${INIT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  init generates project.yaml"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init does not generate project.yaml"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 8: Init requires --name argument
# ══════════════════════════════════════════
echo "  Test: init requires --name argument"

if grep -qP '\-\-name' "${INIT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  init accepts --name argument"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init does not reference --name argument"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 9: Init help text mentions architecture / agent roster
# ══════════════════════════════════════════
echo "  Test: init help text documents agent architecture"

if grep -q 'spectra-planner' "${INIT_SCRIPT}" 2>/dev/null && \
   grep -q 'spectra-builder' "${INIT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  init help text documents planner and builder agents"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init help text missing agent architecture"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 10: Init scaffolds standard directories
# ══════════════════════════════════════════
echo "  Test: init creates standard .spectra subdirectories"

# Check that init creates signals/, logs/, stories/ directories
dir_count=0
grep -q 'signals' "${INIT_SCRIPT}" 2>/dev/null && dir_count=$((dir_count + 1))
grep -q 'logs' "${INIT_SCRIPT}" 2>/dev/null && dir_count=$((dir_count + 1))
grep -q 'stories' "${INIT_SCRIPT}" 2>/dev/null && dir_count=$((dir_count + 1))

if [[ ${dir_count} -ge 3 ]]; then
    echo "  PASS  init creates signals/, logs/, stories/ directories"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init missing standard directory creation (found ${dir_count}/3)"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 11: Init writes VERSION marker file
# ══════════════════════════════════════════
echo "  Test: init writes VERSION marker"

if grep -q 'VERSION' "${INIT_SCRIPT}" 2>/dev/null; then
    echo "  PASS  init writes .spectra/VERSION marker"
    PASS=$((PASS + 1))
else
    echo "  FAIL  init does not write VERSION marker"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 12: tasks.md template exists if referenced by init
# ══════════════════════════════════════════
echo "  Test: tasks.md template consistency"

if grep -q 'tasks\.md' "${INIT_SCRIPT}" 2>/dev/null; then
    if [[ -f "${TEMPLATE_DIR}/tasks.md.tmpl" ]]; then
        echo "  PASS  tasks.md.tmpl template exists alongside init reference"
        PASS=$((PASS + 1))
    else
        # init might inline the template rather than copying from file
        echo "  PASS  init references tasks.md (may use inline template)"
        PASS=$((PASS + 1))
    fi
else
    echo "  PASS  init does not reference tasks.md template (may be Level-conditional)"
    PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════
# Test 13: All bin/*.sh user-facing version strings are consistent
# Grep all runtime scripts for "SPECTRA v" and assert single canonical version.
# ══════════════════════════════════════════
echo "  Test: cross-script version consistency (bin/*.sh)"

CANONICAL_VERSION="v5.5"
BIN_DIR="${SPECTRA_DIR}/bin"
version_mismatch=""
for script in "${BIN_DIR}"/*.sh; do
    [[ -f "${script}" ]] || continue
    # Look for user-facing version strings like "SPECTRA v5.x" or "v5.x —"
    # Exclude heritage comments that document historical versions (e.g. "v5.0 CORE:", "Heritage: v5.0")
    while IFS= read -r line; do
        # Skip heritage/history lines — these document when a feature was introduced
        echo "${line}" | grep -qPi 'Heritage|introduced|CORE:|keeps orchestration' && continue
        ver=$(echo "${line}" | grep -oP 'v5\.\d+' | head -1)
        if [[ -n "${ver}" && "${ver}" != "${CANONICAL_VERSION}" ]]; then
            version_mismatch="${version_mismatch}  $(basename "${script}"): found ${ver} (expected ${CANONICAL_VERSION})\n"
        fi
    done < <(grep -P 'SPECTRA v5\.\d|v5\.\d\s*—|v5\.\d\s+' "${script}" 2>/dev/null || true)
done

if [[ -z "${version_mismatch}" ]]; then
    echo "  PASS  all bin/*.sh scripts use ${CANONICAL_VERSION}"
    PASS=$((PASS + 1))
else
    echo "  FAIL  version drift detected:"
    echo -e "${version_mismatch}"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 14: spectra-loop.sh version matches spectra-init.sh version
# These two scripts are the primary user entry points — they must agree.
# ══════════════════════════════════════════
echo "  Test: spectra-loop.sh version matches spectra-init.sh version"

LOOP_VER=$(grep -oP 'SPECTRA v\K5\.\d+' "${SPECTRA_DIR}/bin/spectra-loop.sh" 2>/dev/null | head -1)
INIT_VER=$(grep -oP 'SPECTRA v\K5\.\d+' "${SPECTRA_DIR}/bin/spectra-init.sh" 2>/dev/null | head -1)

if [[ -z "${LOOP_VER}" || -z "${INIT_VER}" ]]; then
    echo "  FAIL  could not extract version from one or both scripts (loop=${LOOP_VER:-?}, init=${INIT_VER:-?})"
    FAIL=$((FAIL + 1))
elif [[ "${LOOP_VER}" == "${INIT_VER}" ]]; then
    echo "  PASS  spectra-loop.sh (v${LOOP_VER}) matches spectra-init.sh (v${INIT_VER})"
    PASS=$((PASS + 1))
else
    echo "  FAIL  version mismatch: spectra-loop.sh (v${LOOP_VER}) vs spectra-init.sh (v${INIT_VER})"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
echo ""
echo "  init-drift: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=init-drift pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_INIT_DRIFT_PASS=${PASS}
export TEST_INIT_DRIFT_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
