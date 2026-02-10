#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Contract Validator (v4 canonical schema)
# Validates .spectra/plan.md against the approved canonical schema.
# Level-conditional: fields required vary by project level (0-4).
# Usage: spectra-plan-validate.sh [--file PATH] [--quiet] [--level N]

SPECTRA_DIR=".spectra"
PLAN_FILE="${SPECTRA_DIR}/plan.md"
QUIET=false
LEVEL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            PLAN_FILE="$2"
            shift 2
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --level)
            LEVEL_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
Usage: spectra-plan-validate.sh [OPTIONS]

Validates canonical plan.md task schema (v4).

Options:
  --file PATH   Validate a specific file (default: .spectra/plan.md)
  --level N     Override project level (default: read from project.yaml)
  --quiet       Print errors only
  -h, --help    Show this help

Canonical task shape (Level 3+):
  ## Task NNN: Title
  - [ ] NNN: Title
  - AC:
    - criterion 1
    - criterion 2
  - Files: path/a.ts, path/b.ts
  - Verify: \`command that exits 0\`
  - Risk: low|medium|high
  - Max-iterations: 5
  - Scope: code|infra|docs|config|multi-repo
  - File-ownership:
    - owns: [file-a]
    - touches: [file-b]
    - reads: [file-c]
  - Wiring-proof:
    - CLI: command path
    - Integration: cross-module assertion

Checkbox states: [ ] pending, [x] complete, [!] stuck

Level-conditional fields:
  Level 0: header, checkbox, AC, Files, Verify required; rest optional
  Level 1: + Risk, Max-iterations required
  Level 2: + Scope, Wiring-proof required
  Level 3+: + File-ownership, Parallelism Assessment required
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "${PLAN_FILE}" ]]; then
    echo "Plan validation failed: file not found: ${PLAN_FILE}" >&2
    exit 1
fi

# ── Determine project level ──
PROJECT_LEVEL=1
if [[ -n "${LEVEL_OVERRIDE}" ]]; then
    PROJECT_LEVEL="${LEVEL_OVERRIDE}"
elif [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
    PROJECT_LEVEL=$(grep -oP '^level:\s*\K\d+' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 || echo "1")
fi

# ── Parse task headers ──
mapfile -t TASK_HEADERS < <(grep -nE '^## Task [0-9]{3}: .+' "${PLAN_FILE}" || true)

declare -a ERRORS=()
declare -a WARNINGS=()
declare -A SEEN_IDS=()
declare -A ALL_OWNS=()
declare -A ALL_TOUCHES=()

if [[ ${#TASK_HEADERS[@]} -eq 0 ]]; then
    ERRORS+=("No canonical task headers found. Expected lines like: '## Task 001: ...'")
fi

prev_num=0

for i in "${!TASK_HEADERS[@]}"; do
    header="${TASK_HEADERS[$i]}"
    start_line="${header%%:*}"
    header_text="${header#*:}"
    task_id=$(echo "${header_text}" | sed -E 's/^## Task ([0-9]{3}):.*/\1/')
    task_num=$((10#${task_id}))

    # ── Duplicate / ordering checks ──
    if [[ -n "${SEEN_IDS[${task_id}]:-}" ]]; then
        ERRORS+=("Task ${task_id}: duplicate task ID")
    fi
    SEEN_IDS["${task_id}"]=1

    if [[ ${task_num} -le ${prev_num} ]]; then
        ERRORS+=("Task ${task_id}: task IDs must be strictly increasing")
    fi
    prev_num=${task_num}

    # ── Extract task block ──
    if [[ $((i + 1)) -lt ${#TASK_HEADERS[@]} ]]; then
        next_start="${TASK_HEADERS[$((i + 1))]%%:*}"
        end_line=$((next_start - 1))
        task_block=$(sed -n "${start_line},${end_line}p" "${PLAN_FILE}")
    else
        task_block=$(sed -n "${start_line},\$p" "${PLAN_FILE}")
    fi

    # ══════════════════════════════════════════
    # ALWAYS REQUIRED (all levels)
    # ══════════════════════════════════════════

    # Checkbox line (supports [ ] pending, [x] complete, [!] stuck)
    if ! echo "${task_block}" | grep -qE "^- \\[[ xX!]\\] ${task_id}: .+"; then
        ERRORS+=("Task ${task_id}: missing checkbox line '- [ ] ${task_id}: ...'")
    fi

    # AC: multi-line (at least one sub-item starting with "  - ")
    if echo "${task_block}" | grep -qE '^- AC:$'; then
        # Multi-line AC header found, check for at least one sub-item
        if ! echo "${task_block}" | grep -qE '^  - .+'; then
            ERRORS+=("Task ${task_id}: AC section has no criteria (need '  - criterion')")
        fi
    elif echo "${task_block}" | grep -qE '^- AC: .+'; then
        # Single-line AC also accepted for backward compat
        true
    else
        ERRORS+=("Task ${task_id}: missing '- AC:' section")
    fi

    # Files
    if ! echo "${task_block}" | grep -qE '^- Files: .+'; then
        ERRORS+=("Task ${task_id}: missing '- Files: ...'")
    fi

    # Verify (backtick-wrapped)
    if ! echo "${task_block}" | grep -qE '^- Verify: `[^`]+`'; then
        ERRORS+=("Task ${task_id}: missing/invalid '- Verify: \`...\`'")
    fi

    # ══════════════════════════════════════════
    # LEVEL 1+ REQUIRED (optional at Level 0)
    # ══════════════════════════════════════════

    if [[ "${PROJECT_LEVEL}" -ge 1 ]]; then
        # Risk
        if ! echo "${task_block}" | grep -qiE '^- Risk: (low|medium|high)$'; then
            ERRORS+=("Task ${task_id}: missing/invalid '- Risk: low|medium|high'")
        fi

        # Max-iterations (hyphenated)
        if ! echo "${task_block}" | grep -qE '^- Max-iterations: [0-9]+$'; then
            # Also accept legacy unhyphenated for backward compat
            if ! echo "${task_block}" | grep -qE '^- Max iterations: [0-9]+$'; then
                ERRORS+=("Task ${task_id}: missing/invalid '- Max-iterations: N'")
            else
                WARNINGS+=("Task ${task_id}: '- Max iterations:' should be '- Max-iterations:' (hyphenated)")
            fi
        fi
    fi

    # ══════════════════════════════════════════
    # LEVEL 2+ REQUIRED
    # ══════════════════════════════════════════

    if [[ "${PROJECT_LEVEL}" -ge 2 ]]; then
        # Scope
        if ! echo "${task_block}" | grep -qiE '^- Scope: (code|infra|docs|config|multi-repo)$'; then
            ERRORS+=("Task ${task_id}: missing/invalid '- Scope: code|infra|docs|config|multi-repo'")
        fi

        # Wiring-proof (hyphenated)
        if ! echo "${task_block}" | grep -qE '^- Wiring-proof:'; then
            # Accept legacy unhyphenated
            if ! echo "${task_block}" | grep -qE '^- Wiring proof:'; then
                ERRORS+=("Task ${task_id}: missing '- Wiring-proof:' section")
            else
                WARNINGS+=("Task ${task_id}: '- Wiring proof:' should be '- Wiring-proof:' (hyphenated)")
            fi
        fi
    fi

    # ══════════════════════════════════════════
    # LEVEL 3+ REQUIRED
    # ══════════════════════════════════════════

    if [[ "${PROJECT_LEVEL}" -ge 3 ]]; then
        # File-ownership (hyphenated)
        local_has_ownership=false
        if echo "${task_block}" | grep -qE '^- File-ownership:'; then
            local_has_ownership=true
        elif echo "${task_block}" | grep -qE '^- File ownership:'; then
            local_has_ownership=true
            WARNINGS+=("Task ${task_id}: '- File ownership:' should be '- File-ownership:' (hyphenated)")
        fi

        if [[ "${local_has_ownership}" == false ]]; then
            ERRORS+=("Task ${task_id}: Level ${PROJECT_LEVEL} requires '- File-ownership:' section")
        else
            # owns: required
            if ! echo "${task_block}" | grep -qE '^[[:space:]]*- owns: \['; then
                ERRORS+=("Task ${task_id}: missing '- owns: [...]' in File-ownership")
            else
                # Collect owned files for SIGN-005
                owned_files=$(echo "${task_block}" | grep -oP '^\s*- owns: \[\K[^]]*' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    if [[ -n "${ALL_OWNS[${f}]:-}" ]]; then
                        ERRORS+=("SIGN-005 FAIL: File '${f}' owned by both Task ${ALL_OWNS[${f}]} and Task ${task_id}")
                    else
                        ALL_OWNS["${f}"]="${task_id}"
                    fi
                done <<< "${owned_files}"
            fi

            # touches: optional but checked for SIGN-005 warnings
            touched_files=$(echo "${task_block}" | grep -oP '^\s*- touches: \[\K[^]]*' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                if [[ -n "${ALL_TOUCHES[${f}]:-}" ]]; then
                    WARNINGS+=("SIGN-005 WARN: File '${f}' touched by both Task ${ALL_TOUCHES[${f}]} and Task ${task_id} — ensure sequential dependency")
                else
                    ALL_TOUCHES["${f}"]="${task_id}"
                fi
            done <<< "${touched_files}"

            # reads: accepted, no conflict check needed
            if ! echo "${task_block}" | grep -qE '^[[:space:]]*- reads: \['; then
                WARNINGS+=("Task ${task_id}: missing '- reads: [...]' in File-ownership (optional but recommended)")
            fi
        fi
    fi
done

# ══════════════════════════════════════════
# DEPENDENCY-AWARE TOUCHES SUPPRESSION
# ══════════════════════════════════════════

# Parse Sequential dependencies section for dependency chains (e.g., "001 -> 002")
declare -A SEQ_DEPS=()
seq_deps_line=$(grep -oP 'Sequential dependencies:\s*\K.*' "${PLAN_FILE}" 2>/dev/null || true)
if [[ -n "${seq_deps_line}" ]]; then
    # Extract all "NNN -> NNN" pairs (supports chains like "001 -> 002 -> 005")
    while read -r chain; do
        chain=$(echo "${chain}" | tr -d '[]' | sed 's/,//g')
        prev=""
        for node in ${chain}; do
            [[ "${node}" == "->" ]] && continue
            # Skip non-numeric tokens (e.g., "none", empty strings, punctuation)
            [[ ! "${node}" =~ ^[0-9]+$ ]] && continue
            node=$(printf '%03d' "$((10#${node}))")
            if [[ -n "${prev}" ]] && [[ -n "${node}" ]]; then
                SEQ_DEPS["${prev}->${node}"]=1
                SEQ_DEPS["${node}->${prev}"]=1
            fi
            prev="${node}"
        done
    done <<< "$(echo "${seq_deps_line}" | tr ',' '\n')"
fi

# Filter WARNINGS: suppress SIGN-005 touches WARN when sequential dependency covers the overlap
if [[ ${#WARNINGS[@]} -gt 0 ]] && [[ ${#SEQ_DEPS[@]} -gt 0 ]]; then
    declare -a FILTERED_WARNINGS=()
    for warn in "${WARNINGS[@]}"; do
        if echo "${warn}" | grep -q 'SIGN-005 WARN'; then
            # Extract the two task IDs from the warning
            task_a=$(echo "${warn}" | grep -oP 'Task \K[0-9]{3}' | head -1 || true)
            task_b=$(echo "${warn}" | grep -oP 'Task \K[0-9]{3}' | tail -1 || true)
            if [[ -n "${task_a}" ]] && [[ -n "${task_b}" ]] && [[ -n "${SEQ_DEPS["${task_a}->${task_b}"]:-}" ]]; then
                # Suppress — sequential dependency covers this overlap
                continue
            fi
        fi
        FILTERED_WARNINGS+=("${warn}")
    done
    WARNINGS=("${FILTERED_WARNINGS[@]+"${FILTERED_WARNINGS[@]}"}")
fi

# ══════════════════════════════════════════
# PLAN-LEVEL CHECKS
# ══════════════════════════════════════════

# Parallelism Assessment required at Level 3+
if [[ "${PROJECT_LEVEL}" -ge 3 ]]; then
    if ! grep -qE '^## Parallelism Assessment' "${PLAN_FILE}" 2>/dev/null; then
        ERRORS+=("Level ${PROJECT_LEVEL} requires '## Parallelism Assessment' section")
    fi
fi

# ── Output ──
if [[ ${#WARNINGS[@]} -gt 0 ]] && [[ "${QUIET}" == false ]]; then
    echo "Plan validation warnings (${#WARNINGS[@]}):" >&2
    for warn in "${WARNINGS[@]}"; do
        echo "  - ${warn}" >&2
    done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "Plan validation failed (${#ERRORS[@]} error(s)):" >&2
    for err in "${ERRORS[@]}"; do
        echo "  - ${err}" >&2
    done
    exit 1
fi

if [[ "${QUIET}" == false ]]; then
    echo "Plan validation passed: ${PLAN_FILE} (Level ${PROJECT_LEVEL}, ${#TASK_HEADERS[@]} tasks)"
fi
