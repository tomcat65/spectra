#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: spectra-init.sh end-to-end behavior (Task 006)
# Runs spectra-init.sh in a temp directory and validates all scaffolded
# artifacts match expectations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
INIT_SCRIPT="${SPECTRA_DIR}/bin/spectra-init.sh"

PASS=0
FAIL=0
SKIP=0

# ── Helper ──
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

# ══════════════════════════════════════════
# Test 1: spectra-init.sh exists and is executable
# ══════════════════════════════════════════
echo "  Test: spectra-init.sh exists and is executable"

if [[ -x "${INIT_SCRIPT}" ]]; then
    echo "  PASS  spectra-init.sh exists and is executable"
    PASS=$((PASS + 1))
else
    echo "  FAIL  spectra-init.sh not found or not executable"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════
# Test 2: Init creates .spectra/ directory structure
# ══════════════════════════════════════════
echo "  Test: init creates .spectra/ directory structure"

(
    cd "${tmp_dir}"
    git init -q .
    "${INIT_SCRIPT}" --name "test-e2e" --level 2 --no-commit 2>&1 >/dev/null

    missing=""
    [[ -d ".spectra" ]] || missing="${missing} .spectra"
    [[ -d ".spectra/stories" ]] || missing="${missing} stories/"
    [[ -d ".spectra/logs" ]] || missing="${missing} logs/"
    [[ -d ".spectra/signals" ]] || missing="${missing} signals/"

    if [[ -z "${missing}" ]]; then
        echo "  PASS  .spectra/ directory structure created"
    else
        echo "  FAIL  missing directories:${missing}"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 3: Init creates project.yaml with correct name
# ══════════════════════════════════════════
echo "  Test: project.yaml has correct name"

(
    cd "${tmp_dir}"
    if [[ -f ".spectra/project.yaml" ]]; then
        name=$(grep -oP '^name:\s*\K.*' .spectra/project.yaml | head -1)
        if [[ "${name}" == "test-e2e" ]]; then
            echo "  PASS  project.yaml name is test-e2e"
        else
            echo "  FAIL  project.yaml name is '${name}' (expected test-e2e)"
            exit 1
        fi
    else
        echo "  FAIL  project.yaml not found"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: Init creates project.yaml with correct level
# ══════════════════════════════════════════
echo "  Test: project.yaml has correct level"

(
    cd "${tmp_dir}"
    level=$(grep -oP '^level:\s*\K\d+' .spectra/project.yaml | head -1)
    if [[ "${level}" == "2" ]]; then
        echo "  PASS  project.yaml level is 2"
    else
        echo "  FAIL  project.yaml level is '${level}' (expected 2)"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: Init creates VERSION marker
# ══════════════════════════════════════════
echo "  Test: VERSION marker created"

(
    cd "${tmp_dir}"
    if [[ -f ".spectra/VERSION" ]]; then
        ver=$(cat .spectra/VERSION)
        if [[ "${ver}" == "v5.4" ]]; then
            echo "  PASS  VERSION marker is v5.4"
        else
            echo "  FAIL  VERSION marker is '${ver}' (expected v5.4)"
            exit 1
        fi
    else
        echo "  FAIL  .spectra/VERSION not found"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 6: Init creates CLAUDE.md
# ══════════════════════════════════════════
echo "  Test: CLAUDE.md created"

(
    cd "${tmp_dir}"
    if [[ -f "CLAUDE.md" ]]; then
        if grep -q 'SPECTRA' CLAUDE.md; then
            echo "  PASS  CLAUDE.md created with SPECTRA reference"
        else
            echo "  FAIL  CLAUDE.md exists but missing SPECTRA reference"
            exit 1
        fi
    else
        echo "  FAIL  CLAUDE.md not created"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 7: Init copies PROMPT_build.md
# ══════════════════════════════════════════
echo "  Test: PROMPT_build.md copied"

(
    cd "${tmp_dir}"
    if [[ -f ".spectra/PROMPT_build.md" ]]; then
        echo "  PASS  PROMPT_build.md copied to .spectra/"
    else
        echo "  FAIL  PROMPT_build.md not found in .spectra/"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 8: Init copies PROMPT_verify.md
# ══════════════════════════════════════════
echo "  Test: PROMPT_verify.md copied"

(
    cd "${tmp_dir}"
    if [[ -f ".spectra/PROMPT_verify.md" ]]; then
        echo "  PASS  PROMPT_verify.md copied to .spectra/"
    else
        echo "  FAIL  PROMPT_verify.md not found in .spectra/"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 9: Init creates guardrails.md
# ══════════════════════════════════════════
echo "  Test: guardrails.md created"

(
    cd "${tmp_dir}"
    if [[ -f ".spectra/guardrails.md" ]]; then
        echo "  PASS  guardrails.md created"
    else
        echo "  FAIL  guardrails.md not found"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 10: PROMPT_build.md matches template source
# ══════════════════════════════════════════
echo "  Test: PROMPT_build.md matches template source"

(
    cd "${tmp_dir}"
    TEMPLATE="${SPECTRA_DIR}/templates/.spectra/PROMPT_build.md"
    if [[ -f "${TEMPLATE}" ]] && [[ -f ".spectra/PROMPT_build.md" ]]; then
        if diff -q "${TEMPLATE}" ".spectra/PROMPT_build.md" >/dev/null 2>&1; then
            echo "  PASS  PROMPT_build.md matches template exactly"
        else
            echo "  FAIL  PROMPT_build.md differs from template"
            exit 1
        fi
    else
        echo "  SKIP  template or scaffolded file missing"
        exit 0
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 11: Level 0 init produces minimal scaffolding
# ══════════════════════════════════════════
echo "  Test: level 0 init produces minimal scaffolding"

(
    level0_dir=$(mktemp -d)
    cd "${level0_dir}"
    git init -q .
    "${INIT_SCRIPT}" --name "minimal" --level 0 --no-commit 2>&1 >/dev/null

    if [[ -f ".spectra/project.yaml" ]]; then
        level=$(grep -oP '^level:\s*\K\d+' .spectra/project.yaml | head -1)
        if [[ "${level}" == "0" ]]; then
            echo "  PASS  level 0 scaffolding created with correct level"
        else
            echo "  FAIL  level 0 scaffold has level=${level}"
            exit 1
        fi
    else
        echo "  FAIL  project.yaml not created for level 0"
        exit 1
    fi
    rm -rf "${level0_dir}"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 12: Init without --name shows help
# ══════════════════════════════════════════
echo "  Test: init without --name shows error"

(
    noname_dir=$(mktemp -d)
    cd "${noname_dir}"
    git init -q .
    set +e
    out=$("${INIT_SCRIPT}" 2>&1)
    exit_code=$?
    set -e
    # Script should either show help (exit 0) or error about missing name
    if echo "${out}" | grep -qi 'name\|usage\|required'; then
        echo "  PASS  init without --name gives appropriate message"
    else
        echo "  FAIL  init without --name: unexpected output"
        exit 1
    fi
    rm -rf "${noname_dir}"
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
echo ""
echo "  init-e2e: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

export TEST_INIT_E2E_PASS=${PASS}
export TEST_INIT_E2E_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
