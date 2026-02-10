#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v2.0 Execution Loop — All-Anthropic Autonomous Pipeline ║
# ║  Heritage: Ralph Wiggum (fresh context) + YCE (evidence chain)   ║
# ║  Architecture: Claude Code Tier 2 Subagents                      ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-loop [--plan-only] [--skip-planning] [--dry-run] [--cost-ceiling N] [--risk-first]
#
# Pipeline: Plan → Review → [Lock] → For each task: Audit → Build → Verify
#           On FAIL: retry with diminishing budget
#           On COMPLETE: PR review → signal
#           On STUCK: halt immediately

SPECTRA_HOME="${HOME}/.spectra"
SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
LOGS_DIR="${SPECTRA_DIR}/logs"

# ── Defaults ──
PLAN_ONLY=false
SKIP_PLANNING=false
DRY_RUN=false
COST_CEILING=""
MAX_TASKS=50
START_TIME=$(date +%s)
ENABLE_TEAMS=false
EXECUTION_MODE="sequential"
RISK_FIRST=false

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan-only)     PLAN_ONLY=true; shift ;;
        --skip-planning) SKIP_PLANNING=true; shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --enable-teams)  ENABLE_TEAMS=true; shift ;;
        --risk-first)    RISK_FIRST=true; shift ;;
        --cost-ceiling)  COST_CEILING="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA v2.0 Execution Loop

Usage: spectra-loop [OPTIONS]

Options:
  --plan-only       Run planning + review gate only, then exit
  --skip-planning   Skip to execution (plan already approved)
  --dry-run         Print what would be executed without spawning agents
  --enable-teams    Enable Agent Teams for parallel task execution (Level 3+)
  --risk-first      Execute high-risk tasks first (default on for Level 2+)
  --cost-ceiling N  Override cost ceiling from project.yaml (USD)
  -h, --help        Show this help

Pipeline:
  1. Planning:   spectra-planner (Opus) generates artifacts
  2. Review:     spectra-reviewer (Sonnet) validates plan
  3. Execution:  For each task in plan.md:
     a. Pre-flight: spectra-auditor (Haiku) scans for Sign violations
     b. Build:      spectra-builder (Opus) implements task
     c. Negotiate:  If NEGOTIATE signal, route to reviewer before retry
     d. Verify:     spectra-verifier (Opus, read-only) audits task
     e. On FAIL:    retry with diminishing token budget
  4. PR Review:  spectra-reviewer (Sonnet) reviews final diff
  5. Complete:   Signal + notifications

Signals (in .spectra/signals/):
  STATUS    — Written after every task cycle (read-only monitoring)
  STUCK     — Halts execution, requires human intervention
  NEGOTIATE — Builder proposes spec adaptation, reviewer evaluates
  COMPLETE  — All tasks passed, PR ready
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

# ── Branch isolation ──
BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if [[ "$DRY_RUN" == false ]]; then
        git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
        echo "→ Branch: ${BRANCH_NAME}"
    fi
fi

# ══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ══════════════════════════════════════════════════════════════

elapsed() {
    local now=$(date +%s)
    local diff=$((now - START_TIME))
    printf '%02d:%02d:%02d' $((diff/3600)) $(((diff%3600)/60)) $((diff%60))
}

write_status() {
    local task_num="$1" task_title="$2" iteration="$3" max_iter="$4"
    local agent="${5:-idle}" pass_history="${6:-}"
    cat > "${SIGNALS_DIR}/STATUS" <<EOF
## SPECTRA Run Status
- Current Task: ${task_num}
- Task Title: ${task_title}
- Iteration: ${iteration} / ${max_iter}
- Elapsed Time: $(elapsed)
- Cumulative Cost: \$0.00 estimated
- Pass History: ${pass_history}
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
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  ⛔  STUCK — Execution halted             ║"
    echo "╚══════════════════════════════════════════╝"
    echo "  Reason: ${reason}"
    echo "  Branch preserved: ${BRANCH_NAME}"

    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"⛔ SPECTRA STUCK: ${reason} (branch: ${BRANCH_NAME})\"}" > /dev/null 2>&1 || true
    fi

    write_final_report
    exit 1
}

signal_complete() {
    cat > "${SIGNALS_DIR}/COMPLETE" <<EOF
## SPECTRA Complete
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Elapsed: $(elapsed)
- Branch: ${BRANCH_NAME}
- Pass History: ${PASS_HISTORY}
EOF
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  ✅  COMPLETE — All tasks passed           ║"
    echo "╚══════════════════════════════════════════╝"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"✅ SPECTRA COMPLETE: All tasks passed (branch: ${BRANCH_NAME}, elapsed: $(elapsed))\"}" > /dev/null 2>&1 || true
    fi
}

write_final_report() {
    cat > "${LOGS_DIR}/final-report.md" <<EOF
## SPECTRA Final Report
- Branch: ${BRANCH_NAME}
- Elapsed: $(elapsed)
- Pass History: ${PASS_HISTORY:-none}
- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

refresh_claude_md() {
    # CLAUDE.md is the single integration point for all subagents
    local project_name level signs plan_status
    project_name=$(grep 'name:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | sed 's/name: *//' || echo "unknown")
    level=$(grep 'level:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | grep -oP '\d+' || echo "1")

    # Extract active Signs
    signs=""
    if [[ -f "${SPECTRA_DIR}/guardrails.md" ]]; then
        signs=$(grep -E "^### SIGN-|^> " "${SPECTRA_DIR}/guardrails.md" 2>/dev/null | head -20 || echo "None defined")
    fi

    # Extract plan status
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

# Propagate promoted Signs to global guardrails
propagate_signs() {
    local guardrails_local="${SPECTRA_DIR}/guardrails.md"
    local guardrails_global="${SPECTRA_HOME}/guardrails-global.md"

    if [[ ! -f "$guardrails_local" ]] || [[ ! -f "$guardrails_global" ]]; then
        return
    fi

    # Find PROMOTED Signs in local guardrails that aren't in global
    while IFS= read -r sign_line; do
        local sign_id
        sign_id=$(echo "$sign_line" | grep -oP 'SIGN-\d+' || echo "")
        if [[ -n "$sign_id" ]] && ! grep -q "$sign_id" "$guardrails_global" 2>/dev/null; then
            # New Sign — append to global with the description line following it
            local line_num
            line_num=$(grep -n "$sign_id" "$guardrails_local" | head -1 | cut -d: -f1)
            local desc_line
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

# Reorder plan.md tasks by risk (high first), preserving dependency constraints
reorder_by_risk() {
    local plan="${SPECTRA_DIR}/plan.md"
    [[ -f "$plan" ]] || return

    # Only reorder unchecked tasks — extract task numbers and their risk levels
    local -a high_tasks=() medium_tasks=() low_tasks=()
    local current_task="" current_risk=""

    while IFS= read -r line; do
        if echo "$line" | grep -qP '^## Task \d+:'; then
            current_task=$(echo "$line" | grep -oP 'Task \K\d+')
            current_risk=""
        fi
        if [[ -n "$current_task" ]] && echo "$line" | grep -qiP 'Risk:\s*(high|medium|low)'; then
            current_risk=$(echo "$line" | grep -oiP 'Risk:\s*\K(high|medium|low)')
            case "${current_risk,,}" in
                high)   high_tasks+=("$current_task") ;;
                medium) medium_tasks+=("$current_task") ;;
                low)    low_tasks+=("$current_task") ;;
            esac
            current_task=""
        fi
    done < "$plan"

    local reordered="${high_tasks[*]:-} ${medium_tasks[*]:-} ${low_tasks[*]:-}"
    echo "  Risk-first order: ${reordered}"
    echo "    High: ${high_tasks[*]:-none}"
    echo "    Medium: ${medium_tasks[*]:-none}"
    echo "    Low: ${low_tasks[*]:-none}"

    # Write risk ordering hint for next_task() to use
    echo "${reordered}" > "${SPECTRA_DIR}/.risk-order"
}

# Generate 3-line task summary and append to CLAUDE.md Task History
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

    # Extract key files changed from git
    local files_changed=""
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        files_changed=$(git diff --name-only HEAD~1 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//' || echo "unknown")
    fi

    # Append to CLAUDE.md Task History section
    if [[ -f CLAUDE.md ]]; then
        if grep -q '## Task History' CLAUDE.md 2>/dev/null; then
            # Append to existing section
            {
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        else
            # Create section
            {
                echo ""
                echo "## Task History"
                echo "${summary_line}"
                echo "  Files: ${files_changed:-none}"
            } >> CLAUDE.md
        fi
    fi
}

# Count tasks
count_tasks() {
    local total done remaining
    total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
    done=$(grep -c '^\- \[x\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
    remaining=$((total - done))
    echo "${total} ${done} ${remaining}"
}

# Get next unchecked task number and title (respects risk-order if present)
next_task() {
    # If risk-order file exists, use it to pick the next task
    if [[ -f "${SPECTRA_DIR}/.risk-order" ]]; then
        local risk_order
        risk_order=$(cat "${SPECTRA_DIR}/.risk-order" 2>/dev/null)
        for task_id in $risk_order; do
            # Find this task's checkbox line in plan.md
            local section_line
            section_line=$(grep -nP "^## Task ${task_id}:" "${SPECTRA_DIR}/plan.md" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
            if [[ -z "$section_line" ]]; then continue; fi

            # Find the unchecked checkbox within this task section
            local checkbox_line
            checkbox_line=$(sed -n "${section_line},\$p" "${SPECTRA_DIR}/plan.md" | grep -n '^\- \[ \]' | head -1 | cut -d: -f1 || echo "")
            if [[ -z "$checkbox_line" ]]; then continue; fi

            local actual_line=$((section_line + checkbox_line - 1))
            local task_text
            task_text=$(sed -n "${actual_line}p" "${SPECTRA_DIR}/plan.md" | sed 's/^- \[ \] //')
            echo "${task_id}|${task_text}|${actual_line}"
            return
        done
    fi

    # Fallback: sequential order
    local line
    line=$(grep -n '^\- \[ \]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | head -1 || echo "")
    if [[ -z "$line" ]]; then
        echo ""
        return
    fi
    local line_num task_text task_num
    line_num=$(echo "$line" | cut -d: -f1)
    task_text=$(echo "$line" | cut -d: -f2- | sed 's/^- \[ \] //')

    # Try to extract task number from section header above
    task_num=$(sed -n "1,${line_num}p" "${SPECTRA_DIR}/plan.md" | grep -oP 'Task \K\d+' | tail -1 || echo "0")
    echo "${task_num}|${task_text}|${line_num}"
}

# Get max iterations for a failure type
max_retries_for() {
    local failure_type="$1"
    case "$failure_type" in
        test_failure|missing_dependency) echo 3 ;;
        wiring_gap)                      echo 2 ;;
        *)                               echo 0 ;;  # STUCK
    esac
}

# ══════════════════════════════════════════════════════════════
# AGENT TEAMS FUNCTIONS
# ══════════════════════════════════════════════════════════════

# Extract project level from project.yaml
get_project_level() {
    local level
    level=$(grep 'level:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | grep -oP '\d+' || echo "1")
    echo "$level"
}

PROJECT_LEVEL=$(get_project_level)

# Check if Agent Teams execution is eligible
teams_eligible() {
    # Requirement 1: Level >= 3
    if [[ "$PROJECT_LEVEL" -lt 3 ]]; then
        return 1
    fi

    # Requirement 2: --enable-teams flag
    if [[ "$ENABLE_TEAMS" != true ]]; then
        return 1
    fi

    # Requirement 3: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
        return 1
    fi

    # Requirement 4: plan.md has TEAM_ELIGIBLE recommendation
    if ! grep -q 'TEAM_ELIGIBLE' "${SPECTRA_DIR}/plan.md" 2>/dev/null; then
        return 1
    fi

    return 0
}

# Extract parallel (independent) tasks from plan.md parallelism assessment
get_parallel_tasks() {
    local independent
    independent=$(grep -A1 'Independent tasks:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tail -1 | sed 's/^[- ]*//' || echo "")
    if [[ -z "$independent" ]]; then
        independent=$(grep -oP 'Independent tasks:\s*\K.*' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "")
    fi
    echo "$independent"
}

# Extract file ownership for a specific task from plan.md
get_file_ownership() {
    local task_num="$1"
    local in_task=false owns=""
    while IFS= read -r line; do
        if echo "$line" | grep -qP "^## Task ${task_num}:"; then
            in_task=true
            continue
        fi
        if [[ "$in_task" == true ]] && echo "$line" | grep -qP '^## Task \d+:'; then
            break
        fi
        if [[ "$in_task" == true ]] && echo "$line" | grep -q 'owns:'; then
            owns=$(echo "$line" | sed 's/.*owns:\s*//' | tr -d '[]')
        fi
    done < "${SPECTRA_DIR}/plan.md"
    echo "$owns"
}

# Install team hooks into .claude/settings.json and .spectra/hooks/
install_team_hooks() {
    local hooks_dir="${SPECTRA_HOME}/hooks"

    # Verify hooks exist
    if [[ ! -x "${hooks_dir}/spectra-task-completed.sh" ]]; then
        echo "  Warning: TaskCompleted hook not found at ${hooks_dir}/spectra-task-completed.sh"
    fi
    if [[ ! -x "${hooks_dir}/spectra-teammate-idle.sh" ]]; then
        echo "  Warning: TeammateIdle hook not found at ${hooks_dir}/spectra-teammate-idle.sh"
    fi

    echo "  Hooks installed from ${hooks_dir}"
}

# Build team prompt from plan.md file ownership data
build_team_prompt() {
    local prompt="You are the team lead for a SPECTRA Agent Teams parallel execution.\n\n"
    prompt+="Read CLAUDE.md for project context, then read .spectra/plan.md for the full plan.\n\n"
    prompt+="## Execution Rules\n"
    prompt+="1. Each teammate owns specific files listed in the plan's file_ownership sections.\n"
    prompt+="2. No two teammates may modify the same file simultaneously.\n"
    prompt+="3. Independent tasks (listed in Parallelism Assessment) can run in parallel.\n"
    prompt+="4. Sequential dependencies must be respected — check blockedBy fields.\n"
    prompt+="5. Each task must pass spectra-verify before being marked complete.\n"
    prompt+="6. If a teammate's task fails verification, they retry with diminishing budget.\n"
    prompt+="7. If any task hits STUCK, halt all execution and signal STUCK.\n\n"
    prompt+="## Task Assignment\n"
    prompt+="Create tasks from plan.md, assign file ownership per the plan, and coordinate execution.\n"
    prompt+="Use the TaskCompleted hook at ${SPECTRA_HOME}/hooks/spectra-task-completed.sh for verification gates.\n"
    echo -e "$prompt"
}

# Execute tasks using Agent Teams (parallel mode)
execute_with_teams() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Agent Teams — Parallel Execution         ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Project Level: ${PROJECT_LEVEL}"
    echo "  Parallel Tasks: $(get_parallel_tasks)"
    echo ""

    # Install hooks
    install_team_hooks

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would spawn team lead in delegate mode"
        echo "  [DRY RUN] Team lead would coordinate parallel task execution"
        return 0
    fi

    # Build the team prompt
    local team_prompt
    team_prompt=$(build_team_prompt)

    # Spawn team lead in delegate mode
    echo "  Spawning team lead (Opus, delegate mode)..."
    set +e
    claude --headless --permission-mode delegate \
        --prompt "${team_prompt}" \
        --max-turns 100 2>&1 | tee "${LOGS_DIR}/teams-execution.log"
    local teams_exit=$?
    set -e

    # Check results — count remaining tasks
    read TOTAL DONE REMAINING <<< $(count_tasks)
    if [[ $REMAINING -eq 0 ]]; then
        echo "  Agent Teams completed all tasks."
        return 0
    else
        echo "  Agent Teams completed ${DONE}/${TOTAL} tasks. ${REMAINING} remaining — falling back to sequential."
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# PHASE 1: PLANNING (if not skipped)
# ══════════════════════════════════════════════════════════════

if [[ "$SKIP_PLANNING" == false ]] && [[ ! -f "${SIGNALS_DIR}/plan-review.md" ]]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Phase 1: Planning                        ║"
    echo "╚══════════════════════════════════════════╝"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would spawn: spectra-planner (Opus)"
        echo "  [DRY RUN] Would spawn: spectra-reviewer (Sonnet)"
    else
        # Spawn planner
        echo "→ Spawning spectra-planner (Opus)..."
        claude --agent spectra-planner --headless --permission-mode plan \
            --prompt "Read the project description and generate all required SPECTRA planning artifacts for this project. Write to .spectra/ directory." \
            --max-turns 40 2>&1 | tee "${LOGS_DIR}/planning.log" || true

        # Spawn reviewer for plan validation
        echo "→ Spawning spectra-reviewer (Sonnet) for plan validation..."
        claude --agent spectra-reviewer --headless --permission-mode plan \
            --prompt "Review all planning artifacts in .spectra/ (constitution.md, plan.md, prd.md if present). Write your verdict to .spectra/signals/plan-review.md following the exact format in your instructions." \
            --max-turns 25 2>&1 | tee "${LOGS_DIR}/plan-review.log" || true

        # Check review verdict
        if [[ -f "${SIGNALS_DIR}/plan-review.md" ]]; then
            VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/plan-review.md" | head -1 || echo "UNKNOWN")
            echo "→ Plan review verdict: ${VERDICT}"

            case "$VERDICT" in
                APPROVED)
                    echo "  ✅ Plan approved. Proceeding to execution."
                    ;;
                APPROVED_WITH_WARNINGS)
                    echo "  ⚠  Plan approved with warnings. Warnings appended to guardrails.md."
                    # Extract and append warnings
                    sed -n '/### Warnings/,/### /p' "${SIGNALS_DIR}/plan-review.md" | \
                        grep '^\-' >> "${SPECTRA_DIR}/guardrails.md" 2>/dev/null || true
                    ;;
                REJECTED)
                    echo "  ❌ Plan rejected. Attempting one revision..."
                    # One autonomous revision attempt
                    claude --agent spectra-planner --headless --permission-mode plan \
                        --prompt "Your plan was REJECTED. Read .spectra/signals/plan-review.md for rejection reasons. Revise the planning artifacts to address all blocking issues. This is your ONE revision attempt." \
                        --max-turns 40 2>&1 | tee "${LOGS_DIR}/planning-revision.log" || true

                    # Re-review
                    rm -f "${SIGNALS_DIR}/plan-review.md"
                    claude --agent spectra-reviewer --headless --permission-mode plan \
                        --prompt "Re-review the revised planning artifacts in .spectra/. This is the second review — if still inadequate, REJECT again. Write verdict to .spectra/signals/plan-review.md." \
                        --max-turns 25 2>&1 | tee "${LOGS_DIR}/plan-re-review.log" || true

                    RE_VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/plan-review.md" 2>/dev/null | head -1 || echo "UNKNOWN")
                    if [[ "$RE_VERDICT" == "REJECTED" ]] || [[ "$RE_VERDICT" == "UNKNOWN" ]]; then
                        signal_stuck "Plan rejected twice. Human must revise planning artifacts."
                    fi
                    echo "  ✅ Revised plan approved (${RE_VERDICT}). Proceeding."
                    ;;
                *)
                    signal_stuck "Plan review returned unknown verdict: ${VERDICT}"
                    ;;
            esac
        else
            echo "  ⚠  No plan-review.md generated. Proceeding without formal review."
        fi
    fi

    if [[ "$PLAN_ONLY" == true ]]; then
        echo "→ --plan-only flag set. Exiting after planning phase."
        exit 0
    fi
fi

# ══════════════════════════════════════════════════════════════
# PRE-EXECUTION CHECKS
# ══════════════════════════════════════════════════════════════

if [[ ! -f "${SPECTRA_DIR}/plan.md" ]]; then
    echo "Error: No plan.md found. Cannot execute."
    exit 1
fi

# Check for existing STUCK signal
if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
    echo "⛔ STUCK signal found from previous run. Clear .spectra/signals/STUCK to continue."
    exit 1
fi

# Read task counts
read TOTAL DONE REMAINING <<< $(count_tasks)
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA v2.0 Execution Loop              ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Tasks:        ${DONE}/${TOTAL} complete (${REMAINING} remaining)"
echo "  Cost Ceiling: \$${COST_CEILING}"
echo "  Branch:       ${BRANCH_NAME}"
echo "  Dry Run:      ${DRY_RUN}"

# Auto-enable risk-first for Level 2+
if [[ "$PROJECT_LEVEL" -ge 2 ]] && [[ "$RISK_FIRST" == false ]]; then
    RISK_FIRST=true
    echo "  Risk-First:   auto-enabled (Level ${PROJECT_LEVEL})"
fi

# Determine execution mode
if teams_eligible; then
    EXECUTION_MODE="teams"
fi
echo "  Exec Mode:    ${EXECUTION_MODE}"
echo "  Teams Flag:   ${ENABLE_TEAMS}"
echo "  Risk First:   ${RISK_FIRST}"
echo "  Project Level: ${PROJECT_LEVEL}"
echo ""

# Apply risk-first reordering
if [[ "$RISK_FIRST" == true ]]; then
    echo "→ Applying risk-first task ordering..."
    reorder_by_risk
    echo ""
fi

# Generate initial CLAUDE.md
refresh_claude_md

PASS_HISTORY=""
TASK_FAILURES=()  # Track failure types per task for compound failure detection

# ══════════════════════════════════════════════════════════════
# PHASE 2.5: AGENT TEAMS EXECUTION (if eligible)
# ══════════════════════════════════════════════════════════════

if [[ "$EXECUTION_MODE" == "teams" ]]; then
    if execute_with_teams; then
        # Teams completed all tasks — skip sequential loop
        read TOTAL DONE REMAINING <<< $(count_tasks)
        if [[ $REMAINING -eq 0 ]]; then
            # Jump to Phase 5 completion
            PASS_HISTORY="Agent Teams: all tasks PASS"
            # Skip sequential loop entirely
            TASK_COUNT=$MAX_TASKS
        fi
    fi
    # If teams didn't finish everything, fall through to sequential
    read TOTAL DONE REMAINING <<< $(count_tasks)
    echo "  Continuing with sequential execution for ${REMAINING} remaining tasks..."
fi

# ══════════════════════════════════════════════════════════════
# PHASE 3: EXECUTION LOOP (sequential)
# ══════════════════════════════════════════════════════════════

TASK_COUNT=${TASK_COUNT:-0}
while [[ $TASK_COUNT -lt $MAX_TASKS ]]; do
    TASK_COUNT=$((TASK_COUNT + 1))

    # Get next task
    TASK_INFO=$(next_task)
    if [[ -z "$TASK_INFO" ]]; then
        echo "→ No more unchecked tasks."
        break
    fi

    TASK_NUM=$(echo "$TASK_INFO" | cut -d'|' -f1)
    TASK_TITLE=$(echo "$TASK_INFO" | cut -d'|' -f2)
    TASK_LINE=$(echo "$TASK_INFO" | cut -d'|' -f3)

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Task ${TASK_NUM}: ${TASK_TITLE:0:30}"
    echo "╚══════════════════════════════════════════╝"

    ITERATION=0
    MAX_ITER=3
    TASK_PASS=false
    LAST_FAILURE_TYPE=""
    TASK_FAILURE_TYPES=()

    while [[ $ITERATION -lt $MAX_ITER ]] && [[ "$TASK_PASS" == false ]]; do
        ITERATION=$((ITERATION + 1))

        write_status "${TASK_NUM}" "${TASK_TITLE}" "${ITERATION}" "${MAX_ITER}" "auditor" "${PASS_HISTORY}"

        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY RUN] Iteration ${ITERATION}/${MAX_ITER}"
            echo "  [DRY RUN] Would spawn: spectra-auditor (Haiku)"
            echo "  [DRY RUN] Would spawn: spectra-builder (Opus)"
            echo "  [DRY RUN] Would spawn: spectra-verifier (Opus)"
            TASK_PASS=true
            break
        fi

        # ── Step A: Pre-Flight Audit (Haiku — fast, cheap) ──
        echo "  [${ITERATION}/${MAX_ITER}] 🔍 Pre-flight audit (Haiku)..."
        PREFLIGHT_PROMPT="Scan codebase for active Sign violations before Task ${TASK_NUM} build. Report to .spectra/logs/task-${TASK_NUM}-preflight.md"
        claude --agent spectra-auditor --headless --permission-mode plan \
            --prompt "${PREFLIGHT_PROMPT}" \
            --max-turns 10 2>&1 | tail -5 || true

        # Read preflight advisory for builder context
        PREFLIGHT_ADVISORY=""
        if [[ -f "${LOGS_DIR}/task-${TASK_NUM}-preflight.md" ]]; then
            PREFLIGHT_ADVISORY=$(grep -A5 "Advisory for Builder" "${LOGS_DIR}/task-${TASK_NUM}-preflight.md" 2>/dev/null || echo "")
        fi

        # ── Step B: Build (Opus — full capability) ──
        write_status "${TASK_NUM}" "${TASK_TITLE}" "${ITERATION}" "${MAX_ITER}" "builder" "${PASS_HISTORY}"

        # Calculate token budget based on iteration (diminishing)
        case $ITERATION in
            1) MAX_TURNS=50 ;;
            2) MAX_TURNS=35 ;;  # ~70%
            3) MAX_TURNS=25 ;;  # ~50%
        esac

        BUILD_PROMPT="You are working on Task ${TASK_NUM}. Read CLAUDE.md for full context, then read .spectra/guardrails.md for active Signs."
        if [[ $ITERATION -gt 1 ]]; then
            BUILD_PROMPT="${BUILD_PROMPT} This is retry ${ITERATION}. Read .spectra/logs/task-${TASK_NUM}-verify.md for the verifier's failure report. Fix the specific issues identified."
        fi
        if [[ -n "$PREFLIGHT_ADVISORY" ]]; then
            BUILD_PROMPT="${BUILD_PROMPT} Pre-flight advisory: ${PREFLIGHT_ADVISORY}"
        fi

        echo "  [${ITERATION}/${MAX_ITER}] 🔨 Building (Opus, max ${MAX_TURNS} turns)..."
        claude --agent spectra-builder --headless --permission-mode acceptEdits \
            --prompt "${BUILD_PROMPT}" \
            --max-turns ${MAX_TURNS} 2>&1 | tail -10 || true

        # Check for STUCK signal from builder
        if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
            signal_stuck "Builder raised STUCK on Task ${TASK_NUM}: $(cat "${SIGNALS_DIR}/STUCK")"
        fi

        # ── Step B.5: Negotiate Detection ──
        if [[ -f "${SIGNALS_DIR}/NEGOTIATE" ]]; then
            echo "  [${ITERATION}/${MAX_ITER}] 🤝 Negotiate signal detected — routing to reviewer..."
            NEGOTIATE_PROMPT="A builder has raised a spec negotiation for Task ${TASK_NUM}. Read .spectra/signals/NEGOTIATE for the proposed adaptation. Evaluate against constitution.md and non-goals.md. Write your verdict to .spectra/signals/NEGOTIATE_REVIEW following the Spec Negotiation Review format in your instructions."
            claude --agent spectra-reviewer --headless --permission-mode plan \
                --prompt "${NEGOTIATE_PROMPT}" \
                --max-turns 15 2>&1 | tail -5 || true

            if [[ -f "${SIGNALS_DIR}/NEGOTIATE_REVIEW" ]]; then
                NEG_VERDICT=$(grep -oP 'Verdict:\s*\K\S+' "${SIGNALS_DIR}/NEGOTIATE_REVIEW" | head -1 || echo "UNKNOWN")
                echo "  Negotiate verdict: ${NEG_VERDICT}"

                case "$NEG_VERDICT" in
                    APPROVED)
                        echo "  ✅ Spec adaptation approved — appending constraint to plan.md"
                        # Extract the constraint to append
                        CONSTRAINT=$(sed -n '/### Constraint to Append/,/^$/p' "${SIGNALS_DIR}/NEGOTIATE_REVIEW" 2>/dev/null | grep '^>' | head -3 || echo "")
                        if [[ -n "$CONSTRAINT" ]]; then
                            echo "$CONSTRAINT" >> "${SPECTRA_DIR}/plan.md"
                        fi
                        ;;
                    ESCALATE)
                        signal_stuck "Spec negotiation escalated on Task ${TASK_NUM}. Reviewer says human must decide. See .spectra/signals/NEGOTIATE_REVIEW"
                        ;;
                    *)
                        echo "  ⚠  Unknown negotiate verdict: ${NEG_VERDICT}. Continuing build."
                        ;;
                esac
            else
                echo "  ⚠  No NEGOTIATE_REVIEW generated. Continuing without adaptation."
            fi

            # Clean up negotiate signals for this cycle
            rm -f "${SIGNALS_DIR}/NEGOTIATE"
            rm -f "${SIGNALS_DIR}/NEGOTIATE_REVIEW"
        fi

        # ── Step C: Verify (Opus — read-only, independent) ──
        write_status "${TASK_NUM}" "${TASK_TITLE}" "${ITERATION}" "${MAX_ITER}" "verifier" "${PASS_HISTORY}"

        # Determine verification depth (graduated for mid-tasks, full for final)
        read _TOTAL _DONE _REMAINING <<< $(count_tasks)
        VERIFY_FLAGS=""
        if [[ $_REMAINING -le 1 ]]; then
            VERIFY_DEPTH="full"
            VERIFY_FLAGS="--full-sweep"
        else
            VERIFY_DEPTH="graduated"
            VERIFY_FLAGS="--graduated"
        fi

        echo "  [${ITERATION}/${MAX_ITER}] ✓ Verifying (Opus, ${VERIFY_DEPTH})..."
        VERIFY_PROMPT="Verify Task ${TASK_NUM}. Verification depth: ${VERIFY_DEPTH}. Read CLAUDE.md and .spectra/plan.md for context. Write your report to .spectra/logs/task-${TASK_NUM}-verify.md"
        set +e
        claude --agent spectra-verifier --headless --permission-mode plan \
            --prompt "${VERIFY_PROMPT}" \
            --max-turns 30 2>&1 | tail -10
        VERIFY_EXIT=$?
        set -e

        # ── Step D: Parse verification result ──
        RESULT="UNKNOWN"
        FAILURE_TYPE=""
        if [[ -f "${LOGS_DIR}/task-${TASK_NUM}-verify.md" ]]; then
            RESULT=$(grep -oiP 'Result:\s*\K\S+' "${LOGS_DIR}/task-${TASK_NUM}-verify.md" | head -1 || echo "UNKNOWN")
            FAILURE_TYPE=$(grep -oiP 'Failure Type:\s*\K\S+' "${LOGS_DIR}/task-${TASK_NUM}-verify.md" | head -1 || echo "")
        fi

        # Also check exit code
        if [[ $VERIFY_EXIT -eq 0 ]] && [[ "$RESULT" == "UNKNOWN" ]]; then
            RESULT="PASS"
        fi

        if [[ "${RESULT^^}" == "PASS" ]]; then
            # ── PASS ──
            echo "  ✅ Task ${TASK_NUM} PASSED (iteration ${ITERATION})"
            TASK_PASS=true

            # Update plan.md — check off the task
            sed -i "${TASK_LINE}s/\- \[ \]/- [x]/" "${SPECTRA_DIR}/plan.md"

            # Update pass history
            if [[ $ITERATION -eq 1 ]]; then
                PASS_HISTORY="${PASS_HISTORY:+${PASS_HISTORY}, }Task ${TASK_NUM}: PASS"
            else
                PASS_HISTORY="${PASS_HISTORY:+${PASS_HISTORY}, }Task ${TASK_NUM}: FAIL→PASS"
            fi

            # Commit plan update
            if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                git add -A 2>/dev/null || true
                git commit -m "spectra: Task ${TASK_NUM} verified PASS (iter ${ITERATION})" --no-verify 2>/dev/null || true
            fi

            # Progressive context: append task summary to CLAUDE.md Task History
            generate_task_summary "${TASK_NUM}" "${TASK_TITLE}" "PASS" "${ITERATION}"

        else
            # ── FAIL ──
            echo "  ❌ Task ${TASK_NUM} FAILED (iteration ${ITERATION}, type: ${FAILURE_TYPE:-unknown})"

            # Track failure type for compound failure detection
            if [[ -n "$FAILURE_TYPE" ]]; then
                TASK_FAILURE_TYPES+=("$FAILURE_TYPE")
            fi

            # Compound failure check: two different failure types → STUCK
            if [[ ${#TASK_FAILURE_TYPES[@]} -ge 2 ]]; then
                UNIQUE_TYPES=($(printf '%s\n' "${TASK_FAILURE_TYPES[@]}" | sort -u))
                if [[ ${#UNIQUE_TYPES[@]} -ge 2 ]]; then
                    signal_stuck "Compound failure on Task ${TASK_NUM}: ${UNIQUE_TYPES[*]}. Two different failure types = plan is wrong, not code."
                fi
            fi

            # Check if failure type allows retry
            ALLOWED_RETRIES=$(max_retries_for "${FAILURE_TYPE}")
            if [[ "$ALLOWED_RETRIES" -eq 0 ]]; then
                signal_stuck "Non-retryable failure on Task ${TASK_NUM}: ${FAILURE_TYPE}"
            fi

            # Write fail context for builder retry
            cat > "${LOGS_DIR}/task-${TASK_NUM}-fail.md" <<EOF
## Fail Context — Task ${TASK_NUM}, Iteration ${ITERATION}
- Failure Type: ${FAILURE_TYPE}
- Remaining Iterations: $((MAX_ITER - ITERATION))
- Verifier Report: See .spectra/logs/task-${TASK_NUM}-verify.md
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Instructions for Builder
Fix the specific issues identified in the verifier report.
Include in your build report: what slipped, why, and what prevents recurrence.
EOF

            # Append to lessons-learned
            {
                echo ""
                echo "### LESSON-$(date +%Y%m%d%H%M%S)"
                echo "- **State:** TEMP"
                echo "- **Pattern:** Task ${TASK_NUM} failed verification (${FAILURE_TYPE})"
                echo "- **Fix:** Pending builder retry (iteration $((ITERATION + 1)))"
                echo "- **Projects Seen:** [$(basename "$(pwd)")]"
                echo "- **TTL Remaining:** 5 projects"
            } >> "${SPECTRA_DIR}/lessons-learned.md" 2>/dev/null || true

            # Check for TEMP→PROMOTED lessons and propagate to global guardrails
            propagate_signs
        fi

        # Refresh CLAUDE.md after each cycle
        refresh_claude_md

    done  # end iteration loop

    if [[ "$TASK_PASS" == false ]]; then
        signal_stuck "Task ${TASK_NUM} exhausted all ${MAX_ITER} iterations without passing."
    fi

    # Update progress
    read TOTAL DONE REMAINING <<< $(count_tasks)
    echo "  Progress: ${DONE}/${TOTAL} tasks complete (${REMAINING} remaining)"

done  # end task loop

# ══════════════════════════════════════════════════════════════
# PHASE 5: COMPLETION
# ══════════════════════════════════════════════════════════════

# Check if all tasks are done
read TOTAL DONE REMAINING <<< $(count_tasks)

if [[ $REMAINING -eq 0 ]] && [[ $TOTAL -gt 0 ]]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Phase 5: Final Review                    ║"
    echo "╚══════════════════════════════════════════╝"

    if [[ "$DRY_RUN" == false ]]; then
        # Final PR review by Sonnet
        echo "→ Spawning spectra-reviewer (Sonnet) for final PR review..."
        claude --agent spectra-reviewer --headless --permission-mode plan \
            --prompt "Perform a final PR review. Read .spectra/logs/ for all task reports. Review the git diff. Check lessons-learned.md for patterns worth promoting to Signs. Write your review to .spectra/logs/pr-review.md." \
            --max-turns 25 2>&1 | tee "${LOGS_DIR}/pr-review-session.log" || true
    fi

    signal_complete
    write_final_report

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
    echo "  ⚠  Loop ended with ${REMAINING} tasks remaining."
    write_final_report
fi
