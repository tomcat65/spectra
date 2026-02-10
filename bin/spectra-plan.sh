#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Generator (BMAD → Ralph Bridge)
# Scans .spectra/stories/*.md and generates .spectra/plan.md in Ralph-compatible format
# Model and tools defined in ~/.claude/agents/spectra-planner.md
# Usage: spectra-plan

SPECTRA_HOME="${HOME}/.spectra"
PLAN_VALIDATOR="${SPECTRA_HOME}/bin/spectra-plan-validate.sh"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: spectra-plan"
            echo ""
            echo "Generates .spectra/plan.md from story files in .spectra/stories/"
            echo "Model and tools governed by spectra-planner agent definition."
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

# Verify we're in a SPECTRA project
if [[ ! -d .spectra/stories ]]; then
    echo "Error: No .spectra/stories/ directory found. Run 'spectra-init' first."
    exit 1
fi

# Count stories
STORY_COUNT=$(find .spectra/stories -name "*.md" -not -name ".gitkeep" 2>/dev/null | wc -l)

if [[ "$STORY_COUNT" -eq 0 ]]; then
    echo "Error: No story files found in .spectra/stories/"
    echo "Create story files like: .spectra/stories/001-feature-name.md"
    exit 1
fi

echo "╔══════════════════════════════════════════╗"
echo "║        SPECTRA Plan Generator             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Stories found: ${STORY_COUNT}"
echo "  Agent: spectra-planner"
echo ""

# Build context from all stories
STORIES_CONTENT=""
for story in $(find .spectra/stories -name "*.md" -not -name ".gitkeep" | sort); do
    STORIES_CONTENT="${STORIES_CONTENT}
--- $(basename "$story") ---
$(cat "$story")
"
done

# Read constitution if it exists
CONSTITUTION=""
if [[ -f .spectra/constitution.md ]]; then
    CONSTITUTION=$(cat .spectra/constitution.md)
fi

# Determine project level
PROJECT_LEVEL=1
if [[ -f .spectra/project.yaml ]]; then
    PROJECT_LEVEL=$(grep -oP '^level:\s*\K\d+' .spectra/project.yaml 2>/dev/null | head -1 || echo "1")
fi
echo "  Project Level: ${PROJECT_LEVEL}"

# Build level-conditional schema instructions
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

# Generate the plan using Claude
PLAN_PROMPT="You are a SPECTRA plan generator. Convert the following stories into a canonical plan.md file.

## Constitution
${CONSTITUTION}

## Stories
${STORIES_CONTENT}

## Project Level: ${PROJECT_LEVEL}

## Output Format
Generate EXACTLY this schema (no extra text before/after markdown):

\`\`\`markdown
# SPECTRA Execution Plan

## Project: (extract from constitution or stories)
## Level: ${PROJECT_LEVEL}
## Generated: $(date +%Y-%m-%d)
## Source: .spectra/stories/

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
\`\`\`

Rules:
- One \`## Task NNN\` block per logical unit of work
- Header ID and checkbox ID must match exactly (e.g., Task 003 + - [ ] 003)
- Tasks must be in dependency order (prerequisite tasks first)
- Each task must have a concrete verification command
- Task numbers must be 3-digit zero-padded and strictly increasing (001, 002, ...)
- AC must be multi-line with \`  - \` sub-items (at least one criterion per task)
- Checkbox states: [ ] pending, [x] complete, [!] stuck
- Max-iterations: 3 for trivial, 5 for setup, 8 for feature, 10 for complex tasks
- Risk must be exactly one of: low, medium, high
- Scope must be exactly one of: code, infra, docs, config, multi-repo
- For Level 3+: file ownership must be explicit and non-overlapping (SIGN-005)
- For Level 3+: owns = exclusive, touches = shared-modify, reads = read-only

Output ONLY the markdown content, no code fences wrapping it."

echo "→ Generating plan from stories..."

claude --agent spectra-planner -p "${PLAN_PROMPT}" > .spectra/plan.md.new

# Validate generated plan against canonical schema
if [[ -x "${PLAN_VALIDATOR}" ]]; then
    if ! "${PLAN_VALIDATOR}" --file .spectra/plan.md.new --quiet; then
        echo "⚠  Generated plan failed schema validation. Review .spectra/plan.md.new"
        echo "  Hint: ensure each task uses canonical '## Task NNN' + '- [ ] NNN:' format."
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

mv .spectra/plan.md.new .spectra/plan.md
TASK_COUNT=$(grep -cE '^## Task [0-9]{3}:' .spectra/plan.md || echo "0")
echo ""
echo "  Plan generated: ${TASK_COUNT} tasks"
echo "  Output: .spectra/plan.md"
echo ""
echo "Next: Run 'spectra-loop' to start execution"
