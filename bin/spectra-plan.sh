#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Generator (BMAD → Ralph Bridge)
# Scans .spectra/stories/*.md OR BMAD artifacts and generates .spectra/plan.md
# Model and tools defined in ~/.claude/agents/spectra-planner.md
# Usage: spectra-plan [--from-bmad] [--bmad-dir PATH] [--dry-run]

SPECTRA_HOME="${HOME}/.spectra"
PLAN_VALIDATOR="${SPECTRA_HOME}/bin/spectra-plan-validate.sh"

# Defaults
FROM_BMAD=false
BMAD_DIR=""
DRY_RUN=false
LEVEL_OVERRIDE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from-bmad)    FROM_BMAD=true; shift ;;
        --bmad-dir)     BMAD_DIR="$2"; FROM_BMAD=true; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --level)        LEVEL_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA v5.0 Plan Generator

Usage: spectra-plan [OPTIONS]

Generates .spectra/plan.md from story files or BMAD artifacts.
Model and tools governed by spectra-planner agent definition.

Options:
  --from-bmad       Generate plan from BMAD artifacts (PRD + Architecture + Stories)
  --bmad-dir PATH   Explicit BMAD directory path (implies --from-bmad)
  --dry-run         Print generated plan to stdout, don't write file
  --level N         Override project level (0-4)
  -h, --help        Show this help

Modes:
  Default:      Reads .spectra/stories/*.md
  --from-bmad:  Reads bmad/ or .bmad/ (PRD, architecture, stories)

BMAD artifact discovery (checked in order):
  1. --bmad-dir PATH (explicit)
  2. bmad/ directory
  3. .bmad/ directory
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Source env (for Slack/Linear integration tokens)
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u
    source "${SPECTRA_HOME}/.env"
    set -u
fi

# ══════════════════════════════════════════
# LEVEL + TUNING RESOLUTION
# ══════════════════════════════════════════

PROJECT_LEVEL=1
if [[ -f .spectra/project.yaml ]]; then
    PROJECT_LEVEL=$(grep -oP '^level:\s*\K\d+' .spectra/project.yaml 2>/dev/null | head -1 || echo "1")
fi

RETRY_BUDGET=5
SCOPE_DEFAULT="code"
WIRING_DEPTH="basic"
HAS_ASSESSMENT=false

if [[ -f .spectra/assessment.yaml ]]; then
    HAS_ASSESSMENT=true
    RETRY_BUDGET=$(grep -oP '^\s*retry_budget:\s*\K\d+' .spectra/assessment.yaml 2>/dev/null | head -1 || echo "5")
    SCOPE_DEFAULT=$(grep -oP '^\s*scope_default:\s*\K\w+' .spectra/assessment.yaml 2>/dev/null | head -1 || echo "code")
    WIRING_DEPTH=$(grep -oP '^\s*wiring_depth:\s*\K\w+' .spectra/assessment.yaml 2>/dev/null | head -1 || echo "basic")
    ASSESSED_LEVEL=$(grep -oP '^\s*level:\s*\K\d+' .spectra/assessment.yaml 2>/dev/null | head -1 || echo "")
    if [[ -n "${ASSESSED_LEVEL}" ]] && [[ "${PROJECT_LEVEL}" -eq 1 ]]; then
        PROJECT_LEVEL="${ASSESSED_LEVEL}"
    fi
elif [[ "${FROM_BMAD}" == true ]]; then
    echo "  WARN: No .spectra/assessment.yaml found. Defaulting to Level 2 (bmad_method)."
    PROJECT_LEVEL=2
fi

# --level flag overrides everything
if [[ -n "${LEVEL_OVERRIDE}" ]]; then
    PROJECT_LEVEL="${LEVEL_OVERRIDE}"
fi

# ══════════════════════════════════════════
# BMAD ARTIFACT COLLECTION (--from-bmad mode)
# ══════════════════════════════════════════

STORIES_CONTENT=""
STORY_FILES=""
STORY_COUNT=0
PLAN_SOURCE=".spectra/stories/"
BMAD_WARNINGS=()
PRD_FILE=""
ARCH_FILE=""

if [[ "${FROM_BMAD}" == true ]]; then
    # Auto-discover BMAD directory if not explicit
    if [[ -z "${BMAD_DIR}" ]]; then
        if [[ -d "bmad" ]]; then
            BMAD_DIR="bmad"
        elif [[ -d ".bmad" ]]; then
            BMAD_DIR=".bmad"
        else
            echo "Error: --from-bmad specified but no bmad/ or .bmad/ directory found."
            echo "  Use --bmad-dir PATH to specify the BMAD artifact location."
            exit 1
        fi
    elif [[ ! -d "${BMAD_DIR}" ]]; then
        echo "Error: BMAD directory '${BMAD_DIR}' does not exist."
        exit 1
    fi

    PLAN_SOURCE="BMAD (${BMAD_DIR}/)"

    # Collect PRD (file path only — agent reads content from disk)
    PRD_FILE=$(find "${BMAD_DIR}" -maxdepth 2 -iname "*prd*" -name "*.md" 2>/dev/null | head -1 || true)
    if [[ -n "${PRD_FILE}" ]]; then
        echo "  PRD: ${PRD_FILE}"
    else
        BMAD_WARNINGS+=("No PRD found in ${BMAD_DIR}. Acceptance criteria derived from stories only.")
        echo "  WARN: No PRD found in ${BMAD_DIR}."
    fi

    # Collect Architecture (file path only — agent reads content from disk)
    ARCH_FILE=$(find "${BMAD_DIR}" -maxdepth 2 -iname "*arch*" -name "*.md" 2>/dev/null | head -1 || true)
    if [[ -n "${ARCH_FILE}" ]]; then
        echo "  Architecture: ${ARCH_FILE}"
    else
        BMAD_WARNINGS+=("No architecture doc in ${BMAD_DIR}. File ownership will be best-effort.")
        echo "  WARN: No architecture doc in ${BMAD_DIR}."
    fi

    # Collect Stories — look in stories/ subdir first, then top-level .story.md, then remaining .md
    BMAD_STORY_FILES=""
    if [[ -d "${BMAD_DIR}/stories" ]]; then
        BMAD_STORY_FILES=$(find "${BMAD_DIR}/stories" -name "*.md" -not -name ".gitkeep" 2>/dev/null | sort || true)
    fi
    if [[ -z "${BMAD_STORY_FILES}" ]]; then
        BMAD_STORY_FILES=$(find "${BMAD_DIR}" -maxdepth 1 -name "*.story.md" 2>/dev/null | sort || true)
    fi
    if [[ -z "${BMAD_STORY_FILES}" ]]; then
        # Remaining .md files excluding PRD and architecture
        BMAD_STORY_FILES=$(find "${BMAD_DIR}" -maxdepth 1 -name "*.md" \
            ! -iname "*prd*" ! -iname "*arch*" ! -iname "README.md" 2>/dev/null | sort || true)
    fi

    # Count BMAD stories
    if [[ -n "${BMAD_STORY_FILES}" ]]; then
        STORY_COUNT=$(echo "${BMAD_STORY_FILES}" | grep -c . || echo "0")
    fi

    # Fallback to .spectra/stories/ if BMAD has no stories
    if [[ "${STORY_COUNT}" -eq 0 ]] && [[ -d .spectra/stories ]]; then
        BMAD_STORY_FILES=$(find .spectra/stories -name "*.md" -not -name ".gitkeep" 2>/dev/null | sort || true)
        if [[ -n "${BMAD_STORY_FILES}" ]]; then
            STORY_COUNT=$(echo "${BMAD_STORY_FILES}" | grep -c . || echo "0")
        fi
        if [[ "${STORY_COUNT}" -gt 0 ]]; then
            BMAD_WARNINGS+=("No stories in ${BMAD_DIR}. Using .spectra/stories/ fallback.")
            echo "  WARN: No stories in ${BMAD_DIR}. Falling back to .spectra/stories/"
            PLAN_SOURCE="BMAD (${BMAD_DIR}/) + .spectra/stories/"
        fi
    fi

    # Hard fail if no stories anywhere
    if [[ "${STORY_COUNT}" -eq 0 ]]; then
        echo "Error: No stories found in ${BMAD_DIR}/ or .spectra/stories/."
        echo "  BMAD bridge requires at least one story file to generate a plan."
        echo "  Expected: ${BMAD_DIR}/stories/*.md or .spectra/stories/*.md"
        exit 1
    fi

    # Build stories content (for validation) and file list (for agent prompt)
    while IFS= read -r story; do
        [[ -z "${story}" ]] && continue
        STORY_FILES="${STORY_FILES}
- ${story}"
        STORIES_CONTENT="${STORIES_CONTENT}
--- $(basename "${story}") ---
$(cat "${story}")
"
    done <<< "${BMAD_STORY_FILES}"

    # Validate story content has meaningful structure (catches case-901/902 malformed artifacts)
    # Requires at least one: - AC: (codex format), ## Summary, ## Acceptance Criteria
    STORY_MARKERS=$(echo "${STORIES_CONTENT}" | grep -cE '^(- AC:|## (Summary|Acceptance Criteria|Acceptance))' 2>/dev/null | tr -dc '0-9' || echo "0")
    STORY_MARKERS=${STORY_MARKERS:-0}
    if [[ "${STORY_MARKERS}" -eq 0 ]]; then
        echo "Error: Story files found but contain no valid story entries."
        echo "  Expected: '# Story' or '## Story' headings with acceptance criteria."
        echo "  Check: ${BMAD_DIR}/stories/*.md or ${BMAD_DIR}/*.md"
        exit 1
    fi

else
    # ── Standard mode: read from .spectra/stories/ ──
    if [[ ! -d .spectra/stories ]]; then
        echo "Error: No .spectra/stories/ directory found. Run 'spectra-init' first."
        exit 1
    fi

    STORY_COUNT=$(find .spectra/stories -name "*.md" -not -name ".gitkeep" 2>/dev/null | wc -l | tr -dc '0-9')
    STORY_COUNT=${STORY_COUNT:-0}

    if [[ "$STORY_COUNT" -eq 0 ]]; then
        echo "Error: No story files found in .spectra/stories/"
        echo "Create story files like: .spectra/stories/001-feature-name.md"
        exit 1
    fi

    for story in $(find .spectra/stories -name "*.md" -not -name ".gitkeep" | sort); do
        STORY_FILES="${STORY_FILES}
- ${story}"
        STORIES_CONTENT="${STORIES_CONTENT}
--- $(basename "$story") ---
$(cat "$story")
"
    done
fi

# ══════════════════════════════════════════
# DISPLAY BANNER
# ══════════════════════════════════════════

echo "╔══════════════════════════════════════════╗"
echo "║        SPECTRA Plan Generator             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Mode:    $(if [[ "${FROM_BMAD}" == true ]]; then echo "BMAD bridge (--from-bmad)"; else echo "Standard (stories)"; fi)"
echo "  Source:  ${PLAN_SOURCE}"
echo "  Stories: ${STORY_COUNT}"
echo "  Level:   ${PROJECT_LEVEL}"
echo "  Retry:   ${RETRY_BUDGET} (from assessment)"
echo "  Agent:   spectra-planner"
if [[ "${DRY_RUN}" == true ]]; then
    echo "  Dry-run: YES (no file write)"
fi
echo ""

# Print BMAD warnings
for w in "${BMAD_WARNINGS[@]+${BMAD_WARNINGS[@]}}"; do
    echo "  WARN: ${w}"
done

# ══════════════════════════════════════════
# BUILD LEVEL-CONDITIONAL SCHEMA INSTRUCTIONS
# ══════════════════════════════════════════

LEVEL_FIELDS=""
if [[ "${PROJECT_LEVEL}" -ge 1 ]]; then
    LEVEL_FIELDS="${LEVEL_FIELDS}
- Risk: [low|medium|high]
- Max-iterations: [3|5|8|10]"
fi
if [[ "${PROJECT_LEVEL}" -ge 2 ]]; then
    LEVEL_FIELDS="${LEVEL_FIELDS}
- Scope: [code|infra|docs|config|multi-repo]
- Wiring-proof:
  - CLI: [exact command to exercise this task]
  - Integration: [cross-module/pipeline assertion]"
fi
if [[ "${PROJECT_LEVEL}" -ge 3 ]]; then
    LEVEL_FIELDS="${LEVEL_FIELDS}
- File-ownership:
  - owns: [files this task creates/modifies exclusively]
  - touches: [files this task modifies but shares with other tasks]
  - reads: [files this task only reads]"
fi

PARALLELISM_SECTION=""
if [[ "${PROJECT_LEVEL}" -ge 3 ]]; then
    PARALLELISM_SECTION="
## Parallelism Assessment
- Independent tasks: [001, 002] or [none]
- Sequential dependencies: [001 -> 002] or [none]
- Recommendation: [TEAM_ELIGIBLE|SEQUENTIAL_ONLY]"
fi

# ══════════════════════════════════════════
# BMAD BRIDGE INSTRUCTIONS (meta-rules only, no file content)
# ══════════════════════════════════════════

BMAD_INSTRUCTIONS=""
if [[ "${FROM_BMAD}" == true ]]; then
    BMAD_INSTRUCTIONS="
## BMAD Bridge Instructions
You are generating a plan from BMAD artifacts. Additional rules:
1. Extract acceptance criteria from PRD user stories AND from individual story files. Prefer story-level criteria when both exist.
2. If architecture.md defines component structure (e.g., src/auth/, src/api/), use it for File-ownership derivation (Level 3+).
3. If architecture.md defines API contracts or data models, reference them in Wiring-proof Integration field.
4. Map PRD non-functional requirements to Risk assessment (security/performance concerns = high risk).
5. Each BMAD story may map to 1-3 plan tasks. Split by logical unit of work — one task per independently verifiable deliverable.
6. Preserve BMAD story IDs in task titles where possible (e.g., 'US-1: ...' becomes 'Task 001: US-1 — ...').
7. Default Scope to '${SCOPE_DEFAULT}' unless the task clearly targets a different scope."
fi

# ══════════════════════════════════════════
# BUILD PLANNER PROMPT (file-path approach — BUG #2 fix)
# ══════════════════════════════════════════

GENERATED_DATE=$(date +%Y-%m-%d)

# Build file list for agent to read from disk (instead of inlining content)
READ_FILES="${STORY_FILES}"
[[ -n "${PRD_FILE}" ]] && READ_FILES="${READ_FILES}
- ${PRD_FILE}"
[[ -n "${ARCH_FILE}" ]] && READ_FILES="${READ_FILES}
- ${ARCH_FILE}"
[[ -f .spectra/constitution.md ]] && READ_FILES="${READ_FILES}
- .spectra/constitution.md"
[[ -f .spectra/assessment.yaml ]] && READ_FILES="${READ_FILES}
- .spectra/assessment.yaml"
[[ -f .spectra/discovery.md ]] && READ_FILES="${READ_FILES}
- .spectra/discovery.md"

PLAN_PROMPT="OUTPUT COMPLETE RAW MARKDOWN TO STDOUT starting with '# SPECTRA Execution Plan'.
No summary, no commentary, no permission requests. Your stdout IS the file — the calling script captures it via redirect.

Read these files:
${READ_FILES}

Generate a Level ${PROJECT_LEVEL} canonical plan.md from these $(if [[ "${FROM_BMAD}" == true ]]; then echo "BMAD artifacts"; else echo "stories"; fi).
${BMAD_INSTRUCTIONS}
## Project Level: ${PROJECT_LEVEL}

## Output Format
Generate EXACTLY this schema (no extra text before/after markdown):

# SPECTRA Execution Plan

## Project: (extract from constitution or stories)
## Level: ${PROJECT_LEVEL}
## Generated: ${GENERATED_DATE}
## Source: ${PLAN_SOURCE}

---

## Task 001: [Task title]
- [ ] 001: [Task title]
- AC:
  - [acceptance criterion 1]
  - [acceptance criterion 2]
- Files: [comma-separated file paths]
- Verify: \`[command that exits 0 on success]\`${LEVEL_FIELDS}

## Task 002: [Task title]
- [ ] 002: [Task title]
- AC:
  - [acceptance criterion 1]
- Files: [comma-separated file paths]
- Verify: \`[command that exits 0 on success]\`${LEVEL_FIELDS}
${PARALLELISM_SECTION}

Rules:
- One \`## Task NNN\` block per logical unit of work
- Header ID and checkbox ID must match exactly (e.g., Task 003 + - [ ] 003)
- Tasks must be in dependency order (prerequisite tasks first)
- Each task must have a concrete verification command
- Task numbers must be 3-digit zero-padded and strictly increasing (001, 002, ...)
- AC must be multi-line with \`  - \` sub-items (at least one criterion per task)
- Checkbox states: [ ] pending, [x] complete, [!] stuck
- Max-iterations: default ${RETRY_BUDGET} (from assessment); use 3 for trivial, 5 for setup, 8 for feature, 10 for complex
- Risk must be exactly one of: low, medium, high
- Scope must be exactly one of: code, infra, docs, config, multi-repo
- For Level 3+: file ownership lists MUST use square brackets: \`- owns: [file1.py, file2.py]\`. Use \`[]\` for empty lists, never \`(none)\`.
- For Level 3+: file ownership must be explicit and non-overlapping (SIGN-005)
- For Level 3+: owns = exclusive, touches = shared-modify, reads = read-only

Output ONLY the markdown content, no code fences wrapping it."

echo "→ Generating plan from $(if [[ "${FROM_BMAD}" == true ]]; then echo "BMAD artifacts"; else echo "stories"; fi)..."

# ── Slack notification: plan generation started ──
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    curl -s -X POST "${SLACK_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"SPECTRA: Plan generation started (${STORY_COUNT} stories, Level ${PROJECT_LEVEL})\"}" > /dev/null 2>&1 || true
fi

# ── Background progress indicator (BUG #4 fix) ──
show_progress() {
    local pid=$1
    local steps=("Parsing stories" "Reading PRD" "Reading architecture" "Generating plan" "Generating plan" "Generating plan" "Validating")
    local pcts=(10 20 30 50 60 70 90)
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $i -lt ${#steps[@]} ]]; then
            printf "\r  [%3d%%] %s..." "${pcts[$i]}" "${steps[$i]}"
            i=$((i + 1))
        else
            printf "\r  [%3d%%] Generating plan (still working)..." 80
        fi
        sleep 10
    done
    printf "\r  [100%%] Done.                              \n"
}

# ── Timeout-wrapped invocation (BUG #6 fix) ──
PLAN_TIMEOUT=${PLAN_TIMEOUT:-300}
set +e
timeout "${PLAN_TIMEOUT}" claude --agent spectra-planner --output-format text -p "${PLAN_PROMPT}" > .spectra/plan.md.new &
CLAUDE_PID=$!
show_progress $CLAUDE_PID
wait $CLAUDE_PID
CLAUDE_EXIT=$?
set -e

if [[ $CLAUDE_EXIT -eq 124 ]]; then
    echo "⚠  Plan generation timed out after ${PLAN_TIMEOUT}s. Try again or increase PLAN_TIMEOUT."
    rm -f .spectra/plan.md.new
    exit 1
elif [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "⚠  Plan generation failed (claude exit code: ${CLAUDE_EXIT})."
    rm -f .spectra/plan.md.new
    exit 1
fi

# ── Empty output check (BUG #7 fix) ──
if [[ ! -s .spectra/plan.md.new ]]; then
    echo "⚠  Plan generation produced empty output. Claude may have errored."
    echo "  Check: claude --agent spectra-planner -p 'test' to verify agent works."
    rm -f .spectra/plan.md.new
    exit 1
fi

# ══════════════════════════════════════════
# VALIDATE GENERATED PLAN
# ══════════════════════════════════════════

if [[ -x "${PLAN_VALIDATOR}" ]]; then
    VALIDATOR_LEVEL_FLAG=""
    [[ -n "${LEVEL_OVERRIDE}" ]] && VALIDATOR_LEVEL_FLAG="--level ${LEVEL_OVERRIDE}"
    if ! "${PLAN_VALIDATOR}" --file .spectra/plan.md.new --quiet ${VALIDATOR_LEVEL_FLAG}; then
        echo "⚠  Generated plan failed schema validation. Review .spectra/plan.md.new"
        echo "  Hint: ensure each task uses canonical '## Task NNN' + '- [ ] NNN:' format."
        if [[ "${DRY_RUN}" == true ]]; then
            cat .spectra/plan.md.new
            rm -f .spectra/plan.md.new
            echo "" >&2
            echo "  [dry-run] Plan printed to stdout despite validation failure." >&2
        fi
        exit 1
    fi
else
    echo "⚠  Plan validator not found at ${PLAN_VALIDATOR}. Falling back to basic checkbox check."
    if ! grep -qE '^\- \[ \] [0-9]{3}:' .spectra/plan.md.new 2>/dev/null; then
        echo "⚠  Generated plan doesn't look right. Saved to .spectra/plan.md.new for review."
        echo "  Expected checkbox format: - [ ] NNN: description"
        exit 1
    fi
fi

# ══════════════════════════════════════════
# RECONCILE SIGNAL (Phase 4.5 infrastructure)
# ══════════════════════════════════════════

if [[ "${HAS_ASSESSMENT}" == true ]] && [[ "${FROM_BMAD}" == true ]]; then
    # Check for assessment drift: compare assessment retry_budget vs generated Max-iterations
    PLAN_MAX_ITERS=$(grep -oP '^\- Max-iterations:\s*\K\d+' .spectra/plan.md.new 2>/dev/null | sort -u || true)
    DRIFT_DETAILS=""
    while IFS= read -r iter_val; do
        [[ -z "${iter_val}" ]] && continue
        if [[ "${iter_val}" -gt "${RETRY_BUDGET}" ]]; then
            DRIFT_DETAILS="${DRIFT_DETAILS}Max-iterations=${iter_val} exceeds retry_budget=${RETRY_BUDGET}; "
        fi
    done <<< "${PLAN_MAX_ITERS}"

    if [[ -n "${DRIFT_DETAILS}" ]]; then
        mkdir -p .spectra/signals
        cat > .spectra/signals/RECONCILE <<SIGNAL
signal: RECONCILE
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
reason: assessment_drift
source: spectra-plan --from-bmad
details: "${DRIFT_DETAILS%%; }"
SIGNAL
        echo "  RECONCILE signal written (assessment drift detected)."
    fi
fi

# ══════════════════════════════════════════
# OUTPUT ROUTING (dry-run vs normal)
# ══════════════════════════════════════════

if [[ "${DRY_RUN}" == true ]]; then
    cat .spectra/plan.md.new
    rm -f .spectra/plan.md.new
    echo "" >&2
    echo "  [dry-run] Plan printed to stdout. No files modified." >&2
else
    mv .spectra/plan.md.new .spectra/plan.md
    TASK_COUNT=$(grep -cE '^## Task [0-9]{3}:' .spectra/plan.md 2>/dev/null | tr -dc '0-9' || echo "0")
    TASK_COUNT=${TASK_COUNT:-0}
    echo ""
    echo "  Plan generated: ${TASK_COUNT} tasks"
    echo "  Output: .spectra/plan.md"
    echo ""
    echo "Next: Run 'spectra-loop' to start execution"

    # Slack notification: plan generation complete
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA: Plan generated (${TASK_COUNT} tasks, Level ${PROJECT_LEVEL})\"}" > /dev/null 2>&1 || true
    fi
fi
