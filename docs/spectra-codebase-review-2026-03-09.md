# SPECTRA Codebase Review

Date: 2026-03-09
Reviewer: codex-sp
Scope: full repository review of the current `~/.spectra` codebase before ECC integration planning

## Status Snapshot

- Repository style: shell-first framework with agent prompts, templates, fixtures, and CI around it
- Core runtime entrypoint: `bin/spectra-loop.sh`
- Current local test result: `bash tests/run-tests.sh` -> `288 passed, 0 failed`
- Working tree note: repo has untracked runtime/state directories (`.claude/`, `lessons/projects/`)

## What SPECTRA Actually Is

SPECTRA is a bash-native orchestration framework for AI-assisted development. The implementation is not a general SDK or daemon. It is a structured set of shell scripts, prompt files, templates, and tests that coordinate Claude subagents around a locked `plan.md` contract.

The codebase is organized into six practical layers:

1. Control plane: `bin/spectra-loop.sh` plus `lib/loop-*.sh`
2. Planning plane: `spectra-init.sh`, `spectra-assess.sh`, `spectra-plan.sh`, `spectra-plan-validate.sh`, `plan-extract.sh`
3. Verification plane: `spectra-verify.sh`, `spectra-verify-wiring.sh`, `hooks/pre-commit`, `lang-profiles/`
4. Agent policy plane: `agents/*.md`, `agents/references/*`, `SKILL.md`, autonomy and method docs
5. Memory plane: `lib/loop-lessons.sh` and `lessons/`
6. Assurance plane: `tests/`, `fixtures/`, `.github/workflows/spectra-ci.yml`, `shellcheck-baseline.json`

## Runtime Architecture

### 1. Project bootstrap

`bin/spectra-init.sh` scaffolds `.spectra/`, writes `project.yaml`, copies prompts/templates, sets up `verify.yaml`, propagates global Signs, and generates an initial `CLAUDE.md`.

Important detail: init is partly on older version labels. It writes `spectra_version: "5.1"` into `project.yaml`, but also writes `.spectra/VERSION` as `v5.4`.

### 2. Assessment and planning

`bin/spectra-assess.sh` is a deterministic rule engine, not an LLM planner. It maps track/risk/team/integration inputs to:

- SPECTRA level
- execution mode
- verification intensity
- wiring depth
- retry budget
- scope default

`bin/spectra-plan.sh` is the actual plan generator wrapper. It optionally runs discovery, assembles a very explicit planner prompt, invokes `spectra-planner`, validates the output, and then emits both:

- `.spectra/plan.md`
- `.spectra/plan.json` via `bin/plan-extract.sh`

`bin/spectra-plan-validate.sh` is the hard contract gate for plan shape. It enforces:

- canonical task headers and checkbox lines
- AC/Files/Verify
- Risk and Max-iterations at Level 1+
- Scope and Wiring-proof at Level 2+
- File-ownership and Parallelism Assessment at Level 3+
- SIGN-005 ownership overlap checks
- dependency cycle detection

### 3. Main execution loop

`bin/spectra-loop.sh` is the orchestrator. It sources modular helpers from `lib/` and owns:

- argument parsing
- project/env setup
- plan parsing into in-memory arrays
- branch setup
- optional planning/review phase
- batch selection through dependency and file-conflict rules
- auditor invocation
- parallel builder invocation
- sequential verifier invocation
- retry budget enforcement
- checkpoint save/restore
- NEGOTIATE and RECONCILE signal handling
- final review and COMPLETE/STUCK signaling

The loop is materially file-driven. It persists state into:

- `.spectra/plan.md`
- `.spectra/signals/*`
- `.spectra/logs/*`
- `.spectra/lessons-active.md`
- `~/.spectra/lessons/...`

That design matters for ECC work because it already has strong "state in files, not memory" alignment.

### 4. Modular helpers

The `lib/` modules are cleanly separated:

- `loop-build.sh`: prompt assembly, retry budgets, parallel builder spawning, timeout/infra failure signaling
- `loop-checkpoint.sh`: checkpoint JSON, restore logic, plan checksum lock
- `loop-git.sh`: branch setup, task commits, pre-commit hook install
- `loop-retry.sh`: failure-type retry budgets, pass history, Sign propagation
- `loop-signals.sh`: phase/status/final report/STUCK/COMPLETE writes
- `loop-verify.sh`: verifier prompt + oracle classifier wrapper
- `loop-wiring.sh`: post-verify wiring gate wrapper
- `loop-lessons.sh`: continuous learning store, sanitization, promotion lifecycle, active lesson injection, brownfield upgrade
- `loop-stuck-recovery.sh`: party-mode STUCK classification and recovery-plan generation

## Verification and Policy Model

### Wiring proof

There are two related systems:

- `bin/spectra-verify.sh`: standalone 4-step verifier script
- `bin/spectra-verify-wiring.sh`: specialized wiring checker driven by `.spectra/verify.yaml`

The wiring verifier is more concrete than the high-level verifier. It checks:

- dead code from missing callsites
- framework anti-patterns from YAML rules
- write abstraction guards
- constant/assertion presence from plan assertions

It is also git-scope aware, which keeps checks focused on changed files when possible.

### Agent contracts

The agent markdown files are effectively policy specs. They define:

- tool allowlists
- memory scope
- max turn budgets
- trigger/exclusion rules
- role-specific output contracts

The architecture depends on these contracts being true. The loop assumes:

- planner/reviewer/verifier are read-only
- builder has edit authority
- auditor/oracle are advisory

### Lessons and institutional memory

`lib/loop-lessons.sh` is one of the most mature subsystems in the repo. It provides:

- append-only JSONL lesson storage with `flock`
- normalized fingerprints
- sanitization and prompt-injection guards
- recurrence-based promotion
- adaptive TTL
- snapshot compaction
- live `lessons-active.md` injection
- brownfield upgrade for pre-v5.4 projects

This is the clearest existing anchor for ECC-style continuous learning.

## Test and CI Posture

The repository has strong shell-level assurance for its size:

- `tests/run-tests.sh` aggregates 15 suites
- current total is 288 passing tests
- CI has separate `lint`, `tests`, and `wiring` jobs
- ShellCheck is pinned and ratcheted with per-file/per-rule baseline
- module anti-drift is explicitly checked in CI

The tested areas are strongest around:

- plan validation and extraction
- loop module boundaries and behavior
- wiring enforcement
- lessons lifecycle
- STUCK recovery
- agent frontmatter/routing

Fixtures are also well structured:

- `fixtures/plan-bridge/`: valid and invalid `plan.md` shapes
- `fixtures/assessment/`: assessment outputs
- `fixtures/bmad-bridge/`: BMAD input/output/error cases
- `fixtures/ci-wiring-pass` and `fixtures/ci-wiring-fail`: wiring proof fixtures

## High-Value Findings

### 1. Planning phase inside `spectra-loop.sh` is not truly wired

The loop invokes `spectra-planner` in `plan` mode and tells it to "Write to .spectra/ directory", but:

- the planner agent has no `Edit` or `Write` tools
- the loop only tees planner stdout to `planning.log`
- there is no file-routing logic in the loop equivalent to what `spectra-plan.sh` does

Implication: the standalone planning path in `spectra-loop.sh` is weaker than the dedicated `spectra-plan.sh` path and may not actually materialize planning artifacts reliably.

### 2. Formal plan review is treated as optional in code

The autonomy contract says plan review is mandatory before execution, but the loop currently proceeds if `plan-review.md` is missing.

Implication: a failed or empty reviewer run does not hard-stop execution, which weakens the contract.

### 3. README claims automatic preflight integration that the loop does not implement

`README.md` says `spectra-loop` automatically calls `spectra-preflight`, but there is no invocation in `bin/spectra-loop.sh`.

Implication: token validation exists as a script, but not as an enforced runtime gate.

### 4. RECONCILE behavior is documented differently from the implementation

README says non-interactive RECONCILE "logs a warning and continues". The loop actually deletes the signal and exits non-zero in non-interactive mode.

Implication: operator expectations from the docs do not match actual automation behavior.

### 5. Forced-failure tasks are policy, not enforcement

Planner and reviewer instructions require a forced-failure task for Level 2+, but `spectra-plan-validate.sh` does not enforce that requirement.

Implication: part of the methodology still lives only in prompts/docs, not runtime validation.

### 6. Version labeling is inconsistent

The codebase presents itself simultaneously as:

- v5.0 for the loop runtime
- v5.1 for init/plan/verify tooling
- v5.4 for project VERSION markers and agent metadata
- v5.4.1 in top-level docs

Implication: future integration work should avoid adding more version-dependent branching until this is normalized.

### 7. Standalone verifier regression detection is Python-biased

`bin/spectra-verify.sh` selects `python -m pytest -q` if a `tests/` directory exists, even if the repo is not Python.

Implication: standalone verification is less language-aware than the docs suggest and can misclassify non-Python repos.

### 8. Coverage is strong for the loop, weaker for utility scripts

There is little or no direct test coverage for:

- `bin/spectra-status.sh`
- `bin/spectra-preflight.sh`
- `bin/spectra-quick.sh`
- `install.sh`
- `spectra-init.sh` end-to-end behavior
- full planning artifact generation path inside `spectra-loop.sh`

Implication: the core loop is the safest extension target; utility/operational surfaces need more caution.

## ECC-Relevant Extension Points

These are the places most likely to support ECC-inspired enhancements cleanly:

### Continuous learning / Sign auto-discovery

- `lib/loop-lessons.sh`
- failure path in `bin/spectra-loop.sh`
- `.spectra/logs/task-*-fail.md`
- `.spectra/logs/task-*-verify.md`
- `.spectra/lessons-active.md`
- `.spectra/guardrails.md`

This subsystem already has promotion, sanitization, and project/global separation. It is the best insertion point for post-verify pattern extraction.

### Pre-commit / post-edit quality gates

- builder agent `PostToolUse` hook
- `hooks/pre-commit`
- `bin/spectra-verify-wiring.sh`
- optional `.spectra/scripts/lint-check.sh` hook path already referenced in builder frontmatter

This gives a natural place for Plankton-style lint/auto-fix layers without disturbing verifier isolation.

### Iterative retrieval / context minimization

- `lib/loop-build.sh` prompt budget logic
- generated `CLAUDE.md`
- task-local sections in `plan.md`
- `agents/references/`
- `lessons-active.md`

The current design already assumes short prompts plus disk reads. That makes progressive disclosure a good additive fit.

### Runtime profiles and depth controls

- `assessment.yaml` tuning
- `project.yaml`
- `verify.yaml`
- `lang-profiles/`
- `verify_depth` handling in `bin/spectra-loop.sh`

This is where an ECC-style verify-depth or language-aware quality profile system would naturally land.

## Bottom Line

SPECTRA is strongest where it is most concrete:

- bash orchestration
- file-based execution contracts
- modular loop helpers
- plan schema validation
- lessons storage and propagation
- shell-based assurance

It is weaker where the methodology relies on prompts or docs without an enforcing script:

- planner artifact persistence inside the loop
- mandatory review guarantees
- forced-failure task enforcement
- preflight integration
- cross-language verification maturity

Conclusion: the repo is ready for ECC integration planning, but the first planning pass should treat the loop, lessons system, hooks, and wiring verifier as the stable extension surface. Planning/docs drift should be addressed explicitly in that plan rather than assumed away.
