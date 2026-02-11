# AI-Driven Software Engineering Frameworks
## Unified Method: Combining Your Claude Engineer + Enhanced Ralph Wiggum + BMAD

---

## 1. Efficiency Analysis

### The Efficiency Problem

Each framework optimizes for a different bottleneck, and none solves all three:

| Framework | Optimizes For | Sacrifices |
|-----------|--------------|------------|
| **Your Claude Engineer** | Reliability & traceability (Linear tracking, screenshot evidence, verification gates) | Setup complexity, token cost on orchestration overhead |
| **Enhanced Ralph Wiggum** | Simplicity & context freshness (bash loop, clean restarts, zero infrastructure) | Planning depth, can burn tokens on retry loops |
| **BMAD Method** | Planning completeness & governance (4-phase methodology, 21+ agents, audit trails) | Speed-to-first-code, overhead for small projects |

### Efficiency Verdict

**No single framework is universally "most efficient."** Efficiency depends on what you measure:

- **Time-to-first-working-code**: Ralph Wiggum wins. A bash loop and a spec file gets code shipping in minutes.
- **Time-to-production-quality**: Your Claude Engineer wins. Verification gates and screenshot evidence catch regressions early, reducing total rework.
- **Time-to-enterprise-ready**: BMAD wins. PRDs, architecture docs, and QA agents mean fewer surprises at scale.
- **Token efficiency**: Your Claude Engineer wins. Haiku handles orchestration; Sonnet only fires for actual coding. Ralph burns full-context tokens every loop iteration.
- **Developer cognitive load**: Ralph Wiggum wins. Nothing to learn — it's a bash script.

### The Real Insight

The three systems are **complementary, not competing**. They solve different phases of the same problem:

```
BMAD handles: "What should we build and how?"     → PLANNING
Ralph handles: "Build it, fix it, ship it."        → EXECUTION  
YCE handles:  "Track it, verify it, integrate it." → ORCHESTRATION
```

---

## 2. The Unified Method: SPECTRA

**S**ystematic **P**lanning → **E**xecution via **C**lean-context loops → **T**racking & verification with **R**eal-time **A**gent orchestration

### Core Philosophy

> Plan like BMAD. Execute like Ralph. Orchestrate like Your Claude Engineer.

SPECTRA takes the best mechanism from each framework and wires them into a single pipeline:

| Phase | Source Framework | What It Contributes |
|-------|-----------------|-------------------|
| **Phase 0: Scale Assessment** | BMAD | Right-size the planning depth (Level 0-4) |
| **Phase 1: Specification** | BMAD + SpecKit | Constitution → PRD → Architecture → Stories |
| **Phase 2: Task Decomposition** | Ralph Wiggum | Acceptance-criteria-driven task files on disk |
| **Phase 3: Autonomous Execution** | Ralph Wiggum | Clean-context bash loop, one task per iteration |
| **Phase 4: Verification & Tracking** | Your Claude Engineer | Linear tracking, screenshot evidence, verification gates |
| **Phase 5: Integration & Delivery** | Your Claude Engineer | Git commits, PRs, Slack notifications, completion detection |

---

## 3. SPECTRA Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SPECTRA UNIFIED METHOD                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │  BMAD BRAIN   │───▶│  RALPH HANDS  │───▶│  YCE BACKBONE  │  │
│  │  (Planning)   │    │  (Execution)  │    │ (Orchestration)│  │
│  └──────────────┘    └──────────────┘    └───────────────┘  │
│         │                    │                     │          │
│    Constitution         Bash Loop            Linear API      │
│    PRD + Arch          Fresh Context         Screenshot       │
│    Story Files         Test Gates            Verification     │
│    Scale Levels        Git Commits           Slack Notify     │
│                                              PR Creation      │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│              SHARED STATE (Filesystem + Cloud)                │
│                                                               │
│  .spectra/                    Linear Project (cloud)          │
│  ├── constitution.md          ├── Issues (source of truth)    │
│  ├── prd.md                   ├── META tracking issue         │
│  ├── architecture.md          └── Progress dashboard          │
│  ├── stories/                                                 │
│  │   ├── 001-story.md         .linear_project.json (local)    │
│  │   ├── 002-story.md                                         │
│  │   └── ...                  screenshots/ (evidence)         │
│  ├── plan.md (Ralph reads)                                    │
│  └── tasks.md (checkboxes)                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Phase-by-Phase Walkthrough

### Phase 0: Scale Assessment (from BMAD)

Before any work begins, assess project scale to right-size the process:

```
Level 0 — Bug Fix / Hotfix
  → Skip to Phase 2 (write a single task, run Ralph once)
  → No PRD, no architecture, no stories

Level 1 — Small Feature (< 1 day)
  → Quick spec with acceptance criteria
  → Skip architecture, minimal stories
  → Ralph loop: 3-5 iterations max

Level 2 — Medium Feature (1-5 days)
  → Full PRD with acceptance criteria
  → Light architecture (tech stack + data flow)
  → 3-8 stories, Ralph loop per story

Level 3 — Large Feature / New Module (1-4 weeks)
  → Full BMAD pipeline: PRD + Architecture + Stories
  → Bash-native parallel execution (& + wait)
  → Independent tasks build simultaneously, serial verify
  → JSON checkpoint for deterministic resume

Level 4 — Enterprise System / Greenfield (1+ months)
  → Full BMAD with all agents (Analyst → PM → Architect → SM)
  → Parallel builders + GitHub/Slack integration
  → Sprint-based delivery with QA agent validation
  → Bash orchestration coordinates all phases autonomously
```

**Decision rule**: If you can describe the change in one sentence, it's Level 0-1. If you need a meeting to explain it, it's Level 2-3. If it needs a slide deck, it's Level 4.

### Phase 1: Specification (BMAD-powered)

For Level 2+ projects, produce structured planning artifacts:

```
Step 1: Constitution (5 min)
  └── Project principles, tech constraints, coding standards
      File: .spectra/constitution.md

Step 2: PRD — Product Requirements Document (15-30 min)  
  └── User stories, acceptance criteria, NFRs, scope boundaries
      File: .spectra/prd.md

Step 3: Architecture (15-30 min, Level 3+ only)
  └── Tech stack, data models, API contracts, component diagram
      File: .spectra/architecture.md

Step 4: Story Decomposition (10-20 min)
  └── Break PRD into implementable stories with:
      - Clear acceptance criteria (testable)
      - Implementation hints (files to touch, patterns to follow)
      - Dependencies (which stories must complete first)
      Files: .spectra/stories/NNN-story-name.md
```

**BMAD Quick Flow shortcut**: For Level 2, use `/quick-spec` to generate all four artifacts in one pass.

**Key principle from BMAD**: Stories should be so detailed that the coding agent never has to guess intent. Every story includes "Definition of Done" with checkable criteria.

### Phase 2: Task Decomposition (Ralph-style)

Convert stories into Ralph-compatible task files:

```
Step 1: Generate plan.md from stories
  └── Ordered task list with checkboxes
  └── Each task maps to one story (or sub-story)
  └── Dependencies resolved into sequential order

Step 2: Generate tasks.md (execution manifest)
  └── For each task:
      - [ ] Task name
      - Acceptance criteria (copy from story)
      - Files to create/modify
      - Test commands to validate
      - Max iterations before "stuck" flag
```

**File: .spectra/plan.md**
```markdown
# SPECTRA Execution Plan
## Project: [name]
## Generated from: .spectra/stories/

### Tasks (in dependency order)
- [ ] 001: Initialize project structure and dependencies
  - AC: package.json exists, `npm install` succeeds, dev server starts
  - Files: package.json, tsconfig.json, src/index.ts
  - Verify: `npm run dev` exits 0
  - Max iterations: 5

- [ ] 002: Implement user authentication API
  - AC: POST /auth/login returns JWT, POST /auth/register creates user
  - Files: src/routes/auth.ts, src/middleware/jwt.ts
  - Verify: `npm test -- --grep "auth"` passes
  - Max iterations: 10

- [ ] 003: Build dashboard UI component
  - AC: Dashboard renders with user data, responsive on mobile
  - Files: src/components/Dashboard.tsx, src/components/Dashboard.test.tsx
  - Verify: `npm test` passes, screenshot matches spec
  - Max iterations: 8
```

### Phase 3: Autonomous Execution (Ralph Loop)

The core execution engine — a clean-context bash loop:

**File: scripts/spectra-loop.sh**
```bash
#!/bin/bash
# SPECTRA Execution Loop (Ralph Wiggum heritage)
# Usage: ./scripts/spectra-loop.sh [max_iterations]

MAX_ITER=${1:-30}
ITER=0

while [ $ITER -lt $MAX_ITER ]; do
    ITER=$((ITER + 1))
    echo "╔══════════════════════════════════════╗"
    echo "║  SPECTRA Loop — Iteration $ITER/$MAX_ITER"
    echo "╚══════════════════════════════════════╝"
    
    # Feed the execution prompt with full context
    cat .spectra/PROMPT_build.md | claude -p \
        --allowedTools "Bash(git*),Bash(npm*),Bash(npx*),Read,Write,Edit"
    
    EXIT_CODE=$?
    
    # Check for completion signal
    if grep -q "SPECTRA_COMPLETE" .spectra/plan.md; then
        echo "✅ All tasks complete. Exiting loop."
        break
    fi
    
    # Check for stuck signal (10 consecutive failures on same task)
    if grep -q "STUCK:" .spectra/plan.md; then
        echo "⚠️  Task stuck. Splitting into subtasks..."
        cat .spectra/PROMPT_split.md | claude -p
    fi
    
    echo "Loop $ITER complete. Restarting with fresh context..."
    sleep 2
done

echo "SPECTRA loop finished after $ITER iterations."
```

**Why this works** (Ralph Wiggum insight):
- Each iteration spawns a **fresh agent process** — no context overflow
- State persists in **files on disk** (plan.md, git history), not LLM memory
- Agent reads plan → picks next unchecked task → implements → tests → commits → exits
- Natural convergence: each iteration makes measurable progress
- If stuck after 10 attempts: task gets split into smaller sub-tasks automatically

### Phase 4: Verification & Tracking (YCE-powered)

After each Ralph loop iteration, the orchestrator verifies and tracks:

```
┌─────────────────────────────────────────────┐
│         VERIFICATION GATE (from YCE)         │
│                                               │
│  1. Read .spectra/plan.md for completed task  │
│  2. Run acceptance criteria tests             │
│  3. Capture screenshot evidence               │
│  4. Update Linear issue status                │
│  5. If verification FAILS:                    │
│     → Block next task                         │
│     → Feed failure context to next iteration  │
│  6. If verification PASSES:                   │
│     → Mark task Done in Linear                │
│     → Commit + push via GitHub agent          │
│     → Notify via Slack agent                  │
└─────────────────────────────────────────────┘
```

**Key YCE principle**: No task gets marked "Done" without evidence. Screenshots prove the feature works visually. Tests prove it works programmatically. Both are required.

**Verification script hook** (runs after each Ralph iteration):
```bash
# Post-iteration verification (YCE heritage)
verify_iteration() {
    TASK_ID=$(grep -m1 "^\- \[x\]" .spectra/plan.md | grep -oP '\d{3}')
    
    if [ -z "$TASK_ID" ]; then
        echo "No newly completed task. Continuing..."
        return
    fi
    
    # Run task-specific tests
    TEST_CMD=$(grep -A5 "$TASK_ID:" .spectra/plan.md | grep "Verify:" | cut -d: -f2-)
    eval $TEST_CMD
    
    if [ $? -ne 0 ]; then
        echo "❌ Verification failed for task $TASK_ID"
        # Uncheck the task — force retry in next iteration
        sed -i "s/\- \[x\] $TASK_ID/\- \[ \] $TASK_ID/" .spectra/plan.md
        echo "RETRY: $TASK_ID" >> .spectra/plan.md
        return 1
    fi
    
    # Capture screenshot evidence
    npx playwright screenshot --url http://localhost:3000 \
        .spectra/screenshots/${TASK_ID}-$(date +%s).png
    
    echo "✅ Task $TASK_ID verified with evidence"
}
```

### Phase 5: Integration & Delivery (YCE-powered)

When all tasks are checked off:

```
1. Orchestrator detects: done_count == total_tasks
2. Run full test suite (unit + integration + e2e)
3. Generate final screenshot evidence gallery
4. Create PR with:
   - Summary of all implemented stories
   - Link to Linear project dashboard
   - Screenshot evidence attachments
5. Send Slack notification: PROJECT_COMPLETE
6. Archive .spectra/ artifacts for future reference
```

---

## 5. File Structure

```
project/
├── .spectra/                          # SPECTRA unified workspace
│   ├── constitution.md                # Project principles (from BMAD)
│   ├── prd.md                         # Product requirements (from BMAD)
│   ├── architecture.md                # System design (from BMAD)
│   ├── stories/                       # Detailed story files (from BMAD)
│   │   ├── 001-project-setup.md
│   │   ├── 002-auth-api.md
│   │   └── 003-dashboard-ui.md
│   ├── plan.md                        # Execution manifest (Ralph reads this)
│   ├── tasks.md                       # Granular task tracking
│   ├── PROMPT_build.md                # Build mode prompt (for Ralph loop)
│   ├── PROMPT_split.md                # Task-splitting prompt (stuck handler)
│   ├── PROMPT_verify.md               # Verification prompt (YCE gate)
│   ├── screenshots/                   # Visual evidence (from YCE)
│   │   ├── 001-1738900000.png
│   │   └── 002-1738900100.png
│   └── .linear_project.json           # Cloud state marker (from YCE)
├── scripts/
│   ├── spectra-loop.sh                # Main execution loop (Ralph heritage)
│   ├── spectra-verify.sh              # Verification gate (YCE heritage)
│   ├── spectra-plan.sh                # Generate plan from stories (BMAD→Ralph bridge)
│   └── spectra-init.sh                # Project initialization
├── src/                               # Application source code
├── tests/                             # Test suites
└── package.json
```

---

## 6. SPECTRA Prompt Templates

### PROMPT_build.md (Ralph Loop — Each Iteration)

```markdown
# SPECTRA Build Agent

You are an autonomous coding agent executing one task per session.

## Context Files (read these first)
1. `.spectra/constitution.md` — Project principles and constraints
2. `.spectra/plan.md` — Current task list with checkboxes
3. `.spectra/architecture.md` — System design (if exists)

## Your Mission
1. Read `plan.md` and find the FIRST unchecked task (`- [ ]`)
2. Read the corresponding story in `.spectra/stories/`
3. Implement the task following the acceptance criteria EXACTLY
4. Run the verification command listed in the task
5. If tests pass: check off the task (`- [x]`), git commit with message `feat(NNN): description`
6. If tests fail: fix the issue and retry (up to 3 attempts this session)
7. If stuck after 3 attempts: add `STUCK: NNN` to plan.md and exit

## Rules
- ONE task per session. Do not start the next task.
- All tests must pass before committing.
- Follow the constitution strictly.
- Do not modify completed tasks (already checked `- [x]`).
- If ALL tasks are checked, write `SPECTRA_COMPLETE` at the end of plan.md.

## Exit
After completing (or getting stuck on) your task, exit cleanly.
The loop will restart you with fresh context for the next task.
```

### PROMPT_verify.md (YCE Verification Gate)

```markdown
# SPECTRA Verification Agent

You verify that completed tasks meet their acceptance criteria.

## Your Mission
1. Read `plan.md` for the most recently checked task
2. Read the corresponding story's acceptance criteria
3. Run ALL verification commands
4. Capture screenshot evidence if the task has UI components
5. Report: PASS or FAIL with evidence

## If FAIL
- Uncheck the task in plan.md
- Add failure reason as a comment below the task
- The build loop will retry on next iteration

## If PASS
- Confirm the task completion
- Note the screenshot path for the evidence gallery
```

---

## 7. When to Use What

### SPECTRA Scale Selector

```
"I need to fix a bug"
  → Level 0: Write one task in plan.md, run Ralph once
  → Skip everything else. Total time: 5 minutes.

"I need to add a small feature"
  → Level 1: Quick spec → 3-5 tasks → Ralph loop
  → No PRD, no architecture. Total time: 30 minutes.

"I need to build a new module"
  → Level 2: PRD → Stories → Ralph loop + verification
  → Full pipeline minus architecture. Total time: 2-4 hours.

"I need to build a new service"
  → Level 3: Full SPECTRA pipeline
  → All phases, Linear tracking, Slack notifications
  → Total time: 1-2 days of agent work.

"I need to build a new product"
  → Level 4: Full SPECTRA + parallel execution
  → Multiple Ralph loops on git worktrees
  → Sprint-based delivery with QA validation
  → Total time: 1-4 weeks of agent work.
```

---

## 8. Comparison: SPECTRA vs Individual Frameworks

| Dimension | YCE Alone | Ralph Alone | BMAD Alone | **SPECTRA** |
|-----------|-----------|-------------|------------|-------------|
| Setup time | 60 min | 5 min | 120 min | **15-60 min** (scale-adaptive) |
| Planning depth | Shallow (Linear issues) | Medium (specs) | Deep (4-phase) | **Right-sized** (Level 0-4) |
| Execution | Agent SDK orchestrator | Bash loop | Manual agent calls | **Bash loop** (proven) |
| Context management | Fresh sessions | Fresh context | Persistent | **Fresh context** (files persist) |
| Verification | Screenshots + tests | Tests only | QA agent | **Screenshots + tests + QA** |
| Progress tracking | Linear dashboard | Git commits | Sprint YAML | **Linear + Git + files** |
| Failure handling | Block & fix | Retry loop | Feedback loop | **Retry → split → verify** |
| Token efficiency | High (Haiku/Sonnet split) | Low (full context loops) | Medium | **Medium-High** (right-sized prompts) |
| Team scalability | 1-5 devs | Solo | 5-50+ | **1-50+** (scale-adaptive) |
| Learning curve | Medium | Low | High | **Low-Medium** (progressive disclosure) |

---

## 9. Quick Start

### Minimum Viable SPECTRA (Level 1 — Solo Developer)

```bash
# 1. Create project
mkdir my-project && cd my-project
git init

# 2. Initialize SPECTRA
mkdir -p .spectra/stories .spectra/screenshots scripts

# 3. Write a quick constitution
cat > .spectra/constitution.md << 'EOF'
# Constitution
- Language: TypeScript
- Framework: Next.js 15
- Testing: Vitest
- Style: Functional, minimal dependencies
EOF

# 4. Write your spec as a story
cat > .spectra/stories/001-mvp.md << 'EOF'
# Story 001: MVP Landing Page
## Acceptance Criteria
- [ ] Next.js app initializes and runs on port 3000
- [ ] Landing page renders with hero section
- [ ] Contact form submits to API route
- [ ] All tests pass
## Verify
`npm test && npm run build`
EOF

# 5. Generate plan from stories
cat > .spectra/plan.md << 'EOF'
# Execution Plan
- [ ] 001: Initialize Next.js project with TypeScript and Vitest
  - Verify: `npm run dev` starts without errors
  - Max iterations: 5
- [ ] 002: Build landing page with hero section
  - Verify: `npm test` passes, screenshot captured
  - Max iterations: 8
- [ ] 003: Add contact form with API route
  - Verify: `npm test -- --grep "contact"` passes
  - Max iterations: 8
EOF

# 6. Copy the PROMPT_build.md (from Section 6 above)

# 7. Run the loop
./scripts/spectra-loop.sh 20
```

### Full SPECTRA (Level 3+ — Team with Integrations)

```bash
# 1. Install BMAD for planning
npx bmad-method install --modules bmm --tools claude-code

# 2. Run BMAD planning pipeline
# (Analyst → PM → Architect → Scrum Master)
claude "/bmad-help"  # Guided setup
claude "/quick-spec"  # Or fast-track

# 3. Bridge BMAD output to SPECTRA format
./scripts/spectra-plan.sh  # Converts stories → plan.md

# 4. Setup YCE integrations
# Configure: Linear workspace, Arcade MCP Gateway, GitHub repo, Slack channel
cp .env.example .env
# Edit .env with your tokens

# 5. Initialize cloud tracking
./scripts/spectra-init.sh  # Creates Linear project + issues from plan.md

# 6. Run SPECTRA loop with full orchestration
./scripts/spectra-loop.sh 50  # With verification gates + Linear updates
```

---

## 10. Key Principles (Inherited Wisdom)

### From Your Claude Engineer
> **"No Done without evidence."** Every completed task requires proof — screenshots for UI, test results for logic. The verification gate is non-negotiable.

### From Ralph Wiggum  
> **"Fresh context is a feature, not a bug."** Each iteration starts clean. State lives in files and git, never in LLM memory. Context overflow is impossible.

### From BMAD
> **"Plan proportionally."** A bug fix doesn't need a PRD. An enterprise system does. Scale your process to your problem.

### SPECTRA's Own
> **"Complement, don't compromise."** Use the right tool for the right phase. Planning tools plan. Execution tools execute. Orchestration tools orchestrate. Don't force one framework to do everything.

---

## Appendix A: Token Cost Estimation

| Project Scale | Planning Tokens | Execution Tokens | Verification Tokens | **Total Estimate** |
|--------------|----------------|-----------------|--------------------|--------------------|
| Level 0 (Bug fix) | 0 | 5K-15K | 2K | **~17K** |
| Level 1 (Small feature) | 5K | 30K-80K | 10K | **~95K** |
| Level 2 (Medium feature) | 20K | 150K-400K | 50K | **~470K** |
| Level 3 (Large feature) | 50K | 500K-1.5M | 150K | **~1.7M** |
| Level 4 (Enterprise) | 150K | 2M-8M | 500K | **~8.6M** |

*v5.0 model assignments: Opus for planning/building/verification, Sonnet for cross-model review, Haiku for pre-flight audit and oracle classification. Models defined in agent YAML frontmatter (`~/.claude/agents/spectra-*.md`), not env vars.*

## Appendix B: Framework Source Links

- **Your Claude Engineer**: [github.com/coleam00/your-claude-engineer](https://github.com/coleam00/your-claude-engineer)
- **Enhanced Ralph Wiggum**: [github.com/fstandhartinger/ralph-wiggum](https://github.com/fstandhartinger/ralph-wiggum)
- **BMAD Method**: [github.com/bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)
- **SpecKit (GitHub)**: [github.com/nichochar/speckit](https://github.com/nichochar/speckit)
- **Ralph Wiggum Official Site**: [ralph-wiggum.ai](https://ralph-wiggum.ai/)

---

## 15. Self-Audit & Wiring Verification (v5.1)

### Why Self-Audit Exists

Phase 8 audits revealed the same failure mode for the THIRD time: the builder produces code that passes unit tests but isn't wired into the runtime. Dead functions, wrong constants, mock-only tests. The fix cycle doubles the work every time.

v5.1 eliminates this by making the builder self-auditing and adding automated verification.

### The 4 Universal Checks (Builder Self-Audit)

Before every commit, the builder must run these 4 checks:

1. **Reachability** — Every public function has at least one callsite in existing runtime code (not just tests)
2. **Spec Fidelity** — Every specific value in the task description (model names, status codes, field counts) appears literally in the code
3. **Integration Test Exists** — At least one test exercises the path from an entry point through the new code without mocking the connection
4. **Single Source of Truth** — IDs, timestamps, and computed values are generated once and passed through (no duplicate generation)

### verify.yaml Configuration

Each SPECTRA project can include `.spectra/verify.yaml` to define machine-checkable rules:

```yaml
project:
  source_dirs: ["src/"]
  test_dirs: ["tests/"]
  entry_points: ["src/server.py"]
  language: python

rules:
  wiring:
    enabled: true
    ignore_patterns: ["_*", "test_*"]
  framework_checks:
    - name: "no-flask-tuple-returns"
      pattern: 'return\s+\{.*\},\s*[0-9]{3}'
      paths: ["src/server.py"]
      severity: error
      message: "Flask-style tuple return in FastAPI"
  constants:
    - file: "src/config.py"
      pattern: "claude-sonnet-4-5-20250929"
      message: "Model must be Sonnet 4.5"
  write_guard:
    enabled: true
    abstraction: "safe_write"
    raw_pattern: 'db\.collection.*\.(set|add|update|delete)'
```

`spectra-verify-wiring.sh` reads this config and enforces all rules. It runs as part of the verify command for every task.

### plan.md Assertions

The planner auto-generates an `Assertions` block for each task:

```markdown
- Assertions:
  - GREP ralph/eval/judge.py "claude-sonnet-4-5-20250929" EXISTS
  - CALLSITE score_conversation NOT_ONLY_IN tests/ EXISTS
  - COUNT ralph/server.py "JSONResponse" MIN 3
```

Assertion types: `GREP file "pattern" EXISTS|NOT_EXISTS`, `CALLSITE function NOT_ONLY_IN dir/ EXISTS`, `COUNT file "pattern" MIN N`.

### What This Replaces

Self-audit + automated verification replaces the need for a dedicated auditor LLM for mechanical checks. The Haiku auditor still handles pattern-based Sign scanning, but wiring verification is now deterministic bash — zero tokens, instant feedback.

---

*SPECTRA v5.1 — A unified AI software engineering methodology*
*Combining the planning depth of BMAD, the execution simplicity of Ralph Wiggum, and the orchestration rigor of Your Claude Engineer.*

---

## 11. Validation: spectra-healthcheck Dry Run (Feb 2026)

SPECTRA was validated through a meta-test project called **spectra-healthcheck** — a Python CLI tool that validates SPECTRA project structure. "SPECTRA validates itself."

### Dry Run Scorecard

| Task | Description | First Audit | Fix Cycles | Final |
|------|-------------|------------|------------|-------|
| 1 | Project Structure Validator | PASS WITH NOTES | 0 | ✅ |
| 2 | Plan Parser & Status Reporter | PASS WITH NOTES | 0 | ✅ |
| 3 | Linear Issue Tracking | **FAIL** | 1 | ✅ |
| 4 | Forced Failure & Verification Gate | PASS WITH NOTES | 0 | ✅ |
| 5 | Slack Notification + Integration Test | **FAIL** | 1 | ✅ |

**5/5 tasks delivered. 57 tests. 7 commits. 2 FAILs caught and fixed within max iterations.**

### Multi-Agent Execution
- **Orchestrator** (claude-desktop): Greenlit tasks, enforced evidence chain, captured lessons
- **Builder** (claude-cli): One task per fresh-context session, committed with `feat(task-N)` convention
- **Verifier** (codex-cli): Independent audit — ran tests on separate machine, manual CLI checks
- **Consultant** (ChatGPT): Reviewed spec, added forced failure requirement (non-negotiable)

### What SPECTRA Proved

1. **Verification gates are non-optional.** 40% of tasks (2/5) shipped with passing unit tests but broken real-world execution. Without codex-cli gates, broken code would have shipped.

2. **FAIL → FIX → PASS is self-correcting.** Both failures were fixed in a single iteration. The process catches bugs AND forces them to be resolved before contaminating downstream work.

3. **Fresh context execution works.** The builder operated across 5 separate sessions with zero context rot. State in plan.md + git is sufficient.

4. **Forced failure testing validates the unhappy path.** Task 4 proved SPECTRA handles failure: validator fails → Linear blocked → Slack suppressed → file restored.

5. **Evidence chain enforcement kills status theater.** Every Linear update required commit hash + test command. No "in progress" without proof.

### Recurring Bug Class: "Unit Tests Green, Integration Wiring Missing"

The same bug pattern appeared twice:
- **Task 3**: PyYAML import crash + unhandled CLI exceptions. Class tests passed, CLI execution broken.
- **Task 5**: Integration test skipped Linear sync step. Pipeline not fully exercised despite test named "integration."

**Root cause**: Agents write class-level unit tests that prove logic in isolation but fail to test that components are wired together in the real execution path.

**Resolution**: Added Wiring Proof requirements to SPECTRA:
- Every task in plan.md includes a "Wiring proof" section
- PROMPT_build.md includes a mandatory Wiring Proof Checklist
- PROMPT_verify.md includes specific wiring checks
- guardrails.md captures Signs for the builder to check before committing

### Capability Gap: Agents Generalize Poorly

The builder learned "test CLI paths" from Task 3 and applied it to Task 4 — but the deeper principle ("test the wiring, not just the parts") didn't transfer to Task 5's integration test.

**Implication**: One correction cycle is insufficient for pattern elimination. SPECTRA now requires:
- Builder reflection after every FAIL (what slipped, why it repeated)
- Recurring patterns escalated to Signs in guardrails.md
- Verifier explicitly checks for previously-identified patterns

---

## 12. Signs (Learned Guardrails)

Signs are hard-won lessons from SPECTRA execution failures. They live in `.spectra/guardrails.md` and are checked by both the Builder (before committing) and the Verifier (during audit).

### SIGN-001: Integration tests must invoke what they import
> "Every integration test must invoke every pipeline step it imports — importing a module without calling it is dead code in a test."

### SIGN-002: CLI commands need subprocess-level tests
> "CLI commands must have subprocess-level tests that prove real execution, not just class-level unit tests."

### SIGN-003: Lessons must generalize, not just fix
> "If the spec says A → B → C → D and your test skips B, you've written a unit test with extra steps — not an integration test."

New Signs are discovered through FAIL→FIX cycles and added to guardrails.md per project. Cross-project Signs are stored in the neural knowledge graph for institutional memory.

---

## 13. Wiring Proof (Post Dry-Run Addition)

Every task in plan.md now includes a **Wiring Proof** section:

```markdown
- [ ] NNN: Task description
  - AC: Acceptance criteria
  - Files: Files to create/modify
  - Verify: `test command`
  - Max iterations: N
  - Wiring proof:
    - CLI: `command to run manually` (success + error paths)
    - Cross-module: ModuleA.method() called by ModuleB before ModuleC
    - Pipeline: step1 → step2 → step3 (ALL steps in integration test)
```

The Wiring Proof Checklist is enforced at three levels:
1. **Builder** (PROMPT_build.md): Must complete checklist before committing
2. **Verifier** (PROMPT_verify.md): Independently checks import-to-invocation, CLI boundary, pipeline completeness
3. **Script** (spectra-verify.sh): Automated dead-import detection + regression enforcement

---

## 14. Bash-Native Parallel Execution (v5.0)

SPECTRA v5.0 replaces the LLM-based coordinator (spectra-lead agent) with bash-native orchestration. Bash handles all bookkeeping — LLMs are workers that build, verify, classify, and review with <500 byte prompts.

### Why v5.0?

The v3.1 Agent Teams approach fed a 47KB prompt to an LLM "lead" agent that spent 200 Opus turns on TaskCreate, TaskUpdate, SendMessage — burning >60% of context on coordination. v5.0 moves all coordination to bash, where it costs zero tokens.

### Unified Execution Model

| Project Level | Execution Mode | Parallelism |
|---------------|---------------|-------------|
| Level 0-2 | **Sequential** (spectra-loop-v5.sh) | MAX_BATCH_SIZE forced to 1 |
| Level 3+ | **Parallel** (spectra-loop-v5.sh) | Up to MAX_BATCH_SIZE independent tasks via `&` + `wait` |

One script handles all levels. The `--sequential` flag forces batch size 1 for any level.

### v5.0 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│             SPECTRA v5.0 — Bash-Native Parallel               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  spectra-loop-v5.sh (full orchestrator)                      │
│    ├── parse_plan()     → bash arrays from plan.md           │
│    ├── next_batch()     → independent tasks (dep + SIGN-005) │
│    ├── build_prompt()   → <500 byte prompt per task          │
│    ├── preflight_prompt()→ Haiku auditor per task             │
│    ├── parallel_build() → & + wait for batch                 │
│    ├── verify_prompt()  → sequential verifier per task       │
│    ├── oracle_classify()→ 3-turn Haiku failure typing        │
│    ├── write_checkpoint()→ JSON state for resume             │
│    └── signal_complete()→ COMPLETE signal + final report     │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│  Agents (workers only — no coordination tools):              │
│  - spectra-builder:  Opus, acceptEdits, max 50 turns         │
│  - spectra-verifier: Opus, plan mode, no Edit/Write          │
│  - spectra-auditor:  Haiku, plan mode, 10 turns max          │
│  - spectra-oracle:   Haiku, plan mode, 3 turns max           │
│  - spectra-reviewer: Sonnet, plan mode, cross-model review   │
└─────────────────────────────────────────────────────────────┘
```

### Core Functions

**`parse_plan()`** — Reads plan.md into parallel bash arrays: TASK_IDS, TASK_TITLES, TASK_STATUS, TASK_RISKS, TASK_OWNS, TASK_TOUCHES, TASK_VERIFY, TASK_MAX_ITER, TASK_LINES, TASK_DEPS.

**`next_batch()`** — Returns independent tasks ready to execute. Checks: all deps complete, no file ownership conflicts (SIGN-005), respects MAX_BATCH_SIZE. Risk-first sorting (high risk before low).

**`build_prompt()`** — Generates <500 byte prompt per task. Agent reads full context from disk (CLAUDE.md, plan.md, guardrails.md).

**`parallel_build()`** — Launches batch of builders as background processes (`&`), then `wait`. Each builder writes its report to `.spectra/logs/task-NNN-build.md`.

**`oracle_classify()`** — On verification failure, spawns 3-turn Haiku agent that reads the verify report and returns exactly one classification word: test_failure, missing_dependency, wiring_gap, architecture_mismatch, ambiguous_spec, or external_blocker.

### Checkpoint & Resume

State is stored in `.spectra/signals/CHECKPOINT` as JSON:
```json
{
  "completed": ["001", "003"],
  "stuck": ["002"],
  "retry_counts": {"004": 2},
  "pass_history": {"002": ["test_failure", "wiring_gap"]},
  "elapsed_seconds": 1847,
  "branch": "spectra/my-project"
}
```

Resume is deterministic: read JSON → set arrays → continue from next incomplete task. Uses `jq` if available, falls back to `grep`.

**Compound failure detection:** If `pass_history` shows 2+ different failure types on the same task, the task is marked STUCK (the plan is wrong, not just the code).

**Diminishing budget:** Iteration 1 = 50 turns, iteration 2 = 35, iteration 3 = 25. Prevents infinite burn on fundamentally broken tasks.

### Key Signs

- **SIGN-005: File Ownership Conflict** — No two builders may edit the same file simultaneously. `next_batch()` enforces this.
- **SIGN-006: Verification Parallelism** — Verification is never parallel (Doctrine 5). Always sequential after parallel build.

### Execution Flow (All Levels)

```
spectra-loop-v5.sh
  1. parse_plan() → load all tasks into arrays
  2. restore_checkpoint() → resume from JSON if --resume
  3. WHILE incomplete tasks remain:
     a. next_batch() → get independent, unblocked tasks
     b. For each task in batch: preflight audit (parallel Haiku)
     c. parallel_build() → & + wait for all builders
     d. For each completed task (SERIAL):
        - verify_prompt() → spawn verifier
        - If PASS → mark [x], commit, checkpoint
        - If FAIL → oracle_classify() → increment retry
        - If compound failure → mark [!] STUCK
     e. write_checkpoint() → JSON state to disk
     f. refresh_claude_md() → update project context
  4. All tasks [x] → signal_complete()
  5. Write final report to .spectra/logs/
```
