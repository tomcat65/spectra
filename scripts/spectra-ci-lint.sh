#!/usr/bin/env bash
set -euo pipefail

# Canonical SPECTRA lint implementation.
# GitHub Actions and local operators call this same script; workflow YAML owns
# tool installation only, never a second copy of lint or anti-drift logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_ROOT="${SPECTRA_CI_ROOT:-$(dirname "${SCRIPT_DIR}")}"
MODE="all"
SHELLCHECK="${SHELLCHECK_BIN:-shellcheck}"
ACTIONLINT="${ACTIONLINT_BIN:-actionlint}"

usage() {
    cat <<'USAGE'
Usage: spectra-ci-lint.sh [MODE] [--root PATH]

Modes (default: --all):
  --all          Run every lint gate; required tools must be installed
  --syntax       bash -n all maintained runtime shell files
  --modules      Validate config/loop-modules.txt against disk and wiring
  --shellcheck   Run ShellCheck error gate
  --ratchet      Run the per-file ShellCheck warning ratchet
  --rationale    Require RATIONALE immediately before every suppression
  --actionlint   Validate GitHub Actions workflows
  -h, --help     Show this help

Tool overrides: SHELLCHECK_BIN, ACTIONLINT_BIN
Root override: SPECTRA_CI_ROOT or --root PATH
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) MODE="all"; shift ;;
        --syntax) MODE="syntax"; shift ;;
        --modules) MODE="modules"; shift ;;
        --shellcheck) MODE="shellcheck"; shift ;;
        --ratchet) MODE="ratchet"; shift ;;
        --rationale) MODE="rationale"; shift ;;
        --actionlint) MODE="actionlint"; shift ;;
        --root)
            [[ $# -ge 2 ]] || { echo "ERROR: --root requires a path" >&2; exit 2; }
            SPECTRA_ROOT="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -d "${SPECTRA_ROOT}" || ! -f "${SPECTRA_ROOT}/bin/spectra-loop.sh" ]]; then
    echo "ERROR: not a SPECTRA repository root: ${SPECTRA_ROOT}" >&2
    exit 2
fi
SPECTRA_ROOT="$(cd "${SPECTRA_ROOT}" && pwd)"

collect_shell_targets() {
    local pattern file
    for pattern in \
        "${SPECTRA_ROOT}/bin/"'*.sh' \
        "${SPECTRA_ROOT}/lib/"'*.sh' \
        "${SPECTRA_ROOT}/scripts/"'*.sh' \
        "${SPECTRA_ROOT}/agents/scripts/"'*.sh'; do
        for file in ${pattern}; do
            [[ -f "${file}" ]] || continue
            [[ -L "${file}" ]] && continue
            printf '%s\n' "${file}"
        done
    done
    [[ -f "${SPECTRA_ROOT}/hooks/pre-commit" ]] && printf '%s\n' "${SPECTRA_ROOT}/hooks/pre-commit"
}

require_tool() {
    local tool="$1" label="$2"
    if [[ "${tool}" == */* ]]; then
        [[ -x "${tool}" ]] && return 0
    elif command -v "${tool}" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: ${label} is required for --${MODE}: ${tool}" >&2
    return 2
}

run_syntax() {
    local file failed=0 count=0
    while IFS= read -r file; do
        count=$((count + 1))
        if ! bash -n "${file}" 2>/dev/null; then
            echo "FAIL: bash syntax: ${file#"${SPECTRA_ROOT}/"}" >&2
            failed=1
        fi
    done < <(collect_shell_targets)
    [[ ${count} -gt 0 ]] || { echo "FAIL: no shell targets discovered" >&2; return 1; }
    [[ ${failed} -eq 0 ]] || return 1
    echo "PASS: bash syntax (${count} maintained shell files)"
}

read_module_manifest() {
    local manifest="${SPECTRA_ROOT}/config/loop-modules.txt"
    [[ -f "${manifest}" ]] || { echo "FAIL: missing ${manifest#"${SPECTRA_ROOT}/"}" >&2; return 1; }
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "${manifest}"
}

run_modules() {
    local loop="${SPECTRA_ROOT}/bin/spectra-loop.sh"
    local module file source_count failed=0
    local -a expected=()
    mapfile -t expected < <(read_module_manifest)
    [[ ${#expected[@]} -gt 0 ]] || { echo "FAIL: loop module manifest is empty" >&2; return 1; }

    duplicate=$(printf '%s\n' "${expected[@]}" | sort | uniq -d)
    if [[ -n "${duplicate}" ]]; then
        echo "FAIL: duplicate module manifest entries: ${duplicate}" >&2
        failed=1
    fi

    for module in "${expected[@]}"; do
        if ! [[ "${module}" =~ ^loop-[a-z0-9-]+$ ]]; then
            echo "FAIL: invalid module name in manifest: ${module}" >&2
            failed=1
            continue
        fi
        file="${SPECTRA_ROOT}/lib/${module}.sh"
        if [[ ! -f "${file}" ]]; then
            echo "FAIL: manifest module missing on disk: lib/${module}.sh" >&2
            failed=1
        fi
        source_count=$(grep -cE "^source .*lib/${module}\\.sh" "${loop}" 2>/dev/null || true)
        if [[ "${source_count}" -ne 1 ]]; then
            echo "FAIL: lib/${module}.sh must be sourced exactly once (found ${source_count})" >&2
            failed=1
        fi
    done

    for file in "${SPECTRA_ROOT}"/lib/loop-*.sh; do
        [[ -f "${file}" ]] || continue
        module=$(basename "${file}" .sh)
        if ! printf '%s\n' "${expected[@]}" | grep -qxF "${module}"; then
            echo "FAIL: unlisted module on disk: lib/${module}.sh" >&2
            failed=1
        fi
    done

    while IFS= read -r module; do
        [[ -n "${module}" ]] || continue
        if ! printf '%s\n' "${expected[@]}" | grep -qxF "${module}"; then
            echo "FAIL: spectra-loop.sh sources module absent from manifest: ${module}" >&2
            failed=1
        fi
    done < <(grep -oE 'lib/(loop-[a-z0-9-]+)\.sh' "${loop}" | sed -E 's|lib/(.*)\.sh|\1|' | sort -u)

    if grep -qE 'source.*lib/loop-\*' "${loop}"; then
        echo "FAIL: wildcard module sourcing is not allowed" >&2
        failed=1
    fi

    [[ ${failed} -eq 0 ]] || return 1
    echo "PASS: module inventory and wiring (${#expected[@]} modules)"
}

run_shellcheck() {
    local -a targets=()
    require_tool "${SHELLCHECK}" "ShellCheck" || return $?
    mapfile -t targets < <(collect_shell_targets)
    "${SHELLCHECK}" --severity=error "${targets[@]}"
    echo "PASS: ShellCheck error gate (${#targets[@]} files)"
}

run_ratchet() {
    SPECTRA_HOME="${SPECTRA_ROOT}" "${SPECTRA_ROOT}/bin/spectra-shellcheck-ratchet.sh" --check
}

run_rationale() {
    local file lineno line_text prev_text failed=0
    local disable_marker='# shellcheck'" disable="
    while IFS= read -r file; do
        while IFS=: read -r lineno _; do
            [[ -n "${lineno}" ]] || continue
            line_text=$(sed -n "${lineno}p" "${file}")
            if [[ "${lineno}" -le 1 ]]; then
                echo "FAIL: ${file#"${SPECTRA_ROOT}/"}:${lineno}: suppression cannot have a preceding RATIONALE: ${line_text}" >&2
                failed=1
                continue
            fi
            prev_text=$(sed -n "$((lineno - 1))p" "${file}")
            if ! grep -q '# RATIONALE:' <<< "${prev_text}"; then
                echo "FAIL: ${file#"${SPECTRA_ROOT}/"}:${lineno}: suppression without preceding RATIONALE: ${line_text}" >&2
                failed=1
            fi
        done < <(grep -nF "${disable_marker}" "${file}" || true)
    done < <(collect_shell_targets)
    [[ ${failed} -eq 0 ]] || return 1
    echo "PASS: every ShellCheck suppression has a preceding RATIONALE"
}

run_actionlint() {
    if ! require_tool "${ACTIONLINT}" "actionlint"; then
        if [[ -x "${SPECTRA_ROOT}/actionlint" ]]; then
            ACTIONLINT="${SPECTRA_ROOT}/actionlint"
        else
            return 2
        fi
    fi
    (cd "${SPECTRA_ROOT}" && "${ACTIONLINT}")
    echo "PASS: actionlint"
}

run_mode() {
    case "$1" in
        syntax) run_syntax ;;
        modules) run_modules ;;
        shellcheck) run_shellcheck ;;
        ratchet) run_ratchet ;;
        rationale) run_rationale ;;
        actionlint) run_actionlint ;;
        all)
            run_syntax
            run_modules
            run_shellcheck
            run_ratchet
            run_rationale
            run_actionlint
            ;;
    esac
}

run_mode "${MODE}"
echo "SPECTRA_CI_LINT result=PASS mode=${MODE}"
