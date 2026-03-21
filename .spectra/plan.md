# SPECTRA Execution Plan

## Project: SPECTRA Framework Origin
## Level: 3
## Generated: 2026-03-09
## Source: dogfood review + ECC integration plan

---

## Task 001: Repair in-loop planning persistence
- [x] 001: Repair in-loop planning persistence
- AC:
  - `spectra-loop.sh --plan-only` no longer depends on a read-only planner magically writing `.spectra/plan.md`.
  - The planning path produces a validated `.spectra/plan.md` and fresh `.spectra/plan.json`, or fails loudly with preserved artifacts for review.
  - Planner prompt and runtime ownership of file writes are consistent with actual agent capabilities.
- Files: bin/spectra-loop.sh, bin/spectra-plan.sh, agents/spectra-planner.md, tests/test-loop-planning.sh, fixtures/loop-planning/README.md
- Verify: `bash tests/test-loop-planning.sh && bash tests/test-plan-extract.sh`
- Risk: high
- Max-iterations: 10
- Scope: code
- File-ownership:
  - owns: [tests/test-loop-planning.sh, fixtures/loop-planning/README.md]
  - touches: [bin/spectra-loop.sh, bin/spectra-plan.sh, agents/spectra-planner.md]
  - reads: [bin/spectra-plan-validate.sh, bin/plan-extract.sh, templates/plan-schema.json, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-loop-planning.sh
  - Integration: loop planning delegates to the real plan writer, validator gates malformed output, and plan.json freshness tracks the resulting plan.md.

## Task 002: Enforce reviewer gate on planned execution
- [x] 002: Enforce reviewer gate on planned execution
- AC:
  - When planning runs, missing `plan-review.md` is treated as a blocking condition rather than a silent pass.
  - Rejected plans get one bounded revision attempt, then execution stops with a clear operator-visible reason.
  - Reviewer instructions, verdict parsing, and runtime behavior all agree on the artifact path and accepted verdict values.
- Files: bin/spectra-loop.sh, agents/spectra-reviewer.md, README.md, tests/test-plan-review-gate.sh
- Verify: `bash tests/test-plan-review-gate.sh`
- Risk: high
- Max-iterations: 8
- Scope: code
- File-ownership:
  - owns: [tests/test-plan-review-gate.sh]
  - touches: [bin/spectra-loop.sh, agents/spectra-reviewer.md, README.md]
  - reads: [lib/loop-signals.sh, docs/spectra-codebase-review-2026-03-09.md, .spectra/constitution.md]
- Wiring-proof:
  - CLI: bash tests/test-plan-review-gate.sh
  - Integration: reviewer verdict file gates the loop and rejected plans cannot advance into execution without a valid approval outcome.

## Task 003: Align preflight and RECONCILE behavior with documentation
- [x] 003: Align preflight and RECONCILE behavior with documentation
- AC:
  - Loop startup either runs `spectra-preflight.sh` as documented or the docs are corrected to mark preflight manual.
  - RECONCILE behavior is identical in docs and code for interactive and non-interactive flows.
  - The final operator-facing output gives exact next steps when preflight or RECONCILE blocks progress.
- Files: bin/spectra-loop.sh, bin/spectra-preflight.sh, README.md, tests/test-preflight-reconcile.sh
- Verify: `bash tests/test-preflight-reconcile.sh`
- Risk: high
- Max-iterations: 8
- Scope: code
- File-ownership:
  - owns: [tests/test-preflight-reconcile.sh]
  - touches: [bin/spectra-loop.sh, bin/spectra-preflight.sh, README.md]
  - reads: [bin/spectra-plan.sh, bin/spectra-assess.sh, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-preflight-reconcile.sh
  - Integration: loop startup, assessment drift signaling, and operator docs all describe the same control-flow decisions.

## Task 004: Remove prompt, template, and version drift
- [x] 004: Remove prompt, template, and version drift
- AC:
  - Prompt files, scaffolded templates, and runtime prompts have one explicit source of truth.
  - `spectra-init.sh`, version markers, and visible help text stop emitting conflicting v5.0, v5.1, v5.4, and v5.4.1 labels.
  - Any legacy scaffolds that remain are explicitly labeled legacy instead of looking current.
- Files: bin/spectra-init.sh, README.md, templates/.spectra/PROMPT_build.md, templates/.spectra/PROMPT_verify.md, templates/.spectra/PROMPT_split.md, templates/.spectra/tasks.md.tmpl, tests/test-init-drift.sh
- Verify: `bash tests/test-init-drift.sh`
- Risk: medium
- Max-iterations: 6
- Scope: code
- File-ownership:
  - owns: [tests/test-init-drift.sh]
  - touches: [bin/spectra-init.sh, README.md, templates/.spectra/PROMPT_build.md, templates/.spectra/PROMPT_verify.md, templates/.spectra/PROMPT_split.md, templates/.spectra/tasks.md.tmpl]
  - reads: [templates/.spectra/plan.md.tmpl, SPECTRA_COMPLETE.md, SPECTRA_METHOD.md]
- Wiring-proof:
  - CLI: bash tests/test-init-drift.sh
  - Integration: init-generated artifacts, runtime prompts, and documentation expose the same versioned framework behavior.

## Task 005: Make verifier command selection language-aware
- [x] 005: Make verifier command selection language-aware
- AC:
  - A `tests/` directory alone no longer forces Python or `pytest` regression commands.
  - Regression command selection uses language profiles or repository signals with deterministic fallback behavior.
  - JS or TS and other non-Python fixture coverage exists to prove the selection logic is no longer Python-biased.
- Files: bin/spectra-verify.sh, lang-profiles/python.profile, tests/test-verify-command-detection.sh, fixtures/verify-command/README.md
- Verify: `bash tests/test-verify-command-detection.sh && bash tests/test-phase-d-langprofile.sh`
- Risk: medium
- Max-iterations: 6
- Scope: code
- File-ownership:
  - owns: [tests/test-verify-command-detection.sh, fixtures/verify-command/README.md]
  - touches: [bin/spectra-verify.sh, lang-profiles/python.profile]
  - reads: [bin/spectra-verify-wiring.sh, tests/test-phase-d-langprofile.sh, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-verify-command-detection.sh
  - Integration: verifier chooses repo-appropriate regression commands and still hands off correctly to wiring verification.

## Task 006: Expand direct operational coverage and fixture execution
- [x] 006: Expand direct operational coverage and fixture execution
- AC:
  - `spectra-assess.sh`, `spectra-status.sh`, `spectra-quick.sh`, and init end-to-end behavior each have direct regression coverage.
  - BMAD bridge and plan bridge fixtures are executed by tests rather than serving only as documentation.
  - The repo can demonstrate coverage for the framework control plane without relying on hand inspection.
- Files: tests/test-assess.sh, tests/test-status.sh, tests/test-quick.sh, tests/test-init-e2e.sh, tests/run-tests.sh, README.md
- Verify: `bash tests/run-tests.sh`
- Risk: medium
- Max-iterations: 6
- Scope: code
- File-ownership:
  - owns: [tests/test-status.sh, tests/test-quick.sh, tests/test-init-e2e.sh]
  - touches: [tests/test-assess.sh, tests/run-tests.sh, README.md]
  - reads: [fixtures/assessment/manifest.json, fixtures/bmad-bridge/manifest.json, fixtures/plan-bridge/manifest.json]
- Wiring-proof:
  - CLI: bash tests/run-tests.sh
  - Integration: framework smoke paths, fixture suites, and top-level test runner all exercise the intended control-plane surfaces.

## Task 007: Add progressive context loading with explicit fallback
- [x] 007: Add progressive context loading with explicit fallback
- AC:
  - Builder and verifier start with task-local context and load broader context only when signals require it.
  - Full-context fallback remains available and deterministic for complex or ambiguous tasks.
  - Context loading logic is centralized instead of duplicated across build and verify flows.
- Files: lib/loop-context.sh, lib/loop-build.sh, lib/loop-verify.sh, agents/spectra-builder.md, agents/spectra-verifier.md, tests/test-phase11-context-loading.sh
- Verify: `bash tests/test-phase11-context-loading.sh`
- Risk: medium
- Max-iterations: 8
- Scope: code
- File-ownership:
  - owns: [lib/loop-context.sh, tests/test-phase11-context-loading.sh]
  - touches: [lib/loop-build.sh, lib/loop-verify.sh, agents/spectra-builder.md, agents/spectra-verifier.md]
  - reads: [agents/references/wiring-checklist.md, agents/references/failure-types.md, .spectra/plan.md]
- Wiring-proof:
  - CLI: bash tests/test-phase11-context-loading.sh
  - Integration: build and verify both read through the same context policy, and fallback expands context without bypassing task-local defaults.

## Task 008: Add opt-in Sign candidate discovery after failure recovery
- [x] 008: Add opt-in Sign candidate discovery after failure recovery
- AC:
  - After FAIL to FIX to PASS cycles, a file-backed hook or script can propose new Sign candidates without mutating guardrails automatically.
  - Proposed Sign candidates include enough context to audit why the pattern was suggested.
  - The feature is disabled by default and safe to ignore in existing project flows.
- Files: hooks/post-verify-learn.sh, lib/loop-lessons.sh, README.md, tests/test-phase11-sign-candidates.sh
- Verify: `bash tests/test-phase11-sign-candidates.sh`
- Risk: medium
- Max-iterations: 6
- Scope: code
- File-ownership:
  - owns: [hooks/post-verify-learn.sh, tests/test-phase11-sign-candidates.sh]
  - touches: [lib/loop-lessons.sh, README.md]
  - reads: [agents/references/signs-taxonomy.md, agents/references/failure-types.md, lessons/projects/project/lessons.jsonl]
- Wiring-proof:
  - CLI: bash tests/test-phase11-sign-candidates.sh
  - Integration: verify and lessons artifacts feed candidate generation, but guardrails only change through explicit human review.

## Task 009: Add language-aware quality gates ahead of verifier
- [x] 009: Add language-aware quality gates ahead of verifier
- AC:
  - Builder-side quality gates can run cheap lint or format checks before expensive verifier passes.
  - Auto-fixes are limited to deterministic safe operations and do not bypass verifier authority.
  - Quality gate behavior is aware of repo language signals rather than assuming a Python-only workflow.
- Files: scripts/spectra-quality-gate.sh, hooks/pre-commit, agents/scripts/builder-self-audit.sh, README.md, tests/test-phase11-quality-gate.sh
- Verify: `bash tests/test-phase11-quality-gate.sh`
- Risk: medium
- Max-iterations: 6
- Scope: code
- File-ownership:
  - owns: [scripts/spectra-quality-gate.sh, tests/test-phase11-quality-gate.sh]
  - touches: [hooks/pre-commit, agents/scripts/builder-self-audit.sh, README.md]
  - reads: [lang-profiles/python.profile, bin/spectra-verify-wiring.sh, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-phase11-quality-gate.sh
  - Integration: builder self-audit, pre-commit hook, and quality gate script agree on language selection and never suppress verifier execution.

## Task 010: Add runtime profiles and orchestrator-only session persistence
- [x] 010: Add runtime profiles and orchestrator-only session persistence
- AC:
  - Runtime depth profiles are explicit, environment-driven, and reversible.
  - Any persistence is limited to orchestrator or lead state; builder and verifier remain fresh-context by design.
  - Resume behavior does not leak stale execution context across tasks.
- Files: lib/loop-session.sh, bin/spectra-loop.sh, lib/loop-build.sh, lib/loop-verify.sh, README.md, tests/test-phase11-runtime-profiles.sh
- Verify: `bash tests/test-phase11-runtime-profiles.sh`
- Risk: medium
- Max-iterations: 8
- Scope: code
- File-ownership:
  - owns: [lib/loop-session.sh, tests/test-phase11-runtime-profiles.sh]
  - touches: [bin/spectra-loop.sh, lib/loop-build.sh, lib/loop-verify.sh, README.md]
  - reads: [bin/spectra-status.sh, .spectra/project.yaml, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-phase11-runtime-profiles.sh
  - Integration: loop profile selection, status reporting, and session persistence boundaries remain aligned with fresh-context doctrine.

## Task 011: Add optional post-project cleanup command
- [x] 011: Add optional post-project cleanup command
- AC:
  - Cleanup lives outside the core execution loop and defaults to dry-run behavior.
  - The command can identify dead scaffolds, stale fixtures, and cleanup candidates without mutating operator-owned artifacts unexpectedly.
  - Documentation makes it clear this is an end-of-project hygiene tool, not a required execution phase.
- Files: bin/spectra-refactor-clean.sh, README.md, tests/test-refactor-clean.sh
- Verify: `bash tests/test-refactor-clean.sh`
- Risk: low
- Max-iterations: 5
- Scope: code
- File-ownership:
  - owns: [bin/spectra-refactor-clean.sh, tests/test-refactor-clean.sh]
  - touches: [README.md]
  - reads: [SPECTRA_COMPLETE.md, docs/ci-break-glass.md, docs/spectra-codebase-review-2026-03-09.md]
- Wiring-proof:
  - CLI: bash tests/test-refactor-clean.sh
  - Integration: cleanup inspects framework artifacts and reports actionable results without becoming part of the main loop path.

---

## Parallelism Assessment
- Independent tasks: [none]
- Sequential dependencies: [001 -> 002, 002 -> 003, 003 -> 004, 004 -> 005, 005 -> 006, 006 -> 007, 007 -> 008, 007 -> 009, 009 -> 010, 010 -> 011]
- Recommendation: SEQUENTIAL_ONLY
