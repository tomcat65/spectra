#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v5.0 Execution Loop — Bash-Native Parallel Architecture ║
# ║  Heritage: spectra-loop-legacy.sh (proven sequential engine)     ║
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
CHECKPOINT_FILE="${SIGNALS_DIR}/CHECKPOINT"

# ── Defaults ──
PLAN_ONLY=false
SKIP_PLANNING=false
RESUME=false
DRY_RUN=false
COST_CEILING=""
RISK_FIRST=false
MAX_BATCH_SIZE=4
MAX_TASKS=50
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
    local now=$(date +%s)
    local diff=$(( (now - START_TIME) + ELAPSED_OFFSET ))
    printf '%02d:%02d:%02d' $((diff/3600)) $(((diff%3600)/60)) $((diff%60))
}

elapsed_seconds() {
    local now=$(date +%s)
    echo $(( (now - START_TIME) + ELAPSED_OFFSET ))
}

write_status() {
    local task_num="$1" task_title="$2" iteration="$3" max_iter="$4"
    local agent="${5:-idle}" pass_history="${6:-}"
    cat > "${SIGNALS_DIR}/STATUS" <<EOF
## SPECTRA v5.0 Run Status
- Current Task: ${task_num}
- Task Title: ${task_title}
- Iteration: ${iteration} / ${max_iter}
- Elapsed Time: $(elapsed)
- Pass History: ${pass_history}
- Current Agent: ${agent}
- Last Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

write_batch_status() {
    local batch_desc="$1" agent="${2:-idle}"
    cat > "${SIGNALS_DIR}/STATUS" <<EOF
## SPECTRA v5.0 Run Status
- Current Batch: ${batch_desc}
- Elapsed Time: $(elapsed)
- Pass History: ${PASS_HISTORY}
- Current Agent: ${agent}
- Last Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

signal_stuck() {
    local reason="$1"
    cat > "${SIGNALS_DIR}/STUCK" <<EOF
## SPECTRA STUCK Signal
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Elapsed: $(elapsed)
- Reason: ${reason}
- Branch: ${BRANCH_NAME}
- Recovery: Human intervention required
EOF
    write_signal "PHASE" "stuck"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "  STUCK — Execution halted"
    echo "  Reason: ${reason}"
    echo "  Branch preserved: ${BRANCH_NAME}"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA STUCK: ${reason} (branch: ${BRANCH_NAME})\"}" > /dev/null 2>&1 || true
    fi

    write_final_report
    exit 1
}

write_signal() {
    local signal_name="$1" signal_value="$2"
    echo "${signal_value}" > "${SIGNALS_DIR}/${signal_name}"
}

write_progress() {
    local total=0 done=0 stuck=0
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        total=${total:-0}
        done=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        done=${done:-0}
        stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        stuck=${stuck:-0}
        if [[ "$total" -eq 0 ]]; then
            total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            total=${total:-0}
            done=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            done=${done:-0}
            stuck=0
        fi
        write_signal "PROGRESS" "${done}/${total} tasks (${stuck} stuck)"
    fi
}

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

signal_complete() {
    cat > "${SIGNALS_DIR}/COMPLETE" <<EOF
## SPECTRA Complete
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Elapsed: $(elapsed)
- Branch: ${BRANCH_NAME}
- Pass History: ${PASS_HISTORY}
EOF
    write_signal "PHASE" "complete"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "  COMPLETE — All tasks passed"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA COMPLETE: All tasks passed (branch: ${BRANCH_NAME}, elapsed: $(elapsed))\"}" > /dev/null 2>&1 || true
    fi
}

write_final_report() {
    cat > "${LOGS_DIR}/final-report.md" <<EOF
## SPECTRA v5.0 Final Report
- Branch: ${BRANCH_NAME}
- Elapsed: $(elapsed)
- Pass History: ${PASS_HISTORY:-none}
- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

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

propagate_signs() {
    local guardrails_local="${SPECTRA_DIR}/guardrails.md"
    local guardrails_global="${SPECTRA_HOME}/guardrails-global.md"

    if [[ ! -f "$guardrails_local" ]] || [[ ! -f "$guardrails_global" ]]; then
        return
    fi

    while IFS= read -r sign_line; do
        local sign_id
        sign_id=$(echo "$sign_line" | grep -oP 'SIGN-\d+' || echo "")
        if [[ -n "$sign_id" ]] && ! grep -q "$sign_id" "$guardrails_global" 2>/dev/null; then
            local line_num desc_line
            line_num=$(grep -n "$sign_id" "$guardrails_local" | head -1 | cut -d: -f1)
            desc_line=$(sed -n "$((line_num + 1))p" "$guardrails_local" 2>/dev/null || echo "")
            {
                echo ""
                echo "$sign_line"
                echo "$desc_line"
            } >> "$guardrails_global"
            echo "  Sign propagated to global: ${sign_id}"
        fi
    done < <(grep -E "^### SIGN-" "$guardrails_local" 2>/dev/null || true)
}

generate_task_summary() {
    local task_num="$1" task_title="$2" result="$3" iteration="$4"

    local summary_line
    if [[ "$result" == "PASS" ]] && [[ "$iteration" -eq 1 ]]; then
        summary_line="- Task ${task_num} (${task_title}): PASS on first attempt"
    elif [[ "$result" == "PASS" ]]; then
        summary_line="- Task ${task_num} (${task_title}): PASS after ${iteration} iterations"
    else
        summary_line="- Task ${task_num} (${task_title}): ${result} (${iteration} iterations)"
    fi

    local files_changed=""
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        files_changed=$(git diff --name-only HEAD~1 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//' || echo "unknown")
    fi

    if [[ -f CLAUDE.md ]]; then
        if grep -q '## Task History' CLAUDE.md 2>/dev/null; then
            {
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        else
            {
                echo ""
                echo "## Task History"
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        fi
    fi
}

max_retries_for() {
    local failure_type="$1"
    case "$failure_type" in
        test_failure|missing_dependency) echo 3 ;;
        wiring_gap)                      echo 2 ;;
        *)                               echo 0 ;;  # STUCK
    esac
}

count_tasks() {
    local total done stuck remaining
    total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    total=${total:-0}
    done=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    done=${done:-0}
    stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
    stuck=${stuck:-0}
    if [[ "$total" -eq 0 ]]; then
        total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        total=${total:-0}
        done=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        done=${done:-0}
        stuck=0
    fi
    remaining=$((total - done - stuck))
    echo "${total} ${done} ${remaining} ${stuck}"
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: PLAN PARSER
# ══════════════════════════════════════════════════════════════

parse_plan() {
    local plan="${SPECTRA_DIR}/plan.md"
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
    TASK_VERIFY=()
    TASK_MAX_ITER=()
    TASK_LINES=()
    TASK_DEPS=()

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

        # Parse Risk
        if [[ "$line" =~ ^-\ Risk:\ *(high|medium|low) ]]; then
            TASK_RISKS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse Verify command (between backticks)
        if [[ "$line" =~ ^-\ Verify:\ \`(.+)\`$ ]]; then
            TASK_VERIFY[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse Max-iterations
        if [[ "$line" =~ ^-\ Max-iterations:\ *([0-9]+) ]]; then
            TASK_MAX_ITER[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse File-ownership owns
        if [[ "$line" =~ owns:\ *\[([^]]*)\] ]]; then
            TASK_OWNS[$current_idx]="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse File-ownership touches
        if [[ "$line" =~ touches:\ *\[([^]]*)\] ]]; then
            TASK_TOUCHES[$current_idx]="${BASH_REMATCH[1]}"
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

    echo "  Parsed ${#TASK_IDS[@]} tasks from plan.md"
    return 0
}

parse_dependencies() {
    local plan="${SPECTRA_DIR}/plan.md"
    local in_dep_graph=false

    while IFS= read -r line; do
        # Enter dependency graph section
        if [[ "$line" == "## Dependency Graph" ]]; then
            in_dep_graph=true
            continue
        fi

        # Exit on next section
        if [[ "$in_dep_graph" == true ]] && [[ "$line" =~ ^## ]]; then
            break
        fi

        if [[ "$in_dep_graph" != true ]]; then
            continue
        fi

        # Parse chain notation: Tasks 001 → 002 → 003 (or -> ASCII arrows)
        # Normalize Unicode arrow → to ASCII -> before matching
        local norm_line="${line//→/->}"
        if [[ "$norm_line" =~ [Tt]asks?\ +([0-9]{3}(\ *-\>\ *[0-9]{3})+) ]]; then
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
# v5.0 CORE: PROMPT GENERATORS (<500 bytes each)
# ══════════════════════════════════════════════════════════════

build_prompt() {
    local idx="$1"
    local iteration="${2:-1}"
    local task_id="${TASK_IDS[$idx]}"
    local title="${TASK_TITLES[$idx]}"
    local preflight_advisory="${3:-}"

    local prompt="Implement Task ${task_id}: ${title}."
    prompt+=" Read CLAUDE.md for project context."
    prompt+=" Read .spectra/plan.md section '## Task ${task_id}' for full acceptance criteria and file ownership."
    prompt+=" Read .spectra/guardrails.md for active Signs."

    if [[ "$iteration" -gt 1 ]]; then
        prompt+=" This is retry ${iteration}. Read .spectra/logs/task-${task_id}-verify.md for the failure report. Fix the specific issues."
    fi

    if [[ -n "$preflight_advisory" ]]; then
        prompt+=" Pre-flight advisory: ${preflight_advisory}"
    fi

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

verify_prompt() {
    local idx="$1"
    local verify_depth="${2:-graduated}"
    local task_id="${TASK_IDS[$idx]}"

    local prompt="Verify Task ${task_id}. Read CLAUDE.md and .spectra/plan.md section '## Task ${task_id}' for context. Output your verification report with 'Result: PASS' or 'Result: FAIL' and 'Failure Type:' if applicable. Depth: ${verify_depth}."

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

preflight_prompt() {
    local task_id="$1"

    local prompt="Scan codebase for active Sign violations before Task ${task_id} build. Output your report with an 'Advisory for Builder' section if violations found."

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: PARALLEL BUILD
# ══════════════════════════════════════════════════════════════

parallel_build() {
    local batch=("$@")
    local -a pids=()
    local -a batch_task_ids=()

    for idx in "${batch[@]}"; do
        local task_id="${TASK_IDS[$idx]}"
        local iteration="${RETRY_COUNTS[$idx]:-1}"
        batch_task_ids+=("$task_id")

        # Calculate diminishing budget
        local budget=50
        case $iteration in
            1) budget=50 ;;
            2) budget=35 ;;
            3) budget=25 ;;
            *) budget=20 ;;
        esac

        # Read preflight advisory if exists
        local advisory=""
        if [[ -f "${LOGS_DIR}/task-${task_id}-preflight.md" ]]; then
            advisory=$(grep -A5 "Advisory for Builder" "${LOGS_DIR}/task-${task_id}-preflight.md" 2>/dev/null | head -3 || echo "")
        fi

        local prompt_text
        prompt_text=$(build_prompt "$idx" "$iteration" "$advisory")

        echo "  Spawning builder for Task ${task_id} (iter ${iteration}, budget ${budget})..."

        if [[ "$DRY_RUN" == true ]]; then
            echo "    [DRY RUN] Prompt (${#prompt_text} bytes): ${prompt_text:0:120}..."
            continue
        fi

        claude --agent spectra-builder -p --permission-mode acceptEdits \
            "${prompt_text}" > "${LOGS_DIR}/task-${task_id}-build.log" 2>&1 &
        pids+=($!)
    done

    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    # Wait for all builders and track exit codes
    local failed=false
    local -a builder_exits=()
    for i in "${!pids[@]}"; do
        local _bx=0
        wait "${pids[$i]}" || _bx=$?
        builder_exits+=("$_bx")
        if [[ "$_bx" -ne 0 ]]; then
            echo "  Builder for Task ${batch_task_ids[$i]} exited non-zero (exit=$_bx)"
            failed=true
        fi
    done

    # Detect infra failures (CLI errors, not code errors)
    for i in "${!batch_task_ids[@]}"; do
        local _tid="${batch_task_ids[$i]}"
        local _log="${LOGS_DIR}/task-${_tid}-build.log"
        if [[ "${builder_exits[$i]}" -ne 0 ]] && [[ -f "$_log" ]]; then
            if grep -qiE 'error: unknown option|unknown flag|unrecognized option|command not found' "$_log" 2>/dev/null; then
                echo "  INFRA FAILURE detected for Task ${_tid} (CLI/tooling error, not code)"
                echo "INFRA_FAILURE" > "${SIGNALS_DIR}/INFRA_FAIL_${_tid}"
            fi
        fi
    done

    # Check for STUCK signal from any builder
    if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
        return 1
    fi

    $failed && return 1
    return 0
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: ORACLE CLASSIFIER (3-turn, Haiku)
# ══════════════════════════════════════════════════════════════

oracle_classify() {
    local task_id="$1"

    if [[ "$DRY_RUN" == true ]]; then
        echo "test_failure"
        return
    fi

    local classification
    classification=$(claude --agent spectra-oracle -p --permission-mode plan \
        "Read .spectra/logs/task-${task_id}-verify.md. Classify the failure as EXACTLY one of: test_failure, missing_dependency, wiring_gap, architecture_mismatch, ambiguous_spec, external_blocker. Respond with ONLY the classification word, nothing else." \
        2>&1 | tail -1 | tr -d '[:space:]' || echo "")

    # Validate classification is one of the known types
    case "$classification" in
        test_failure|missing_dependency|wiring_gap|architecture_mismatch|ambiguous_spec|external_blocker)
            echo "$classification"
            ;;
        *)
            # If oracle returned garbage, fall back to verifier's reported type
            local verifier_type=""
            if [[ -f "${LOGS_DIR}/task-${task_id}-verify.md" ]]; then
                verifier_type=$(grep -oiP 'Failure Type:\s*\K\S+' "${LOGS_DIR}/task-${task_id}-verify.md" | head -1 || echo "")
            fi
            echo "${verifier_type:-test_failure}"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# v5.0 CORE: CHECKPOINT SYSTEM
# ══════════════════════════════════════════════════════════════

write_checkpoint() {
    local -a completed=() stuck_list=()
    local retry_json="{}" failure_json="{}"

    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        case "${TASK_STATUS[$i]}" in
            complete) completed+=("\"${TASK_IDS[$i]}\"") ;;
            stuck)    stuck_list+=("\"${TASK_IDS[$i]}\"") ;;
        esac
    done

    # Build retry counts JSON
    local retry_pairs=()
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local rc="${RETRY_COUNTS[$i]:-0}"
        if [[ "$rc" -gt 0 ]]; then
            retry_pairs+=("\"${TASK_IDS[$i]}\": ${rc}")
        fi
    done
    if [[ ${#retry_pairs[@]} -gt 0 ]]; then
        retry_json="{ $(IFS=', '; echo "${retry_pairs[*]}") }"
    fi

    # Build failure types JSON
    local fail_pairs=()
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local ft="${FAILURE_TYPES[$i]:-}"
        if [[ -n "$ft" ]]; then
            fail_pairs+=("\"${TASK_IDS[$i]}\": \"${ft}\"")
        fi
    done
    if [[ ${#fail_pairs[@]} -gt 0 ]]; then
        failure_json="{ $(IFS=', '; echo "${fail_pairs[*]}") }"
    fi

    local completed_json="[$(IFS=', '; echo "${completed[*]+"${completed[*]}"}")]"
    local stuck_json="[$(IFS=', '; echo "${stuck_list[*]+"${stuck_list[*]}"}")]"

    cat > "${CHECKPOINT_FILE}" <<EOF
{
  "version": "5.0",
  "completed": ${completed_json},
  "stuck": ${stuck_json},
  "in_progress": [],
  "retry_counts": ${retry_json},
  "pass_history": "${PASS_HISTORY}",
  "failure_types": ${failure_json},
  "elapsed_seconds": $(elapsed_seconds),
  "branch": "${BRANCH_NAME}",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

restore_checkpoint() {
    if [[ ! -f "${CHECKPOINT_FILE}" ]]; then
        echo "  No checkpoint found. Starting fresh."
        return 1
    fi

    echo "  Restoring from checkpoint..."

    local checkpoint
    checkpoint=$(cat "${CHECKPOINT_FILE}")

    # Checkpoint is the source of truth for task state on resume.
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        TASK_STATUS[$i]="pending"
    done

    # Extract completed tasks
    local completed_str=""
    local stuck_str=""
    if command -v jq &>/dev/null; then
        completed_str=$(echo "$checkpoint" | jq -r '.completed[]' 2>/dev/null || echo "")
        stuck_str=$(echo "$checkpoint" | jq -r '.stuck[]' 2>/dev/null || echo "")
        PASS_HISTORY=$(echo "$checkpoint" | jq -r '.pass_history // ""' 2>/dev/null || echo "")
        ELAPSED_OFFSET=$(echo "$checkpoint" | jq -r '.elapsed_seconds // 0' 2>/dev/null || echo "0")
        BRANCH_NAME=$(echo "$checkpoint" | jq -r '.branch // ""' 2>/dev/null || echo "")

        # Restore retry counts
        local retry_keys
        retry_keys=$(echo "$checkpoint" | jq -r '.retry_counts | keys[]' 2>/dev/null || echo "")
        for key in $retry_keys; do
            local val
            val=$(echo "$checkpoint" | jq -r ".retry_counts[\"${key}\"]" 2>/dev/null || echo "0")
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$key" ]]; then
                    RETRY_COUNTS[$i]="$val"
                    break
                fi
            done
        done

        # Restore failure types
        local fail_keys
        fail_keys=$(echo "$checkpoint" | jq -r '.failure_types | keys[]' 2>/dev/null || echo "")
        for key in $fail_keys; do
            local val
            val=$(echo "$checkpoint" | jq -r ".failure_types[\"${key}\"]" 2>/dev/null || echo "")
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$key" ]]; then
                    FAILURE_TYPES[$i]="$val"
                    break
                fi
            done
        done
    else
        # Fallback: grep-based parsing
        completed_str=$(echo "$checkpoint" | awk '/"completed"[[:space:]]*:/,/\]/' | grep -oP '"\K[0-9]{3}(?=")' || echo "")
        stuck_str=$(echo "$checkpoint" | awk '/"stuck"[[:space:]]*:/,/\]/' | grep -oP '"\K[0-9]{3}(?=")' || echo "")
        PASS_HISTORY=$(echo "$checkpoint" | grep -oP '"pass_history":\s*"\K[^"]*' || echo "")
        ELAPSED_OFFSET=$(echo "$checkpoint" | grep -oP '"elapsed_seconds":\s*\K[0-9]+' || echo "0")
        BRANCH_NAME=$(echo "$checkpoint" | grep -oP '"branch":\s*"\K[^"]*' || echo "")

        # Restore retry counts from retry_counts object.
        local retry_block retry_pair retry_key retry_val
        retry_block=$(echo "$checkpoint" | awk '/"retry_counts"[[:space:]]*:/,/\}/')
        while IFS= read -r retry_pair; do
            retry_key=$(echo "$retry_pair" | grep -oP '"\K[0-9]{3}(?=")' || echo "")
            retry_val=$(echo "$retry_pair" | grep -oP ':\s*\K[0-9]+' || echo "")
            if [[ -z "$retry_key" ]] || [[ -z "$retry_val" ]]; then
                continue
            fi
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$retry_key" ]]; then
                    RETRY_COUNTS[$i]="$retry_val"
                    break
                fi
            done
        done < <(echo "$retry_block" | grep -oP '"[0-9]{3}"\s*:\s*[0-9]+' || true)

        # Restore failure types from failure_types object.
        local failure_block failure_pair failure_key failure_val
        failure_block=$(echo "$checkpoint" | awk '/"failure_types"[[:space:]]*:/,/\}/')
        while IFS= read -r failure_pair; do
            failure_key=$(echo "$failure_pair" | grep -oP '"\K[0-9]{3}(?=")' || echo "")
            failure_val=$(echo "$failure_pair" | grep -oP ':\s*"\K[^"]+' || echo "")
            if [[ -z "$failure_key" ]] || [[ -z "$failure_val" ]]; then
                continue
            fi
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$failure_key" ]]; then
                    FAILURE_TYPES[$i]="$failure_val"
                    break
                fi
            done
        done < <(echo "$failure_block" | grep -oP '"[0-9]{3}"\s*:\s*"[^"]+"' || true)
    fi

    # Update TASK_STATUS from checkpoint completed list
    for task_id in $completed_str; do
        for ((i=0; i<${#TASK_IDS[@]}; i++)); do
            if [[ "${TASK_IDS[$i]}" == "$task_id" ]]; then
                TASK_STATUS[$i]="complete"
                break
            fi
        done
    done

    # Also restore stuck tasks
    for task_id in $stuck_str; do
        for ((i=0; i<${#TASK_IDS[@]}; i++)); do
            if [[ "${TASK_IDS[$i]}" == "$task_id" ]]; then
                TASK_STATUS[$i]="stuck"
                break
            fi
        done
    done

    local completed_count=0 stuck_count=0
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        case "${TASK_STATUS[$i]}" in
            complete) completed_count=$((completed_count + 1)) ;;
            stuck)    stuck_count=$((stuck_count + 1)) ;;
        esac
    done

    echo "  Checkpoint restored: ${completed_count} complete, ${stuck_count} stuck"
    echo "  Pass history: ${PASS_HISTORY:-none}"
    echo "  Elapsed offset: ${ELAPSED_OFFSET}s"
    echo "  Branch: ${BRANCH_NAME}"

    return 0
}

# ══════════════════════════════════════════════════════════════
# BRANCH ISOLATION
# ══════════════════════════════════════════════════════════════

if [[ "$RESUME" == true ]] && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    EXISTING_BRANCH=$(git branch --list 'spectra/run-*' | tail -1 | tr -d ' *' || true)
    if [[ -n "$EXISTING_BRANCH" ]]; then
        BRANCH_NAME="$EXISTING_BRANCH"
        echo "  Resuming on existing branch: ${BRANCH_NAME}"
        if [[ "$DRY_RUN" == false ]]; then
            git checkout "${BRANCH_NAME}" 2>/dev/null || true
        fi
    fi
fi

if [[ -z "$BRANCH_NAME" ]]; then
    BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        if [[ "$DRY_RUN" == false ]]; then
            git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
            echo "  Branch: ${BRANCH_NAME}"
        fi
    fi
fi

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
            "Review all planning artifacts in .spectra/ (constitution.md, plan.md, prd.md if present). Output your verdict following the exact format in your instructions with 'Verdict:' line." \
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
                        "Re-review the revised planning artifacts in .spectra/. This is the second review. Output your verdict with 'Verdict:' line." \
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

# ── Parse plan into arrays ──
echo ""
echo "  Parsing plan.md..."
parse_plan

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
read TOTAL DONE REMAINING STUCK_COUNT <<< $(count_tasks)
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
        read _TOTAL _DONE _REMAINING _STUCK <<< $(count_tasks)
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
    BUILD_EXIT=$?
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

    # Check for STUCK from builders
    if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
        signal_stuck "Builder raised STUCK during batch [${batch_desc}]: $(head -5 "${SIGNALS_DIR}/STUCK")"
    fi

    # Check for infra failures (CLI/tooling errors, not code errors)
    INFRA_FAILED=false
    for idx in "${BATCH[@]}"; do
        task_id="${TASK_IDS[$idx]}"
        if [[ -f "${SIGNALS_DIR}/INFRA_FAIL_${task_id}" ]]; then
            TASK_STATUS[$idx]="stuck"
            task_line="${TASK_LINES[$idx]}"
            if [[ "$task_line" -gt 0 ]]; then
                sed_inplace "${task_line}s/\- \[ \]/- [!]/" "${SPECTRA_DIR}/plan.md"
            fi
            INFRA_FAILED=true
        fi
    done
    if [[ "$INFRA_FAILED" == true ]]; then
        write_checkpoint
        signal_stuck "Infrastructure failure detected in batch [${batch_desc}]. Check build logs for CLI errors."
    fi

    # Bogus run detection: if batch completes too fast, builders likely crashed
    MIN_EXPECTED=$((local_batch_size * 30))
    if [[ "$BATCH_ELAPSED" -lt "$MIN_EXPECTED" ]]; then
        echo "  WARNING: Batch completed in ${BATCH_ELAPSED}s (expected >=${MIN_EXPECTED}s for ${local_batch_size} task(s))."
        echo "  This may indicate builders crashed immediately. Check build logs."
    fi

    # ── Step C: Sequential verification for each task in batch ──
    echo "  Verifying (sequential)..."
    for idx in "${BATCH[@]}"; do
        task_id="${TASK_IDS[$idx]}"
        task_title="${TASK_TITLES[$idx]}"
        iteration="${RETRY_COUNTS[$idx]}"
        max_iter="${TASK_MAX_ITER[$idx]}"

        write_status "${task_id}" "${task_title}" "${iteration}" "${max_iter}" "verifier" "${PASS_HISTORY}"

        # Determine verification depth
        read _TOTAL _DONE _REMAINING _STUCK <<< $(count_tasks)
        verify_depth="graduated"
        if [[ $_REMAINING -le 1 ]]; then
            verify_depth="full"
        fi

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
            # ── PASS ──
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

            # Git commit
            if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                git add -A 2>/dev/null || true
                git commit -m "feat(task-${task_id}): ${task_title}" --no-verify 2>/dev/null || true
            fi

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

    read TOTAL DONE REMAINING STUCK_COUNT <<< $(count_tasks)
    echo ""
    echo "  Progress: ${DONE}/${TOTAL} tasks complete (${REMAINING} remaining)"

    # NEGOTIATE signal handling
    if [[ -f "${SIGNALS_DIR}/NEGOTIATE" ]]; then
        echo "  Negotiate signal detected — routing to reviewer..."
        last_task_id="${TASK_IDS[${BATCH[-1]}]}"
        claude --agent spectra-reviewer -p --permission-mode plan \
            "A builder has raised a spec negotiation for Task ${last_task_id}. Read .spectra/signals/NEGOTIATE for the proposed adaptation. Evaluate against constitution.md and non-goals.md. Output your verdict with 'Verdict:' line." \
            2>&1 | tee "${LOGS_DIR}/negotiate-review.log" "${SIGNALS_DIR}/NEGOTIATE_REVIEW" || true

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

read TOTAL DONE REMAINING STUCK_COUNT <<< $(count_tasks)

if [[ $REMAINING -eq 0 ]] && [[ $TOTAL -gt 0 ]]; then
    echo ""
    echo "  Phase 5: Final Review"
    echo "  ────────────────────────────────────"

    if [[ "$DRY_RUN" == false ]]; then
        echo "  Spawning spectra-reviewer (Sonnet) for final PR review..."
        claude --agent spectra-reviewer -p --permission-mode plan \
            "Perform a final PR review. Read .spectra/logs/ for all task reports. Review the git diff. Check lessons-learned.md for patterns worth promoting to Signs. Output your review with a 'Verdict:' line." \
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
