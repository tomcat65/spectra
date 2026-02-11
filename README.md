# SPECTRA

**S**ystematic **P**lanning, **E**xecution via **C**lean-context loops, **T**racking & verification with **R**eal-time **A**gent orchestration.

> Plan like BMAD. Execute like Ralph Wiggum. Orchestrate like Your Claude Engineer.

SPECTRA is a unified AI-driven software engineering methodology that combines the planning depth of [BMAD](https://github.com/bmad-code-org/BMAD-METHOD), the execution simplicity of [Ralph Wiggum](https://ralph-wiggum.ai/), and the orchestration rigor of [Your Claude Engineer](https://github.com/coleam00/your-claude-engineer) into a single, scale-adaptive pipeline.

## How It Works

```
Stories  -->  Plan  -->  Execute  -->  Verify  -->  Ship
 (BMAD)      (BMAD)     (Ralph)      (YCE)      (YCE)
```

SPECTRA right-sizes process to project complexity. You tell it how big the job is (or let it figure it out), and it adjusts how much planning, verification, and coordination happens:

| Level | Scope | Planning | Execution |
|-------|-------|----------|-----------|
| 0 | Bug fix / hotfix | Skip to task | Single agent, one pass |
| 1 | Small feature (< 1 day) | Quick spec | Sequential loop (3-5 iterations) |
| 2 | Medium feature (1-5 days) | Full PRD + stories | Sequential loop + verification gates |
| 3 | Large feature (1-4 weeks) | Full pipeline | Parallel builders (`&` + `wait`) |
| 4 | Enterprise system (1+ months) | Full pipeline + sprints | Parallel builders + sprint delivery |

## Installation

SPECTRA is installed globally at `~/.spectra/` and integrates with Claude Code via agent definitions at `~/.claude/agents/`.

### Prerequisites

- [Claude Code CLI](https://claude.com/claude-code) (Opus 4.6+)
- Git
- `jq` (optional, for checkpoint JSON parsing; falls back to grep)

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
    spectra-assess.sh               #   BMAD adapter (project assessment)
    spectra-plan.sh                 #   Plan generation (uses spectra-planner agent)
    spectra-plan-validate.sh        #   Canonical plan.md schema validation (v4)
    spectra-loop.sh                 #   Main loop (symlink → spectra-loop-v5.sh)
    spectra-loop-v5.sh              #   v5.0 bash-native parallel loop (all levels)
    spectra-loop-legacy.sh          #   Legacy sequential loop (preserved for reference)
    spectra-preflight.sh            #   Token verification (runs once, then on .env change)
    spectra-quick.sh                #   Quick single-task execution
    spectra-verify.sh               #   Standalone verification
    spectra-verify-wiring.sh        #   Automated wiring verification (v5.1)
    spectra-status.sh               #   Observability dashboard (--json, --watch)
  hooks/                            # Claude Code lifecycle hooks (reserved)
  templates/                        # Project scaffolding templates
    .spectra/                       #   Per-project template files
  fixtures/                         # Test fixtures
    verify.yaml.template            #   Wiring verification config template (v5.1)
    plan-bridge/                    #   Plan schema validation fixtures
    assessment/                     #   Assessment YAML fixtures
    bmad-bridge/                    #   BMAD bridge parsing fixtures
  proposals/                        # Design artifacts and contracts
  agents/                           # Legacy agent copies (canonical at ~/.claude/agents/)
  signals/                          # Signal file definitions

~/.claude/agents/                   # Canonical agent definitions
  spectra-planner.md                # Planning artifact generator (Opus)
  spectra-builder.md                # Code implementer (Opus)
  spectra-verifier.md               # Quality gate (Opus)
  spectra-reviewer.md               # Cross-model adversarial reviewer (Sonnet)
  spectra-auditor.md                # Fast pre-flight scanner (Haiku)
  spectra-oracle.md                 # 3-turn failure classifier (Haiku)
  spectra-scout.md                  # Pre-planning investigator
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
    project.yaml                    # Runtime config (level, agents, cost)
    verify.yaml                     # Wiring verification rules (v5.1)
    assessment.yaml                 # BMAD assessment (from spectra-assess)
    guardrails.md                   # Project-specific Signs
    lessons-learned.md              # FAIL -> FIX log
    PROMPT_build.md                 # Builder context prompt
    PROMPT_verify.md                # Verifier context prompt
    PROMPT_split.md                 # Stuck task splitter prompt
    screenshots/                    # Visual evidence
    signals/                        # Runtime status signals
      PHASE                         #   Current execution phase
      AGENT                         #   Active agent name
      PROGRESS                      #   Task completion counters
      STATUS                        #   Human-readable status line
      STUCK                         #   Stuck marker with reason
      COMPLETE                      #   Completion marker with timestamp
      RECONCILE                     #   Planning gap feedback (Phase 4.5)
```

## Project Assessment (`spectra-assess`)

Before writing code, SPECTRA figures out how complex your project is and what verification intensity it needs. That's what `spectra-assess` does.

**What it does:** Maps your project's characteristics (language, team size, integrations, risk factors) to a SPECTRA Level (0-4) and tuning parameters (verification intensity, retry budget, etc.).

**Output:** `.spectra/assessment.yaml` — a read-only analysis file that `spectra-init` and `spectra-plan` use to configure the project.

### Three-Tier Detection

`spectra-assess` tries to detect if you're using [BMAD](https://github.com/bmad-code-org/BMAD-METHOD) for planning:

1. **BMAD CLI installed** (`bmad` command available) — records version, sets `source.mode: bmad-detected`
2. **BMAD directory found** (`bmad/` or `.bmad/`) — records path, sets `source.mode: bmad-detected`
3. **Neither found** — falls back to interactive prompts (or `--non-interactive` defaults)

In all cases, assessment uses the same deterministic decision tree to map inputs to Level + tuning.

### Track-to-Level Mapping

| Track | Level | When |
|-------|-------|------|
| `quick_flow` | 0 | Low blast radius, no integrations, no risks |
| `quick_flow` | 1 | Any complexity factor present |
| `bmad_method` | 2 | Default for structured planning |
| `bmad_method` | 3 | Complexity triggers: 3+ integrations, 5+ team, high blast, security/payments risk |
| `enterprise` | 4 | Always Level 4 |

### Usage

```bash
# Interactive (asks you questions)
spectra-assess

# CI/automation (must specify track)
spectra-assess --non-interactive --track bmad_method

# Override and force regeneration
spectra-assess --force

# Called automatically by spectra-init (you don't usually need to run it manually)
```

## BMAD Bridge (`spectra-plan --from-bmad`)

If you already have BMAD planning artifacts (PRD, architecture doc, user stories), SPECTRA can consume them directly instead of requiring you to rewrite everything as `.spectra/stories/`.

**What it does:** Reads BMAD artifacts and generates a canonical `plan.md` with proper level-conditional fields, file ownership, and parallelism assessment.

### BMAD Directory Discovery

The bridge looks for your BMAD artifacts in this order:

1. `--bmad-dir PATH` (explicit override)
2. `bmad/` directory in your project root
3. `.bmad/` directory in your project root

Inside that directory, it looks for:
- `*prd*.md` — Product requirements (acceptance criteria, risk factors)
- `*arch*.md` — Architecture (component structure, file ownership hints)
- `stories/*.md` — Individual user stories (task decomposition)

### Graceful Degradation

| Missing Artifact | What Happens |
|-----------------|--------------|
| Stories | Hard FAIL (exit 1) — can't build a plan without tasks |
| PRD | Warning + proceed — derives AC from stories alone |
| Architecture | Warning + proceed — file ownership is best-effort |

### Usage

```bash
# Generate plan from BMAD artifacts
spectra-plan --from-bmad

# Specify BMAD directory explicitly
spectra-plan --from-bmad --bmad-dir ./my-bmad-docs

# Preview without writing (prints to stdout)
spectra-plan --from-bmad --dry-run

# Override level regardless of assessment
spectra-plan --from-bmad --level 3

# Standard mode (unchanged — reads .spectra/stories/)
spectra-plan
```

### How It Works

1. Reads `assessment.yaml` for level and tuning (or defaults to Level 2 if missing)
2. Collects BMAD artifacts (PRD + architecture + stories)
3. Validates story content has meaningful structure (heading + acceptance criteria)
4. Sends everything to the `spectra-planner` agent with augmented BMAD bridge instructions
5. Planner generates canonical `plan.md` with level-appropriate fields
6. Validates output through `spectra-plan-validate.sh`
7. Checks for assessment drift and writes `RECONCILE` signal if needed
8. Writes `.spectra/plan.md` (or prints to stdout with `--dry-run`)

Complex BMAD stories are split into multiple plan tasks (1:N ratio) — one task per independently verifiable deliverable. File ownership for Level 3+ is derived from the architecture doc on a best-effort basis.

## Examples

These examples walk through SPECTRA from simplest to most complex. Start with Example 1 — you can stop reading at any point and still have enough to use SPECTRA.

### Example 1: Fix a Bug (Level 0)

The simplest case. You found a bug and want an AI agent to fix it.

```bash
# Navigate to your project
cd my-web-app

# Initialize SPECTRA for a quick fix
spectra-init --name "fix-login-redirect" --level 0
```

This creates a `.spectra/` directory in your project with template files. The important one is the story file. Open it and describe the bug:

```bash
# Edit the story file (use any editor)
# File: .spectra/stories/001-fix-login-redirect.md
```

Write something like:

```markdown
# Story 001: Fix login redirect

## Summary
After login, users are redirected to /undefined instead of /dashboard.

## Acceptance Criteria
- Successful login redirects to /dashboard
- Failed login stays on /login with error message
- Direct navigation to /dashboard without login redirects to /login

## Technical Notes
- Bug is likely in src/auth/login.ts redirect logic
```

Now generate the plan and run it:

```bash
# Generate the execution plan (calls AI planner)
spectra-plan

# Run it — SPECTRA handles the rest
spectra-loop

# Check status anytime while it's running
spectra-status
```

For a Level 0 fix, `spectra-loop` runs a single agent that reads the plan, makes the fix, and verifies it. If the verification command passes, you're done. If it fails, the agent retries (up to `Max-iterations` times).

**What gets created:**
- `.spectra/plan.md` — one task with your bug description, files to change, and a verify command
- `.spectra/signals/PROGRESS` — shows `1/1 done` when complete
- `.spectra/signals/COMPLETE` — written when the loop finishes successfully

### Example 2: Build a Small Feature (Level 1)

Adding a dark mode toggle to an existing app. This needs 2-3 stories and a few iterations.

```bash
cd my-web-app
spectra-init --name "dark-mode" --level 1
```

Write 2 stories:

**`.spectra/stories/001-toggle-component.md`:**
```markdown
# Story 001: Dark mode toggle component

## Summary
Add a toggle switch in the header that switches between light and dark themes.

## Acceptance Criteria
- Toggle renders in the top-right of the header
- Clicking toggles between light/dark class on <body>
- Preference persists in localStorage
- Default follows OS preference (prefers-color-scheme)
```

**`.spectra/stories/002-theme-styles.md`:**
```markdown
# Story 002: Dark mode CSS variables

## Summary
Define CSS custom properties for both themes and apply them globally.

## Acceptance Criteria
- Light theme: white background, dark text
- Dark theme: dark background, light text
- All existing components use CSS variables (no hardcoded colors)
- Transition animation between themes (200ms)
```

Generate and run:

```bash
spectra-plan
# → Generates plan.md with 2 tasks, each with AC, files, and verify commands

spectra-loop
# → Runs sequential loop: build task 001, verify, build task 002, verify
# → Level 1 uses 3-5 iterations per task

# Watch progress
spectra-status
```

Expected `spectra-status` output during execution:

```
SPECTRA Status
  Phase:    executing
  Agent:    spectra-builder
  Progress: 1/2 tasks (0 stuck)
  Current:  Task 002: Dark mode CSS variables
```

### Example 3: Build from BMAD Artifacts (Level 2-3)

You already ran BMAD planning and have docs ready. SPECTRA consumes them directly.

```bash
# Your project already has:
#   bmad/prd.md                    — Product requirements
#   bmad/architecture.md           — System design
#   bmad/stories/001-user-auth.md  — Detailed stories
#   bmad/stories/002-dashboard.md

cd my-project

# Step 1: Assess the project (detects BMAD artifacts)
spectra-assess
# → Creates .spectra/assessment.yaml
# → Output: "Level 2, medium verification, retry_budget: 3"

# Step 2: Initialize with assessment-driven defaults
spectra-init --name "user-dashboard"
# → Picks up level from assessment.yaml automatically

# Step 3: Generate plan from BMAD artifacts
spectra-plan --from-bmad
# → Reads PRD for acceptance criteria and risk factors
# → Reads architecture for file ownership (Level 3+)
# → Reads stories for task decomposition
# → Generates .spectra/plan.md with Scope, Wiring-proof, etc.

# Preview first if you want
spectra-plan --from-bmad --dry-run

# Step 4: Execute
spectra-loop

# Step 5: Watch progress live (refreshes every 5 seconds)
spectra-status --watch
```

At Level 3, SPECTRA spawns multiple builders in parallel (`&` + `wait`) on independent tasks with no file ownership overlap, then verifies each task sequentially.

### Example 4: Monitor a Running Build

`spectra-status` has three output modes:

```bash
# Human-readable dashboard (default)
spectra-status
```

Output:
```
SPECTRA Status
  Phase:    executing
  Agent:    spectra-builder
  Progress: 3/5 tasks (1 stuck)
  Current:  Task 004: Add payment validation
  Stuck:    Task 003 — "test timeout after 30s"
```

```bash
# JSON for scripts and CI
spectra-status --json
```

Output:
```json
{"phase":"executing","agent":"spectra-builder","total":5,"done":3,"stuck":1}
```

```bash
# Live monitoring (refreshes every 5s, Ctrl+C to stop)
spectra-status --watch
```

**What the signals mean:**
- **Phase: executing** — agents are actively working
- **Phase: complete** — all tasks done, COMPLETE signal written
- **Phase: stuck** — a task hit Max-iterations without passing verification
- **Progress: 3/5 (1 stuck)** — 3 tasks passed verification, 1 failed permanently, 1 remaining
- **RECONCILE signal** — the plan used different settings than assessment recommended (informational, no action needed in v4.0)

### Example 5: When Things Go Wrong

**A task fails verification** — the builder retries automatically up to `Max-iterations` times (default varies by task complexity: 3 for trivial, 5 for setup, 8 for features, 10 for complex). You don't need to do anything.

**A task gets stuck** (exhausted all retries):
```
# spectra-status shows:
  Progress: 4/5 tasks (1 stuck)
  Stuck:    Task 003 — "npm test -- auth fails: ECONNREFUSED"
```

The `[!]` stuck state is written to `plan.md`. Check what happened:

```bash
# See the stuck signal
cat .spectra/signals/STUCK

# Check lessons learned (the agent writes what it tried)
cat .spectra/lessons-learned.md
```

To fix manually and continue:
1. Fix the underlying issue (maybe a missing env var, a database that's down, etc.)
2. Edit `.spectra/plan.md` — change `[!]` back to `[ ]` for the stuck task
3. Run `spectra-loop` again — it picks up where it left off

**Common mistakes and what they mean:**

| You see... | It means... |
|------------|-------------|
| `Error: No .spectra/stories/ directory` | Run `spectra-init` first |
| `Error: No stories found` | Write at least one `.md` file in `.spectra/stories/` |
| `WARN: No assessment.yaml` | Run `spectra-assess` or let `spectra-init` do it |
| `Generated plan failed schema validation` | The AI produced malformed output. Check `.spectra/plan.md.new` and try again |
| `--non-interactive requires --track` | In CI, you must specify `--track quick_flow\|bmad_method\|enterprise` |

## Agent Architecture (v5.0)

Model selection and tool restrictions are defined in agent YAML frontmatter at `~/.claude/agents/spectra-*.md`. There are no env vars for model routing. Bash is the orchestrator — agents are workers with <500 byte prompts that read context from disk.

| Agent | Model | Role | Key Tools | Constraint |
|-------|-------|------|-----------|------------|
| **spectra-builder** | Opus | Implementer | Read, Edit, Write, Bash | acceptEdits mode, max 50 turns |
| **spectra-verifier** | Opus | Quality gate | Read, Bash, Grep | No Edit/Write |
| **spectra-reviewer** | Sonnet | Adversarial review | Read, Grep, Bash | Cross-model assurance |
| **spectra-auditor** | Haiku | Pre-flight scan | Read, Grep, Glob | 10 turns max, minimal cost |
| **spectra-oracle** | Haiku | Failure classifier | Read, Grep | 3 turns max, single-word output |
| **spectra-planner** | Opus | Plan generation | Read, Grep, Glob, Bash | plan mode, research only |

### Why Different Models?

- **Opus** for builder/verifier: Maximum capability for code generation and verification
- **Sonnet** for reviewer: Different model architecture catches different bugs (cross-model assurance, not cost optimization)
- **Haiku** for auditor/oracle: Speed and cost efficiency for scans and classification that don't need deep reasoning

### v5.0 Architecture: Bash-Native Parallel

v5.0 replaces the LLM-based coordinator (spectra-lead agent) with bash-native orchestration. Key changes:

- **No Agent Teams API** — no TeamCreate, TaskCreate, TaskUpdate, SendMessage overhead
- **Prompts <500 bytes** — agents read context from disk (CLAUDE.md, plan.md, guardrails.md)
- **Parallel via `&` + `wait`** — independent tasks build simultaneously, no coordination protocol
- **Deterministic resume** — JSON checkpoint file, no LLM reconstruction
- **Oracle classifier** — 3-turn Haiku replaces lead agent judgment for failure typing

## Canonical plan.md Schema (v4)

The plan.md file is the execution contract between planning and execution phases. All consumers (generator, validator, verifier, loop scripts, team prompt) agree on this schema.

```markdown
## Task 001: {title}
- [ ] 001: {title}
- AC:
  - {criterion 1}
  - {criterion 2}
- Files: {comma-separated paths}
- Verify: `{command that exits 0 on success}`
- Risk: {low|medium|high}
- Max-iterations: {3|5|8|10}
- Scope: {code|infra|docs|config|multi-repo}
- File-ownership:
  - owns: [{exclusive files}]
  - touches: [{shared-modify files}]
  - reads: [{read-only files}]
- Wiring-proof:
  - CLI: {command path}
  - Integration: {cross-module assertion}
```

**Checkbox states:** `[ ]` pending, `[x]` complete, `[!]` stuck

A task starts as `[ ]`, moves to `[x]` when verification passes, or `[!]` if it exhausts all retries. The loop script reads these states to decide what to work on next.

**Level-conditional fields:** Not all fields are required at every level. The validator (`spectra-plan-validate.sh`) enforces based on project level:

| Field | Level 0 | Level 1 | Level 2 | Level 3+ |
|-------|---------|---------|---------|----------|
| Header, checkbox, AC, Files, Verify | Required | Required | Required | Required |
| Risk, Max-iterations | Optional | Required | Required | Required |
| Scope, Wiring-proof | - | - | Required | Required |
| File-ownership, Parallelism | - | - | - | Required |

**SIGN-005 enforcement:** File ownership prevents two builders from editing the same file at the same time.
- `owns:` overlap between tasks = **FAIL** (plan is invalid)
- `touches:` overlap = **WARN** (allowed if tasks have a sequential dependency declared in Parallelism Assessment)
- `reads:` overlap = **PASS** (reading the same file is always fine)

**Parallelism Assessment** (Level 3+ only): Appears at the end of plan.md.

```markdown
## Parallelism Assessment
- Independent tasks: [001, 003]
- Sequential dependencies: [001 -> 002]
- Recommendation: TEAM_ELIGIBLE
```

The loop script uses this to decide which tasks can run in parallel (`&` + `wait`) and which must wait.

## Observability

SPECTRA writes signal files during execution for real-time status monitoring. These are plain text files in `.spectra/signals/` that any tool can read:

| Signal File | Content | Written By |
|-------------|---------|------------|
| `PHASE` | Current phase: `executing`, `complete`, `stuck` | Loop scripts |
| `AGENT` | Active agent name (e.g., `spectra-builder`) | Loop scripts |
| `PROGRESS` | Task completion: `3/5 done (1 stuck)` | Loop scripts |
| `STATUS` | Human-readable status line | Loop scripts |
| `COMPLETE` | Completion marker with timestamp | Loop/Lead |
| `STUCK` | Stuck marker with task ID and reason | Loop/Lead |
| `RECONCILE` | Assessment drift detection (Phase 4.5) | spectra-plan |

The `RECONCILE` signal is written by `spectra-plan --from-bmad` when the generated plan uses `Max-iterations` values that exceed the `retry_budget` from `assessment.yaml`. It's informational in v4.0 — a future version will use it to trigger planning corrections.

```bash
# Dashboard view
spectra-status

# JSON output for programmatic use
spectra-status --json

# Live monitoring (refreshes every 5s)
spectra-status --watch
```

## Wiring Verification (v5.1)

SPECTRA v5.1 adds automated wiring verification to catch the most common builder failure: code that passes unit tests but isn't wired into the runtime.

### Builder Self-Audit

Before every commit, the builder runs 4 mandatory checks:
1. **Reachability** — every new function has callsites in runtime code (not just tests)
2. **Spec Fidelity** — specific values from the task (model names, status codes) appear literally in code
3. **Integration Test** — at least one test traces from entry point through new code without mocking the connection
4. **Single Source** — IDs and computed values generated once, not duplicated

### verify.yaml

Each project has `.spectra/verify.yaml` (generated by `spectra-init`) with project-specific rules:
- **Wiring check** — dead code detection per language (Python, TypeScript, Go, Rust)
- **Framework checks** — anti-pattern detection (e.g., Flask-style returns in FastAPI)
- **Constants** — required values in specific files
- **Write guard** — enforce write abstractions (e.g., `safe_write()` instead of raw DB access)

### Usage

```bash
# Run wiring verification
spectra-verify-wiring.sh .

# Run self-test (validates the script itself)
spectra-verify-wiring.sh --self-test

# Verbose output with fix suggestions
spectra-verify-wiring.sh . --verbose --fix-hints
```

### plan.md Assertions

The planner auto-generates `Assertions` blocks in plan.md tasks. These are machine-checkable rules (`GREP`, `CALLSITE`, `COUNT`) that `spectra-verify-wiring.sh` enforces during verification.

## Core Principles

1. **No Done without evidence.** Every task needs test results AND proof. The verification gate is non-negotiable.

2. **Fresh context is a feature.** Each iteration starts clean. State lives in files and git, never in LLM memory.

3. **Plan proportionally.** A bug fix doesn't need a PRD. An enterprise system does.

4. **Complement, don't compromise.** Planning tools plan. Execution tools execute. Orchestration tools orchestrate.

5. **Parallel build, serial verify.** (Doctrine 5) Multiple builders can work simultaneously, but verification is always sequential.

## Signs (Learned Guardrails)

Signs are hard-won lessons from execution failures — things that went wrong and the rules we added to prevent them from happening again. They live in `guardrails.md` and are checked by both the Builder and Verifier.

| Sign | Rule |
|------|------|
| SIGN-001 | Integration tests must invoke what they import |
| SIGN-002 | CLI commands need subprocess-level tests |
| SIGN-003 | Lessons must generalize, not just fix |
| SIGN-004 | Lead must never edit source files |
| SIGN-005 | No two builders on the same file simultaneously |
| SIGN-006 | Verification is never parallel |
| SIGN-007 | Always shutdown_request before TeamDelete |
| SIGN-008 | Research before declaring STUCK on external blockers |

New Signs are discovered through FAIL -> FIX cycles. Cross-project Signs propagate via the verifier's `user`-scoped memory and the neural knowledge graph.

## Integration Tokens

Integration tokens live in `~/.spectra/.env` (chmod 600):

| Token | Used By | Purpose |
|-------|---------|---------|
| `LINEAR_API_KEY` | spectra-init.sh | Create Linear projects/issues |
| `LINEAR_TEAM_ID` | spectra-init.sh | Target Linear team |
| `SLACK_WEBHOOK_URL` | spectra-loop-v5.sh, spectra-verify.sh, spectra-init.sh | Notifications |
| `GITHUB_TOKEN` | Fallback (gh CLI handles its own auth) | GitHub API |

### Preflight Verification

`spectra-preflight` verifies all `.env` tokens are valid before SPECTRA launches. It runs automatically as part of `spectra-loop` and uses hash-based caching to avoid redundant checks.

**How it works:**
1. On first run (or when `.env` changes), it makes real HTTP calls to test each token
2. On success, it stores `sha256sum(.env)` in `.env.verified`
3. On subsequent runs, it compares hashes and silently skips if unchanged

```bash
# Manual verification
spectra-preflight           # Runs only if .env changed since last check
spectra-preflight --force   # Always run, ignore cached hash
```

**Automatic integration:** `spectra-loop` calls `spectra-preflight` after sourcing `.env` and before any project work. If any token fails, the loop aborts with a clear error.

| Token | Test Method |
|-------|-------------|
| `LINEAR_API_KEY` | GraphQL query to `api.linear.app` (HTTP 200) |
| `LINEAR_TEAM_ID` | Team lookup via Linear GraphQL (HTTP 200) |
| `SLACK_WEBHOOK_URL` | Empty payload POST (HTTP 400 = valid URL, no message posted) |
| `GITHUB_TOKEN` | GET `/user` on `api.github.com` (HTTP 200) |

Tokens that are not set in `.env` are reported as SKIP (not FAIL) — only invalid tokens block the launch.

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
| v4.0 | Feb 10, 2026 | Canonical plan.md schema (Phase A), contract test suite + observability signals (Phase B), BMAD adapter spectra-assess (Phase C), BMAD bridge spectra-plan --from-bmad (Phase D), RECONCILE signal infrastructure (Phase 4.5 prep) |
| v4.1 | Feb 10, 2026 | Dynamic max_turns, incomplete exit detection, level fallback chain, file-ownership format fallback |
| v5.0 | Feb 11, 2026 | Bash-native parallel architecture: replaced LLM coordinator (spectra-lead) with bash `&` + `wait`, <500 byte prompts, JSON checkpoint resume, oracle failure classifier (Haiku), removed Agent Teams dependency |
| v5.1 | Feb 11, 2026 | Builder self-audit protocol (4 checks before every commit), automated wiring verification (`spectra-verify-wiring.sh` + `verify.yaml`), plan.md assertions generation, `spectra-init` verify.yaml scaffolding |

## Reference

- Full methodology: [SPECTRA_METHOD.md](SPECTRA_METHOD.md)
- Autonomy contract: [SPECTRA_AUTONOMY_CONTRACT.md](SPECTRA_AUTONOMY_CONTRACT.md)
- Completion signals: [SPECTRA_COMPLETE.md](SPECTRA_COMPLETE.md)
- Global guardrails: [guardrails-global.md](guardrails-global.md)
