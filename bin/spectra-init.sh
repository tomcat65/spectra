#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v5.1 Project Initializer                                ║
# ║  Scaffolds .spectra/ + CLAUDE.md for All-Anthropic subagents     ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-init --name "Project" [--level 0-4] [--linear] [--slack]

SPECTRA_HOME="${HOME}/.spectra"
TEMPLATE_DIR="${SPECTRA_HOME}/templates/.spectra"

# Defaults
PROJECT_NAME=""
LEVEL=1
LEVEL_EXPLICIT=false
USE_LINEAR=false
USE_SLACK=false
NO_COMMIT=false
COST_CEILING="50.00"
PER_TASK_BUDGET="10.00"

# Cross-platform sed -i helper (GNU vs BSD)
sed_inplace() {
    if sed --version >/dev/null 2>&1; then sed -i "$@"
    else sed -i '' "$@"; fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)           PROJECT_NAME="$2"; shift 2 ;;
        --level)          LEVEL="$2"; LEVEL_EXPLICIT=true; shift 2 ;;
        --linear)         USE_LINEAR=true; shift ;;
        --slack)          USE_SLACK=true; shift ;;
        --no-commit)      NO_COMMIT=true; shift ;;
        --cost-ceiling)   COST_CEILING="$2"; shift 2 ;;
        --per-task-budget) PER_TASK_BUDGET="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA v5.1 Project Initializer

Usage: spectra-init --name "Project Name" [OPTIONS]

Options:
  --name NAME          Project name (required)
  --level 0-4          SPECTRA scale level (default: 1)
  --linear             Enable Linear issue tracking
  --slack              Enable Slack notifications
  --no-commit          Skip initial git commit
  --cost-ceiling N     Cost ceiling in USD (default: 50.00)
  --per-task-budget N  Per-task budget in USD (default: 10.00)
  -h, --help           Show this help

Architecture (v5.1 — All-Anthropic):
  spectra-planner   Opus    Planning artifacts
  spectra-reviewer  Sonnet  Cross-model plan validation
  spectra-auditor   Haiku   Pre-flight Sign scanning
  spectra-builder   Opus    Task implementation
  spectra-verifier  Opus    Independent 4-step audit (read-only)
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: --name is required"
    exit 1
fi

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA v5.1 Project Initializer         ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Project: ${PROJECT_NAME}"
echo "  Level:   ${LEVEL}"
echo "  Date:    ${DATE}"
echo ""

# ── Create directory structure ──
echo "→ Creating .spectra/ directory structure..."
mkdir -p .spectra/stories .spectra/screenshots .spectra/logs .spectra/signals

# ── Assessment (optional — populates level + tuning) ──
if [[ ! -f .spectra/assessment.yaml ]]; then
    if [[ -x "${SPECTRA_HOME}/bin/spectra-assess.sh" ]]; then
        echo "→ Running project assessment..."
        if [[ -t 0 ]]; then
            "${SPECTRA_HOME}/bin/spectra-assess.sh" --force || true
        else
            "${SPECTRA_HOME}/bin/spectra-assess.sh" --force --non-interactive --track bmad_method || true
        fi
    fi
fi

if [[ -f .spectra/assessment.yaml ]] && [[ "${LEVEL_EXPLICIT}" == false ]]; then
    ASSESSED_LEVEL=$(grep -oP '^\s*level:\s*\K\d+' .spectra/assessment.yaml 2>/dev/null | head -1 || echo "")
    if [[ -n "${ASSESSED_LEVEL}" ]]; then
        LEVEL="${ASSESSED_LEVEL}"
        echo "  Level set from assessment: ${LEVEL}"
    fi
fi

# ── Hydrate templates ──
hydrate() {
    local src="$1" dst="$2"
    sed -e "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" \
        -e "s/{{DATE}}/${DATE}/g" \
        -e "s/{{LEVEL}}/${LEVEL}/g" \
        "$src" > "$dst"
}

echo "→ Copying templates..."
hydrate "${TEMPLATE_DIR}/constitution.md.tmpl" ".spectra/constitution.md"
hydrate "${TEMPLATE_DIR}/plan.md.tmpl" ".spectra/plan.md"
hydrate "${TEMPLATE_DIR}/tasks.md.tmpl" ".spectra/tasks.md"

# Level-gated artifacts
[[ "$LEVEL" -ge 1 ]] && hydrate "${TEMPLATE_DIR}/prd.md.tmpl" ".spectra/prd.md"
[[ "$LEVEL" -ge 3 ]] && hydrate "${TEMPLATE_DIR}/architecture.md.tmpl" ".spectra/architecture.md"

# Guardrails and lessons-learned (Level 1+)
if [[ "$LEVEL" -ge 1 ]]; then
    hydrate "${TEMPLATE_DIR}/guardrails.md.tmpl" ".spectra/guardrails.md"
    # Append global Signs to local guardrails
    if [[ -f "${SPECTRA_HOME}/guardrails-global.md" ]]; then
        echo "" >> ".spectra/guardrails.md"
        echo "# --- Global Signs (propagated from ~/.spectra/guardrails-global.md) ---" >> ".spectra/guardrails.md"
        grep -E "^### SIGN-|^> " "${SPECTRA_HOME}/guardrails-global.md" >> ".spectra/guardrails.md" 2>/dev/null || true
        echo "→ Global Signs propagated to local guardrails.md"
    fi
    hydrate "${TEMPLATE_DIR}/lessons-learned.md.tmpl" ".spectra/lessons-learned.md"
fi

# ── Wiring Verification Setup ──
echo "→ Setting up wiring verification..."
if [[ -f "${SPECTRA_HOME}/templates/verify.yaml.template" ]]; then
    cp "${SPECTRA_HOME}/templates/verify.yaml.template" ".spectra/verify.yaml"

    if [[ -t 0 ]]; then
        # Interactive mode: ask user for project-specific values
        echo ""
        echo "=== Wiring Verification Setup ==="
        read -p "  Source directories (comma-separated, e.g. src/,lib/): " WV_SOURCE_DIRS
        read -p "  Test directories (comma-separated, default: tests/): " WV_TEST_DIRS
        WV_TEST_DIRS="${WV_TEST_DIRS:-tests/}"
        read -p "  Entry point files (comma-separated, e.g. src/server.py): " WV_ENTRY_POINTS
        read -p "  Language (python/typescript/javascript/go/rust): " WV_LANGUAGE

        # Format as YAML lists
        fmt_list() { echo "$1" | tr ',' '\n' | sed 's/^\s*//;s/\s*$//' | grep -v '^$' \
            | sed 's/.*/"&"/' | paste -sd, | sed 's/^/[/;s/$/]/'; }

        [[ -n "$WV_SOURCE_DIRS" ]] && sed_inplace "s|source_dirs: \[\]|source_dirs: $(fmt_list "$WV_SOURCE_DIRS")|" .spectra/verify.yaml
        sed_inplace "s|test_dirs: \[\"tests/\"\]|test_dirs: $(fmt_list "$WV_TEST_DIRS")|" .spectra/verify.yaml
        [[ -n "$WV_ENTRY_POINTS" ]] && sed_inplace "s|entry_points: \[\]|entry_points: $(fmt_list "$WV_ENTRY_POINTS")|" .spectra/verify.yaml
        [[ -n "$WV_LANGUAGE" ]] && sed_inplace "s|language: \"\"|language: \"$WV_LANGUAGE\"|" .spectra/verify.yaml

        # Framework auto-detection
        if [[ "$WV_LANGUAGE" == "python" ]]; then
            if grep -qi "fastapi" requirements.txt 2>/dev/null || grep -qi "fastapi" pyproject.toml 2>/dev/null; then
                echo "  Detected FastAPI — adding framework checks..."
                sed_inplace '/framework_checks: \[\]/c\  framework_checks:\n    - name: "no-flask-tuple-returns"\n      pattern: '"'"'return\\s+\\{.*\\},\\s*[0-9]{3}'"'"'\n      paths: '"$(fmt_list "$WV_SOURCE_DIRS")"'\n      severity: error\n      message: "Flask-style tuple return in FastAPI — use JSONResponse"' .spectra/verify.yaml
            fi
        fi
    else
        echo "  Non-interactive: verify.yaml template copied (edit manually)"
    fi
    echo "  Created: .spectra/verify.yaml"
else
    echo "  WARN: verify.yaml.template not found. Skipping wiring verification setup."
fi

# ── Generate project.yaml (v5.0 — All-Anthropic agents) ──
cat > .spectra/project.yaml <<YAML
# SPECTRA v5.1 Project Configuration
name: ${PROJECT_NAME}
level: ${LEVEL}
created: ${DATE}
status: initialized
spectra_version: "5.1"

# All-Anthropic Agent Roster (Claude Code Tier 2 Subagents)
agents:
  planner: spectra-planner     # Opus — generates planning artifacts
  reviewer: spectra-reviewer   # Sonnet — cross-model plan validation
  auditor: spectra-auditor     # Haiku — pre-flight Sign scanning
  builder: spectra-builder     # Opus — task implementation
  verifier: spectra-verifier   # Opus — independent 4-step audit (read-only)

# Cost Governance (Autonomy Contract §6)
cost:
  ceiling: ${COST_CEILING}
  per_task_budget: ${PER_TASK_BUDGET}
  parallelism_budget: 0

# Integrations
integrations:
  linear: ${USE_LINEAR}
  slack: ${USE_SLACK}

# Verification Configuration
verification:
  wiring_proof: true
  evidence_chain: true
  regression_required: true
  four_step_audit: true
YAML

# ── Copy prompt files ──
cp "${TEMPLATE_DIR}/PROMPT_build.md" ".spectra/PROMPT_build.md"
cp "${TEMPLATE_DIR}/PROMPT_verify.md" ".spectra/PROMPT_verify.md"
[[ -f "${TEMPLATE_DIR}/PROMPT_split.md" ]] && cp "${TEMPLATE_DIR}/PROMPT_split.md" ".spectra/PROMPT_split.md"

# ── Gitkeeps ──
cp "${TEMPLATE_DIR}/stories/.gitkeep" ".spectra/stories/.gitkeep" 2>/dev/null || true
cp "${TEMPLATE_DIR}/screenshots/.gitkeep" ".spectra/screenshots/.gitkeep" 2>/dev/null || true
touch ".spectra/logs/.gitkeep" ".spectra/signals/.gitkeep"

# ── Generate CLAUDE.md (single integration point for all subagents) ──
echo "→ Generating CLAUDE.md..."
cat > CLAUDE.md <<EOF
# CLAUDE.md — SPECTRA Context (auto-generated, do not edit manually)
# Refreshed by spectra-loop after every task cycle.

## SPECTRA Context
- Project: ${PROJECT_NAME}
- Level: ${LEVEL}
- Phase: initialized
- Branch: (not yet started)
- Spectra Version: 5.1

## Active Signs
$(cat .spectra/guardrails.md 2>/dev/null | grep -E "^### SIGN-|^> " | head -20 || echo "None defined yet — will populate from guardrails.md")

## Non-Goals
$(cat .spectra/non-goals.md 2>/dev/null || echo "None defined — create .spectra/non-goals.md if needed")

## Wiring Proof (Mandatory — 5 checks before every commit)
1. CLI paths — subprocess-level tests prove real execution
2. Import invocation — every import is actually called (no dead code)
3. Pipeline completeness — integration tests exercise full chain
4. Error boundaries — CLI exceptions produce clean messages, not tracebacks
5. Dependencies declared — every import in requirements/pyproject/package.json

## Evidence Chain
- Commits: feat(task-N) or fix(task-N)
- Reports: .spectra/logs/task-N-{build|verify|preflight}.md

## Plan Status
$(grep -E '^\- \[.\]' .spectra/plan.md 2>/dev/null | head -20 || echo "No tasks yet — fill in plan.md")
EOF

# ── Source env for integrations ──
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# ── Linear integration ──
if [[ "$USE_LINEAR" == true ]]; then
    if [[ -z "${LINEAR_API_KEY:-}" ]]; then
        echo "⚠  --linear requested but LINEAR_API_KEY not set in ${SPECTRA_HOME}/.env"
    else
        echo "→ Creating Linear project..."
        RESPONSE=$(curl -s https://api.linear.app/graphql \
            -H "Authorization: ${LINEAR_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "{\"query\":\"mutation { projectCreate(input: { name: \\\"${PROJECT_NAME}\\\", teamIds: [\\\"${LINEAR_TEAM_ID:-}\\\"] }) { success project { id name url } } }\"}")
        PROJECT_URL=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('projectCreate',{}).get('project',{}).get('url',''))" 2>/dev/null || echo "")
        if [[ -n "$PROJECT_URL" ]]; then
            echo "  Linear project: ${PROJECT_URL}"
            echo "{\"linear_project_url\": \"${PROJECT_URL}\"}" > .spectra/.linear_project.json
        else
            echo "⚠  Linear project creation failed."
        fi
    fi
fi

# ── Slack notification ──
if [[ "$USE_SLACK" == true ]]; then
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"🚀 SPECTRA v5.1 initialized: *${PROJECT_NAME}* (Level ${LEVEL})\"}" > /dev/null 2>&1 || true
        echo "→ Slack notified."
    fi
fi

# ── Git commit ──
if [[ "$NO_COMMIT" == false ]]; then
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "→ Creating initial SPECTRA commit..."
        git add .spectra/ CLAUDE.md
        git commit -m "chore: initialize SPECTRA v5.1 framework (Level ${LEVEL})" --no-verify 2>/dev/null || echo "  Nothing to commit."
    else
        echo "⚠  Not a git repository. Run 'git init' first."
    fi
fi

# ── PATH setup ──
if [[ ":${PATH}:" != *":${SPECTRA_HOME}/bin:"* ]]; then
    SHELL_RC="${HOME}/.bashrc"
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-/bin/bash}")" == "zsh" ]]; then
        SHELL_RC="${HOME}/.zshrc"
    fi
    if ! grep -q 'spectra/bin' "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo '# SPECTRA CLI tools' >> "$SHELL_RC"
        echo "export PATH=\"\$HOME/.spectra/bin:\$PATH\"" >> "$SHELL_RC"
        echo "  PATH: Added ~/.spectra/bin to ${SHELL_RC}"
        echo "        Run 'source ${SHELL_RC}' or open a new terminal to use spectra-* commands."
    fi
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA v5.1 initialized!                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Files created:"
echo "    .spectra/project.yaml    — Project config (All-Anthropic agents)"
echo "    .spectra/constitution.md — Project constraints"
echo "    .spectra/plan.md         — Execution plan (fill in tasks)"
echo "    .spectra/guardrails.md   — Sign patterns"
echo "    .spectra/verify.yaml     — Wiring verification rules"
echo "    .spectra/signals/        — Runtime signal directory"
echo "    CLAUDE.md                — Subagent context (auto-refreshed)"
echo ""
echo "  Next steps:"
echo "    1. Edit .spectra/constitution.md with project constraints"
[[ "$LEVEL" -ge 1 ]] && echo "    2. Fill in .spectra/prd.md with requirements"
[[ "$LEVEL" -ge 2 ]] && echo "    3. Create stories in .spectra/stories/"
echo "    4. Run: spectra-loop              (full autonomous pipeline)"
echo "    5. Or:  spectra-loop --plan-only  (planning + review only)"
echo "    6. Or:  spectra-loop --dry-run    (preview without execution)"
