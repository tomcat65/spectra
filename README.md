# SPECTRA

[![SPECTRA CI](https://github.com/tomcat65/spectra/actions/workflows/spectra-ci.yml/badge.svg)](https://github.com/tomcat65/spectra/actions/workflows/spectra-ci.yml)

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

### Quick Install

```bash
git clone https://github.com/tomcat65/spectra.git ~/.spectra
~/.spectra/install.sh
```

`install.sh` adds `~/.spectra/bin` to your PATH (via `.bashrc`). Agent definitions in `~/.claude/agents/` are managed separately.

### Prerequisites

- [Claude Code CLI](https://claude.com/claude-code) (Opus 4.6+)
- Git
- Bash 4+, GNU grep with PCRE, GNU coreutils (`timeout`), and `flock`
- Claude Code CLI authenticated through `claude.ai` on an active subscription;
  API-key auth is rejected for SPECTRA agents
- Recommended for full local CI parity: `jq`, Python 3, curl, ShellCheck 0.10.0,
  actionlint 1.7.7, and GitHub CLI

Run `spectra-doctor.sh` to distinguish hard blockers from recommended and
safety warnings, including subscription auth and ambient model API keys. Add
`--json` for automation or `--strict` for exact local CI readiness.

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
    spectra-doctor.sh               #   Environment/safety preflight (--json, --strict)
    spectra-agent-run.sh            #   Subscription-only Claude agent boundary
    spectra-assess.sh               #   BMAD adapter (project assessment)
    spectra-elicit.sh               #   Goal/decision contract scaffold + gate
    spectra-plan.sh                 #   Plan generation (uses spectra-planner agent)
    spectra-plan-validate.sh        #   Canonical plan.md schema validation (v4)
    spectra-loop.sh                 #   Main loop — v5.0 bash-native parallel (all levels)
    spectra-preflight.sh            #   Token verification (runs once, then on .env change)
    spectra-quick.sh                #   Quick single-task execution
    spectra-verify.sh               #   Standalone verification
    spectra-verify-wiring.sh        #   Automated wiring verification (v5.1)
    spectra-status.sh               #   Observability dashboard (--json, --watch)
    spectra-refactor-clean.sh       #   Post-project cleanup (dry-run default)
    spectra-runtime-probe.sh        #   Bounded live endpoint/smoke-command probe
  lib/                              # Sourced modules (extracted from spectra-loop.sh)
    loop-signals.sh                 #   Signal/status file management
    loop-retry.sh                   #   Retry budgets and signs propagation
    loop-wiring.sh                  #   Wiring gate for pre-commit verification
    loop-git.sh                     #   Branch isolation and commit management
    loop-structured.sh              #   Typed helper bridge for plan/status/metrics
    loop-checkpoint.sh              #   Checkpoint save/restore and plan checksum
    loop-build.sh                   #   Build prompts and parallel build orchestration
    loop-verify.sh                  #   Verify prompts and oracle failure classifier
    loop-lessons.sh                 #   Continuous learning system (Phase 9+10)
    loop-stuck-recovery.sh          #   Party Mode STUCK recovery (classify, attempt, escalate)
    loop-context.sh                 #   Centralized context loading policy (build + verify)
    loop-session.sh                 #   Runtime profiles + orchestrator session persistence
    loop-metrics.sh                 #   Per-task execution metrics + retrospective (Phase F)
  config/
    loop-modules.txt                #   Canonical loop module inventory
    agent-runtimes.tsv              #   Per-agent driver, billing, auth, model, and plan
  hooks/                            # Git lifecycle hooks
    pre-commit                      #   Wiring verification gate (auto-installed by loop)
    post-verify-learn.sh            #   Opt-in Sign candidate discovery after FAIL→PASS recovery
  scripts/                          # Standalone utility scripts
    spectra-ci-lint.sh              #   Canonical local/GitHub lint implementation
    spectra-quality-gate.sh         #   Language-aware lint/format pre-checks (5 languages)
    spectra-structured.py           #   Typed parser/status/metrics helper (Python)
  tests/                            # Test suites (698 tests across 39 suite buckets)
    run-tests.sh                    #   Test runner (aggregates all suites)
    test-plan-validate.sh           #   Plan schema validation (11 tests)
    test-assess.sh                  #   Assessment + BMAD/plan bridge fixtures (26 tests)
    test-loop-unit.sh               #   Loop unit tests (checksum, timeout, signals) (8 tests)
    test-plan-extract.sh            #   Plan extraction + JSON bridge (17 tests)
    test-phase3-enforcement.sh      #   Wiring enforcement (pre-commit, no --no-verify) (15 tests)
    test-phase4-ci.sh               #   CI parity (workflow structure, fixtures) (10 tests)
    test-phase5-ratchet.sh          #   ShellCheck ratchet behavior (14 tests)
    test-phase6-modular.sh          #   Module extraction (anti-drift, golden behavior) (15 tests)
    test-phase7-shellcheck.sh       #   ShellCheck burn-down (0 warnings, RATIONALE policy) (8 tests)
    test-phase8-behavior.sh         #   Behavior parity (timeout, infra-fail, oracle fallback) (10 tests)
    test-phase9-lessons.sh          #   Continuous learning + bidirectional lessons (72 tests)
    test-agent-routing.sh           #   Agent YAML frontmatter validation (63 tests)
    test-phase-d-stuck.sh           #   Party Mode STUCK recovery (16 tests)
    test-phase-d-langprofile.sh     #   Language profile detection + SIGN-010 (12 tests)
    test-loop-planning.sh           #   In-loop planning delegation (16 tests)
    test-plan-review-gate.sh        #   Reviewer gate enforcement (18 tests)
    test-preflight-reconcile.sh     #   Preflight + RECONCILE alignment (15 tests)
    test-init-drift.sh              #   Prompt/template/version drift (16 tests)
    test-verify-command-detection.sh #  Language-aware verifier command selection (20 tests)
    test-status.sh                  #   Status dashboard (10 tests)
    test-quick.sh                   #   Quick mode (10 tests)
    test-init-e2e.sh                #   Init end-to-end scaffolding (12 tests)
    test-phase11-context-loading.sh #   Progressive context loading (20 tests)
    test-phase11-sign-candidates.sh #   Sign candidate discovery (14 tests)
    test-phase11-quality-gate.sh    #   Language-aware quality gates (15 tests)
    test-phase11-runtime-profiles.sh #  Runtime profiles + session persistence (26 tests)
    test-refactor-clean.sh          #   Post-project cleanup command (20 tests)
    test-phaseF-metrics.sh          #   Per-task metrics + retrospective + profile suggest (22 tests)
    test-phaseF-feedback-loops.sh   #   Prior failure context, adaptive retry, fallback-model (18 tests)
    test-structured-helper.sh       #   Typed helper plan/status generation (7 tests)
    test-verify-project-trials.sh   #   Python/JS/polyglot verifier regression trials (5 tests)
    test-verdict-extraction.sh      #   Structured verdict parsing and fallbacks (18 tests)
    test-wiring-scope.sh            #   Task-scoped wiring assertions and hook contract (12 tests)
    test-elicit.sh                  #   Goal contract scaffolding + enforcement (18 tests)
    test-runtime-probe.sh           #   Runtime probe behavior + verifier integration (22 tests)
    test-ci-parity.sh               #   Shared lint implementation + negative paths (13 tests)
    test-doctor.sh                  #   Environment/safety report contracts (15 tests)
    test-subscription-routing.sh    #   Subscription billing boundary + negative paths (12 tests)
  .github/workflows/
    spectra-ci.yml                  #   CI pipeline (Lint, Tests, Wiring jobs)
  templates/                        # Project scaffolding templates
    discovery.md.tmpl               #   Scout discovery output template
    negotiate.md.tmpl               #   Negotiation prompt template
    verify.yaml.template            #   Wiring verification config template (v5.1)
    .spectra/                       #   Per-project template files
  fixtures/                         # Test fixtures
    plan-bridge/                    #   Plan schema validation fixtures
    assessment/                     #   Assessment YAML fixtures
    bmad-bridge/                    #   BMAD bridge parsing fixtures
  lessons/                          # Continuous learning data store (Phase 9+10)
    schema-version                  #   Schema version file (integer, starts at 1)
    global-signs.jsonl              #   SIGN-level lessons (promoted globally)
    projects/{name}/                #   Per-project lesson stores
      lessons.jsonl                 #     Append-only lesson entries (flock-locked)
      lessons.snapshot              #     Compacted snapshot (post-run)
  agents/                           # Canonical agent definitions (mirrored to ~/.claude/agents/)
    references/                     #   Agent reference docs (failure-types, signs-taxonomy, etc.)
    scripts/                        #   Executable agent scripts
      builder-self-audit.sh         #     4-step self-audit (reachability, spec fidelity, integration, SSOT)
  lang-profiles/                    # Language-specific wiring profiles (sourceable bash)
    python.profile                  #   Python: import patterns, entry points, dep manifests
    javascript.profile              #   JavaScript/TypeScript: test patterns, skip imports
    bash.profile                    #   Bash: shell script test patterns
  docs/
    SPECTRA_IMPROVEMENT_PLAN.md     #   Evidence-gated roadmap from 7/10 onward
  install.sh                        # Installer (adds bin/ to PATH via .bashrc)
  SKILL.md                          # Claude Code skill definition (spectra-method, spectra-plan, etc.)

~/.claude/agents/                   # Canonical agent definitions
  spectra-planner.md                # Planning artifact generator (Opus)
  spectra-builder.md                # Code implementer (Opus)
  spectra-verifier.md               # Quality gate (Opus)
  spectra-reviewer.md               # Same-lineage cross-tier reviewer (Sonnet)
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
    prd.md                          # Product requirements (Level 1+)
    architecture.md                 # System design (Level 3+)
    stories/                        # User stories with acceptance criteria
      001-feature-name.md
      002-another-feature.md
    plan.md                         # Execution manifest (task checkboxes)
    project.yaml                    # Runtime config (level, agents, cost)
    verify.yaml                     # Wiring verification rules (v5.1)
    assessment.yaml                 # BMAD assessment (from spectra-assess)
    guardrails.md                   # Project-specific Signs (static rules only since v5.4)
    lessons-active.md               # Live lesson feed (auto-generated by inject_active_lessons)
    lessons-learned.md              # FAIL -> FIX log
    VERSION                         # SPECTRA version marker (e.g., "v5.5")
    PROMPT_build.md                 # Builder context prompt
    PROMPT_verify.md                # Verifier context prompt
    PROMPT_split.md                 # Stuck task splitter prompt
    screenshots/                    # Visual evidence
    metrics/                        # Execution metrics (Phase F)
      tasks.jsonl                   #   Per-task timing, retries, outcomes (append-only)
    status.json                     #   Generated runtime snapshot (authoritative dashboard state)
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
spectra-assess.sh

# CI/automation (must specify track)
spectra-assess.sh --non-interactive --track bmad_method

# Override and force regeneration
spectra-assess.sh --force

# Called automatically by spectra-init (you don't usually need to run it manually)
```

## Goal Contract (`spectra-elicit`)

New projects include `.spectra/goals.md`, a decision contract that discovery,
planning, builders, verifiers, and later spec negotiations use as shared input.
Complete it before planning, then run the gate:

```bash
$EDITOR .spectra/goals.md
spectra-elicit.sh --check
spectra-plan.sh
```

The gate rejects missing or empty required sections, template placeholders,
`TBD`/`TODO` markers, and decisions still marked `OPEN`. `spectra-plan.sh`
enforces the gate before discovery whenever `goals.md` exists. Older projects
without a goal contract remain compatible; run `spectra-elicit.sh` to scaffold
one without overwriting an existing file.

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
spectra-plan.sh --from-bmad

# Specify BMAD directory explicitly
spectra-plan.sh --from-bmad --bmad-dir ./my-bmad-docs

# Preview without writing (prints to stdout)
spectra-plan.sh --from-bmad --dry-run

# Override level regardless of assessment
spectra-plan.sh --from-bmad --level 3

# Standard mode (unchanged — reads .spectra/stories/)
spectra-plan.sh
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

These examples walk through SPECTRA from disposable bootstrap to larger project work. Start with Example 0 if you're trialing SPECTRA in CI or a scratch repo. Otherwise Example 1 is the fastest real workflow.

> **PATH setup:** Run `~/.spectra/install.sh` once to add `~/.spectra/bin` to your PATH automatically. Then invoke as `spectra-loop.sh`, `spectra-plan.sh`, etc. Or use full paths (e.g., `~/.spectra/bin/spectra-loop.sh`).
> **Tests/CI:** Set `SPECTRA_SKIP_PATH_SETUP=true` before `spectra-init.sh` if you need scaffolding without mutating `~/.bashrc` or `~/.zshrc`.
> **Bootstrap commits:** The examples below use `--no-commit` to avoid surprise scaffold commits while learning the tool. Remove that flag if you want `spectra-init.sh` to create the initial SPECTRA commit.

### Example 0: Trial SPECTRA in CI or a Scratch Repo

Use this when you want to verify that SPECTRA scaffolds correctly without touching your shell configuration.

```bash
mkdir -p /tmp/spectra-smoke
cd /tmp/spectra-smoke
git init -q .

SPECTRA_SKIP_PATH_SETUP=true ~/.spectra/bin/spectra-init.sh \
  --name "smoke-trial" \
  --level 0 \
  --no-commit

# Complete and validate the goal contract, describe one tiny task, then plan
$EDITOR .spectra/goals.md
~/.spectra/bin/spectra-elicit.sh --check
$EDITOR .spectra/stories/001-smoke-test.md
~/.spectra/bin/spectra-plan.sh --dry-run
```

This is the safest bootstrap path for CI, temporary repos, and external trial runs because it scaffolds `.spectra/` without writing PATH exports into `~/.bashrc` or `~/.zshrc`.

### Example 1: Fix a Bug (Level 0)

The simplest case. You found a bug and want an AI agent to fix it.

```bash
# Navigate to your project
cd my-web-app

# Initialize SPECTRA for a quick fix
spectra-init.sh --name "fix-login-redirect" --level 0 --no-commit
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
spectra-plan.sh

# Run it — SPECTRA handles the rest
spectra-loop.sh

# Check status anytime while it's running
spectra-status.sh

# Same snapshot, but machine-readable
spectra-status.sh --json
```

For a Level 0 fix, `spectra-loop` runs a single builder agent that reads the plan, makes the fix, and runs verification. If verification passes, you're done. If it fails, the oracle classifier categorizes the failure type and the builder retries (up to the type-specific retry budget — see Example 5).

**What gets created:**
- `.spectra/plan.md` — one task with your bug description, files to change, and a verify command
- `.spectra/plan.json` — generated task payload used by the loop fast path
- `.spectra/status.json` — authoritative runtime snapshot for dashboards and scripts
- `.spectra/signals/PROGRESS` — shows `1/1 done` when complete
- `.spectra/signals/COMPLETE` — written when the loop finishes successfully

### Example 2: Build a Small Feature (Level 1)

Adding a dark mode toggle to an existing app. This needs 2-3 stories and sequential build/verify iterations.

```bash
cd my-web-app
spectra-init.sh --name "dark-mode" --level 1 --no-commit
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
spectra-plan.sh
# → Generates plan.md with 2 tasks, each with AC, files, and verify commands

spectra-loop.sh
# → Runs sequential loop: build task 001, verify, build task 002, verify
# → Each task retries based on failure type (test_failure: up to 3, wiring_gap: up to 2)

# Watch progress
spectra-status.sh

# Re-run the verifier manually for a completed task if you want a fresh 4-step audit
spectra-verify.sh --task 1 --full-sweep
```

Expected `spectra-status` output during execution:

```
  SPECTRA Status
  ────────────────────────────────────
  Project:  dark-mode
  Level:    1
  Branch:   spectra/run-20260217-091500
  Phase:    executing
  Agent:    spectra-builder
  ────────────────────────────────────
  Tasks:    1/2 complete
  Remaining: 1
  Stuck:    0
  Progress: 1/2 tasks (0 stuck)
```

The same information is also written to `.spectra/status.json`, so scripts and dashboards should read that file or `spectra-status.sh --json` instead of scraping the text dashboard.

### Example 3: Build from BMAD Artifacts in a Polyglot Repo (Level 2-3)

You already ran BMAD planning and have docs ready. This example assumes a Python backend plus a JavaScript frontend, because that is the strongest current multi-language path SPECTRA supports first-class.

```bash
# Your project already has:
#   bmad/prd.md                    — Product requirements
#   bmad/architecture.md           — System design
#   bmad/stories/001-user-auth.md  — Detailed stories
#   bmad/stories/002-dashboard.md
#   backend/pyproject.toml         — Python service
#   frontend/package.json          — JavaScript app

cd my-project

# Step 1: Assess the project (detects BMAD artifacts)
spectra-assess.sh
# → Creates .spectra/assessment.yaml
# → Output: "Level 2, medium verification, retry_budget: 3"

# Step 2: Initialize with assessment-driven defaults
spectra-init.sh --name "user-dashboard" --no-commit
# → Picks up level from assessment.yaml automatically

# Step 3: Generate plan from BMAD artifacts
spectra-plan.sh --from-bmad
# → Reads PRD for acceptance criteria and risk factors
# → Reads architecture for file ownership (Level 3+)
# → Reads stories for task decomposition
# → Generates .spectra/plan.md with Scope, Wiring-proof, etc.

# Preview first if you want
spectra-plan.sh --from-bmad --dry-run

# Step 4: Execute
spectra-loop.sh

# Step 5: Watch progress live (refreshes every 5 seconds)
spectra-status.sh --watch

# Optional: verify one task explicitly after the loop finishes
# In a polyglot repo, full-sweep covers every detected first-class language surface
spectra-verify.sh --task 2 --full-sweep
```

At Level 3, SPECTRA spawns multiple builders in parallel (`&` + `wait`) on independent tasks with no file ownership overlap, then verifies each task sequentially with the full 4-step audit (including wiring proof). If the repo is polyglot, `spectra-verify.sh --full-sweep` now runs every detected first-class language surface it has a profile or fallback for, instead of stopping at the first manifest.

### Example 4: Monitor a Running Build

`spectra-status` has three output modes:

```bash
# Human-readable dashboard (default)
spectra-status.sh
```

Output:
```
  SPECTRA Status
  ────────────────────────────────────
  Project:  my-api
  Level:    3
  Branch:   spectra/run-20260217-100000
  Phase:    executing
  Agent:    spectra-builder
  ────────────────────────────────────
  Tasks:    3/5 complete
  Remaining: 1
  Stuck:    1
  Progress: 3/5 tasks (1 stuck)
  ────────────────────────────────────
  STUCK: Task 003 — test timeout after 30s
```

```bash
# JSON for scripts and CI
spectra-status.sh --json

# The same payload is also written to:
cat .spectra/status.json
```

Output:
```json
{
  "project": "my-api",
  "level": 3,
  "phase": "executing",
  "agent": "spectra-builder",
  "branch": "spectra/run-20260217-100000",
  "tasks": {
    "total": 5,
    "done": 3,
    "stuck": 1,
    "remaining": 1
  },
  "complete": false,
  "complete_elapsed": null,
  "stuck_signal": "Task 003 — test timeout after 30s",
  "progress": "3/5 tasks (1 stuck)",
  "timestamp": "2026-02-17T06:00:00Z"
}
```

```bash
# Live monitoring (refreshes every 5s, Ctrl+C to stop)
spectra-status.sh --watch
```

**What the signals mean:**
- **Phase: executing** — agents are actively working
- **Phase: complete** — all tasks done, COMPLETE signal written
- **Phase: stuck** — a task exhausted its retry budget and was marked stuck
- **Progress: 3/5 (1 stuck)** — 3 tasks passed verification, 1 failed permanently, 1 remaining
- **RECONCILE signal** — the plan used different settings than assessment recommended (informational)

### Example 5: When Things Go Wrong

**A task fails verification** — the oracle classifier (Haiku, 3 turns) categorizes the failure, and the builder retries based on the type-specific budget:

| Failure Type | Retry Budget | Typical Cause |
|---|---|---|
| `test_failure` | 3 retries | Tests don't pass, assertions wrong |
| `missing_dependency` | 3 retries | Import errors, package not installed |
| `wiring_gap` | 2 retries | Code exists but isn't connected to runtime |
| `architecture_mismatch` | 0 (STUCK) | Wrong approach — needs human guidance |
| `ambiguous_spec` | 0 (STUCK) | Requirements unclear — needs clarification |
| `external_blocker` | 0 (STUCK) | Dependency on external service/team |

You don't need to do anything during retries — they happen automatically.

**Party Mode STUCK Recovery** — Before escalating to the user, the loop attempts autonomous recovery via `lib/loop-stuck-recovery.sh`:

1. **Classify** — pattern-match the STUCK reason (`dependency_failure`, `environment_issue`, `spec_conflict`, `unknown`)
2. **Attempt recovery** — for recoverable types (dependency/environment), generate a `RECOVERY_PLAN` and retry
3. **Escalate** — non-recoverable types (`spec_conflict`, `unknown`) stay STUCK for human intervention

On successful recovery, the STUCK signal is cleared, failure history is reset, and the task re-enters the retry loop. Recovery attempts are logged to `logs/task-{id}-recovery.md` and the STUCK signal includes a `Recovery-Attempted: yes/no` field.

**A task gets stuck** (exhausted retries, non-retryable failure, or failed recovery):
```
  Progress: 4/5 tasks (1 stuck)
  ────────────────────────────────────
  STUCK: Task 003 — npm test auth fails: ECONNREFUSED
```

The `[!]` stuck state is written to `plan.md`. Check what happened:

```bash
# See the stuck signal
cat .spectra/signals/STUCK

# Check the verification report
cat .spectra/logs/task-003-verify.md

# Check lessons learned (the agent writes what it tried)
cat .spectra/lessons-learned.md
```

To fix manually and continue:
1. Fix the underlying issue (maybe a missing env var, a database that's down, etc.)
2. Edit `.spectra/plan.md` — change `[!]` back to `[ ]` for the stuck task. This is a recovery-only manual edit; normal loop updates are generated for you.
3. Run `spectra-loop.sh --resume` — it picks up from the checkpoint and re-reads the plan

**Common mistakes and what they mean:**

| You see... | It means... |
|------------|-------------|
| `Error: No .spectra/stories/ directory` | Run `spectra-init.sh` first |
| `Error: No stories found` | Write at least one `.md` file in `.spectra/stories/` |
| `WARN: No assessment.yaml` | Run `spectra-assess.sh` or let `spectra-init.sh` do it |
| `Generated plan failed schema validation` | The AI produced malformed output. Check `.spectra/plan.md.new` and try again |
| `--non-interactive requires --track` | In CI, you must specify `--track quick_flow\|bmad_method\|enterprise` |

## Agent Architecture (v5.5)

Primary model selection and tool restrictions are defined in agent YAML frontmatter at `~/.claude/agents/spectra-*.md`. Billing and auth are separately locked by `config/agent-runtimes.tsv` and `spectra-agent-run.sh`: every call requires `claude.ai` subscription auth and runs with per-token credentials, credential helpers, and alternate provider routes cleared in both the shell and Claude settings. Subscription OAuth setup tokens remain valid. Bash is the orchestrator — agents are workers with <500 byte prompts that read context from disk. The routing and subscription suites validate all seven agent contracts. Existing capacity fallbacks can select another Claude tier, but cannot change the verified subscription route.

| Agent | Model | Billing | Role | Key Tools | Constraint |
|-------|-------|---------|------|-----------|------------|
| **spectra-planner** | Opus | Claude subscription | Plan generation | Read, Grep, Glob, Bash | plan mode, research only, 40 max turns |
| **spectra-builder** | Opus | Claude subscription | Implementer | Read, Edit, Write, Bash | acceptEdits mode, max 50 turns, reads lessons-active.md |
| **spectra-verifier** | Opus | Claude subscription | Quality gate | Read, Bash, Grep | No Edit/Write, checks lesson violations, 30 max turns |
| **spectra-reviewer** | Sonnet | Claude subscription | Adversarial review | Read, Grep, Bash | Same-lineage cross-tier review, 25 max turns |
| **spectra-auditor** | Haiku | Claude subscription | Pre-flight scan | Read, Grep, Glob | 10 max turns, no Bash, lower quota draw |
| **spectra-scout** | Haiku | Claude subscription | Pre-planning discovery | Read, Grep, Glob, Bash | 15 max turns, discovery phase |
| **spectra-oracle** | Haiku | Claude subscription | Failure classifier | Read, Grep | 3 max turns, single-word output |

### Why Different Models?

- **Opus** for builder/verifier: Maximum capability for code generation and verification
- **Sonnet** for reviewer: A separate, lower-tier context can catch anchoring, but remains the same Claude lineage
- **Haiku** for auditor/oracle: Speed and lower prepaid-quota use for bounded classification work

This is not a heterogeneous council. When independent model lineages are
material, use a separately authorized workflow such as `grounded-council` with
explicit subscription drivers and grounded arbitration.

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
spectra-status.sh

# JSON output for programmatic use
spectra-status.sh --json

# Live monitoring (refreshes every 5s)
spectra-status.sh --watch
```

## Wiring Verification (v5.1)

SPECTRA v5.1 adds automated wiring verification to catch the most common builder failure: code that passes unit tests but isn't wired into the runtime.

### Builder Self-Audit

Before every commit, the builder runs 4 mandatory checks (implemented in `agents/scripts/builder-self-audit.sh`):
1. **Reachability** — every new public function/class has external callsites in runtime code (not just tests or the defining file)
2. **Spec Fidelity** — literal values from the task spec (quoted strings, backtick values, AC colon-values) appear in the codebase, plus plan.md Assertions block execution
3. **Integration Test** — at least one test exercises real wiring (subprocess, e2e, integration markers)
4. **Single Source of Truth** — value generation patterns (uuid, datetime, random) appear in at most one file per concept

```bash
# Run standalone (used by builder agent before commit)
agents/scripts/builder-self-audit.sh [TASK_FILE] [PROJECT_ROOT]
```

### verify.yaml

Each project has `.spectra/verify.yaml` (generated by `spectra-init`) with project-specific rules:
- **Wiring check** — dead code detection per language (Python, TypeScript, Go, Rust), scoped to git-modified files
- **Framework checks** — anti-pattern detection (e.g., Flask-style returns in FastAPI)
- **Constants** — required values in specific files
- **Write guard** — enforce write abstractions (e.g., `safe_write()` instead of raw DB access)

Its optional `runtime:` block can also verify a running artifact through an
HTTP endpoint or smoke command. A configured probe runs when
`SPECTRA_RUNTIME_PROBE=1`, and automatically for tasks with `Scope: infra` or
`Scope: deploy`. Set `SPECTRA_RUNTIME_PROBE=0` to explicitly disable that
automatic signal. Command attempts are bounded by `timeout` (30 seconds by
default), and failures are advisory unless `runtime.blocking: true` or
`SPECTRA_RUNTIME_PROBE_BLOCKING=1` is set. Explicit environment values,
including false/zero, override YAML.

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

The planner auto-generates `Assertions` blocks in plan.md tasks. These are machine-checkable rules (`GREP`, `CALLSITE`, `COUNT`, `NOT_EXISTS`) that `spectra-verify-wiring.sh` enforces during verification.

## CI Pipeline

SPECTRA includes a GitHub Actions CI pipeline (`.github/workflows/spectra-ci.yml`) that runs on every push and PR to `main`. Three parallel jobs:

| Job | What It Checks |
|-----|---------------|
| **Lint** | Canonical `scripts/spectra-ci-lint.sh`: syntax, manifest-backed module anti-drift (14 modules), ShellCheck errors/ratchet, suppression rationales, actionlint |
| **Tests** | Full test suite via `tests/run-tests.sh` (698 tests across 39 suite buckets) |
| **Wiring** | Anti-bypass guard (`SPECTRA_SKIP_WIRING` blocked in CI), wiring verification against pass/fail fixtures |

The **ShellCheck ratchet** enforces a per-file, per-rule warning baseline (`shellcheck-baseline.json`). New warnings must be fixed before merge — the baseline can only decrease, never increase. Run `bin/spectra-shellcheck-ratchet.sh --update-baseline` locally to regenerate after fixing warnings.

GitHub and local lint call the same repository-owned script; workflow YAML only
installs pinned tools. The **module anti-drift** check uses
`config/loop-modules.txt` as its single inventory and ensures every module
exists, is sourced exactly once, has no unlisted peers, and uses no wildcard
sourcing.

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
| SIGN-004 | Lead Drift — team lead must not write code |
| SIGN-005 | File Collision — no two builders on the same file simultaneously |
| SIGN-006 | Stale Task — nudge or reassign after 10 minutes without output |
| SIGN-007 | Silent Failure — teammate errors must be surfaced, not swallowed |
| SIGN-008 | Research Before STUCK — web search before declaring external blockers |
| SIGN-009 | Test Ordering Pollution — tests must pass in isolation and full suite |
| SIGN-010 | Language Blindspot — wiring proof must cover all project languages |

New Signs are discovered through FAIL -> FIX cycles. The continuous learning system (Phase 9+10) tracks lessons from TEMP through CONFIRMED/PROMOTED to SIGN status, with adaptive TTL, cross-project fingerprint deduplication, and automatic propagation via `lessons-active.md`.

## Integration Tokens

Optional operational integration tokens live in `~/.spectra/.env` (chmod 600).
Do not put model credentials there: `spectra-doctor` warns on model API keys and
the agent runner removes Claude API/auth overrides before every invocation.

| Token | Used By | Purpose |
|-------|---------|---------|
| `LINEAR_API_KEY` | spectra-init.sh | Create Linear projects/issues |
| `LINEAR_TEAM_ID` | spectra-init.sh | Target Linear team |
| `SLACK_WEBHOOK_URL` | spectra-loop.sh, spectra-verify.sh, spectra-init.sh | Notifications |
| `GITHUB_TOKEN` | Fallback (gh CLI handles its own auth) | GitHub API |

### Preflight Verification

`spectra-preflight` verifies all `.env` tokens are valid before SPECTRA launches. It runs automatically as part of `spectra-loop` and uses hash-based caching to avoid redundant checks.

**How it works:**
1. On first run (or when `.env` changes), it makes real HTTP calls to test each token
2. On success, it stores `sha256sum(.env)` in `.env.verified`
3. On subsequent runs, it compares hashes and silently skips if unchanged

```bash
# Manual verification
spectra-preflight.sh           # Runs only if .env changed since last check
spectra-preflight.sh --force   # Always run, ignore cached hash
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
| v5.2 | Feb 17, 2026 | CI pipeline (Lint, Tests, Wiring jobs), pre-commit wiring enforcement, ShellCheck ratchet (0 warnings across 20 files), loop modularization (7 sourced modules), plan.json typed bridge, DAG cycle validation, oracle failure classifier with type-specific retry budgets, 127 tests across 11 suites |
| v5.3 | Feb 17, 2026 | Phase 9: Continuous learning system — JSONL + flock append-only storage, normalized fingerprint dedup, adaptive TTL (severity-based with recurrence extension), promotion lifecycle (TEMP→CONFIRMED→PROMOTED→SIGN), snapshot compaction, prompt injection guard (`sanitize_for_propagation()`), schema versioning/migration, cross-project correlation. 8 sourced modules (added `loop-lessons.sh`). 182 tests across 11 suites |
| v5.4 | Feb 24, 2026 | Phase 10: Bidirectional lessons architecture — `inject_active_lessons()` merges project-local + global CONFIRMED+ lessons into live `lessons-active.md` feed (rank-sorted, capped at 25), `spectra_upgrade_project()` non-destructive brownfield migration with VERSION marker, builder reads lessons at session start, verifier checks for lesson violations. Dry-run guards prevent state mutation. 195 tests across 11 suites |
| v5.4.1 | Mar 5, 2026 | Phases A-D: Builder self-audit script (`agents/scripts/builder-self-audit.sh` — 4-step executable audit), agent routing tests (63 tests validating YAML frontmatter), Party Mode STUCK recovery (`lib/loop-stuck-recovery.sh` — classify/recover/escalate with compound failure integration), language profiles (`lang-profiles/python.profile`), SIGN-010 (Language Blindspot), `install.sh` installer, `SKILL.md` skill definition. 9 loop modules. 290 tests across 15 suites |
| v5.5 | Mar 9, 2026 | Dogfood sprint (11 tasks self-executed): in-loop planning persistence, reviewer gate enforcement, preflight/RECONCILE alignment, version drift removal, language-aware verifier command selection (JS/bash/python profiles), operational coverage expansion (status/quick/init-e2e/assess fixtures), progressive context loading (`loop-context.sh`), opt-in Sign candidate discovery (`hooks/post-verify-learn.sh`), language-aware quality gates (`scripts/spectra-quality-gate.sh` — 5 languages), runtime profiles + session persistence (`loop-session.sh` — quick/standard/thorough), post-project cleanup (`spectra-refactor-clean.sh`). Phase F closed-loop self-improvement: per-task execution metrics (`loop-metrics.sh`), generated `status.json` snapshots, typed plan/status/metrics parsing via `scripts/spectra-structured.py`, adaptive retry intelligence, model fallback (`--fallback-model`), post-run retrospective, auto-profile selection from metrics history, multi-language regression sweeps across detected manifests, and profile-owned dependency verification with JS semantic wiring checks. Maintenance hardening adds a required goal/decision contract, bounded scope-aware runtime evidence, canonical local/GitHub lint, manifest-backed module parity, an environment/safety doctor, and a subscription-only agent runtime boundary. Test runner hardening streams live suite output, requires a structured `SPECTRA_TEST_RESULT` contract per suite, and supports `SPECTRA_SKIP_PATH_SETUP=true` / `CI` init scaffolding without shell rc mutation. 14 loop modules, 35 shellcheck-clean files. 698 tests across 39 suite buckets. |

## Continuous Learning (v5.3+)

SPECTRA learns from execution failures and propagates lessons across projects automatically.

### Lesson Lifecycle

```
TEMP → CONFIRMED → PROMOTED → SIGN
  └→ EXPIRED (adaptive TTL)    └→ Human-gated, cross-project enforcement
```

| Status | Trigger | Scope |
|--------|---------|-------|
| TEMP | First failure occurrence | Single project |
| CONFIRMED | Seen in 2+ projects | Cross-project |
| PROMOTED | High confidence + recurrence | Global |
| SIGN | Human approval | Permanent guardrail |
| EXPIRED | Exceeded adaptive TTL (TEMP only) | Removed from active set |

### Storage

Append-only JSONL with `flock` file locking — no mutable JSON, no lost updates. Each entry carries a normalized fingerprint (`{area}/{error_code}/{primary_file}`) for deduplication.

```
~/.spectra/lessons/
  schema-version                    # Integer schema version
  global-signs.jsonl                # SIGN-level lessons
  projects/{name}/
    lessons.jsonl                   # Append-only events (create, increment, promote, demote)
    lessons.snapshot                # Compacted state (post-run)
```

### Bidirectional Feed (v5.4)

Before each builder task, `inject_active_lessons()` merges project-local and global CONFIRMED+ lessons into `.spectra/lessons-active.md`. Lessons are:

- **Deduplicated** by fingerprint (highest status wins)
- **Rank-sorted** (SIGN > PROMOTED > CONFIRMED) so caps drop lowest-priority first
- **Capped** at 25 entries (15 project + 10 global)
- **Sanitized** against prompt injection (`sanitize_for_propagation()`)

The builder reads `lessons-active.md` at session start (hard guardrails). The verifier checks whether active lessons were violated.

### Brownfield Migration

Pre-v5.4 projects auto-upgrade on first loop run:
1. Backup `guardrails.md` → `guardrails.md.pre-v10`
2. Strip lessons section (preserve SIGNs and non-lesson content)
3. Generate `lessons-active.md` from lesson store
4. Write `VERSION` marker (idempotent — skips if already current)

## Known Limitations

- **RECONCILE signal requires operator decision** — In interactive mode, prompts user to re-run assessment. In non-interactive mode (CI/piped), exits with error and actionable next steps. Remove the signal file manually if drift is acceptable.
- **No Level 4 (Enterprise) implementation** — The level table defines it but no sprint delivery logic exists in the loop scripts.
- **spectra-scout auto-runs when discovery is missing** — The planner automatically invokes scout when `discovery.md` is absent. Manual flags (`--discover`, `--skip-discovery`) are also available.
- **Language profiles cover Python, JavaScript, and Bash** — Verification now sweeps every detected first-class language in a repo, but Go and Rust still rely on fallback regression commands and do not have profile-backed wiring proof yet.

## Reference

- Full methodology: [SPECTRA_METHOD.md](SPECTRA_METHOD.md)
- Autonomy contract: [SPECTRA_AUTONOMY_CONTRACT.md](SPECTRA_AUTONOMY_CONTRACT.md)
- Completion signals: [SPECTRA_COMPLETE.md](SPECTRA_COMPLETE.md)
- Global guardrails: [guardrails-global.md](guardrails-global.md)
