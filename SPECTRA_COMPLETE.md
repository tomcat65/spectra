# SPECTRA v3.0 — Complete Reference

**S**ystematic **P**lanning, **E**xecution via **C**lean-context loops, **T**racking & verification with **R**eal-time **A**gent orchestration

> Plan like BMAD. Execute like Ralph. Orchestrate like Your Claude Engineer.

**Version:** 3.0
**Date:** February 9, 2026
**Architecture:** All-Anthropic (Native Agent Teams via Claude Code Opus 4.6)
**Heritage:** BMAD (planning) + Ralph Wiggum (execution) + YCE (orchestration)

---

## 1. Core Philosophy

Each source framework optimizes for a different bottleneck. SPECTRA unifies them:

| Phase | Source Framework | What It Contributes |
|-------|-----------------|-------------------|
| **Phase 0: Scale Assessment** | BMAD | Right-size planning depth (Level 0-4) |
| **Phase 1: Specification** | BMAD | Constitution, PRD, Architecture, Stories |
| **Phase 2: Task Decomposition** | Ralph Wiggum | Acceptance-criteria-driven tasks on disk |
| **Phase 3: Autonomous Execution** | Ralph Wiggum | Clean-context bash loop, one task per iteration |
| **Phase 4: Verification & Tracking** | YCE | Evidence chain, verification gates |
| **Phase 5: Integration & Delivery** | YCE | Git commits, PRs, Slack notifications |

---

## 2. Agent Roster (v1.2)

| Agent | Model | Role | Tools |
|-------|-------|------|-------|
| spectra-planner | Opus | Generates constitution, PRD, architecture, stories, plan.md | Read, Grep, Glob, Bash |
| spectra-reviewer | Sonnet | Cross-model validates planning artifacts; final PR review | Read, Grep, Glob, Bash, Write, Edit |
| spectra-auditor | Haiku | Pre-flight guardrails scan for Sign violations | Read, Grep, Glob, Write, Edit |
| spectra-builder | Opus | Implements one task per session from plan.md | Read, Edit, Write, Bash, Grep, Glob |
| spectra-verifier | Opus | Independent 4-step verification audit (read-only) | Read, Bash, Grep, Glob, Write, Edit |

### Agent Definitions

**spectra-planner (Opus)**
- Generates all planning artifacts from project description
- Assesses project level (0-4) and scales artifact depth
- For Level 3+: includes File Ownership Map and Parallelism Assessment
- Permission mode: plan (research-only, cannot modify source code)

**spectra-reviewer (Sonnet)**
- Cross-model validates planning artifacts (different architecture from planner)
- Writes machine-readable verdicts: APPROVED, APPROVED_WITH_WARNINGS, REJECTED
- Performs final PR review after all tasks pass
- Provides genuine diversity of perspective (not same-weights self-validation)

**spectra-auditor (Haiku)**
- Fast, cheap pre-flight scan before each build cycle
- Checks codebase against active Signs in guardrails.md
- Uses user-scope memory: violation patterns accumulate across all projects
- Advisory only (does not block build), but findings passed to builder

**spectra-builder (Opus)**
- Implements one task per fresh-context session
- Reads guardrails.md before building
- Runs wiring proof checklist before committing
- Reflects on failures for institutional memory (lessons-learned.md)

**spectra-verifier (Opus)**
- Independent 4-step audit: verify command, regression, evidence chain, wiring proof
- Read-only enforcement via tool allowlist (no Edit, no Write in verification)
- Reports PASS/FAIL with failure type classification
- Knows 3+ bug patterns (Signs) to check proactively

---

## 3. Scale Assessment

| Level | Name | Duration | Artifacts Required |
|-------|------|----------|-------------------|
| 0 | Micro-task / Bug Fix | < 1 hour | None — skip planning |
| 1 | Small Feature | < 1 day | plan.md with checkboxes |
| 2 | Medium Feature | 1-3 days | constitution.md + plan.md + stories |
| 3 | Large Feature | 1-2 weeks | Full pipeline + File Ownership + Agent Teams eligible |
| 4 | Enterprise | 2-4 weeks | Full pipeline + parallel execution streams + Agent Teams |

**Decision rule**: One sentence = Level 0-1. Needs a meeting = Level 2-3. Needs a slide deck = Level 4.

---

## 4. Planning Artifacts

### constitution.md
Project constraints, non-negotiables, guardrails. What the project IS and IS NOT.

### prd.md (Level 2+)
Product requirements: user stories, acceptance criteria, non-functional requirements, scope boundaries.

### architecture.md (Level 3+)
System design: component diagram, data flow, API contracts, dependency map, integration points.

### plan.md — The Execution Contract

Each task must include:

```markdown
## Task 001: [Title]
- [ ] 001: [Title]
- AC:
  - [criterion 1]
  - [criterion 2]
- Files: [comma-separated file paths]
- Verify: `[exact CLI command that exits 0 on success]`
- Risk: [low|medium|high]
- Max-iterations: [3|5|8|10]
- Scope: [code|infra|docs|config|multi-repo]
- File-ownership:                          # Level 3+ only
  - owns: [files this task creates/modifies exclusively]
  - touches: [files this task modifies but shares]
  - reads: [files this task only reads]
- Wiring-proof:                            # Level 2+ only
  - CLI: [exact command path to exercise]
  - Integration: [cross-module/pipeline assertion]
```

Checkbox states: `[ ]` pending, `[x]` complete, `[!]` stuck

### Mandatory Plan Requirements

1. Every task must have a verify command
2. Wiring proof sections mandatory for Level 2+
3. Level 2+ must include a forced failure task
4. Tasks ordered for independent verification
5. No task requires context from a previous builder session
6. Level 3+: File Ownership Map with no overlap between parallel tasks
7. Level 3+: Parallelism Assessment with TEAM_ELIGIBLE or SEQUENTIAL_ONLY recommendation

### non-goals.md
Explicit list of what the project must NOT do. Checked by verifier during audit Step 4.

---

## 5. Execution Pipeline

```
spectra-loop-v3.sh (thin launcher)
  └─→ claude -p "TEAM_PROMPT" --permission-mode delegate --max-turns 200
        └─→ Team Lead orchestrates:
              Plan → Review → [Lock] → For each task: Audit → Build → Verify
              On FAIL: retry with diminishing budget
              On COMPLETE: PR review → signal
              On STUCK: halt immediately
```

### Architecture (v3.0)

SPECTRA v3.0 uses a single Claude Code session with native Agent Teams instead of spawning 12+ separate CLI processes. The thin launcher (`spectra-loop-v3.sh`) generates a team prompt via `spectra-team-prompt.sh` and launches one Claude session as the team lead. All orchestration logic (retry loops, failure taxonomy, diminishing budgets, compound failure detection) is handled natively by the team lead via natural language instructions.

### Phase 1: Planning
- Team lead spawns spectra-planner (Opus) teammate to generate artifacts
- Team lead spawns spectra-reviewer (Sonnet) teammate to validate
- If REJECTED: planner revises once, reviewer re-evaluates. If re-rejected → STUCK.

### Phase 2: Plan Lock
- Plan is locked after APPROVED/APPROVED_WITH_WARNINGS
- No reinterpretation, reordering, addition, or removal of tasks
- Plans are disposable. Running plans are not.

### Phase 3: Execution Loop
For each unchecked task, the team lead coordinates:
1. **Pre-flight audit** — spawn auditor (Haiku) teammate for Sign violations scan
2. **Build** — spawn builder (Opus) teammate with diminishing token budget on retry
3. **Verify** — spawn verifier (Opus) teammate for 4-step audit (never parallel)
4. On PASS: check off task, commit, continue
5. On FAIL: retry (up to max iterations per failure type)
6. On exhausted retries or compound failure: write STUCK signal

For Level 3+ projects with TEAM_ELIGIBLE and non-overlapping file ownership, independent tasks may run with parallel builder teammates.

### Phase 4: Completion
- Team lead spawns spectra-reviewer (Sonnet) teammate for final PR review
- COMPLETE signal written
- Slack notification sent (if configured)
- Final report generated

---

## 6. Verification Protocol

### Four-Step Audit

1. **Task verify command** — run the exact CLI command from plan.md
2. **Full regression suite** — all existing tests must still pass
3. **Evidence chain** — git commit hash matches task ID convention
4. **Wiring proof** — dead import detection, integration test pipeline check, non-goal compliance

### Verification Invariants

- Verification is single-agent only — no Agent Teams in verification, ever
- Verifier has no write access (tool allowlist enforced)
- Results must be reproducible given the same inputs

### Failure Taxonomy

| Failure Type | Max Retries | Action |
|-------------|-------------|--------|
| Test failure / flake | 3 | Retry |
| Missing dependency | 3 | Retry |
| Wiring gap / integration | 2 | Retry |
| External blocker (researchable) | 1 | Research + Retry (SIGN-008: builder must web search/docs lookup before STUCK) |
| Architecture mismatch | 0 | STUCK |
| Ambiguous spec | 0 | STUCK |
| Verifier non-determinism | 0 | STUCK |
| External blocker (hard) | 0 | STUCK |

**Compound failure rule:** Two different failure types on the same task → IMMEDIATE STUCK.

---

## 7. Agent Teams — Native Execution (v3.0)

### Architecture

SPECTRA v3.0 always uses Agent Teams. The thin launcher (`spectra-loop-v3.sh`) generates a comprehensive team prompt via `spectra-team-prompt.sh` and launches a single Claude Code session as team lead in delegate mode. The team lead spawns teammates for each SPECTRA role:

| Role | Agent Type | Model | Purpose |
|------|-----------|-------|---------|
| Planner | spectra-planner | Opus | Generates planning artifacts |
| Reviewer | spectra-reviewer | Sonnet | Cross-model validation, final PR review |
| Auditor | spectra-auditor | Haiku | Pre-flight Sign violation scans |
| Builder | spectra-builder | Opus | Implements tasks from plan.md |
| Verifier | spectra-verifier | Opus | Independent 4-step audit (read-only) |

### How It Works

1. `spectra-loop-v3.sh` handles CLI args, branch isolation, and directory setup
2. `spectra-team-prompt.sh` reads plan.md, guardrails.md, constitution.md, non-goals.md
3. Prompt embeds SPECTRA doctrine, team roster, full plan, active Signs, failure handling rules
4. Single session launched: `claude -p "TEAM_PROMPT" --permission-mode delegate --max-turns 200`
5. Team lead creates tasks from plan.md and coordinates teammates
6. Each teammate implements assigned tasks respecting file ownership boundaries
7. TaskCompleted hook runs spectra-verify on completion
8. TeammateIdle hook assigns next task if work remains
9. On COMPLETE: launcher detects signal file and reports success
10. On STUCK: launcher detects signal file and preserves branch for human

### File Ownership Rules

1. **No overlap** — Two tasks must never own the same file
2. **Explicit boundaries** — Every source file appears in exactly one task's ownership
3. **Shared files sequenced** — Files like `__init__.py` assigned to one task, others `blockedBy`
4. **Test isolation** — Each task owns its own test files
5. **Integration task last** — Final task may read all files but owns only integration-specific files

### Hook Scripts

| Hook | File | Trigger | Behavior |
|------|------|---------|----------|
| TaskCompleted | `~/.spectra/hooks/spectra-task-completed.sh` | Teammate marks task complete | Runs spectra-verify; exit 0 = allow, exit 2 = reject with feedback |
| TeammateIdle | `~/.spectra/hooks/spectra-teammate-idle.sh` | Teammate goes idle | Checks remaining tasks, uncommitted changes, missing reports; exit 2 = assign next task |

### Agent Teams Signs

| Sign | Rule |
|------|------|
| SIGN-004: Lead Drift | Team lead must not write code. If lead implements, escalate immediately. |
| SIGN-005: File Collision | No two teammates may edit the same file. Task decomposition must assign file ownership. |
| SIGN-006: Stale Task | If task stays in-progress >10 minutes without output, lead must nudge or reassign. |
| SIGN-007: Silent Failure | Teammate errors must be surfaced to lead via mailbox. Silent swallowing is a system fault. |

### Constraints

- Verification is never parallel — single deterministic verifier only
- Team Lead runs in delegate mode only (no direct coding)
- If team session dies mid-run → loop reads git log, falls back to sequential
- Cost ceiling enforcement: if parallel cost exceeds ceiling → disable teams, downgrade to sequential

---

## 8. Signs (Learned Guardrails)

Signs are hard-won lessons from SPECTRA execution failures. They live in `.spectra/guardrails.md` and are checked by both the Builder (before committing) and the Verifier (during audit).

### SIGN-001: Integration tests must invoke what they import
> "Every integration test must invoke every pipeline step it imports — importing a module without calling it is dead code in a test."

### SIGN-002: CLI commands need subprocess-level tests
> "CLI commands must have subprocess-level tests that prove real execution, not just class-level unit tests."

### SIGN-003: Lessons must generalize, not just fix
> "If the spec says A -> B -> C -> D and your test skips B, you've written a unit test with extra steps — not an integration test."

### SIGN-004: Lead Drift
> "Team lead must not write code. If lead implements, escalate immediately."

### SIGN-005: File Collision
> "No two teammates may edit the same file. Task decomposition must assign file ownership."

### SIGN-006: Stale Task
> "If task stays in-progress >10 minutes without output, lead must nudge or reassign."

### SIGN-007: Silent Failure
> "Teammate errors must be surfaced to lead via mailbox. Silent swallowing is a system fault."

### SIGN-008: Research Before STUCK
> "Before declaring STUCK on any external blocker (dependency install, build error, missing package, environment issue), the builder must spend at least one research cycle using web search or documentation lookup. Most tooling failures have known solutions — a 30-second search beats a full STUCK escalation."

---

## 9. Project Structure

```
project/
├── .spectra/                          # SPECTRA workspace
│   ├── constitution.md                # Project principles
│   ├── prd.md                         # Product requirements (Level 2+)
│   ├── architecture.md                # System design (Level 3+)
│   ├── stories/                       # Story files
│   │   ├── story-1.md
│   │   └── story-N.md
│   ├── plans/
│   │   └── plan.md                    # Execution contract
│   ├── guardrails.md                  # Active Signs
│   ├── non-goals.md                   # Explicit exclusions
│   ├── lessons-learned.md             # Institutional memory
│   ├── project.yaml                   # Project metadata + cost ceilings
│   ├── hooks/                         # Agent Teams hook scripts
│   │   ├── spectra-task-completed.sh
│   │   └── spectra-teammate-idle.sh
│   ├── signals/                       # Runtime signals
│   │   ├── STATUS                     # Current run status
│   │   ├── STUCK                      # Halt signal
│   │   ├── COMPLETE                   # Completion signal
│   │   └── plan-review.md             # Planning gate verdict
│   └── logs/                          # Agent reports
│       ├── task-N-preflight.md        # Auditor scan
│       ├── task-N-build.md            # Builder report
│       ├── task-N-verify.md           # Verifier audit
│       ├── task-N-fail.md             # Fail context
│       ├── plan-review.md             # Review verdict
│       └── final-report.md            # Run summary
├── CLAUDE.md                          # Auto-generated context (refreshed per cycle)
└── src/                               # Application source code
```

---

## 10. Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| spectra-planner.md | `~/.claude/agents/` + `~/.spectra/agents/` | Planner agent definition |
| spectra-reviewer.md | `~/.claude/agents/` + `~/.spectra/agents/` | Reviewer agent definition |
| spectra-auditor.md | `~/.claude/agents/` + `~/.spectra/agents/` | Auditor agent definition |
| spectra-builder.md | `~/.claude/agents/` + `~/.spectra/agents/` | Builder agent definition |
| spectra-verifier.md | `~/.claude/agents/` + `~/.spectra/agents/` | Verifier agent definition |
| spectra-loop-v3.sh | `~/.spectra/bin/` | v3.0 thin launcher (Agent Teams) |
| spectra-team-prompt.sh | `~/.spectra/bin/` | Team prompt generator |
| spectra-loop-legacy.sh | `~/.spectra/bin/` | Legacy v2.0 execution loop (reference) |
| spectra-init | `~/.local/bin/` | Project initialization |
| spectra-verify | `~/.local/bin/` | Standalone verification |
| spectra-task-completed.sh | `~/.spectra/hooks/` | Agent Teams TaskCompleted hook |
| spectra-teammate-idle.sh | `~/.spectra/hooks/` | Agent Teams TeammateIdle hook |
| settings.json | `~/.claude/` | Claude Code settings (env vars, permissions) |

---

## 11. Core Doctrine

Seven principles that govern all operation:

1. **"Agents may reason. Only files may decide."** — If state cannot be proven on disk, it does not exist.
2. **"Plans are disposable. Running plans are not."** — Replan freely before lock. Never after.
3. **"No Done without evidence."** — Every task needs test results AND proof.
4. **"Fresh context is a feature."** — Agents start clean each session. State persists in files, not memory.
5. **"Verification is never parallel."** — One verifier, one verdict, deterministic.
6. **"Fail closed, not open."** — Unknown cost, unknown state, unknown failure = STUCK.
7. **"Institutional memory needs garbage collection."** — Lessons expire, promote, or archive. Accumulation is a fault.

---

## 12. Dry Run Validation (Feb 2026)

SPECTRA was validated through **spectra-healthcheck** — a Python CLI tool that validates SPECTRA project structure.

| Task | Description | First Audit | Fix Cycles | Final |
|------|-------------|------------|------------|-------|
| 1 | Project Structure Validator | PASS WITH NOTES | 0 | PASS |
| 2 | Plan Parser & Status Reporter | PASS WITH NOTES | 0 | PASS |
| 3 | Linear Issue Tracking | FAIL | 1 | PASS |
| 4 | Forced Failure & Verification Gate | PASS WITH NOTES | 0 | PASS |
| 5 | Slack Notification + Integration Test | FAIL | 1 | PASS |

5/5 tasks delivered. 57 tests. 7 commits. 2 FAILs caught and fixed within max iterations.

Recurring bug class: "Unit Tests Green, Integration Wiring Missing" — agents write class-level tests that pass in isolation but fail to test real execution wiring. This led to the Wiring Proof requirement and Signs 1-3.

---

## 13. Adoption & Roadmap

| Component | Status |
|-----------|--------|
| spectra-planner | Deployed |
| spectra-reviewer | Deployed |
| spectra-auditor | Deployed |
| spectra-builder | Deployed |
| spectra-verifier | Deployed |
| spectra-loop-v3.sh | Deployed (v3.0 native Agent Teams) |
| spectra-team-prompt.sh | Deployed (v3.0 prompt generator) |
| Agent Teams hooks | Deployed |
| spectra-init | Deployed |
| spectra-doctor | Planned |

### Roadmap

- [x] Core pipeline (plan, build, verify)
- [x] Cross-model validation (Opus + Sonnet)
- [x] Pre-flight auditor (Haiku)
- [x] Agent Teams parallel execution (Level 3+)
- [x] Native Agent Teams v3.0 (Opus 4.6, thin launcher architecture)
- [ ] spectra-doctor (project health diagnostics)
- [ ] Cost tracking integration (real-time token metering)
- [ ] Multi-project orchestration

---

## 14. Related Documents

- **SPECTRA_AUTONOMY_CONTRACT.md** — Authority, limits, and failure conditions for autonomous operation
- **SPECTRA_METHOD.md** — Original unified methodology reference (BMAD + Ralph + YCE)
- **guardrails.md** — Per-project active Signs
- **lessons-learned.md** — Per-project institutional memory

---

*SPECTRA v3.0 — A unified AI software engineering methodology.*
*Combining the planning depth of BMAD, the execution simplicity of Ralph Wiggum, and the orchestration rigor of Your Claude Engineer.*
*v3.0: Native Agent Teams architecture replacing bash-orchestrated multi-process model.*
