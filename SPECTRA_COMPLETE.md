# SPECTRA v5.5 — Complete Reference

**S**ystematic **P**lanning, **E**xecution via **C**lean-context loops, **T**racking & verification with **R**eal-time **A**gent orchestration

> Plan like BMAD. Execute like Ralph. Orchestrate like Your Claude Engineer.

**Version:** 5.5
**Date:** March 9, 2026
**Architecture:** All-Anthropic (Bash-native parallel orchestration via Claude Code Opus 4.6)
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

## 2. Agent Roster (v5.5)

| Agent | Model | Permission | Key Constraint |
|-------|-------|------------|----------------|
| spectra-planner | Opus | plan | Research only, 40 max turns |
| spectra-builder | Opus | acceptEdits | 50 max turns |
| spectra-verifier | Opus | plan | No Edit/Write, 30 max turns |
| spectra-reviewer | Sonnet | plan | Cross-model assurance, 25 max turns |
| spectra-auditor | Haiku | plan | 10 max turns, fast scan, no Bash |
| spectra-scout | Haiku | plan | 15 max turns, discovery phase |
| spectra-oracle | Haiku | plan | 3 max turns, failure classifier |

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
- Permission mode: plan (no Edit/Write — read-only cross-model assurance)

**spectra-auditor (Haiku)**
- Fast, cheap pre-flight scan before each build cycle
- Checks codebase against active Signs in guardrails.md
- Permission mode: plan (no Bash, no Edit/Write — advisory scan only)
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

**spectra-scout (Haiku)**
- Discovery-phase agent for codebase exploration and dependency mapping
- Runs before planning to gather project context
- Permission mode: plan (15 max turns, lightweight discovery)

**spectra-oracle (Haiku)**
- Failure classification agent invoked on build/verify failures
- Classifies failure type to route retry strategy
- Permission mode: plan (3 max turns, fast triage)

---

## 3. Scale Assessment

| Level | Name | Duration | Artifacts Required |
|-------|------|----------|-------------------|
| 0 | Micro-task / Bug Fix | < 1 hour | None — skip planning |
| 1 | Small Feature | < 1 day | plan.md with checkboxes |
| 2 | Medium Feature | 1-3 days | constitution.md + plan.md + stories |
| 3 | Large Feature | 1-2 weeks | Full pipeline + File Ownership + parallel execution eligible |
| 4 | Enterprise | 2-4 weeks | Full pipeline + parallel execution streams |

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
spectra-loop.sh (bash-native orchestrator)
  └─→ parse_plan() → next_batch() → parallel_build() → verify (sequential)
        On FAIL: oracle classification + diminishing retry budget
        Checkpoint/resume via JSON state
```

### Architecture (v5.0)

v5.0 bash-native parallel architecture. `spectra-loop.sh` orchestrates: `parse_plan()` reads the plan and builds a dependency graph, `next_batch()` identifies independent tasks eligible for parallel execution, `parallel_build()` launches builder agents in parallel for non-overlapping tasks, and verification runs sequentially after each build. On FAIL: oracle classification determines failure type and routes retry strategy with a diminishing retry budget. Checkpoint/resume via JSON state file enables recovery from interrupted runs.

### Phase 1: Planning
- `spectra-plan.sh` invokes spectra-planner (Opus) to generate artifacts
- spectra-reviewer (Sonnet) validates artifacts cross-model
- If REJECTED: planner revises once, reviewer re-evaluates. If re-rejected → STUCK.

### Phase 2: Plan Lock
- Plan is locked after APPROVED/APPROVED_WITH_WARNINGS
- No reinterpretation, reordering, addition, or removal of tasks
- Plans are disposable. Running plans are not.

### Phase 3: Execution Loop
For each batch of independent tasks, the bash orchestrator coordinates:
1. **Pre-flight audit** — invoke auditor (Haiku) for Sign violations scan
2. **Build** — invoke builder (Opus) agents in parallel for non-overlapping tasks
3. **Verify** — invoke verifier (Opus) sequentially for each completed task (never parallel)
4. On PASS: check off task, commit, continue to next batch
5. On FAIL: oracle (Haiku) classifies failure type, retry with diminishing budget
6. On exhausted retries or compound failure: attempt Party Mode recovery, then STUCK if unrecoverable

### Phase 4: Completion
- spectra-reviewer (Sonnet) performs final PR review
- COMPLETE signal written
- Final report generated

---

## 6. Verification Protocol

### Four-Step Audit

1. **Task verify command** — run the exact CLI command from plan.md
2. **Full regression suite** — all existing tests must still pass
3. **Evidence chain** — git commit hash matches task ID convention
4. **Wiring proof** — dead import detection, integration test pipeline check, non-goal compliance

### Verification Invariants

- Verification is single-agent only — no parallel verification, ever
- Verifier has no write access (tool allowlist enforced)
- Results must be reproducible given the same inputs

### Failure Taxonomy

| Failure Type | Max Retries | Action |
|-------------|-------------|--------|
| Test failure / flake | 3 | Retry |
| Missing dependency | 3 | Retry |
| Wiring gap / integration | 2 | Retry |
| External blocker (researchable) | 0 | STUCK (SIGN-008 research happens during build; Party Mode recovery attempted before escalation) |
| Architecture mismatch | 0 | STUCK |
| Ambiguous spec | 0 | STUCK |
| Verifier non-determinism | 0 | STUCK |
| External blocker (hard) | 0 | STUCK |

**Compound failure rule:** Two different failure types on the same task → Party Mode recovery attempted first. If recovery fails or type is non-recoverable → STUCK.

---

## 7. Bash-Native Parallel Execution (v5.0)

### Architecture

SPECTRA v5.0 replaces the Agent Teams model with bash-native parallel orchestration. `spectra-loop.sh` parses the plan's dependency graph, identifies batches of independent tasks, and launches parallel builder agents as separate CLI processes. No team lead agent — the bash script is the orchestrator.

| Role | Agent | Model | Invocation |
|------|-------|-------|------------|
| Planner | spectra-planner | Opus | `claude --agent spectra-planner -p "PROMPT"` |
| Reviewer | spectra-reviewer | Sonnet | `claude --agent spectra-reviewer -p "PROMPT"` |
| Auditor | spectra-auditor | Haiku | `claude --agent spectra-auditor -p "PROMPT"` |
| Builder | spectra-builder | Opus | `claude --agent spectra-builder -p "PROMPT"` |
| Verifier | spectra-verifier | Opus | `claude --agent spectra-verifier -p "PROMPT"` |
| Scout | spectra-scout | Haiku | `claude --agent spectra-scout -p "PROMPT"` |
| Oracle | spectra-oracle | Haiku | `claude --agent spectra-oracle -p "PROMPT"` |

### How It Works

1. `spectra-loop.sh` handles CLI args, branch isolation, and directory setup
2. `parse_plan()` reads plan.md and builds a dependency graph
3. `next_batch()` identifies tasks with no unresolved dependencies
4. `parallel_build()` launches builder agents in parallel for non-overlapping tasks
5. Verification runs sequentially after each build (never parallel)
6. On FAIL: oracle agent classifies failure type, retry with diminishing budget
7. Checkpoint/resume via JSON state file for recovery from interrupted runs
8. On COMPLETE: final report generated, COMPLETE signal written
9. On STUCK: STUCK signal written, branch preserved for human

### File Ownership Rules

1. **No overlap** — Two tasks must never own the same file
2. **Explicit boundaries** — Every source file appears in exactly one task's ownership
3. **Shared files sequenced** — Files like `__init__.py` assigned to one task, others `blockedBy`
4. **Test isolation** — Each task owns its own test files
5. **Integration task last** — Final task may read all files but owns only integration-specific files

### Execution Signs

| Sign | Rule |
|------|------|
| SIGN-004: Lead Drift | No team lead agent in v5.0 — bash script orchestrates, agents build. |
| SIGN-005: File Collision | No two parallel builders may edit the same file. Task decomposition must assign file ownership. |
| SIGN-006: Stale Task | If task stays in-progress >10 minutes without output, loop must nudge or reassign. |
| SIGN-007: Silent Failure | Worker errors must be surfaced via loop logs/signals. Silent swallowing is a system fault. |

### Constraints

- Verification is never parallel — single deterministic verifier only
- Bash script is the orchestrator (no team lead agent)
- If run dies mid-execution → JSON checkpoint enables resume from last completed task
- Oracle classifies failures to route retry strategy efficiently

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

### SIGN-009: Test Ordering Pollution
> "Tests that pass in isolation but fail in the full suite indicate test pollution — shared state leaking between test files."

### SIGN-010: Language Blindspot
> "Wiring proof must cover all languages present in the project. Running Python-only checks on a non-Python project is equivalent to no wiring proof. Prevention: auto-detect language, require profile match or emit WARNING."

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
│   ├── plan.md                        # Execution contract
│   ├── project.yaml                   # Project metadata + cost ceilings
│   ├── assessment.yaml                # Scale assessment output
│   ├── verify.yaml                    # Wiring verification rules
│   ├── guardrails.md                  # Project-specific Signs (static rules since v5.4)
│   ├── lessons-active.md              # Live lesson feed (auto-generated by inject_active_lessons)
│   ├── lessons-learned.md             # FAIL -> FIX log
│   ├── non-goals.md                   # Explicit exclusions
│   ├── VERSION                        # SPECTRA version marker
│   ├── PROMPT_build.md                # Builder context prompt
│   ├── PROMPT_verify.md               # Verifier context prompt
│   ├── PROMPT_split.md                # Stuck task splitter prompt
│   ├── signals/                       # Runtime signals
│   │   ├── STATUS                     # Current run status
│   │   ├── STUCK                      # Halt signal (includes Recovery-Attempted field)
│   │   ├── COMPLETE                   # Completion signal
│   │   ├── PROGRESS                   # Task completion counters
│   │   ├── PHASE                      # Current execution phase
│   │   ├── AGENT                      # Active agent name
│   │   ├── RECONCILE                  # Assessment drift detection
│   │   └── RECOVERY_PLAN              # Party Mode recovery plan (if applicable)
│   └── logs/                          # Agent reports
│       ├── task-N-preflight.md        # Auditor scan
│       ├── task-N-build.md            # Builder report
│       ├── task-N-verify.md           # Verifier audit
│       ├── task-N-fail.md             # Fail context
│       ├── task-N-recovery.md         # STUCK recovery attempt log
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
| spectra-oracle.md | `~/.claude/agents/` + `~/.spectra/agents/` | Oracle agent definition (failure classifier) |
| spectra-scout.md | `~/.claude/agents/` + `~/.spectra/agents/` | Scout agent definition (discovery phase) |
| spectra-loop.sh | `~/.spectra/bin/` | v5.0 bash-native parallel orchestrator |
| spectra-init.sh | `~/.spectra/bin/` | Project initialization |
| spectra-verify.sh | `~/.spectra/bin/` | Standalone verification |
| spectra-assess.sh | `~/.spectra/bin/` | Scale assessment (Level 0-4) |
| spectra-plan.sh | `~/.spectra/bin/` | Plan generation |
| spectra-status.sh | `~/.spectra/bin/` | Observability dashboard |
| spectra-preflight.sh | `~/.spectra/bin/` | Token verification |
| spectra-verify-wiring.sh | `~/.spectra/bin/` | Automated wiring verification |
| install.sh | `~/.spectra/` | Installer (adds bin/ to PATH) |
| SKILL.md | `~/.spectra/` | Claude Code skill definition |
| lib/loop-stuck-recovery.sh | `~/.spectra/lib/` | Party Mode STUCK recovery |
| lib/loop-lessons.sh | `~/.spectra/lib/` | Continuous learning system |
| lib/loop-context.sh | `~/.spectra/lib/` | Centralized context loading policy |
| lib/loop-session.sh | `~/.spectra/lib/` | Runtime profiles + session persistence |
| lang-profiles/python.profile | `~/.spectra/lang-profiles/` | Python language wiring profile |
| lang-profiles/javascript.profile | `~/.spectra/lang-profiles/` | JavaScript/TypeScript wiring profile |
| lang-profiles/bash.profile | `~/.spectra/lang-profiles/` | Bash wiring profile |
| scripts/spectra-quality-gate.sh | `~/.spectra/scripts/` | Language-aware lint/format quality gates |
| hooks/post-verify-learn.sh | `~/.spectra/hooks/` | Opt-in Sign candidate discovery |
| agents/scripts/builder-self-audit.sh | `~/.spectra/agents/scripts/` | 4-step builder self-audit |
| bin/spectra-refactor-clean.sh | `~/.spectra/bin/` | Post-project cleanup (dry-run default) |
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
| spectra-loop.sh | Deployed (v5.0 bash-native parallel orchestrator) |
| spectra-scout | Deployed (v5.0 discovery agent) |
| spectra-oracle | Deployed (v5.0 failure classifier) |
| spectra-init | Deployed |
| spectra-doctor | Planned |

### Roadmap

- [x] Core pipeline (plan, build, verify)
- [x] Cross-model validation (Opus + Sonnet)
- [x] Pre-flight auditor (Haiku)
- [x] Agent Teams parallel execution (Level 3+) — replaced by v5.0
- [x] Native Agent Teams v3.0 (Opus 4.6, thin launcher architecture) — replaced by v5.0
- [x] Bash-native parallel orchestration v5.0 (replaces Agent Teams)
- [x] Continuous learning system v5.3 (JSONL + flock, fingerprint dedup, adaptive TTL)
- [x] Bidirectional lessons v5.4 (inject_active_lessons, brownfield migration)
- [x] Party Mode STUCK recovery v5.4.1 (classify/recover/escalate)
- [x] Language profiles v5.4.1 (python.profile, auto-detection, SIGN-010)
- [x] Builder self-audit script v5.4.1 (4-step executable audit)
- [x] Agent routing validation v5.4.1 (63 frontmatter tests)
- [x] Dogfood sprint v5.5 (11 self-executed tasks, 522 tests across 28 suites)
- [x] Language-aware verifier + quality gates v5.5 (JS/bash profiles, 5-language quality gate)
- [x] Progressive context loading v5.5 (centralized loop-context.sh)
- [x] Runtime profiles v5.5 (quick/standard/thorough, session persistence)
- [x] Post-project cleanup v5.5 (spectra-refactor-clean.sh, dry-run default)
- [ ] spectra-doctor (project health diagnostics)
- [ ] Cost tracking integration (real-time token metering)
- [ ] Multi-project orchestration
- [ ] Additional language profiles (Go, Rust)

---

## 14. Related Documents

- **SPECTRA_AUTONOMY_CONTRACT.md** — Authority, limits, and failure conditions for autonomous operation
- **SPECTRA_METHOD.md** — Original unified methodology reference (BMAD + Ralph + YCE)
- **guardrails.md** — Per-project active Signs
- **lessons-learned.md** — Per-project institutional memory

---

*SPECTRA v5.5 — A unified AI software engineering methodology.*
*Combining the planning depth of BMAD, the execution simplicity of Ralph Wiggum, and the orchestration rigor of Your Claude Engineer.*
*v5.0: Bash-native parallel architecture. v5.3+: Continuous learning. v5.4.1: Party Mode STUCK recovery. v5.5: Dogfood sprint — 11 self-executed tasks, progressive context, runtime profiles, quality gates.*
