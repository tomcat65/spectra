#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v5.0 Execution Loop — Bash-Native Parallel Architecture ║
# ║  Heritage: v2.0 sequential engine (removed in v5.0)              ║
# ║  New: parse_plan(), next_batch(), parallel_build(), checkpoint   ║
# ║  Architecture: Bash orchestrates. LLMs are workers.              ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-loop-v5 [--plan-only] [--skip-planning] [--resume] [--dry-run]
#                        [--cost-ceiling N] [--risk-first] [--max-batch N]
#
# Pipeline: Plan → Review → [Lock] → For each batch: Audit → Build (parallel) → Verify (sequential)
#           On FAIL: retry with diminishing budget + oracle classification
#           On COMPLETE: PR review → signal
#           On STUCK: halt immediately
#
# KEY DIFFERENCE FROM v4.1:
#   v4.1 put orchestration INTO an LLM (spectra-lead agent, 47KB prompt, 200 turns of Opus bookkeeping)
#   v5.0 keeps orchestration IN BASH. LLMs only do: build, verify, classify, review.
#   Prompts are <500 bytes. Agents read from disk. Checkpoint enables deterministic resume.

SPECTRA_HOME="${HOME}/.spectra"
SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
LOGS_DIR="${SPECTRA_DIR}/logs"
PLAN_VALIDATOR="${SPECTRA_HOME}/bin/spectra-plan-validate.sh"
# RATIONALE: CHECKPOINT_FILE is read by write_checkpoint()/restore_checkpoint() in loop-checkpoint module
# shellcheck disable=SC2034
CHECKPOINT_FILE="${SIGNALS_DIR}/CHECKPOINT"

# ── Source modules (explicit ordered list — no wildcards) ──
source "${SPECTRA_HOME}/lib/loop-signals.sh"
source "${SPECTRA_HOME}/lib/loop-retry.sh"
source "${SPECTRA_HOME}/lib/loop-wiring.sh"
source "${SPECTRA_HOME}/lib/loop-git.sh"
source "${SPECTRA_HOME}/lib/loop-checkpoint.sh"
source "${SPECTRA_HOME}/lib/loop-build.sh"
source "${SPECTRA_HOME}/lib/loop-verify.sh"

# ── Defaults ──
PLAN_ONLY=false
SKIP_PLANNING=false
RESUME=false
DRY_RUN=false
COST_CEILING=""
RISK_FIRST=false
MAX_BATCH_SIZE=4
MAX_TASKS=50
# RATIONALE: BUILDER_TIMEOUT is read by parallel_build() in loop-build module
# shellcheck disable=SC2034
BUILDER_TIMEOUT=600  # seconds per builder invocation (default 10 min)
START_TIME=$(date +%s)
ELAPSED_OFFSET=0

# ── Plan arrays (populated by parse_plan) ──
TASK_IDS=()
TASK_TITLES=()
TASK_STATUS=()    # pending|complete|stuck
TASK_RISKS=()     # high|medium|low
TASK_OWNS=()      # comma-separated owned files
TASK_TOUCHES=()   # comma-separated touched files
TASK_VERIFY=()    # verify command
TASK_MAX_ITER=()  # max iterations per task
TASK_LINES=()     # line number of checkbox in plan.md
TASK_DEPS=()      # comma-separated dependency task IDs
TASK_READS=()     # comma-separated read-only files

PASS_HISTORY=""
BRANCH_NAME=""

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan-only)     PLAN_ONLY=true; shift ;;
        --skip-planning) SKIP_PLANNING=true; shift ;;
        --resume)        RESUME=true; SKIP_PLANNING=true; shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --risk-first)    RISK_FIRST=true; shift ;;
        --cost-ceiling)  COST_CEILING="$2"; shift 2 ;;
        --max-batch)     MAX_BATCH_SIZE="$2"; shift 2 ;;
        --builder-timeout)
            # RATIONALE: BUILDER_TIMEOUT is read by parallel_build() in loop-build module
            # shellcheck disable=SC2034
            BUILDER_TIMEOUT="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA v5.0 Execution Loop — Bash-Native Parallel Architecture

Usage: spectra-loop-v5 [OPTIONS]

Options:
  --plan-only       Run planning + review gate only, then exit
  --skip-planning   Skip to execution (plan already approved)
  --resume          Resume from checkpoint (deterministic, no LLM involvement)
  --dry-run         Print what would be executed without spawning agents
  --risk-first      Execute high-risk tasks first (default on for Level 2+)
  --cost-ceiling N  Override cost ceiling from project.yaml (USD)
  --max-batch N     Max parallel builders per batch (default: 4, Level 0-2 forces 1)
  --builder-timeout N  Seconds before killing a hung builder (default: 600)
  -h, --help        Show this help

Architecture (v5.0):
  Bash is the orchestrator. LLMs are workers.
  - Planner (Opus)  — generates plan artifacts
  - Reviewer (Sonnet) — validates plan + final PR review
  - Auditor (Haiku) — pre-flight Sign scanning
  - Builder (Opus)  — implements tasks (parallel for independent tasks)
  - Verifier (Opus) — audits tasks (always sequential)
  - Oracle (Haiku)  — 3-turn failure classifier

  Prompts: <500 bytes. Agents read context from disk.
  Resume:  Deterministic. Read JSON checkpoint, set arrays, go.
  Parallel: background processes + wait. No coordination protocol.
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Source env ──
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# ── Verify project ──
if [[ ! -d "${SPECTRA_DIR}" ]]; then
    echo "Error: No .spectra/ directory found. Run 'spectra-init' first."
    exit 1
fi

# ── Ensure directories ──
mkdir -p "${SIGNALS_DIR}" "${LOGS_DIR}"

# ── Cost ceiling from project.yaml or override ──
if [[ -z "$COST_CEILING" ]] && [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
    COST_CEILING=$(grep 'ceiling:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "50.00")
fi
COST_CEILING="${COST_CEILING:-50.00}"

# ── Project level ──
PROJECT_LEVEL="1"
if [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
    PROJECT_LEVEL=$(grep 'level:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | grep -oP '\d+' || echo "1")
fi

# Force batch=1 for Level 0-2
if [[ "$PROJECT_LEVEL" -le 2 ]]; then
    MAX_BATCH_SIZE=1
fi

# Auto-enable risk-first for Level 2+
if [[ "$PROJECT_LEVEL" -ge 2 ]] && [[ "$RISK_FIRST" == false ]]; then
    RISK_FIRST=true
fi

# ══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS (carried from legacy)
# ══════════════════════════════════════════════════════════════

sed_inplace() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

elapsed() {
    local now
    now=$(date +%s)
    local diff=$(( (now - START_TIME) + ELAPSED_OFFSET ))
    printf '%02d:%02d:%02d' $((diff/3600)) $(((diff%3600)/60)) $((diff%60))
}

elapsed_seconds() {
    local now
    now=$(date +%s)
    echo $(( (now - START_TIME) + ELAPSED_OFFSET ))
}

## Functions extracted to lib/loop-signals.sh:
## write_status(), write_batch_status(), signal_stuck(), write_signal(),
## write_progress(), signal_complete(), write_final_report()

validate_plan_contract() {
    if [[ ! -f "${SPECTRA_DIR}/plan.md" ]]; then
        echo "Error: No plan.md found. Cannot execute."
        return 1
    fi

    if [[ -x "${PLAN_VALIDATOR}" ]]; then
        if ! "${PLAN_VALIDATOR}" --file "${SPECTRA_DIR}/plan.md" --quiet; then
            echo "Error: plan.md failed schema validation."
            echo "  Fix .spectra/plan.md or regenerate with 'spectra-plan'."
            return 1
        fi
    fi

    return 0
}

## signal_complete(), write_final_report() — extracted to lib/loop-signals.sh

refresh_claude_md() {
    local project_name level signs plan_status
    project_name=$(grep 'name:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | sed 's/name: *//' || echo "unknown")
    level=$(grep 'level:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | grep -oP '\d+' || echo "1")

    signs=""
    if [[ -f "${SPECTRA_DIR}/guardrails.md" ]]; then
        signs=$(grep -E "^### SIGN-|^> " "${SPECTRA_DIR}/guardrails.md" 2>/dev/null | head -20 || echo "None defined")
    fi

    plan_status=""
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        plan_status=$(grep -E '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | head -20 || echo "No tasks")
    fi

    cat > CLAUDE.md <<EOF
# CLAUDE.md — SPECTRA Context (auto-generated, do not edit)

## SPECTRA Context
- Project: ${project_name}
- Level: ${level}
- Phase: execution
- Branch: ${BRANCH_NAME}

## Active Signs
${signs}

## Non-Goals
$(cat "${SPECTRA_DIR}/non-goals.md" 2>/dev/null || echo "None defined")

## Wiring Proof
All tasks require 5-check wiring proof before commit:
1. CLI paths — subprocess-level tests
2. Import invocation — no dead imports
3. Pipeline completeness — full chain tested
4. Error boundaries — clean messages, no tracebacks
5. Dependencies declared — all imports in requirements

## Evidence Chain
- Commits: feat(task-N) or fix(task-N)
- Reports: .spectra/logs/task-N-{build|verify|preflight}.md

## Plan Status
${plan_status}
EOF
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        git add CLAUDE.md 2>/dev/null || true
    fi
}

## Functions extracted to lib/loop-retry.sh:
## propagate_signs(), generate_task_summary(), max_retries_for()

count_tasks() {
    local total completed stuck remaining
    total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    total=${total:-0}
    completed=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    completed=${completed:-0}
    stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    stuck=${stuck:-0}
    if [[ "$total" -eq 0 ]]; then
        total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        total=${total:-0}
        completed=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        completed=${completed:-0}
        stuck=0
    fi
    remaining=$((total - completed - stuck))
    echo "${total} ${completed} ${remaining} ${stuck}"
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: PLAN PARSER
# ══════════════════════════════════════════════════════════════

parse_plan() {
    local plan="${SPECTRA_DIR}/plan.md"
    local plan_json="${SPECTRA_DIR}/plan.json"

    if [[ ! -f "$plan" ]]; then
        echo "Error: No plan.md found."
        return 1
    fi

    # Reset arrays
    TASK_IDS=()
    TASK_TITLES=()
    TASK_STATUS=()
    TASK_RISKS=()
    TASK_OWNS=()
    TASK_TOUCHES=()
    TASK_READS=()
    TASK_VERIFY=()
    TASK_MAX_ITER=()
    TASK_LINES=()
    TASK_DEPS=()

    # Fast path: if plan.json exists, is fresh, and jq is available, use JSON
    if [[ -f "$plan_json" ]] && command -v jq &>/dev/null; then
        # Freshness gate: plan.json must embed a source_hash matching plan.md's current hash.
        # Fall back to strict mtime (json > md, not >=) if source_hash is absent.
        local json_fresh=false
        local md_hash json_source_hash
        md_hash=$(sha256sum "$plan" 2>/dev/null | cut -d' ' -f1 || echo "")
        json_source_hash=$(jq -r '.source_hash // empty' "$plan_json" 2>/dev/null || echo "")

        if [[ -n "$md_hash" ]] && [[ -n "$json_source_hash" ]]; then
            # Hash-based freshness (strongest)
            if [[ "$json_source_hash" == "$md_hash" ]]; then
                json_fresh=true
            fi
        elif [[ -n "$md_hash" ]] && [[ -z "$json_source_hash" ]]; then
            # No source_hash in JSON — fall back to strict mtime (json strictly newer)
            local md_mtime json_mtime
            md_mtime=$(stat -c %Y "$plan" 2>/dev/null || stat -f %m "$plan" 2>/dev/null || echo "0")
            json_mtime=$(stat -c %Y "$plan_json" 2>/dev/null || stat -f %m "$plan_json" 2>/dev/null || echo "0")
            if [[ "$json_mtime" -gt "$md_mtime" ]]; then
                json_fresh=true
            fi
        fi

        if [[ "$json_fresh" == true ]]; then
            if parse_plan_from_json "$plan_json"; then
                echo "  Parsed ${#TASK_IDS[@]} tasks from plan.json (jq fast path)"
                return 0
            else
                echo "  Warning: plan.json parse failed, falling back to markdown"
            fi
        else
            echo "  Warning: plan.json is stale (does not match plan.md), using markdown path"
        fi
    fi

    # Fallback: parse from markdown
    parse_plan_from_markdown
    echo "  Parsed ${#TASK_IDS[@]} tasks from plan.md"
    return 0
}

parse_plan_from_json() {
    local json_file="$1"
    local task_count

    # Validate JSON is parseable
    if ! jq empty "$json_file" 2>/dev/null; then
        echo "  Warning: plan.json is not valid JSON" >&2
        return 1
    fi

    # Validate required top-level structure
    task_count=$(jq '.tasks | length' "$json_file" 2>/dev/null) || return 1
    if [[ -z "$task_count" ]] || [[ "$task_count" -eq 0 ]]; then
        return 1
    fi

    # Validate schema version (must be exactly "1.0")
    local version
    version=$(jq -r '.version // empty' "$json_file" 2>/dev/null) || return 1
    if [[ "$version" != "1.0" ]]; then
        echo "  Warning: plan.json has unsupported version: '${version}' (expected '1.0')" >&2
        return 1
    fi

    # Validate each task has required fields before populating arrays
    for ((i=0; i<task_count; i++)); do
        local tid ttitle tstatus trisk tline tmax
        tid=$(jq -r ".tasks[$i].id // empty" "$json_file" 2>/dev/null) || return 1
        ttitle=$(jq -r ".tasks[$i].title // empty" "$json_file" 2>/dev/null) || return 1
        tstatus=$(jq -r ".tasks[$i].status // empty" "$json_file" 2>/dev/null) || return 1
        tline=$(jq -r ".tasks[$i].line_number // empty" "$json_file" 2>/dev/null) || return 1

        # Required fields must be non-empty
        if [[ -z "$tid" ]] || [[ -z "$ttitle" ]] || [[ -z "$tstatus" ]] || [[ -z "$tline" ]]; then
            echo "  Warning: plan.json task $i missing required field (id/title/status/line_number)" >&2
            return 1
        fi

        # Validate line_number is a non-negative integer
        if [[ ! "$tline" =~ ^[0-9]+$ ]]; then
            echo "  Warning: plan.json task $i has non-integer line_number: $tline" >&2
            return 1
        fi

        # Validate id format (3-digit)
        if [[ ! "$tid" =~ ^[0-9]{3}$ ]]; then
            echo "  Warning: plan.json task $i has invalid id format: $tid" >&2
            return 1
        fi

        # Validate status enum
        if [[ "$tstatus" != "pending" ]] && [[ "$tstatus" != "complete" ]] && [[ "$tstatus" != "stuck" ]]; then
            echo "  Warning: plan.json task $i has invalid status: $tstatus" >&2
            return 1
        fi

        # Validate risk enum (with fallback default)
        trisk=$(jq -r ".tasks[$i].risk // \"medium\"" "$json_file" 2>/dev/null)
        if [[ "$trisk" != "low" ]] && [[ "$trisk" != "medium" ]] && [[ "$trisk" != "high" ]]; then
            echo "  Warning: plan.json task $i has invalid risk: $trisk" >&2
            return 1
        fi

        # Validate max_iterations is a positive integer
        tmax=$(jq -r ".tasks[$i].max_iterations // 5" "$json_file" 2>/dev/null)
        if [[ ! "$tmax" =~ ^[0-9]+$ ]] || [[ "$tmax" -eq 0 ]]; then
            echo "  Warning: plan.json task $i has invalid max_iterations: $tmax" >&2
            return 1
        fi

        # Validate arrays are actually arrays (not null or string)
        for arr_field in owns touches reads deps; do
            local arr_type
            arr_type=$(jq -r ".tasks[$i].${arr_field} | type" "$json_file" 2>/dev/null) || return 1
            if [[ "$arr_type" != "array" ]]; then
                echo "  Warning: plan.json task $i.${arr_field} is not an array (got: $arr_type)" >&2
                return 1
            fi
        done
    done

    # All validation passed — populate arrays
    for ((i=0; i<task_count; i++)); do
        TASK_IDS+=("$(jq -r ".tasks[$i].id" "$json_file")")
        TASK_TITLES+=("$(jq -r ".tasks[$i].title" "$json_file")")
        TASK_STATUS+=("$(jq -r ".tasks[$i].status" "$json_file")")
        TASK_RISKS+=("$(jq -r ".tasks[$i].risk // \"medium\"" "$json_file")")
        TASK_OWNS+=("$(jq -r '.tasks['"$i"'].owns | join(",")' "$json_file")")
        TASK_TOUCHES+=("$(jq -r '.tasks['"$i"'].touches | join(",")' "$json_file")")
        TASK_READS+=("$(jq -r '.tasks['"$i"'].reads | join(",")' "$json_file")")
        TASK_VERIFY+=("$(jq -r ".tasks[$i].verify // \"\"" "$json_file")")
        TASK_MAX_ITER+=("$(jq -r ".tasks[$i].max_iterations // 5" "$json_file")")
        TASK_LINES+=("$(jq -r ".tasks[$i].line_number // 0" "$json_file")")
        TASK_DEPS+=("$(jq -r '.tasks['"$i"'].deps | join(",")' "$json_file")")
    done

    return 0
}

parse_plan_from_markdown() {
    local plan="${SPECTRA_DIR}/plan.md"
    local current_task="" current_idx=-1
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Detect task section header: ## Task NNN: Title
        if [[ "$line" =~ ^##\ Task\ ([0-9]{3}):\ (.+)$ ]]; then
            current_task="${BASH_REMATCH[1]}"
            local title="${BASH_REMATCH[2]}"
            current_idx=${#TASK_IDS[@]}

            TASK_IDS+=("$current_task")
            TASK_TITLES+=("$title")
            TASK_STATUS+=("pending")  # default, updated below
            TASK_RISKS+=("medium")    # default
            TASK_OWNS+=("")
            TASK_TOUCHES+=("")
            TASK_READS+=("")
            TASK_VERIFY+=("")
            TASK_MAX_ITER+=("5")      # default
            TASK_LINES+=("0")         # updated when checkbox found
            TASK_DEPS+=("")
            continue
        fi

        # Skip if not inside a task section
        if [[ $current_idx -lt 0 ]]; then
            continue
        fi

        # Detect checkbox and status: - [x] NNN: or - [ ] NNN: or - [!] NNN:
        if [[ "$line" =~ ^-\ \[([xX!\ ])\]\ ${TASK_IDS[$current_idx]}: ]]; then
            local mark="${BASH_REMATCH[1]}"
            TASK_LINES[$current_idx]="$line_num"
            case "$mark" in
                x|X) TASK_STATUS[$current_idx]="complete" ;;
                '!') TASK_STATUS[$current_idx]="stuck" ;;
                ' ') TASK_STATUS[$current_idx]="pending" ;;
            esac
            continue
        fi

        # Parse Risk (case-insensitive: normalize to lowercase)
        if [[ "${line,,}" =~ ^-\ risk:\ *(high|medium|low) ]]; then
            TASK_RISKS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse Verify command (between backticks)
        if [[ "$line" =~ ^-\ Verify:\ \`(.+)\`$ ]]; then
            TASK_VERIFY[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse Max-iterations (accept both hyphenated and unhyphenated)
        if [[ "$line" =~ ^-\ Max-iterations:\ *([0-9]+) ]] || [[ "$line" =~ ^-\ Max\ iterations:\ *([0-9]+) ]]; then
            TASK_MAX_ITER[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse File-ownership owns (bracket format, then bare fallback)
        if [[ "$line" =~ owns:\ *\[([^]]*)\] ]]; then
            TASK_OWNS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        elif [[ "$line" =~ ^[[:space:]]*-\ owns:\ +(.+)$ ]] && [[ ! "$line" =~ \[ ]]; then
            TASK_OWNS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse File-ownership touches (bracket format, then bare fallback)
        if [[ "$line" =~ touches:\ *\[([^]]*)\] ]]; then
            TASK_TOUCHES[$current_idx]="${BASH_REMATCH[1]}"
            continue
        elif [[ "$line" =~ ^[[:space:]]*-\ touches:\ +(.+)$ ]] && [[ ! "$line" =~ \[ ]]; then
            TASK_TOUCHES[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse File-ownership reads (bracket format, then bare fallback)
        if [[ "$line" =~ reads:\ *\[([^]]*)\] ]]; then
            TASK_READS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        elif [[ "$line" =~ ^[[:space:]]*-\ reads:\ +(.+)$ ]] && [[ ! "$line" =~ \[ ]]; then
            TASK_READS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse Dependencies line: - Dependencies: Task 001, Task 003 (or just 001, 003)
        if [[ "$line" =~ ^-\ Dependencies: ]]; then
            local dep_str="${line#*Dependencies:}"
            while [[ "$dep_str" =~ ([0-9]{3}) ]]; do
                local dep_id="${BASH_REMATCH[1]}"
                if [[ "$dep_id" != "${TASK_IDS[$current_idx]}" ]]; then
                    if [[ -n "${TASK_DEPS[$current_idx]}" ]]; then
                        TASK_DEPS[$current_idx]="${TASK_DEPS[$current_idx]},${dep_id}"
                    else
                        TASK_DEPS[$current_idx]="${dep_id}"
                    fi
                fi
                dep_str="${dep_str#*${BASH_REMATCH[1]}}"
            done
            continue
        fi

    done < "$plan"

    # ── Parse Dependency Graph section ──
    parse_dependencies
}

parse_dependencies() {
    local plan="${SPECTRA_DIR}/plan.md"
    local in_dep_graph=false

    while IFS= read -r line; do
        # Enter dependency graph section (accept both headers)
        if [[ "$line" == "## Dependency Graph" ]] || [[ "$line" == "## Parallelism Assessment" ]]; then
            in_dep_graph=true
            continue
        fi

        # Exit on next section (but not on the alternate header)
        if [[ "$in_dep_graph" == true ]] && [[ "$line" =~ ^## ]] && [[ "$line" != "## Dependency Graph" ]] && [[ "$line" != "## Parallelism Assessment" ]]; then
            break
        fi

        if [[ "$in_dep_graph" != true ]]; then
            continue
        fi

        # Normalize Unicode arrows to ASCII for consistent parsing
        local norm_line="${line//→/->}"

        # Parse chain notation: any line with 001 -> 002 (-> 003 ...) chains
        if [[ "$norm_line" =~ ([0-9]{3}(\ *-\>\ *[0-9]{3})+) ]]; then
            local chain="${BASH_REMATCH[1]}"
            # Split on arrow
            local -a chain_ids=()
            while [[ "$chain" =~ ([0-9]{3}) ]]; do
                chain_ids+=("${BASH_REMATCH[1]}")
                chain="${chain#*${BASH_REMATCH[1]}}"
            done

            # Build dependencies: each task depends on the previous
            for ((i=1; i<${#chain_ids[@]}; i++)); do
                local dep_id="${chain_ids[$((i-1))]}"
                local task_id="${chain_ids[$i]}"

                # Find index for task_id
                for ((j=0; j<${#TASK_IDS[@]}; j++)); do
                    if [[ "${TASK_IDS[$j]}" == "$task_id" ]]; then
                        if [[ -n "${TASK_DEPS[$j]}" ]]; then
                            TASK_DEPS[$j]="${TASK_DEPS[$j]},${dep_id}"
                        else
                            TASK_DEPS[$j]="$dep_id"
                        fi
                        break
                    fi
                done
            done
        fi

        # Parse "depends on all above"
        if [[ "$line" =~ Task\ ([0-9]{3}).*depends\ on\ all ]]; then
            local capstone="${BASH_REMATCH[1]}"
            for ((j=0; j<${#TASK_IDS[@]}; j++)); do
                if [[ "${TASK_IDS[$j]}" == "$capstone" ]]; then
                    # Depends on all other tasks
                    local all_deps=""
                    for ((k=0; k<${#TASK_IDS[@]}; k++)); do
                        if [[ "${TASK_IDS[$k]}" != "$capstone" ]]; then
                            all_deps="${all_deps:+${all_deps},}${TASK_IDS[$k]}"
                        fi
                    done
                    TASK_DEPS[$j]="$all_deps"
                    break
                fi
            done
        # Parse "Task NNN depends on NNN, NNN, NNN" (explicit list)
        elif [[ "$line" =~ Task\ ([0-9]{3}).*depends\ on\ ([0-9]{3}(,\ *[0-9]{3})*) ]]; then
            local target="${BASH_REMATCH[1]}"
            local dep_list_str="${BASH_REMATCH[2]}"
            # Find target index
            for ((j=0; j<${#TASK_IDS[@]}; j++)); do
                if [[ "${TASK_IDS[$j]}" == "$target" ]]; then
                    # Parse comma-separated deps
                    IFS=',' read -ra explicit_deps <<< "$dep_list_str"
                    for dep in "${explicit_deps[@]}"; do
                        dep=$(echo "$dep" | tr -d ' ')
                        if [[ -n "${TASK_DEPS[$j]}" ]]; then
                            TASK_DEPS[$j]="${TASK_DEPS[$j]},${dep}"
                        else
                            TASK_DEPS[$j]="${dep}"
                        fi
                    done
                    break
                fi
            done
        fi

    done < "$plan"
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: NEXT BATCH SELECTOR
# ══════════════════════════════════════════════════════════════

# Returns space-separated indices of tasks ready to execute
next_batch() {
    local -a candidates=()

    # Step 1: Find pending tasks with all deps complete
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        if [[ "${TASK_STATUS[$i]}" != "pending" ]]; then
            continue
        fi

        # Check all dependencies are complete
        local deps="${TASK_DEPS[$i]}"
        local deps_met=true
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra dep_list <<< "$deps"
            for dep_id in "${dep_list[@]}"; do
                dep_id=$(echo "$dep_id" | tr -d ' ')
                local dep_found=false
                for ((j=0; j<${#TASK_IDS[@]}; j++)); do
                    if [[ "${TASK_IDS[$j]}" == "$dep_id" ]]; then
                        dep_found=true
                        if [[ "${TASK_STATUS[$j]}" != "complete" ]]; then
                            deps_met=false
                        fi
                        break
                    fi
                done
                if [[ "$dep_found" == false ]]; then
                    deps_met=false
                fi
                if [[ "$deps_met" == false ]]; then break; fi
            done
        fi

        if [[ "$deps_met" == true ]]; then
            candidates+=("$i")
        fi
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    # Step 2: Sort by risk if risk-first enabled (high > medium > low)
    if [[ "$RISK_FIRST" == true ]]; then
        local -a high=() medium=() low=()
        for idx in "${candidates[@]}"; do
            case "${TASK_RISKS[$idx]}" in
                high)   high+=("$idx") ;;
                medium) medium+=("$idx") ;;
                low)    low+=("$idx") ;;
                *)      medium+=("$idx") ;;
            esac
        done
        candidates=("${high[@]+"${high[@]}"}" "${medium[@]+"${medium[@]}"}" "${low[@]+"${low[@]}"}")
    fi

    # Step 3: Select batch respecting file ownership conflicts
    local -a batch=()
    local -a batch_files=()  # all owned/touched files in current batch

    for idx in "${candidates[@]}"; do
        if [[ ${#batch[@]} -ge $MAX_BATCH_SIZE ]]; then
            break
        fi

        # Check for file ownership conflicts with existing batch
        local owns="${TASK_OWNS[$idx]}"
        local touches="${TASK_TOUCHES[$idx]}"
        local all_files="${owns}${owns:+,}${touches}"
        local conflict=false

        if [[ -n "$all_files" ]] && [[ ${#batch_files[@]} -gt 0 ]]; then
            IFS=',' read -ra new_files <<< "$all_files"
            for new_file in "${new_files[@]}"; do
                new_file=$(echo "$new_file" | tr -d ' ')
                [[ -z "$new_file" ]] && continue
                for existing_file in "${batch_files[@]}"; do
                    if [[ "$new_file" == "$existing_file" ]]; then
                        conflict=true
                        break 2
                    fi
                done
            done
        fi

        if [[ "$conflict" == false ]]; then
            batch+=("$idx")
            # Add this task's files to the batch file list
            if [[ -n "$all_files" ]]; then
                IFS=',' read -ra new_files <<< "$all_files"
                for f in "${new_files[@]}"; do
                    f=$(echo "$f" | tr -d ' ')
                    [[ -n "$f" ]] && batch_files+=("$f")
                done
            fi
        fi
    done

    echo "${batch[*]}"
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: CHECKPOINT SYSTEM
# ══════════════════════════════════════════════════════════════

## Functions extracted to lib/loop-checkpoint.sh:
## write_checkpoint(), restore_checkpoint(),
## compute_plan_structure_checksum(), verify_plan_checksum()

# ══════════════════════════════════════════════════════════════
# BRANCH ISOLATION (delegated to lib/loop-git.sh)
# ══════════════════════════════════════════════════════════════

setup_branch

# ══════════════════════════════════════════════════════════════
# PHASE 1: PLANNING (if not skipped)
# ══════════════════════════════════════════════════════════════

if [[ "$SKIP_PLANNING" == false ]] && [[ ! -f "${SIGNALS_DIR}/plan-review.md" ]]; then
    echo ""
    echo "  Phase 1: Planning"
    echo "  ────────────────────────────────────"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would spawn: spectra-planner (Opus)"
        echo "  [DRY RUN] Would spawn: spectra-reviewer (Sonnet)"
    else
        echo "  Spawning spectra-planner (Opus)..."
        claude --agent spectra-planner -p --permission-mode plan \
            "Read the project description and generate all required SPECTRA planning artifacts for this project. Write to .spectra/ directory." \
            2>&1 | tee "${LOGS_DIR}/planning.log" || true

        echo "  Spawning spectra-reviewer (Sonnet) for plan validation..."
        claude --agent spectra-reviewer -p --permission-mode plan \
            "Review all planning artifacts in .spectra/ (constitution.md, plan.md, prd.md if present). Output your verdict following the exact format in your instructions. Include a 'Verdict:' line (APPROVED, APPROVED_WITH_WARNINGS, or REJECTED)." \
            2>&1 | tee "${LOGS_DIR}/plan-review.log" "${SIGNALS_DIR}/plan-review.md" || true

        if [[ -f "${SIGNALS_DIR}/plan-review.md" ]]; then
            VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/plan-review.md" | head -1 || echo "UNKNOWN")
            echo "  Plan review verdict: ${VERDICT}"

            case "$VERDICT" in
                APPROVED)
                    echo "  Plan approved. Proceeding to execution."
                    ;;
                APPROVED_WITH_WARNINGS)
                    echo "  Plan approved with warnings."
                    sed -n '/### Warnings/,/### /p' "${SIGNALS_DIR}/plan-review.md" | \
                        grep '^\-' >> "${SPECTRA_DIR}/guardrails.md" 2>/dev/null || true
                    ;;
                REJECTED)
                    echo "  Plan rejected. Attempting one revision..."
                    claude --agent spectra-planner -p --permission-mode plan \
                        "Your plan was REJECTED. Read .spectra/signals/plan-review.md for rejection reasons. Revise the planning artifacts to address all blocking issues. This is your ONE revision attempt." \
                        2>&1 | tee "${LOGS_DIR}/planning-revision.log" || true

                    rm -f "${SIGNALS_DIR}/plan-review.md"
                    claude --agent spectra-reviewer -p --permission-mode plan \
                        "Re-review the revised planning artifacts in .spectra/. This is the second review. Output your verdict with a 'Verdict:' line." \
                        2>&1 | tee "${LOGS_DIR}/plan-re-review.log" "${SIGNALS_DIR}/plan-review.md" || true

                    RE_VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/plan-review.md" 2>/dev/null | head -1 || echo "UNKNOWN")
                    if [[ "$RE_VERDICT" == "REJECTED" ]] || [[ "$RE_VERDICT" == "UNKNOWN" ]]; then
                        signal_stuck "Plan rejected twice. Human must revise planning artifacts."
                    fi
                    echo "  Revised plan approved (${RE_VERDICT}). Proceeding."
                    ;;
                *)
                    signal_stuck "Plan review returned unknown verdict: ${VERDICT}"
                    ;;
            esac
        else
            echo "  No plan-review.md generated. Proceeding without formal review."
        fi
    fi

    if [[ "$PLAN_ONLY" == true ]]; then
        echo "  --plan-only flag set. Exiting after planning phase."
        exit 0
    fi
fi

# ══════════════════════════════════════════════════════════════
# PRE-EXECUTION CHECKS
# ══════════════════════════════════════════════════════════════

if ! validate_plan_contract; then
    exit 1
fi

if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
    echo "  STUCK signal found from previous run. Clear .spectra/signals/STUCK to continue."
    exit 1
fi

# ── RECONCILE signal check (before parse_plan so re-planning updates disk plan first) ──
if [[ -f "${SIGNALS_DIR}/RECONCILE" ]]; then
    RECONCILE_MSG=$(cat "${SIGNALS_DIR}/RECONCILE" 2>/dev/null || echo "Assessment drift detected")
    echo ""
    echo "  RECONCILE signal: ${RECONCILE_MSG}"
    echo ""
    if [[ -t 0 ]]; then
        # Interactive mode — ask user
        read -r -p "  Re-run assessment to reconcile? [y/N] " RECONCILE_ANSWER
        if [[ "${RECONCILE_ANSWER}" =~ ^[Yy] ]]; then
            echo "  Re-running assessment..."
            "${SPECTRA_HOME}/bin/spectra-assess.sh" || true
            echo "  Re-running planning..."
            "${SPECTRA_HOME}/bin/spectra-plan.sh" --level "${PROJECT_LEVEL}" || {
                echo "  ERROR: Re-planning failed after reconciliation."
                exit 1
            }
        fi
    else
        # Non-interactive — log warning and continue
        echo "  (Non-interactive mode: continuing with existing plan)"
    fi
    rm -f "${SIGNALS_DIR}/RECONCILE"
fi

# ── Parse plan into arrays ──
echo ""
echo "  Parsing plan.md..."
parse_plan

# ── Plan checksum lock (functions in lib/loop-checkpoint.sh) ──
PLAN_CHECKSUM=""

if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
    PLAN_CHECKSUM=$(compute_plan_structure_checksum)
fi

# ── Initialize per-task tracking arrays ──
declare -a RETRY_COUNTS=()
declare -a FAILURE_TYPES=()
declare -a TASK_FAILURE_HISTORY=()  # per-task: comma-separated failure types seen
for ((i=0; i<${#TASK_IDS[@]}; i++)); do
    RETRY_COUNTS+=("0")
    FAILURE_TYPES+=("")
    TASK_FAILURE_HISTORY+=("")
done

# ── Resume from checkpoint if requested ──
if [[ "$RESUME" == true ]]; then
    restore_checkpoint || true
fi

# Write initial signals (skip in dry-run to avoid disk pollution)
if [[ "$DRY_RUN" == false ]]; then
    write_signal "PHASE" "executing"
    write_signal "AGENT" "spectra-loop-v5"
    write_progress
fi

# ── Display banner ──
read TOTAL DONE REMAINING STUCK_COUNT <<< "$(count_tasks)"
echo ""
echo "  SPECTRA v5.0 Execution Loop"
echo "  ────────────────────────────────────"
echo "  Tasks:        ${DONE}/${TOTAL} complete (${REMAINING} remaining, ${STUCK_COUNT} stuck)"
echo "  Cost Ceiling: \$${COST_CEILING}"
echo "  Branch:       ${BRANCH_NAME}"
echo "  Level:        ${PROJECT_LEVEL}"
echo "  Max Batch:    ${MAX_BATCH_SIZE}"
echo "  Risk First:   ${RISK_FIRST}"
echo "  Dry Run:      ${DRY_RUN}"
echo "  Resume:       ${RESUME}"
echo ""

# ── Install pre-commit hook (delegated to lib/loop-git.sh) ──
install_precommit_hook

# Generate initial CLAUDE.md (skip in dry-run)
if [[ "$DRY_RUN" == false ]]; then
    refresh_claude_md
fi

# ══════════════════════════════════════════════════════════════
# PHASE 3: MAIN EXECUTION LOOP
# ══════════════════════════════════════════════════════════════

LOOP_COUNT=0
while [[ $LOOP_COUNT -lt $MAX_TASKS ]]; do
    LOOP_COUNT=$((LOOP_COUNT + 1))

    # Get next batch of independent tasks
    BATCH_STR=$(next_batch)
    if [[ -z "$BATCH_STR" ]]; then
        read _TOTAL _DONE _REMAINING _STUCK <<< "$(count_tasks)"
        if [[ $_REMAINING -gt 0 ]]; then
            if [[ "$DRY_RUN" == false ]]; then
                signal_stuck "Dependency deadlock: ${_REMAINING} task(s) remain but none are ready. Check Dependency Graph and task statuses."
            else
                echo "  [DRY RUN] Dependency deadlock detected: ${_REMAINING} task(s) remain but none are ready."
            fi
        fi
        echo "  No more tasks ready to execute."
        break
    fi

    read -ra BATCH <<< "$BATCH_STR"
    local_batch_size=${#BATCH[@]}

    # Verify plan.md hasn't been tampered with before executing batch
    if [[ "$DRY_RUN" == false ]]; then
        if ! verify_plan_checksum; then
            signal_stuck "Plan checksum lock violation — plan.md modified during execution"
            break
        fi
    fi

    # Describe the batch
    batch_desc=""
    for idx in "${BATCH[@]}"; do
        batch_desc="${batch_desc:+${batch_desc}, }Task ${TASK_IDS[$idx]}"
    done

    echo ""
    echo "  Batch ${LOOP_COUNT}: [${batch_desc}] (${local_batch_size} task(s))"
    echo "  ────────────────────────────────────"

    # ── Step A: Pre-flight audit for each task in batch ──
    echo "  Pre-flight audit..."
    if [[ "$DRY_RUN" == false ]]; then
        audit_pids=()
        for idx in "${BATCH[@]}"; do
            task_id="${TASK_IDS[$idx]}"
            write_batch_status "${batch_desc}" "auditor"

            claude --agent spectra-auditor -p --permission-mode plan \
                "$(preflight_prompt "$task_id")" \
                2>&1 | tee "${LOGS_DIR}/task-${task_id}-preflight.log" "${LOGS_DIR}/task-${task_id}-preflight.md" &
            audit_pids+=($!)
        done

        # Wait for all audits (cheap Haiku, can be parallel)
        for pid in "${audit_pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
    else
        for idx in "${BATCH[@]}"; do
            echo "    [DRY RUN] Would audit Task ${TASK_IDS[$idx]}"
        done
    fi

    # ── Step B: Parallel build ──
    if [[ "$DRY_RUN" == false ]]; then
        write_batch_status "${batch_desc}" "builder"
    fi
    echo "  Building..."

    # Set retry counts for iteration tracking
    for idx in "${BATCH[@]}"; do
        if [[ "${RETRY_COUNTS[$idx]}" -eq 0 ]]; then
            RETRY_COUNTS[$idx]=1
        fi
    done

    BATCH_START_TIME=$(date +%s)
    set +e
    parallel_build "${BATCH[@]}"
    set -e
    BATCH_END_TIME=$(date +%s)
    BATCH_ELAPSED=$((BATCH_END_TIME - BATCH_START_TIME))

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] All builds in batch would complete"
        # In dry run, mark in-memory only (no disk writes)
        for idx in "${BATCH[@]}"; do
            TASK_STATUS[$idx]="complete"
            PASS_HISTORY="${PASS_HISTORY:+${PASS_HISTORY}, }Task ${TASK_IDS[$idx]}: PASS (dry-run)"
        done
        continue
    fi

    # Check for infra failures before proceeding to verification
    INFRA_FAILED=false
    for idx in "${BATCH[@]}"; do
        task_id="${TASK_IDS[$idx]}"
        if [[ -f "${SIGNALS_DIR}/INFRA_FAIL_${task_id}" ]]; then
            echo "  Task ${task_id}: INFRA_FAILURE — builder had CLI/infra error, skipping verification"
            TASK_STATUS[$idx]="stuck"
            task_line="${TASK_LINES[$idx]}"
            if [[ "$task_line" -gt 0 ]]; then
                sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
            fi
            rm -f "${SIGNALS_DIR}/INFRA_FAIL_${task_id}"
            INFRA_FAILED=true
        fi
    done
    if [[ "$INFRA_FAILED" == true ]]; then
        write_checkpoint
        signal_stuck "Infrastructure failure detected: one or more builders hit CLI errors. Check build logs in ${LOGS_DIR}/"
    fi

    # Bogus run detection — suspiciously fast batch
    MIN_EXPECTED=$((local_batch_size * 30))
    if [[ "$BATCH_ELAPSED" -lt "$MIN_EXPECTED" ]]; then
        echo ""
        echo "  WARNING: Batch completed in ${BATCH_ELAPSED}s (expected >=${MIN_EXPECTED}s for ${local_batch_size} task(s))"
        echo "  This may indicate builders failed silently (bad CLI flags, empty runs)."
        echo "  Check build logs: ${LOGS_DIR}/task-*-build.log"
        echo "  WARNING" > "${SIGNALS_DIR}/BOGUS_RUN_WARNING"
    fi

    # Check for STUCK from builders
    if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
        signal_stuck "Builder raised STUCK during batch [${batch_desc}]: $(head -5 "${SIGNALS_DIR}/STUCK")"
    fi

    # ── Step C: Sequential verification for each task in batch ──
    echo "  Verifying (sequential)..."
    for idx in "${BATCH[@]}"; do
        task_id="${TASK_IDS[$idx]}"
        task_title="${TASK_TITLES[$idx]}"
        iteration="${RETRY_COUNTS[$idx]}"
        max_iter="${TASK_MAX_ITER[$idx]}"

        write_status "${task_id}" "${task_title}" "${iteration}" "${max_iter}" "verifier" "${PASS_HISTORY}"

        # Full verification on every task (Phase 3: no graduated mode)
        verify_depth="full"

        echo "    Verifying Task ${task_id} (${verify_depth})..."
        set +e
        claude --agent spectra-verifier -p --permission-mode plan \
            "$(verify_prompt "$idx" "$verify_depth")" \
            2>&1 | tee "${LOGS_DIR}/task-${task_id}-verify.log" "${LOGS_DIR}/task-${task_id}-verify.md"
        VERIFY_EXIT=${PIPESTATUS[0]}
        set -e

        # ── Step D: Parse verification result ──
        RESULT="UNKNOWN"
        FAILURE_TYPE=""
        if [[ -f "${LOGS_DIR}/task-${task_id}-verify.md" ]]; then
            RESULT=$(grep -oiP 'Result:\s*\K\S+' "${LOGS_DIR}/task-${task_id}-verify.md" | head -1 || echo "UNKNOWN")
            FAILURE_TYPE=$(grep -oiP 'Failure Type:\s*\K\S+' "${LOGS_DIR}/task-${task_id}-verify.md" | head -1 || echo "")
        fi

        if [[ $VERIFY_EXIT -eq 0 ]] && [[ "$RESULT" == "UNKNOWN" ]]; then
            RESULT="PASS"
        fi

        if [[ "${RESULT^^}" == "PASS" ]]; then
            # ── Wiring gate (delegated to lib/loop-wiring.sh) ──
            set +e
            run_wiring_gate "$task_id"
            WIRING_RESULT=$?
            set -e
            if [[ $WIRING_RESULT -ne 0 ]]; then
                RESULT="FAIL"
                FAILURE_TYPE="wiring_gap"
            fi
        fi

        if [[ "${RESULT^^}" == "PASS" ]]; then
            # ── PASS (verifier + wiring both passed) ──
            echo "    Task ${task_id} PASSED (iteration ${iteration})"
            TASK_STATUS[$idx]="complete"

            # Update plan.md checkbox
            task_line="${TASK_LINES[$idx]}"
            if [[ "$task_line" -gt 0 ]]; then
                sed_inplace "${task_line}s/\- \[ \]/- [x]/" "${SPECTRA_DIR}/plan.md"
            fi

            # Update pass history
            if [[ "$iteration" -eq 1 ]]; then
                PASS_HISTORY="${PASS_HISTORY:+${PASS_HISTORY}, }Task ${task_id}: PASS"
            else
                PASS_HISTORY="${PASS_HISTORY:+${PASS_HISTORY}, }Task ${task_id}: FAIL->PASS"
            fi

            # Git commit (delegated to lib/loop-git.sh)
            commit_task "${task_id}" "${task_title}"

            generate_task_summary "${task_id}" "${task_title}" "PASS" "${iteration}"
        else
            # ── FAIL ──
            # Use oracle to classify if verifier didn't provide type
            if [[ -z "$FAILURE_TYPE" ]] || [[ "$FAILURE_TYPE" == "UNKNOWN" ]]; then
                echo "    Oracle classifying failure for Task ${task_id}..."
                FAILURE_TYPE=$(oracle_classify "$task_id")
            fi

            echo "    Task ${task_id} FAILED (iteration ${iteration}, type: ${FAILURE_TYPE:-unknown})"
            FAILURE_TYPES[$idx]="$FAILURE_TYPE"

            # Track failure history for compound failure detection
            if [[ -n "$FAILURE_TYPE" ]]; then
                if [[ -n "${TASK_FAILURE_HISTORY[$idx]}" ]]; then
                    TASK_FAILURE_HISTORY[$idx]="${TASK_FAILURE_HISTORY[$idx]},${FAILURE_TYPE}"
                else
                    TASK_FAILURE_HISTORY[$idx]="$FAILURE_TYPE"
                fi
            fi

            # Compound failure check: 2 different failure types = STUCK
            if [[ -n "${TASK_FAILURE_HISTORY[$idx]}" ]]; then
                unique_count=0
                unique_count=$(echo "${TASK_FAILURE_HISTORY[$idx]}" | tr ',' '\n' | sort -u | wc -l)
                if [[ "$unique_count" -ge 2 ]]; then
                    # Mark as stuck in plan.md
                    task_line="${TASK_LINES[$idx]}"
                    if [[ "$task_line" -gt 0 ]]; then
                        sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
                    fi
                    TASK_STATUS[$idx]="stuck"
                    write_checkpoint
                    signal_stuck "Compound failure on Task ${task_id}: ${TASK_FAILURE_HISTORY[$idx]}. Two different failure types = plan is wrong, not code."
                fi
            fi

            # Check if failure type allows retry
            allowed_retries=0
            allowed_retries=$(max_retries_for "${FAILURE_TYPE}")
            if [[ "$allowed_retries" -eq 0 ]]; then
                task_line="${TASK_LINES[$idx]}"
                if [[ "$task_line" -gt 0 ]]; then
                    sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
                fi
                TASK_STATUS[$idx]="stuck"
                write_checkpoint
                signal_stuck "Non-retryable failure on Task ${task_id}: ${FAILURE_TYPE}"
            elif [[ "$iteration" -ge "$allowed_retries" ]]; then
                # Type-specific retry budget exhausted
                task_line="${TASK_LINES[$idx]}"
                if [[ "$task_line" -gt 0 ]]; then
                    sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
                fi
                TASK_STATUS[$idx]="stuck"
                write_checkpoint
                signal_stuck "Task ${task_id} exhausted ${FAILURE_TYPE} retry budget (${allowed_retries} attempts)."
            fi

            # Check if max iterations exceeded
            if [[ "$iteration" -ge "${TASK_MAX_ITER[$idx]}" ]]; then
                task_line="${TASK_LINES[$idx]}"
                if [[ "$task_line" -gt 0 ]]; then
                    sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
                fi
                TASK_STATUS[$idx]="stuck"
                write_checkpoint
                signal_stuck "Task ${task_id} exhausted all ${max_iter} iterations without passing."
            fi

            # Increment retry count for next attempt
            RETRY_COUNTS[$idx]=$((iteration + 1))

            # Write fail context
            cat > "${LOGS_DIR}/task-${task_id}-fail.md" <<FAILEOF
## Fail Context — Task ${task_id}, Iteration ${iteration}
- Failure Type: ${FAILURE_TYPE}
- Remaining Iterations: $((${TASK_MAX_ITER[$idx]} - iteration))
- Verifier Report: See .spectra/logs/task-${task_id}-verify.md
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
FAILEOF

            # Append to lessons-learned
            {
                echo ""
                echo "### LESSON-$(date +%Y%m%d%H%M%S)"
                echo "- **State:** TEMP"
                echo "- **Pattern:** Task ${task_id} failed verification (${FAILURE_TYPE})"
                echo "- **Fix:** Pending builder retry (iteration $((iteration + 1)))"
                echo "- **Projects Seen:** [$(basename "$(pwd)")]"
                echo "- **TTL Remaining:** 5 projects"
            } >> "${SPECTRA_DIR}/lessons-learned.md" 2>/dev/null || true

            propagate_signs
        fi
    done

    # ── Checkpoint after each batch (skip in dry-run) ──
    if [[ "$DRY_RUN" == false ]]; then
        write_checkpoint
        write_progress
        refresh_claude_md
    fi

    read TOTAL DONE REMAINING STUCK_COUNT <<< "$(count_tasks)"
    echo ""
    echo "  Progress: ${DONE}/${TOTAL} tasks complete (${REMAINING} remaining)"

    # NEGOTIATE signal handling
    if [[ -f "${SIGNALS_DIR}/NEGOTIATE" ]]; then
        echo "  Negotiate signal detected — routing to reviewer..."
        last_task_id="${TASK_IDS[${BATCH[-1]}]}"
        claude --agent spectra-reviewer -p --permission-mode plan \
            "A builder has raised a spec negotiation for Task ${last_task_id}. Read .spectra/signals/NEGOTIATE for the proposed adaptation. Evaluate against constitution.md and non-goals.md. Output your verdict with a 'Verdict:' line." \
            2>&1 | tee "${LOGS_DIR}/negotiate-review.log" "${SIGNALS_DIR}/NEGOTIATE_REVIEW" | tail -5 || true

        if [[ -f "${SIGNALS_DIR}/NEGOTIATE_REVIEW" ]]; then
            neg_verdict=""
            neg_verdict=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/NEGOTIATE_REVIEW" | head -1 || echo "UNKNOWN")
            echo "  Negotiate verdict: ${neg_verdict}"

            case "$neg_verdict" in
                APPROVED)
                    echo "  Spec adaptation approved"
                    constraint=""
                    constraint=$(sed -n '/### Constraint to Append/,/^$/p' "${SIGNALS_DIR}/NEGOTIATE_REVIEW" 2>/dev/null | grep '^>' | head -3 || echo "")
                    if [[ -n "$constraint" ]]; then
                        echo "$constraint" >> "${SPECTRA_DIR}/plan.md"
                        # RATIONALE: PLAN_CHECKSUM is used by verify_plan_checksum() in sourced lib/loop-checkpoint.sh
                        # shellcheck disable=SC2034
                        PLAN_CHECKSUM=$(compute_plan_structure_checksum)
                    fi
                    ;;
                ESCALATE)
                    signal_stuck "Spec negotiation escalated. See .spectra/signals/NEGOTIATE_REVIEW"
                    ;;
                *)
                    echo "  Unknown negotiate verdict: ${neg_verdict}. Continuing."
                    ;;
            esac
        fi

        rm -f "${SIGNALS_DIR}/NEGOTIATE" "${SIGNALS_DIR}/NEGOTIATE_REVIEW"
    fi

done

# ══════════════════════════════════════════════════════════════
# PHASE 5: COMPLETION
# ══════════════════════════════════════════════════════════════

read TOTAL DONE REMAINING STUCK_COUNT <<< "$(count_tasks)"

if [[ $REMAINING -eq 0 ]] && [[ $TOTAL -gt 0 ]]; then
    echo ""
    echo "  Phase 5: Final Review"
    echo "  ────────────────────────────────────"

    if [[ "$DRY_RUN" == false ]]; then
        echo "  Spawning spectra-reviewer (Sonnet) for final PR review..."
        claude --agent spectra-reviewer -p --permission-mode plan \
            "Perform a final PR review. Read .spectra/logs/ for all task reports. Review the git diff. Check lessons-learned.md for patterns worth promoting to Signs. Output your review." \
            2>&1 | tee "${LOGS_DIR}/pr-review-session.log" "${LOGS_DIR}/pr-review.md" || true
    fi

    if [[ "$DRY_RUN" == false ]]; then
        signal_complete
        write_final_report
        write_checkpoint
    fi

    echo ""
    echo "  Final: ${DONE}/${TOTAL} tasks complete"
    echo "  Elapsed: $(elapsed)"
    echo "  Branch: ${BRANCH_NAME}"
    echo ""
    echo "  Next: Review the branch and merge when ready."
    echo "    git diff main...${BRANCH_NAME}"
    echo "    git merge ${BRANCH_NAME}"
else
    echo ""
    echo "  Loop ended with ${REMAINING} tasks remaining."
    if [[ "$DRY_RUN" == false ]]; then
        write_final_report
        write_checkpoint
    fi
fi
