#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA Quality Gate — Language-Aware Pre-Verifier Checks       ║
# ║  Cheap lint/format checks before expensive verifier passes.      ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-quality-gate.sh [--auto-fix] [--language LANG] [PROJECT_ROOT]
#
# Runs language-appropriate quality checks:
#   Python:     ruff check / black --check (or auto-fix with --auto-fix)
#   JavaScript: eslint / prettier --check
#   Bash:       shellcheck
#   Go:         gofmt -l / go vet
#   Rust:       cargo clippy / cargo fmt --check
#
# IMPORTANT: Auto-fixes are limited to deterministic safe operations
# (formatting, import sorting). They NEVER suppress verifier execution.
#
# Exit codes:
#   0 — all quality checks pass
#   1 — quality issues found (fixable or unfixable)
#   2 — language not detected or no quality tools available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"

AUTO_FIX=false
LANGUAGE_OVERRIDE=""
PROJECT_ROOT="."

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-fix)    AUTO_FIX=true; shift ;;
        --language)    LANGUAGE_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA Quality Gate — Language-Aware Pre-Verifier Checks

Usage: spectra-quality-gate.sh [OPTIONS] [PROJECT_ROOT]

Options:
  --auto-fix         Apply deterministic safe fixes (format, import sort)
  --language LANG    Override language detection (python|javascript|bash|go|rust)
  -h, --help         Show this help

Supported Languages:
  python       ruff check, black --check
  javascript   eslint, prettier --check
  bash         shellcheck
  go           gofmt -l, go vet
  rust         cargo clippy, cargo fmt --check

Exit Codes:
  0  All checks pass
  1  Quality issues found
  2  Language not detected or no tools available
EOF
            exit 0
            ;;
        *)
            if [[ -d "$1" ]]; then
                PROJECT_ROOT="$1"
            else
                echo "Unknown option: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ── Detect language ──
DETECTED_LANG="${LANGUAGE_OVERRIDE}"
if [[ -z "${DETECTED_LANG}" ]]; then
    if [[ -f "${PROJECT_ROOT}/pyproject.toml" || -f "${PROJECT_ROOT}/requirements.txt" || \
          -f "${PROJECT_ROOT}/setup.py" || -f "${PROJECT_ROOT}/setup.cfg" || \
          -f "${PROJECT_ROOT}/Pipfile" || -f "${PROJECT_ROOT}/pytest.ini" ]]; then
        DETECTED_LANG="python"
    elif [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        DETECTED_LANG="javascript"
    elif [[ -f "${PROJECT_ROOT}/go.mod" ]]; then
        DETECTED_LANG="go"
    elif [[ -f "${PROJECT_ROOT}/Cargo.toml" ]]; then
        DETECTED_LANG="rust"
    elif ls "${PROJECT_ROOT}"/bin/*.sh >/dev/null 2>&1 || \
         ls "${PROJECT_ROOT}"/lib/*.sh >/dev/null 2>&1; then
        DETECTED_LANG="bash"
    fi
fi

if [[ -z "${DETECTED_LANG}" ]]; then
    echo "  quality-gate: no language detected — skipping"
    exit 2
fi

echo "  quality-gate: language=${DETECTED_LANG}, auto-fix=${AUTO_FIX}"

ISSUES=0
CHECKS_RUN=0

# ── Language-specific checks ──
case "${DETECTED_LANG}" in
    python)
        # Ruff (fast linter)
        if command -v ruff >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            if [[ "${AUTO_FIX}" == true ]]; then
                ruff check --fix "${PROJECT_ROOT}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            else
                ruff check "${PROJECT_ROOT}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            fi
        fi

        # Black (formatter)
        if command -v black >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            if [[ "${AUTO_FIX}" == true ]]; then
                black "${PROJECT_ROOT}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            else
                black --check "${PROJECT_ROOT}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            fi
        fi
        ;;

    javascript)
        # ESLint
        if command -v eslint >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            if [[ "${AUTO_FIX}" == true ]]; then
                eslint --fix "${PROJECT_ROOT}/src" 2>/dev/null || ISSUES=$((ISSUES + 1))
            else
                eslint "${PROJECT_ROOT}/src" 2>/dev/null || ISSUES=$((ISSUES + 1))
            fi
        fi

        # Prettier
        if command -v prettier >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            if [[ "${AUTO_FIX}" == true ]]; then
                prettier --write "${PROJECT_ROOT}/src/**/*.{js,ts,jsx,tsx}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            else
                prettier --check "${PROJECT_ROOT}/src/**/*.{js,ts,jsx,tsx}" 2>/dev/null || ISSUES=$((ISSUES + 1))
            fi
        fi
        ;;

    bash)
        # ShellCheck
        if command -v shellcheck >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            local_issues=0
            for script in "${PROJECT_ROOT}"/bin/*.sh "${PROJECT_ROOT}"/lib/*.sh; do
                [[ -f "${script}" ]] || continue
                shellcheck "${script}" 2>/dev/null || local_issues=$((local_issues + 1))
            done
            [[ ${local_issues} -gt 0 ]] && ISSUES=$((ISSUES + 1))
        fi
        ;;

    go)
        # gofmt
        if command -v gofmt >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            unformatted=$(gofmt -l "${PROJECT_ROOT}" 2>/dev/null || true)
            if [[ -n "${unformatted}" ]]; then
                if [[ "${AUTO_FIX}" == true ]]; then
                    gofmt -w "${PROJECT_ROOT}" 2>/dev/null || true
                else
                    ISSUES=$((ISSUES + 1))
                    echo "  unformatted: ${unformatted}"
                fi
            fi
        fi

        # go vet
        if command -v go >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            (cd "${PROJECT_ROOT}" && go vet ./... 2>/dev/null) || ISSUES=$((ISSUES + 1))
        fi
        ;;

    rust)
        # cargo clippy
        if command -v cargo >/dev/null 2>&1; then
            CHECKS_RUN=$((CHECKS_RUN + 1))
            (cd "${PROJECT_ROOT}" && cargo clippy -- -D warnings 2>/dev/null) || ISSUES=$((ISSUES + 1))

            CHECKS_RUN=$((CHECKS_RUN + 1))
            (cd "${PROJECT_ROOT}" && cargo fmt --check 2>/dev/null) || ISSUES=$((ISSUES + 1))
        fi
        ;;

    *)
        echo "  quality-gate: unsupported language '${DETECTED_LANG}'"
        exit 2
        ;;
esac

if [[ ${CHECKS_RUN} -eq 0 ]]; then
    echo "  quality-gate: no quality tools available for ${DETECTED_LANG}"
    exit 2
fi

if [[ ${ISSUES} -gt 0 ]]; then
    echo "  quality-gate: ${ISSUES} issue(s) found (${CHECKS_RUN} checks run)"
    exit 1
else
    echo "  quality-gate: all ${CHECKS_RUN} checks passed"
    exit 0
fi
