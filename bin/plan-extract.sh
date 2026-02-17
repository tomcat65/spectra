#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Extractor — plan.md → plan.json
# Converts validated plan.md into a typed JSON intermediate representation.
# Pure bash — no jq dependency for generation (jq used only for optional validation).
#
# Usage: plan-extract.sh --file PATH [--output PATH] [--validate]
#
# Output: JSON array of task objects with typed fields.
# Schema: templates/plan-schema.json

PLAN_FILE=""
OUTPUT_FILE=""
VALIDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)    PLAN_FILE="$2"; shift 2 ;;
        --output)  OUTPUT_FILE="$2"; shift 2 ;;
        --validate) VALIDATE=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA Plan Extractor — plan.md → plan.json

Usage: plan-extract.sh --file PATH [--output PATH] [--validate]

Options:
  --file PATH     Input plan.md file (required)
  --output PATH   Output plan.json file (default: stdout)
  --validate      Validate output JSON with jq (requires jq)
  -h, --help      Show this help

Reads a validated plan.md and emits a JSON representation suitable
for consumption by parse_plan() in spectra-loop.sh.
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "${PLAN_FILE}" ]]; then
    echo "Error: --file is required" >&2
    exit 1
fi

if [[ ! -f "${PLAN_FILE}" ]]; then
    echo "Error: file not found: ${PLAN_FILE}" >&2
    exit 1
fi

# ══════════════════════════════════════════
# JSON HELPERS (pure bash, no jq needed)
# ══════════════════════════════════════════

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Emit a JSON string array from a comma-separated string.
# Empty input produces [].
json_string_array() {
    local csv="$1"
    if [[ -z "$csv" ]]; then
        printf '[]'
        return
    fi

    local first=true
    printf '['
    IFS=',' read -ra items <<< "$csv"
    for item in "${items[@]}"; do
        item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$item" ]] && continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$item")"
    done
    printf ']'
}

# Parse file list from bracket or bare format.
# Input: the raw line content after "owns: " / "touches: " / "reads: "
# Output: comma-separated file list (trimmed)
parse_file_list() {
    local raw="$1"
    # Bracket format: [file1, file2]
    if [[ "$raw" =~ ^\[([^]]*)\]$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    # Bare format: file1, file2
    # Strip leading [ and trailing ] if partial
    raw="${raw#\[}"
    raw="${raw%\]}"
    echo "$raw"
}

# ══════════════════════════════════════════
# EXTRACT PLAN HEADER
# ══════════════════════════════════════════

PLAN_PROJECT=""
PLAN_LEVEL=""
PLAN_GENERATED=""
PLAN_SOURCE=""

while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Project:\ (.+)$ ]]; then
        PLAN_PROJECT="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##\ Level:\ ([0-9]+)$ ]]; then
        PLAN_LEVEL="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##\ Generated:\ (.+)$ ]]; then
        PLAN_GENERATED="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##\ Source:\ (.+)$ ]]; then
        PLAN_SOURCE="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##\ Task\ [0-9]{3}: ]]; then
        break  # Stop at first task
    fi
done < "${PLAN_FILE}"

PLAN_LEVEL="${PLAN_LEVEL:-1}"

# ══════════════════════════════════════════
# PARSE TASKS
# ══════════════════════════════════════════

current_task=""
current_idx=-1
line_num=0

# Per-task accumulators
declare -a T_IDS=()
declare -a T_TITLES=()
declare -a T_STATUS=()
declare -a T_RISK=()
declare -a T_VERIFY=()
declare -a T_MAX_ITER=()
declare -a T_OWNS=()
declare -a T_TOUCHES=()
declare -a T_READS=()
declare -a T_DEPS=()
declare -a T_LINES=()
declare -a T_SCOPE=()
declare -a T_FILES=()
declare -a T_AC=()

in_ac=false

while IFS= read -r line; do
    line_num=$((line_num + 1))

    # Detect task section header: ## Task NNN: Title
    if [[ "$line" =~ ^##\ Task\ ([0-9]{3}):\ (.+)$ ]]; then
        in_ac=false
        current_task="${BASH_REMATCH[1]}"
        current_idx=${#T_IDS[@]}

        T_IDS+=("$current_task")
        T_TITLES+=("${BASH_REMATCH[2]}")
        T_STATUS+=("pending")
        T_RISK+=("medium")
        T_VERIFY+=("")
        T_MAX_ITER+=("5")
        T_OWNS+=("")
        T_TOUCHES+=("")
        T_READS+=("")
        T_DEPS+=("")
        T_LINES+=("0")
        T_SCOPE+=("")
        T_FILES+=("")
        T_AC+=("")
        continue
    fi

    # Skip if not inside a task section
    if [[ $current_idx -lt 0 ]]; then
        continue
    fi

    # Detect checkbox: - [x] NNN: or - [ ] NNN: or - [!] NNN:
    if [[ "$line" =~ ^-\ \[([xX!\ ])\]\ ${T_IDS[$current_idx]}: ]]; then
        local_mark="${BASH_REMATCH[1]}"
        T_LINES[$current_idx]="$line_num"
        case "$local_mark" in
            x|X) T_STATUS[$current_idx]="complete" ;;
            '!') T_STATUS[$current_idx]="stuck" ;;
            ' ') T_STATUS[$current_idx]="pending" ;;
        esac
        continue
    fi

    # Parse Risk (case-insensitive, normalize to lowercase)
    if [[ "${line,,}" =~ ^-\ risk:\ *(high|medium|low) ]]; then
        T_RISK[$current_idx]="${BASH_REMATCH[1]}"
        in_ac=false
        continue
    fi

    # Parse Verify command (between backticks)
    if [[ "$line" =~ ^-\ Verify:\ \`(.+)\`$ ]]; then
        T_VERIFY[$current_idx]="${BASH_REMATCH[1]}"
        in_ac=false
        continue
    fi

    # Parse Max-iterations
    if [[ "$line" =~ ^-\ Max-iterations:\ *([0-9]+) ]] || [[ "$line" =~ ^-\ Max\ iterations:\ *([0-9]+) ]]; then
        T_MAX_ITER[$current_idx]="${BASH_REMATCH[1]}"
        in_ac=false
        continue
    fi

    # Parse Scope
    if [[ "${line,,}" =~ ^-\ scope:\ *(code|infra|docs|config|multi-repo) ]]; then
        T_SCOPE[$current_idx]="${BASH_REMATCH[1]}"
        in_ac=false
        continue
    fi

    # Parse Files
    if [[ "$line" =~ ^-\ Files:\ (.+)$ ]]; then
        T_FILES[$current_idx]="${BASH_REMATCH[1]}"
        in_ac=false
        continue
    fi

    # Parse AC header
    if [[ "$line" =~ ^-\ AC: ]]; then
        in_ac=true
        continue
    fi

    # Parse AC sub-items
    if [[ "$in_ac" == true ]] && [[ "$line" =~ ^\ \ -\ (.+)$ ]]; then
        local_ac="${BASH_REMATCH[1]}"
        if [[ -n "${T_AC[$current_idx]}" ]]; then
            T_AC[$current_idx]="${T_AC[$current_idx]}|||${local_ac}"
        else
            T_AC[$current_idx]="${local_ac}"
        fi
        continue
    fi

    # Exit AC on non-sub-item line
    if [[ "$in_ac" == true ]] && [[ ! "$line" =~ ^\ \ - ]]; then
        in_ac=false
    fi

    # Parse File-ownership owns (bracket format)
    if [[ "$line" =~ ^[[:space:]]*-\ owns:\ (.+)$ ]]; then
        T_OWNS[$current_idx]=$(parse_file_list "${BASH_REMATCH[1]}")
        continue
    fi

    # Parse File-ownership touches (bracket format)
    if [[ "$line" =~ ^[[:space:]]*-\ touches:\ (.+)$ ]]; then
        T_TOUCHES[$current_idx]=$(parse_file_list "${BASH_REMATCH[1]}")
        continue
    fi

    # Parse File-ownership reads (bracket format)
    if [[ "$line" =~ ^[[:space:]]*-\ reads:\ (.+)$ ]]; then
        T_READS[$current_idx]=$(parse_file_list "${BASH_REMATCH[1]}")
        continue
    fi

    # Parse Dependencies line: - Dependencies: Task 001, Task 003
    if [[ "$line" =~ ^-\ Dependencies: ]]; then
        local_dep_str="${line#*Dependencies:}"
        local_deps=""
        while [[ "$local_dep_str" =~ ([0-9]{3}) ]]; do
            local_dep_id="${BASH_REMATCH[1]}"
            if [[ "$local_dep_id" != "${T_IDS[$current_idx]}" ]]; then
                if [[ -n "$local_deps" ]]; then
                    local_deps="${local_deps},${local_dep_id}"
                else
                    local_deps="${local_dep_id}"
                fi
            fi
            local_dep_str="${local_dep_str#*${BASH_REMATCH[1]}}"
        done
        T_DEPS[$current_idx]="$local_deps"
        continue
    fi

done < "${PLAN_FILE}"

# ══════════════════════════════════════════
# PARSE DEPENDENCY GRAPH SECTION
# ══════════════════════════════════════════

in_dep_section=false

while IFS= read -r line; do
    # Enter dependency graph section (accept both headers)
    if [[ "$line" == "## Dependency Graph" ]] || [[ "$line" == "## Parallelism Assessment" ]]; then
        in_dep_section=true
        continue
    fi

    # Exit on next section
    if [[ "$in_dep_section" == true ]] && [[ "$line" =~ ^## ]] && [[ "$line" != "## Dependency Graph" ]] && [[ "$line" != "## Parallelism Assessment" ]]; then
        break
    fi

    if [[ "$in_dep_section" != true ]]; then
        continue
    fi

    # Normalize Unicode arrows to ASCII
    local_norm="${line//→/->}"

    # Parse chain notation: NNN -> NNN (-> NNN ...)
    if [[ "$local_norm" =~ ([0-9]{3}(\ *-\>\ *[0-9]{3})+) ]]; then
        local_chain="${BASH_REMATCH[1]}"
        declare -a chain_ids=()
        while [[ "$local_chain" =~ ([0-9]{3}) ]]; do
            chain_ids+=("${BASH_REMATCH[1]}")
            local_chain="${local_chain#*${BASH_REMATCH[1]}}"
        done

        # Build dependencies: each task depends on the previous
        for ((ci=1; ci<${#chain_ids[@]}; ci++)); do
            local_dep="${chain_ids[$((ci-1))]}"
            local_tid="${chain_ids[$ci]}"

            # Find index for task_id
            for ((cj=0; cj<${#T_IDS[@]}; cj++)); do
                if [[ "${T_IDS[$cj]}" == "$local_tid" ]]; then
                    if [[ -n "${T_DEPS[$cj]}" ]]; then
                        # Avoid duplicate deps
                        if [[ ",${T_DEPS[$cj]}," != *",${local_dep},"* ]]; then
                            T_DEPS[$cj]="${T_DEPS[$cj]},${local_dep}"
                        fi
                    else
                        T_DEPS[$cj]="$local_dep"
                    fi
                    break
                fi
            done
        done
        unset chain_ids
    fi

    # Parse "depends on all above"
    if [[ "$line" =~ Task\ ([0-9]{3}).*depends\ on\ all ]]; then
        local_capstone="${BASH_REMATCH[1]}"
        for ((cj=0; cj<${#T_IDS[@]}; cj++)); do
            if [[ "${T_IDS[$cj]}" == "$local_capstone" ]]; then
                local_all_deps=""
                for ((ck=0; ck<${#T_IDS[@]}; ck++)); do
                    if [[ "${T_IDS[$ck]}" != "$local_capstone" ]]; then
                        local_all_deps="${local_all_deps:+${local_all_deps},}${T_IDS[$ck]}"
                    fi
                done
                T_DEPS[$cj]="$local_all_deps"
                break
            fi
        done
    # Parse "Task NNN depends on NNN, NNN, NNN" (explicit list)
    elif [[ "$line" =~ Task\ ([0-9]{3}).*depends\ on\ ([0-9]{3}(,\ *[0-9]{3})*) ]]; then
        local_target="${BASH_REMATCH[1]}"
        local_dep_list_str="${BASH_REMATCH[2]}"
        for ((cj=0; cj<${#T_IDS[@]}; cj++)); do
            if [[ "${T_IDS[$cj]}" == "$local_target" ]]; then
                IFS=',' read -ra explicit_deps <<< "$local_dep_list_str"
                for dep in "${explicit_deps[@]}"; do
                    dep=$(echo "$dep" | tr -d ' ')
                    [[ -z "$dep" ]] && continue
                    if [[ -n "${T_DEPS[$cj]}" ]]; then
                        # Avoid duplicate deps
                        if [[ ",${T_DEPS[$cj]}," != *",${dep},"* ]]; then
                            T_DEPS[$cj]="${T_DEPS[$cj]},${dep}"
                        fi
                    else
                        T_DEPS[$cj]="${dep}"
                    fi
                done
                break
            fi
        done
    fi

done < "${PLAN_FILE}"

# ══════════════════════════════════════════
# COMPUTE SOURCE HASH (for freshness gate in spectra-loop.sh)
# ══════════════════════════════════════════

SOURCE_HASH=$(sha256sum "${PLAN_FILE}" 2>/dev/null | cut -d' ' -f1 || echo "")

# ══════════════════════════════════════════
# EMIT JSON
# ══════════════════════════════════════════

emit_json() {
    printf '{\n'
    printf '  "version": "1.0",\n'
    printf '  "source_hash": "%s",\n' "${SOURCE_HASH}"
    printf '  "project": "%s",\n' "$(json_escape "${PLAN_PROJECT}")"
    printf '  "level": %s,\n' "${PLAN_LEVEL}"
    printf '  "generated": "%s",\n' "$(json_escape "${PLAN_GENERATED}")"
    printf '  "source": "%s",\n' "$(json_escape "${PLAN_SOURCE}")"
    printf '  "tasks": [\n'

    for ((i=0; i<${#T_IDS[@]}; i++)); do
        if [[ $i -gt 0 ]]; then
            printf ',\n'
        fi

        # Build AC array
        local ac_json="[]"
        if [[ -n "${T_AC[$i]}" ]]; then
            ac_json="["
            local ac_first=true
            IFS='|||' read -ra ac_items <<< "${T_AC[$i]}"
            for ac_item in "${ac_items[@]}"; do
                [[ -z "$ac_item" ]] && continue
                if [[ "$ac_first" == true ]]; then
                    ac_first=false
                else
                    ac_json="${ac_json}, "
                fi
                ac_json="${ac_json}\"$(json_escape "$ac_item")\""
            done
            ac_json="${ac_json}]"
        fi

        printf '    {\n'
        printf '      "id": "%s",\n' "${T_IDS[$i]}"
        printf '      "title": "%s",\n' "$(json_escape "${T_TITLES[$i]}")"
        printf '      "status": "%s",\n' "${T_STATUS[$i]}"
        printf '      "risk": "%s",\n' "${T_RISK[$i]}"
        printf '      "verify": "%s",\n' "$(json_escape "${T_VERIFY[$i]}")"
        printf '      "max_iterations": %s,\n' "${T_MAX_ITER[$i]}"
        printf '      "owns": %s,\n' "$(json_string_array "${T_OWNS[$i]}")"
        printf '      "touches": %s,\n' "$(json_string_array "${T_TOUCHES[$i]}")"
        printf '      "reads": %s,\n' "$(json_string_array "${T_READS[$i]}")"
        printf '      "deps": %s,\n' "$(json_string_array "${T_DEPS[$i]}")"
        printf '      "line_number": %s,\n' "${T_LINES[$i]}"
        printf '      "scope": "%s",\n' "$(json_escape "${T_SCOPE[$i]}")"
        printf '      "files": "%s",\n' "$(json_escape "${T_FILES[$i]}")"
        printf '      "ac": %s\n' "${ac_json}"
        printf '    }'
    done

    printf '\n  ]\n'
    printf '}\n'
}

# Route output
if [[ -n "${OUTPUT_FILE}" ]]; then
    emit_json > "${OUTPUT_FILE}"
else
    emit_json
fi

# Optional validation
if [[ "$VALIDATE" == true ]]; then
    if command -v jq &>/dev/null; then
        if [[ -n "${OUTPUT_FILE}" ]]; then
            if jq empty "${OUTPUT_FILE}" 2>/dev/null; then
                echo "JSON validation: PASS" >&2
            else
                echo "JSON validation: FAIL" >&2
                exit 1
            fi
        else
            echo "JSON validation: skipped (--validate requires --output)" >&2
        fi
    else
        echo "JSON validation: skipped (jq not installed)" >&2
    fi
fi
