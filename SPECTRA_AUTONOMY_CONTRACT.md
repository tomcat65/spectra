# SPECTRA v3.0 — AUTONOMY CONTRACT

> **"Agents may reason. Only files may decide."**

**Status:** Active — Non-Negotiable Guardrail
**Applies To:** SPECTRA v3.0 autonomous execution
**Audience:** Team Lead, Teammates, Verifier, Humans-in-Reserve
**Last Updated:** February 9, 2026
**Architecture:** All-Anthropic (Native Agent Teams via Claude Code Opus 4.6)

---

## 0. Purpose

This document defines the **explicit authority, limits, and failure conditions** of SPECTRA operating in autonomous mode.

Autonomy is permitted only where failure is:

- **Detectable** — every action produces verifiable evidence
- **Containable** — blast radius is bounded by feature branches and cost ceilings
- **Reversible** — no merge to main until all gates pass

Anything outside these bounds must surface as **STUCK**.

---

## 1. Authority Boundary — What SPECTRA May Decide

SPECTRA is authorized to operate unattended **only within the following scope**.

### 1.1 Allowed (Autonomous)

- Generate constitution.md, prd.md, plan.md from project description
- Cross-model validate planning artifacts (Opus generates, Sonnet reviews)
- Execute tasks defined in a locked plan.md
- Spawn builder, verifier, reviewer, auditor, and planner as Agent Teams teammates
- Retry tasks within defined failure budgets (see Section 4)
- Commit code to feature branches via git
- Generate reports, logs, and signal files
- Update plan.md checkboxes after verified PASS
- Append to lessons-learned.md after FAIL→FIX cycles
- Open PRs and notify external systems (Slack, Linear)
- Run pre-flight auditor scans before build cycles
- Auto-promote recurring lessons to guardrails.md Signs

### 1.2 Explicitly Forbidden (Requires Human)

- Modifying project intent or scope after plan lock
- Rewriting plan.md after lock (plans are disposable; running plans are not)
- Bypassing or overriding a verifier FAIL
- Disabling guardrails, Signs, or wiring proof requirements
- Increasing project level mid-execution
- Exceeding cost ceilings (must downgrade or STUCK)
- Deploying Level 3+ projects without human checkpoint
- Merging to main without all tasks at PASS status
- Modifying agent definitions mid-run
- Granting agents tools beyond their allowlist

**Default posture: if an action is not explicitly allowed, it is forbidden.**

---

## 2. Planning Gate — Cross-Model Validation

### 2.1 Architecture

Planning validation uses cross-model assurance within the Anthropic ecosystem:

```
spectra-planner (Opus) → generates artifacts
spectra-reviewer (Sonnet) → validates artifacts
```

Different model architectures provide genuine diversity of perspective. The reviewer is not the same weights arguing with themselves — it is a structurally different model challenging the planner's output.

### 2.2 Mandatory Validation Gate

Autonomous execution **MUST NOT BEGIN** until the spectra-reviewer writes `.spectra/signals/plan-review.md` with one of:

| Verdict | Meaning | Action |
|---------|---------|--------|
| `APPROVED` | Plan is sound | Execution proceeds |
| `APPROVED_WITH_WARNINGS` | Plan is viable but has risks | Warnings appended to guardrails.md as enforceable constraints; execution proceeds |
| `REJECTED` | Plan has blocking issues | One autonomous revision permitted (see 2.3) |

### 2.3 Rejection Handling

If validation returns `REJECTED`:

1. Rejection feedback is written to `.spectra/logs/plan-rejection.md`
2. Planner (Opus) revises artifacts based on rejection feedback — **one attempt only**
3. Reviewer (Sonnet) re-evaluates revised artifacts
4. If re-rejected → **STUCK** — human intervention required
5. No further autonomous revision attempts are permitted

### 2.4 Review Evidence

Every plan review must record:

```markdown
## Plan Review
- Verdict: [APPROVED | APPROVED_WITH_WARNINGS | REJECTED]
- Reviewer Model: [model version]
- Reviewer Prompt Hash: [sha256 of reviewer agent definition]
- Timestamp: [ISO 8601]
- Warnings: [list, if any]
- Enforced: [confirmation warnings appended to guardrails.md]
```

---

## 3. Execution Contract — Plan Lock

### 3.1 Lock Semantics

Once plan.md receives `APPROVED` or `APPROVED_WITH_WARNINGS`:

- The plan is **locked** — no agent may reinterpret intent
- No task order may change
- No new tasks may be added
- No tasks may be removed or skipped

If execution reveals plan ambiguity → **IMMEDIATE STUCK**.

**Plans are disposable. Running plans are not.**

### 3.2 Non-Goals

Each project may optionally define `.spectra/non-goals.md`. If present:

- All agents must verify no task output violates declared non-goals
- Non-goal violations are treated as FAIL (not STUCK — the builder can fix)
- Verifier checks non-goal compliance as part of audit Step 4

### 3.3 Branch Isolation

Every autonomous run operates on a dedicated feature branch:

```bash
git checkout -b spectra/run-$(date +%Y%m%d-%H%M%S)
```

- If STUCK is raised, no merge occurs
- Main branch is always clean
- Rollback = delete the branch

---

## 4. Failure Handling & STUCK Semantics

### 4.1 Failure Taxonomy

The verifier's report must include a `failure_type` field. The loop uses this to determine retry vs. STUCK:

| Failure Type | Max Retries | Action | Rationale |
|-------------|-------------|--------|-----------|
| Test failure / flake | 3 | Retry | Mechanical fixes, builder can resolve |
| Missing dependency | 3 | Retry | Add to requirements, straightforward |
| Wiring gap / integration | 2 | Retry | Repeats signal a design flaw |
| External blocker (researchable) | 1 | Research + Retry | Dependency install, build errors, missing packages — builder must web search/docs lookup before STUCK (SIGN-008) |
| Architecture mismatch | 0 | STUCK | Builder cannot fix architecture — planning problem |
| Ambiguous spec | 0 | STUCK | Execution cannot resolve intent |
| Verifier non-determinism | 0 | STUCK | Determinism breach — system integrity at risk |
| External blocker (hard) | 0 | STUCK | Missing API keys with no workaround, service permanently down, human policy block |

### 4.2 Compound Failure Rule

If **two different failure types** occur on the same task → **IMMEDIATE STUCK**.

This is a strong signal that the plan is wrong, not the code.

### 4.3 Diminishing Retry Budget

Each retry gets fewer resources:

| Iteration | Token Budget | Rationale |
|-----------|-------------|-----------|
| 1 (initial) | 100% | Full capability |
| 2 (first retry) | 70% | Should be a targeted fix |
| 3 (final retry) | 50% | Last chance, must be surgical |

If the builder exceeds token budget on any iteration → kill and count as failed iteration.

### 4.4 STUCK Definition

STUCK means:

- Autonomous execution **halts immediately**
- `.spectra/signals/STUCK` file is written with failure context
- Slack notification sent (if configured)
- Human intervention is required
- **No further agent retries are permitted until human clears the STUCK**
- Feature branch preserved for human inspection

### 4.5 Post-Failure Reflection

After every FAIL→FIX cycle, the builder must include in its build report:

- What slipped and why
- What prevents recurrence
- Whether the pattern matches any existing Sign

The loop captures this in lessons-learned.md automatically.

### 4.6 Research Before STUCK (SIGN-008)

Most external blockers are **researchable** — the answer exists on the web or in documentation. The v3.0 MrBeast puzzle run proved this: a z3-solver install hang caused immediate STUCK, but `pip install z3-solver --only-binary=:all: --no-cache-dir` would have fixed it in 30 seconds.

**Mandatory research cycle before external_blocker STUCK:**

1. **Diagnose:** Capture the exact error message or symptom
2. **Search:** Use web search, context7, or package documentation
3. **Try the fix:** Apply the most promising solution
4. **If fixed:** Continue the task, note the fix in build report
5. **If still blocked:** NOW declare STUCK with research findings attached

The builder agent definition includes the full research protocol. The team lead must include SIGN-008 instructions when spawning builders.

---

## 5. Verification Invariants

### 5.1 Determinism

- Verification is **single-agent only** — no Agent Teams in verification, ever
- The verifier has **no write access** — architecturally enforced via tool allowlist, not prompt instruction
- Verifier tool allowlist: `Read, Bash, Grep, Glob` — no `Edit`, no `Write`
- Verification results must be reproducible given the same inputs

### 5.2 Verifier Drift Control

- Verifier agent definition (`spectra-verifier.md`) must be versioned in git
- SHA256 hash of verifier definition recorded in every `verify-report.md`
- Any change to verifier definition:
  - Invalidates all prior baselines
  - Must be logged in lessons-learned.md
  - Requires re-verification of any in-progress tasks

### 5.3 Four-Step Audit

Every verification executes:

1. **Task verify command** — run the exact CLI command from plan.md
2. **Full regression suite** — all existing tests must still pass
3. **Evidence chain** — git commit hash matches task ID convention
4. **Wiring proof** — dead import detection, integration test pipeline check, non-goal compliance

### 5.4 Verifier Report Format

```markdown
## Verification Report — Task N
- Result: [PASS | FAIL]
- Failure Type: [from taxonomy, if FAIL]
- Verifier Prompt Hash: sha256:[hash]
- Timestamp: [ISO 8601]
- Step 1 (Verify Command): [output summary]
- Step 2 (Regression): [X/Y tests passing]
- Step 3 (Evidence Chain): [commit hash, match status]
- Step 4 (Wiring Proof): [findings]
- Blocking Issues: [list, if FAIL]
- Notes: [non-blocking observations]
```

---

## 6. Cost & Resource Governance

### 6.1 Preflight Cost Estimate

Before execution begins, the loop must:

- Calculate: `(task_count × avg_tokens_per_task × model_rate) × retry_multiplier`
- Compare against project cost ceiling
- If estimate exceeds ceiling → **fail closed** (STUCK before any agent spawns)
- If estimate is incalculable (unknown task complexity) → **fail closed**

### 6.2 Cost Ceilings

Each project defines in `project.yaml`:

```yaml
cost:
  ceiling: 50.00          # USD, absolute maximum for this run
  per_task_budget: 10.00   # USD, per-task maximum (builder + verifier combined)
  parallelism_budget: 0    # USD, additional budget for Agent Teams (0 = disabled)
```

### 6.3 Enforcement

- If cumulative cost exceeds ceiling → Agent Teams disabled, downgrade to sequential
- If sequential downgrade still exceeds → **STUCK**
- Per-task budget exceeded → kill agent, count as failed iteration
- Cost-per-task appended to lessons-learned.md after every cycle

### 6.4 Billing

All agents use single Anthropic API dashboard. Model-tiered budgeting:

| Agent | Model | Relative Cost |
|-------|-------|--------------|
| spectra-auditor | Haiku | ~1x (baseline) |
| spectra-reviewer | Sonnet | ~5x |
| spectra-builder | Opus | ~25x |
| spectra-verifier | Opus | ~25x |
| spectra-planner | Opus | ~25x |

Auditor pre-flights cost pennies. Use them liberally to avoid wasting Opus tokens.

---

## 7. Agent Teams — Native Execution (v3.0)

> **Implementation Status (Feb 9 2026):** SPECTRA v3.0 uses native Claude Code Agent Teams (Opus 4.6). The thin launcher (`spectra-loop-v3.sh`) spawns ONE Claude Code session as team lead in delegate mode. The team lead spawns teammates (planner, reviewer, auditor, builder, verifier) via the Task tool with shared task lists and mailbox messaging.

### 7.1 Architecture

SPECTRA v3.0 replaces the bash-orchestrated multi-process model with a single Claude Code session:

```
spectra-loop-v3.sh (thin launcher)
  └─→ claude -p "TEAM_PROMPT" --permission-mode delegate --max-turns 200
        └─→ Team Lead (coordinates only, no coding)
              ├─→ Planner (Opus, plan mode)
              ├─→ Reviewer (Sonnet, plan mode)
              ├─→ Auditor (Haiku, plan mode)
              ├─→ Builder (Opus, acceptEdits mode)
              └─→ Verifier (Opus, plan mode)
```

The team prompt is generated by `spectra-team-prompt.sh`, which reads plan.md, guardrails.md, constitution.md, and non-goals.md to produce comprehensive natural language instructions.

### 7.2 Activation

Agent Teams are always active in v3.0. Parallel execution of independent tasks is permitted for Level 3+ projects where plan.md includes `TEAM_ELIGIBLE` and tasks have non-overlapping file ownership.

### 7.3 Team Constraints

- Team Lead must run in **delegate mode** (coordinates only, no coding)
- No two teammates may edit the same file (file ownership in task assignment)
- Plan approval required before any teammate implements
- Each teammate commits to feature branch after each task completion
- The team lead manages all orchestration natively: retry loops, failure taxonomy, diminishing budgets, compound failure detection
- If the session dies mid-run, the branch is preserved and `spectra-loop` can be re-run with `--skip-planning`

**Hook Scripts (deployed):**

| Hook | File | Trigger | Behavior |
|------|------|---------|----------|
| TaskCompleted | `~/.spectra/hooks/spectra-task-completed.sh` | Teammate marks task complete | Runs spectra-verify via `claude -p`; exit 0 = allow, exit 2 = reject |
| TeammateIdle | `~/.spectra/hooks/spectra-teammate-idle.sh` | Teammate goes idle | Checks remaining tasks, uncommitted changes; exit 2 = assign next task |

### 7.4 Team Signs

| Sign | Rule |
|------|------|
| SIGN-004: Lead Drift | Team lead must not write code. If lead implements, escalate immediately. |
| SIGN-005: File Collision | No two teammates may edit the same file. Task decomposition must assign file ownership. |
| SIGN-006: Stale Task | If task stays in-progress >10 minutes without output, lead must nudge or reassign. |
| SIGN-007: Silent Failure | Teammate errors must be surfaced to lead via mailbox. Silent swallowing is a system fault. |

### 7.5 Verification Is Never Parallel

Verification uses a single deterministic verifier subagent. Agent Teams are a build-phase tool, not a verification tool.

---

## 8. Pre-Flight Auditor Gate

### 8.1 Purpose

> **Implementation Status (Feb 9 2026):** `spectra-auditor.md` agent deployed to both `~/.claude/agents/` and `~/.spectra/agents/`. In v3.0, the team lead spawns the auditor as a Haiku teammate before each build cycle.

Before every build cycle, the team lead spawns the spectra-auditor (Haiku) as a teammate for a fast guardrails scan. This catches obvious Sign violations before wasting Opus tokens on a builder that would fail.

### 8.2 Execution

In v3.0, the team lead spawns the auditor via the Task tool:
```
Task tool: subagent_type=spectra-auditor, model=haiku, mode=plan
Prompt: "Scan codebase for active Sign violations before Task N build. Report to .spectra/logs/task-N-preflight.md"
Max turns: 10
```

### 8.3 Gate Behavior

- If auditor finds Sign violations → builder receives violation context with its assignment
- Auditor findings are advisory (do not block build), but are logged
- Auditor uses user-scope memory — violation patterns accumulate across all projects

---

## 9. Lessons-Learned Hygiene

### 9.1 The Problem

Institutional memory must not rot. Unchecked accumulation causes builders to optimize for historical quirks instead of current intent.

### 9.2 Entry Lifecycle

Every lessons-learned entry is tagged with a lifecycle state:

| State | Meaning | TTL | Transition |
|-------|---------|-----|------------|
| `TEMP` | Recent observation, not yet proven recurring | 5 projects | Auto-archive if not promoted |
| `PROMOTED` | Elevated to Sign in guardrails.md | Permanent (as Sign) | Manual demotion only |
| `ARCHIVED` | Historical record, not actively enforced | Indefinite | Can be re-promoted if pattern recurs |

### 9.3 Promotion Rules

- Lessons default to `TEMP` with a 5-project TTL
- If a TEMP lesson's pattern recurs in a subsequent project → **auto-promote** to Sign in guardrails.md
- If it doesn't recur within TTL → **auto-archive**
- The loop handles this mechanically — no reasoning required

### 9.4 Entry Format

```markdown
### LESSON-[timestamp]
- **State:** TEMP | PROMOTED | ARCHIVED
- **Pattern:** [description of what went wrong]
- **Fix:** [how it was resolved]
- **Projects Seen:** [list of projects where pattern appeared]
- **TTL Remaining:** [N projects, if TEMP]
- **Promoted To:** [SIGN-NNN, if promoted]
```

---

## 10. CLAUDE.md Contract — Single Source of Truth

### 10.1 Purpose

CLAUDE.md is the **single integration point** between SPECTRA and Claude Code's native agent system. Every subagent auto-loads it from the project root. It replaces the need for MCP, neural messaging, or any other context-passing mechanism during execution.

### 10.2 Auto-Generation

CLAUDE.md is generated by `spectra-init` and **refreshed by the loop after every task cycle**:

```markdown
# CLAUDE.md

## SPECTRA Context
- Project: [name]
- Level: [0-4]
- Phase: [current phase]
- Branch: spectra/run-[timestamp]

## Active Signs
[dynamically pulled from guardrails.md]

## Non-Goals
[pulled from non-goals.md, if present]

## Wiring Proof
All tasks require 5-check wiring proof before commit.

## Evidence Chain
Commits: feat(task-N) or fix(task-N)
Reports: .spectra/logs/task-N-{build|verify|preflight}.md

## Plan Status
[dynamically pulled from plan.md with checkbox states]
```

### 10.3 Invariants

- CLAUDE.md is the only file agents rely on for SPECTRA context
- It must always reflect current plan.md state
- It must always contain current active Signs
- Agents must not cache CLAUDE.md content across sessions

---

## 11. Observability — Mid-Run Monitoring

### 11.1 STATUS Signal

The loop writes `.spectra/signals/STATUS` after every task cycle:

```markdown
## SPECTRA Run Status
- Current Task: [N of total]
- Task Title: [title]
- Iteration: [current / max]
- Elapsed Time: [HH:MM:SS]
- Cumulative Cost: [$X.XX estimated]
- Pass History: [Task 1: PASS, Task 2: PASS, Task 3: FAIL→PASS, ...]
- Current Agent: [builder | verifier | auditor | idle]
- Last Updated: [ISO 8601]
```

### 11.2 Read-Only Window

Humans can monitor STATUS at any time without interrupting execution. The file is advisory — reading it has no side effects.

### 11.3 Log Trail

Every agent writes structured logs to `.spectra/logs/`:

| File | Written By | Content |
|------|-----------|---------|
| `task-N-preflight.md` | Auditor | Sign violation scan results |
| `task-N-build.md` | Builder | Implementation report, wiring proof results |
| `task-N-verify.md` | Verifier | 4-step audit results, failure type |
| `task-N-fail.md` | Loop | Fail context for builder retry |
| `plan-review.md` | Reviewer | Planning gate verdict |
| `plan-rejection.md` | Reviewer | Rejection feedback (if rejected) |
| `final-report.md` | Loop | Run summary, total cost, pass/fail history |

---

## 12. Deployment Rules

### 12.1 Level 0–2

- May deploy autonomously after all PASS conditions
- PR created automatically with full evidence chain
- Merge permitted without human review (if CI/CD passes)

### 12.2 Level 3+

- Requires **one human checkpoint** after final PASS, before merge/deploy
- This checkpoint is about **blast radius**, not trust
- Human reviews: final-report.md, git diff, cost summary
- Human signals approval by merging the PR

### 12.3 Post-Deploy

After deployment (all levels):
- Loop writes `.spectra/signals/COMPLETE`
- Slack notification sent with run summary
- Neural entity observations updated with institutional memory
- Cost and timing data appended to lessons-learned.md

---

## 13. Exit Conditions

Autonomy ends when any of the following occur:

| Condition | Signal | Recovery |
|-----------|--------|----------|
| All tasks PASS | `.spectra/signals/COMPLETE` | PR created, run finished |
| STUCK raised | `.spectra/signals/STUCK` | Human intervention required |
| Cost ceiling breached | `.spectra/signals/STUCK` + cost flag | Human reviews budget |
| Determinism violated | `.spectra/signals/STUCK` + integrity flag | Verifier audit required |
| Human override | Manual STUCK file creation | Graceful halt after current agent completes |

At exit, SPECTRA must:
1. Complete or kill the current agent session cleanly
2. Write final STATUS
3. Preserve all logs and the feature branch
4. Never leave the system in an ambiguous state

---

## 14. Core Doctrine

Seven principles that govern all autonomous operation:

1. **"Agents may reason. Only files may decide."** — If state cannot be proven on disk, it does not exist.
2. **"Plans are disposable. Running plans are not."** — Replan freely before lock. Never after.
3. **"No Done without evidence."** — Every task needs test results AND proof.
4. **"Fresh context is a feature."** — Agents start clean each session. State persists in files, not memory.
5. **"Verification is never parallel."** — One verifier, one verdict, deterministic.
6. **"Fail closed, not open."** — Unknown cost, unknown state, unknown failure → STUCK.
7. **"Institutional memory needs garbage collection."** — Lessons expire, promote, or archive. Accumulation is a fault.

---

**End of Contract**

*This contract is itself subject to SPECTRA's self-improvement loop. After every autonomous run, the orchestrator evaluates whether the contract's constraints were appropriate and captures amendments in lessons-learned.md for review.*
