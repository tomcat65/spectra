# SPECTRA

**S**ystematic **P**lanning, **E**xecution via **C**lean-context loops, **T**racking & verification with **R**eal-time **A**gent orchestration.

> Plan like BMAD. Execute like Ralph Wiggum. Orchestrate like Your Claude Engineer.

SPECTRA is a unified AI-driven software engineering methodology that combines the planning depth of [BMAD](https://github.com/bmad-code-org/BMAD-METHOD), the execution simplicity of [Ralph Wiggum](https://ralph-wiggum.ai/), and the orchestration rigor of [Your Claude Engineer](https://github.com/coleam00/your-claude-engineer) into a single, scale-adaptive pipeline.

## How It Works

```
Stories  -->  Plan  -->  Execute  -->  Verify  -->  Ship
 (BMAD)      (BMAD)     (Ralph)      (YCE)      (YCE)
```

SPECTRA right-sizes process to project complexity:

| Level | Scope | Planning | Execution |
|-------|-------|----------|-----------|
| 0 | Bug fix / hotfix | Skip to task | Single agent, one pass |
| 1 | Small feature (< 1 day) | Quick spec | Sequential loop (3-5 iterations) |
| 2 | Medium feature (1-5 days) | Full PRD + stories | Sequential loop + verification gates |
| 3 | Large feature (1-4 weeks) | Full pipeline | Agent Teams (parallel builders) |
| 4 | Enterprise system (1+ months) | Full pipeline + sprints | Agent Teams + sprint delivery |

## Installation

SPECTRA is installed globally at `~/.spectra/` and integrates with Claude Code via agent definitions at `~/.claude/agents/`.

### Prerequisites

- [Claude Code CLI](https://claude.com/claude-code) (Opus 4.6+)
- Agent Teams enabled: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json` env
- Git

### Directory Structure

```
~/.spectra/                         # Global SPECTRA installation
  .env                              # Integration tokens (Linear, Slack, GitHub)
  SPECTRA_METHOD.md                 # Full methodology reference
  SPECTRA_AUTONOMY_CONTRACT.md      # Agent autonomy boundaries
  SPECTRA_COMPLETE.md               # Completion signal specification
  guardrails-global.md              # Cross-project Signs
  bin/                              # Executable scripts
    spectra-init.sh                 #   Project scaffolding
    spectra-plan.sh                 #   Plan generation (uses spectra-planner agent)
    spectra-loop-v3.sh              #   Main launcher (Level routing)
    spectra-loop-legacy.sh          #   Sequential loop (Level 0-2)
    spectra-quick.sh                #   Quick single-task execution
    spectra-verify.sh               #   Standalone verification
    spectra-team-prompt.sh          #   Team prompt generator (Level 3+)
  hooks/                            # Claude Code lifecycle hooks
    spectra-task-completed.sh       #   Gate check on task completion
    spectra-teammate-idle.sh        #   Safety net for idle agents
  templates/                        # Project scaffolding templates
    .spectra/                       #   Per-project template files
  agents/                           # Legacy agent copies (canonical at ~/.claude/agents/)
  signals/                          # Signal file definitions

~/.claude/agents/                   # Canonical agent definitions
  spectra-lead.md                   # Team coordinator (Level 3+)
  spectra-planner.md                # Planning artifact generator
  spectra-builder.md                # Code implementer
  spectra-verifier.md               # Quality gate
  spectra-reviewer.md               # Cross-model adversarial reviewer
  spectra-auditor.md                # Fast pre-flight scanner
  spectra-scout.md                  # Pre-planning investigator
  spectra-orchestrator.md           # Manual/interactive orchestrator (deprecated for automation)
```

### Per-Project Structure

When you run `spectra-init` inside a project, it scaffolds:

```
your-project/
  .spectra/
    constitution.md                 # Project principles and constraints
    prd.md                          # Product requirements (Level 2+)
    architecture.md                 # System design (Level 3+)
    stories/                        # User stories with acceptance criteria
      001-feature-name.md
      002-another-feature.md
    plan.md                         # Execution manifest (task checkboxes)
    guardrails.md                   # Project-specific Signs
    lessons-learned.md              # FAIL -> FIX log
    PROMPT_build.md                 # Builder context prompt
    PROMPT_verify.md                # Verifier context prompt
    PROMPT_split.md                 # Stuck task splitter prompt
    screenshots/                    # Visual evidence
```

## Usage

### Quick Start (Level 0-1)

```bash
# Initialize a project
cd your-project
spectra-init --name my-feature --level 1

# Write stories
# Edit .spectra/stories/001-my-story.md with acceptance criteria

# Generate execution plan
spectra-plan

# Run the loop
spectra-loop
```

### Full Pipeline (Level 3+)

```bash
# Initialize
cd your-project
spectra-init --name big-feature --level 3

# Planning phase (fills constitution, PRD, architecture, stories)
# Use claude-desktop or /spectra-prime for interactive planning

# Generate plan from stories
spectra-plan

# Launch Agent Teams execution
spectra-loop
# This automatically:
#   1. Detects Level 3 -> launches spectra-lead agent
#   2. Lead creates team, parses plan.md into shared task list
#   3. Spawns auditor -> builder -> verifier per task
#   4. Parallel builders for independent tasks, serial verification
#   5. Final review by spectra-reviewer (Sonnet cross-model)
#   6. Writes COMPLETE signal and shuts down team
```

### Force Sequential Mode

```bash
spectra-loop --sequential    # Uses legacy loop even for Level 3+
```

## Agent Architecture (v3.1)

Model selection and tool restrictions are defined in agent YAML frontmatter at `~/.claude/agents/spectra-*.md`. There are no env vars for model routing.

| Agent | Model | Role | Key Tools | Constraint |
|-------|-------|------|-----------|------------|
| **spectra-lead** | Opus | Coordinator | TeamCreate, TaskCreate, SendMessage | No Edit/Write (SIGN-004) |
| **spectra-builder** | Opus | Implementer | Read, Edit, Write, Bash | acceptEdits mode |
| **spectra-verifier** | Opus | Quality gate | Read, Bash, Grep | No Edit/Write |
| **spectra-reviewer** | Sonnet | Adversarial review | Read, Grep, Bash | Different model = different failure modes |
| **spectra-auditor** | Haiku | Pre-flight scan | Read, Grep, Glob | 10 turns max, minimal cost |
| **spectra-planner** | Opus | Plan generation | Read, Grep, Glob, Bash | plan mode, research only |

### Why Different Models?

- **Opus** for builder/verifier/lead: Maximum capability for code generation and verification
- **Sonnet** for reviewer: Different model architecture catches different bugs (cross-model assurance, not cost optimization)
- **Haiku** for auditor: Speed and cost efficiency for pre-flight scans that don't need deep reasoning

## Core Principles

1. **No Done without evidence.** Every task needs test results AND proof. The verification gate is non-negotiable.

2. **Fresh context is a feature.** Each iteration starts clean. State lives in files and git, never in LLM memory.

3. **Plan proportionally.** A bug fix doesn't need a PRD. An enterprise system does.

4. **Complement, don't compromise.** Planning tools plan. Execution tools execute. Orchestration tools orchestrate.

5. **Parallel build, serial verify.** (Doctrine 5) Multiple builders can work simultaneously, but verification is always sequential.

## Signs (Learned Guardrails)

Signs are hard-won lessons from execution failures. They live in `guardrails.md` and are checked by both the Builder and Verifier.

| Sign | Rule |
|------|------|
| SIGN-001 | Integration tests must invoke what they import |
| SIGN-002 | CLI commands need subprocess-level tests |
| SIGN-003 | Lessons must generalize, not just fix |
| SIGN-004 | Lead must never edit source files |
| SIGN-005 | No two builders on the same file simultaneously |
| SIGN-006 | Verification is never parallel |
| SIGN-007 | Always shutdown_request before TeamDelete |

New Signs are discovered through FAIL -> FIX cycles. Cross-project Signs propagate via the verifier's `user`-scoped memory and the neural knowledge graph.

## Integration Tokens

Integration tokens live in `~/.spectra/.env` (chmod 600):

| Token | Used By | Purpose |
|-------|---------|---------|
| `LINEAR_API_KEY` | spectra-init.sh | Create Linear projects/issues |
| `LINEAR_TEAM_ID` | spectra-init.sh | Target Linear team |
| `SLACK_WEBHOOK_URL` | spectra-loop-v3.sh, spectra-verify.sh, spectra-init.sh | Notifications |
| `GITHUB_TOKEN` | Fallback (gh CLI handles its own auth) | GitHub API |

## Multi-Agent Collaboration

SPECTRA agents can coordinate with external agents (codex-cli, claude-desktop, ChatGPT) via the [Neural AI Collaboration MCP server](https://github.com/your-org/neural-ai-collaboration). Neural provides:

- Shared knowledge graph (entities, relations, observations)
- Cross-agent messaging
- Persistent memory across sessions

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | Feb 7, 2026 | Initial methodology, BMAD+Ralph+YCE unification |
| v1.1 | Feb 8, 2026 | Wiring Proof, Signs (001-003), 4-agent roster, verification gates |
| v3.0 | Feb 9, 2026 | Replaced --headless multi-process with thin launcher + Agent Teams |
| v3.1 | Feb 9-10, 2026 | spectra-lead agent, hybrid Level routing, hook rewrites, model routing cleanup |

## Reference

- Full methodology: [SPECTRA_METHOD.md](SPECTRA_METHOD.md)
- Autonomy contract: [SPECTRA_AUTONOMY_CONTRACT.md](SPECTRA_AUTONOMY_CONTRACT.md)
- Completion signals: [SPECTRA_COMPLETE.md](SPECTRA_COMPLETE.md)
- Global guardrails: [guardrails-global.md](guardrails-global.md)
