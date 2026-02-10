#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v3.1 Execution Loop — Native Agent Teams Architecture   ║
# ║  Hybrid launcher: Level 0-2 → legacy loop, Level 3+ → Agent     ║
# ║  Teams with spectra-lead agent for parallel execution.           ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-loop [--plan-only] [--skip-planning] [--dry-run] [--cost-ceiling N] [--risk-first]
#
# Architecture: All orchestration logic (retry loops, failure taxonomy,
# diminishing budgets, compound failure detection) is embedded in the
# team prompt as natural language instructions. Claude handles it natively
# via Agent Teams instead of bash process management.

SPECTRA_HOME="${HOME}/.spectra"
SPECTRA_DIR=".spectra"
SIGNALS_DIR="${SPECTRA_DIR}/signals"
LOGS_DIR="${SPECTRA_DIR}/logs"
PROMPT_GENERATOR="${SPECTRA_HOME}/bin/spectra-team-prompt.sh"
PLAN_VALIDATOR="${SPECTRA_HOME}/bin/spectra-plan-validate.sh"

# ── Defaults ──
PLAN_ONLY=false
SKIP_PLANNING=false
DRY_RUN=false
COST_CEILING=""
RISK_FIRST=false
FORCE_SEQUENTIAL=false
MAX_TURNS=200
START_TIME=$(date +%s)

# ── Parse arguments ──
PASSTHROUGH_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan-only)     PLAN_ONLY=true; PASSTHROUGH_ARGS+=("$1"); shift ;;
        --skip-planning) SKIP_PLANNING=true; PASSTHROUGH_ARGS+=("$1"); shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --risk-first)    RISK_FIRST=true; PASSTHROUGH_ARGS+=("$1"); shift ;;
        --cost-ceiling)  COST_CEILING="$2"; PASSTHROUGH_ARGS+=("$1" "$2"); shift 2 ;;
        --max-turns)     MAX_TURNS="$2"; shift 2 ;;
        --sequential)    FORCE_SEQUENTIAL=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA v3.1 Execution Loop (Native Agent Teams)

Usage: spectra-loop [OPTIONS]

Options:
  --plan-only       Run planning + review gate only, then exit
  --skip-planning   Skip to execution (plan already approved)
  --dry-run         Print the team prompt without spawning agents
  --risk-first      Execute high-risk tasks first (default on for Level 2+)
  --cost-ceiling N  Override cost ceiling from project.yaml (USD)
  --max-turns N     Override max turns for team lead session (default: 200)
  --sequential      Force legacy sequential loop for any project level
  -h, --help        Show this help

Architecture:
  v3.1 uses a hybrid model:
  - Level 0-2: Sequential execution via spectra-loop-legacy.sh
  - Level 3+: Native Agent Teams with spectra-lead agent
  Use --sequential to force legacy loop for any project level.

  The team lead (spectra-lead agent) spawns teammates using
  TeamCreate/TaskCreate/SendMessage APIs for coordinated execution
  with shared task lists and mailbox messaging.

Legacy:
  The previous bash-orchestrated loop is preserved as spectra-loop-legacy.sh.
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Source env ──
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# ── Preflight: verify .env tokens (runs once, then only on .env change) ──
"${SPECTRA_HOME}/bin/spectra-preflight.sh"

# ── Verify project ──
if [[ ! -d "${SPECTRA_DIR}" ]]; then
    echo "Error: No .spectra/ directory found. Run 'spectra-init' first."
    exit 1
fi

# ── Ensure directories ──
mkdir -p "${SIGNALS_DIR}" "${LOGS_DIR}"

# ── Check for existing STUCK signal ──
if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
    echo "  STUCK signal found from previous run. Clear .spectra/signals/STUCK to continue."
    exit 1
fi

# ── Branch isolation ──
BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if [[ "$DRY_RUN" == false ]]; then
        git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
    fi
fi
export SPECTRA_BRANCH="${BRANCH_NAME}"

# ── Cost ceiling from project.yaml or override ──
if [[ -z "$COST_CEILING" ]] && [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
    COST_CEILING=$(grep 'ceiling:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "50.00")
fi
COST_CEILING="${COST_CEILING:-50.00}"

# ── Auto-enable risk-first for Level 2+ ──
PROJECT_LEVEL="1"
if [[ -f "${SPECTRA_DIR}/project.yaml" ]]; then
    PROJECT_LEVEL=$(grep 'level:' "${SPECTRA_DIR}/project.yaml" 2>/dev/null | head -1 | grep -oP '\d+' || echo "1")
fi
if [[ "$PROJECT_LEVEL" -ge 2 ]] && [[ "$RISK_FIRST" == false ]]; then
    RISK_FIRST=true
    PASSTHROUGH_ARGS+=("--risk-first")
fi

# ── Level-based routing: Level 0-2 → legacy sequential loop ──
if [[ "$FORCE_SEQUENTIAL" == true ]] || [[ "$PROJECT_LEVEL" -le 2 ]]; then
    if [[ "$DRY_RUN" == false ]]; then
        echo "  Level ${PROJECT_LEVEL}: Using sequential execution (legacy loop)"
        exec "${SPECTRA_HOME}/bin/spectra-loop-legacy.sh" "${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}"
    else
        echo "  Level ${PROJECT_LEVEL}: Would use sequential execution (legacy loop)"
        echo "  [DRY RUN] Would launch: spectra-loop-legacy.sh ${PASSTHROUGH_ARGS[*]+"${PASSTHROUGH_ARGS[*]}"}"
        exit 0
    fi
fi

# ── Elapsed time helper ──
elapsed() {
    local now diff
    now=$(date +%s)
    diff=$((now - START_TIME))
    printf '%02d:%02d:%02d' $((diff/3600)) $(((diff%3600)/60)) $((diff%60))
}

validate_plan_contract() {
    if [[ ! -f "${SPECTRA_DIR}/plan.md" ]]; then
        echo "Error: No .spectra/plan.md found."
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

# ── Observability signal helpers ──
write_signal() {
    local signal_name="$1" signal_value="$2"
    echo "${signal_value}" > "${SIGNALS_DIR}/${signal_name}"
}

write_progress() {
    local total done stuck
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        done=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        [[ "$total" -eq 0 ]] && total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0") && done=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0") && stuck=0
        write_signal "PROGRESS" "${done}/${total} tasks (${stuck} stuck)"
    fi
}

# ── Display banner ──
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA v3.1 — Agent Teams Loop          ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Project Level: ${PROJECT_LEVEL}"
echo "  Branch:        ${BRANCH_NAME}"
echo "  Cost Ceiling:  \$${COST_CEILING}"
echo "  Risk First:    ${RISK_FIRST}"
echo "  Max Turns:     ${MAX_TURNS}"
echo "  Dry Run:       ${DRY_RUN}"
echo ""

# ── Verify prompt generator exists ──
if [[ ! -x "$PROMPT_GENERATOR" ]]; then
    echo "Error: Team prompt generator not found at ${PROMPT_GENERATOR}"
    echo "  Expected: ${SPECTRA_HOME}/bin/spectra-team-prompt.sh"
    exit 1
fi

if ! validate_plan_contract; then
    exit 1
fi

# ── Write initial signals ──
write_signal "PHASE" "executing"
write_signal "AGENT" "spectra-lead"
write_progress

# ── Generate team prompt ──
echo "  Generating team prompt..."
TEAM_PROMPT=$("${PROMPT_GENERATOR}" "${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}")

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  DRY RUN — Team Prompt Preview            ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "$TEAM_PROMPT"
    echo ""
    echo "  [DRY RUN] Would launch: claude --agent spectra-lead -p --max-turns ${MAX_TURNS}"
    exit 0
fi

# ── Launch single Claude Code session as team lead ──
echo "  Launching team lead session (spectra-lead agent, max ${MAX_TURNS} turns)..."
echo "  Monitor: tail -f ${SIGNALS_DIR}/STATUS"
echo ""

set +e
claude --agent spectra-lead -p "${TEAM_PROMPT}" \
    --max-turns "${MAX_TURNS}" 2>&1 | tee "${LOGS_DIR}/teams-execution.log"
SESSION_EXIT=$?
set -e

# ── Clean up orphaned team directories ──
rm -rf "${HOME}/.claude/teams/spectra-run" 2>/dev/null || true
rm -rf "${HOME}/.claude/tasks/spectra-run" 2>/dev/null || true

# ── Post-session: check signals ──
echo ""
echo "  Team lead session exited (code: ${SESSION_EXIT})"
echo "  Elapsed: $(elapsed)"

if [[ -f "${SIGNALS_DIR}/COMPLETE" ]]; then
    write_signal "PHASE" "complete"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  COMPLETE — All tasks passed               ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Branch: ${BRANCH_NAME}"
    echo "  Elapsed: $(elapsed)"

    if [[ -f "${LOGS_DIR}/final-report.md" ]]; then
        echo "  Report: ${LOGS_DIR}/final-report.md"
    fi

    echo ""
    echo "  Next: Review the branch and merge when ready."
    echo "    git diff main...${BRANCH_NAME}"
    echo "    git merge ${BRANCH_NAME}"

    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA COMPLETE: All tasks passed (branch: ${BRANCH_NAME}, elapsed: $(elapsed))\"}" > /dev/null 2>&1 || true
    fi

elif [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
    write_signal "PHASE" "stuck"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  STUCK — Execution halted                  ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Reason: $(grep 'Reason:' "${SIGNALS_DIR}/STUCK" 2>/dev/null | sed 's/.*Reason: //' || echo "unknown")"
    echo "  Branch preserved: ${BRANCH_NAME}"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        STUCK_REASON=$(grep 'Reason:' "${SIGNALS_DIR}/STUCK" 2>/dev/null | sed 's/.*Reason: //' || echo "unknown")
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA STUCK: ${STUCK_REASON} (branch: ${BRANCH_NAME})\"}" > /dev/null 2>&1 || true
    fi

    exit 1
else
    echo ""
    echo "  Session ended without COMPLETE or STUCK signal."
    echo "  Check ${LOGS_DIR}/teams-execution.log for details."

    # Check partial progress (supports [x] complete, [!] stuck)
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        TOTAL=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        DONE=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        STUCK=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
        if [[ "${TOTAL}" -eq 0 ]]; then
            TOTAL=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
            DONE=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
            STUCK=0
        fi
        REMAINING=$((TOTAL - DONE - STUCK))
        echo "  Progress: ${DONE}/${TOTAL} tasks complete (${REMAINING} remaining, ${STUCK} stuck)"
    fi

    echo "  Branch preserved: ${BRANCH_NAME}"
    exit 1
fi
