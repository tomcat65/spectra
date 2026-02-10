#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Plan Generator (BMAD → Ralph Bridge)
# Scans .spectra/stories/*.md and generates .spectra/plan.md in Ralph-compatible format
# Model and tools defined in ~/.claude/agents/spectra-planner.md
# Usage: spectra-plan

SPECTRA_HOME="${HOME}/.spectra"

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

# Generate the plan using Claude
PLAN_PROMPT="You are a SPECTRA plan generator. Convert the following stories into a plan.md file.

## Constitution
${CONSTITUTION}

## Stories
${STORIES_CONTENT}

## Output Format
Generate EXACTLY this format (no other text):

\`\`\`markdown
# SPECTRA Execution Plan

## Project: (extract from constitution or stories)
## Generated: $(date +%Y-%m-%d)
## Generated from: .spectra/stories/

### Tasks (in dependency order)

- [ ] NNN: Task description
  - AC: Acceptance criteria (from story)
  - Files: Files to create/modify
  - Verify: \`command that exits 0 on success\`
  - Max iterations: N
\`\`\`

Rules:
- One task per acceptance criterion or logical unit of work
- Tasks must be in dependency order (prerequisite tasks first)
- Each task must have a concrete verification command
- Task numbers must be 3-digit zero-padded (001, 002, ...)
- Max iterations: 5 for setup tasks, 8 for feature tasks, 10 for complex tasks

Output ONLY the markdown content, no code fences wrapping it."

echo "→ Generating plan from stories..."

claude --agent spectra-planner -p "${PLAN_PROMPT}" > .spectra/plan.md.new

# Validate the output looks like a plan
if grep -q '^\- \[ \]' .spectra/plan.md.new 2>/dev/null; then
    mv .spectra/plan.md.new .spectra/plan.md
    TASK_COUNT=$(grep -c '^\- \[ \]' .spectra/plan.md)
    echo ""
    echo "  Plan generated: ${TASK_COUNT} tasks"
    echo "  Output: .spectra/plan.md"
    echo ""
    echo "Next: Run 'spectra-loop' to start execution"
else
    echo "⚠  Generated plan doesn't look right. Saved to .spectra/plan.md.new for review."
    echo "  Expected checkbox format: - [ ] NNN: description"
    exit 1
fi
