#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA Elicit — Goal/Decision elicitation front-end            ║
# ║  Scaffolds and gates .spectra/goals.md BEFORE scout + planning.  ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Goals.md captures the agreed target (goal, success criteria, decisions,
# constraints, out-of-scope, open questions) so discovery and the plan are
# anchored to an explicit spec rather than inferred from a one-line prompt.
# Scout, planner, and the builder/verifier context loader all read it when
# present. Later NEGOTIATE decisions must be evaluated against this contract.
#
# Usage: spectra-elicit.sh [ROOT] [--from "<goal sentence>"] [--check]
#                          [--status] [--self-test] [--help]
#
# Modes:
#   (default)     Create .spectra/goals.md from template if missing (preserves
#                 an existing file), then print a readiness summary.
#   --check       Completeness gate. Exit 0 if every required section has
#                 meaningful content and no unresolved markers remain.
#   --status      Print readiness summary without creating anything (exit 0).
#   --self-test   Run internal verification of create + gate behavior.
#
# Exit codes:
#   0 — success (file ready, or created, or --status)
#   1 — --check found the file incomplete, or a fatal error
#   2 — goals.md does not exist when --check/--status was requested

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"
TEMPLATE="${SPECTRA_HOME}/templates/.spectra/goals.md.tmpl"

PROJECT_ROOT="."
FROM_DESC=""
MODE="ensure"   # ensure | check | status | self-test

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)      FROM_DESC="${2:-}"; shift 2 ;;
        --check)     MODE="check"; shift ;;
        --status)    MODE="status"; shift ;;
        --self-test) MODE="self-test"; shift ;;
        -h|--help)
            sed -n '9,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)   PROJECT_ROOT="$1"; shift ;;
    esac
done

# ── Count unresolved markers in a goals file (placeholders + TBD/TODO) ──
# Echoes: "<placeholders> <tbd> <open_decisions>"
_count_unresolved() {
    local file="$1"
    local placeholders tbd open_dec
    placeholders=$(grep -c '<!--' "${file}" 2>/dev/null || true)
    tbd=$(grep -ciE '\b(TBD|TODO)\b' "${file}" 2>/dev/null || true)
    # OPEN decisions: table rows whose final cell is OPEN (case-insensitive).
    open_dec=$(grep -ciE '\|[[:space:]]*OPEN[[:space:]]*\|?[[:space:]]*$' "${file}" 2>/dev/null || true)
    echo "${placeholders:-0} ${tbd:-0} ${open_dec:-0}"
}

REQUIRED_SECTIONS=(
    "Primary Goal"
    "Success Criteria"
    "Key Decisions"
    "Constraints & Non-Negotiables"
    "Explicitly Out of Scope"
    "Open Questions / Assumptions"
    "Requester"
)

# Print meaningful content beneath an H2 heading, stopping at the next H2.
# Template comments, empty bullets/checkboxes, and table scaffolding do not count.
_section_content() {
    local file="$1" heading="$2"
    awk -v wanted="## ${heading}" '
        $0 == wanted { in_section=1; next }
        in_section && /^## / { exit }
        in_section {
            line=$0
            if (line ~ /<!--/) in_comment=1
            if (in_comment) {
                if (line ~ /-->/) in_comment=0
                next
            }
            if (line ~ /^[[:space:]]*$/) next
            if (line ~ /^[[:space:]]*[-*][[:space:]]*$/) next
            if (line ~ /^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*$/) next
            if (line ~ /^[[:space:]]*\|[[:space:]]*#[[:space:]]*\|/) next
            structural=line
            gsub(/[[:space:]|:-]/, "", structural)
            if (structural == "") next
            print line
        }
    ' "${file}"
}

# Echoes: "<missing_required_sections> <empty_required_sections>"
_count_structure_gaps() {
    local file="$1" section content missing=0 empty=0
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! grep -qxF "## ${section}" "${file}" 2>/dev/null; then
            missing=$((missing + 1))
            continue
        fi
        content=$(_section_content "${file}" "${section}")
        if [[ -z "${content}" ]]; then
            empty=$((empty + 1))
        fi
    done
    echo "${missing} ${empty}"
}

# ── Print a readiness summary; returns 0 if ready, 1 if incomplete ──
_summarize() {
    local file="$1"
    local counts structure ph tbd od missing empty
    counts=$(_count_unresolved "${file}")
    read -r ph tbd od <<< "${counts}"
    structure=$(_count_structure_gaps "${file}")
    read -r missing empty <<< "${structure}"
    echo "  goals.md: ${file}"
    echo "    missing sections:      ${missing}"
    echo "    empty sections:        ${empty}"
    echo "    unfilled placeholders: ${ph}"
    echo "    TBD/TODO markers:      ${tbd}"
    echo "    OPEN decisions:        ${od}"
    if [[ "${missing}" -eq 0 && "${empty}" -eq 0 && "${ph}" -eq 0 && "${tbd}" -eq 0 && "${od}" -eq 0 ]]; then
        echo "  ✅ goals.md is ready for discovery + planning"
        return 0
    fi
    echo "  ⚠  goals.md is INCOMPLETE — resolve the items above before planning"
    return 1
}

# ── Create goals.md from template (idempotent: never clobbers existing) ──
_ensure_file() {
    local target="$1"
    if [[ -f "${target}" ]]; then
        echo "  Preserving existing ${target}"
        return 0
    fi
    if [[ ! -f "${TEMPLATE}" ]]; then
        echo "Error: template not found at ${TEMPLATE}" >&2
        return 1
    fi
    local project date_iso
    project="$(basename "$(cd "${PROJECT_ROOT}" && pwd)")"
    date_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sed -e "s|{{PROJECT_NAME}}|${project}|g" \
        -e "s|{{DATE}}|${date_iso}|g" \
        "${TEMPLATE}" > "${target}"
    # Pre-fill the primary goal if a description was supplied.
    if [[ -n "${FROM_DESC}" ]]; then
        # Replace the placeholder comment directly under "## Primary Goal".
        awk -v desc="${FROM_DESC}" '
            prev=="## Primary Goal" && /<!--/ { print desc; prev=$0; next }
            { print; prev=$0 }
        ' "${target}" > "${target}.tmp" && mv "${target}.tmp" "${target}"
    fi
    echo "  Created: ${target}"
}

# ── Self-test ──
if [[ "${MODE}" == "self-test" ]]; then
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    mkdir -p "${T}/.spectra"
    PROJECT_ROOT="${T}"
    target="${T}/.spectra/goals.md"

    fails=0
    _ensure_file "${target}" >/dev/null || fails=$((fails + 1))
    [[ -f "${target}" ]] || { echo "SELF-TEST FAIL: file not created"; fails=$((fails + 1)); }

    # Fresh template must be flagged incomplete (placeholders + OPEN decision).
    if _summarize "${target}" >/dev/null; then
        echo "SELF-TEST FAIL: fresh template reported ready"; fails=$((fails + 1))
    fi

    # An empty file has no unresolved markers, but must still fail structurally.
    : > "${target}"
    if _summarize "${target}" >/dev/null; then
        echo "SELF-TEST FAIL: empty file reported ready"; fails=$((fails + 1))
    fi

    # Fill it: strip comments, resolve the OPEN decision, remove placeholders.
    cat > "${target}" <<'FILLED'
# Goals & Decisions — demo
## Primary Goal
Ship a CLI that prints the build status.
## Success Criteria
- [ ] `status` command exits 0 and prints a table
## Key Decisions
| # | Decision | Choice | Rationale | Status |
|---|----------|--------|-----------|--------|
| 1 | output format | table | human-readable | RESOLVED |
## Constraints & Non-Negotiables
- Bash only, no runtime deps
## Explicitly Out of Scope
- No web UI
## Open Questions / Assumptions
- Assume POSIX coreutils available
## Requester
Tomas
FILLED

    if ! _summarize "${target}" >/dev/null; then
        echo "SELF-TEST FAIL: completed file reported incomplete"; fails=$((fails + 1))
    fi

    # --from pre-fill should land in Primary Goal on a fresh create.
    rm -f "${target}"
    FROM_DESC="My elicited goal line"
    _ensure_file "${target}" >/dev/null
    if ! grep -qF "My elicited goal line" "${target}"; then
        echo "SELF-TEST FAIL: --from did not pre-fill primary goal"; fails=$((fails + 1))
    fi

    if [[ "${fails}" -eq 0 ]]; then
        echo "  ✅ spectra-elicit self-test passed"
        exit 0
    fi
    echo "  ❌ spectra-elicit self-test: ${fails} failure(s)"
    exit 1
fi

GOALS_FILE="${PROJECT_ROOT%/}/.spectra/goals.md"

case "${MODE}" in
    check)
        if [[ ! -f "${GOALS_FILE}" ]]; then
            echo "Error: ${GOALS_FILE} not found. Run 'spectra-elicit' to scaffold it." >&2
            exit 2
        fi
        if _summarize "${GOALS_FILE}"; then exit 0; else exit 1; fi
        ;;
    status)
        if [[ ! -f "${GOALS_FILE}" ]]; then
            echo "Error: ${GOALS_FILE} not found. Run 'spectra-elicit' to scaffold it." >&2
            exit 2
        fi
        _summarize "${GOALS_FILE}" || true
        exit 0
        ;;
    ensure)
        mkdir -p "${PROJECT_ROOT%/}/.spectra"
        _ensure_file "${GOALS_FILE}"
        echo ""
        _summarize "${GOALS_FILE}" || true
        # 'ensure' never fails on incompleteness — it is a scaffolding step.
        exit 0
        ;;
esac
