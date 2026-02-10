# Plan-Bridge Acceptance Fixtures (Draft)

**Status:** Draft for architect review  
**Scope:** Design fixtures only (no runtime changes)

## 1. Fixture Goal
Define pass/fail acceptance fixtures for `spectra-assess` + `spectra-plan --from-bmad` bridge behavior against the contract in `proposals/bmad-output-schema.md`.

## 2. Proposed Fixture Layout
```
fixtures/plan-bridge/
  001-assess-full-context-pass.input.json
  001-assess-full-context-pass.expected.json
  002-task-required-fields-pass.input.json
  002-task-required-fields-pass.expected.md
  003-scope-conflict-fail.input.json
  003-scope-conflict-fail.expected.json
  004-phase45-correction-pass.input.json
  004-phase45-correction-pass.expected.json
  005-missing-acceptance-fail.input.json
  005-missing-acceptance-fail.expected.json
  006-multi-repo-scope-pass.input.json
  006-multi-repo-scope-pass.expected.md
```

## 3. Fixture Definitions

### F-001: Full Assessment Passthrough (PASS)
Purpose: verify adapter passes complete BMAD assessment context.

Given:
- BMAD assessment includes language/framework/domain/risk/non-functional drivers.

Expected:
- Bridge output embeds `assessment_context.bmad.full_context` unchanged.
- Missing any key -> FAIL.

### F-002: Required Task Fields (PASS)
Purpose: enforce canonical fields from architect directive.

Given:
- One story with complete acceptance + dependency info.

Expected generated task includes:
- `Status`
- `Level`
- `Acceptance`
- `Wiring`
- `Max-iterations`
- `scope`
- `Verify`

Expected markdown contains corresponding labels:
- `Status:`
- `Level:`
- `Acceptance:`
- `Wiring:`
- `Max-iterations:`
- `Scope:`

### F-003: Scope Conflict Detection (FAIL)
Purpose: validate SIGN-005 generalized to scope-level.

Given:
- Task 001 and Task 002 both runnable in parallel.
- Overlap in `scope.config_paths` (`infra/terraform/main.tf`).

Expected:
- Bridge emits validation error:
  - `code`: `SCOPE_CONFLICT`
  - `tasks`: `["001","002"]`
  - `dimension`: `config_paths`
- Plan generation must fail (no partial output promoted).

### F-004: Phase 4.5 Planning Correction (PASS)
Purpose: verify structured feedback object from execution learnings.

Given:
- Verifier reports `wiring_gap` with concrete failing command and report path.

Expected correction object includes:
- `correction_id`, `task_id`, `target_artifact`, `target_ref`
- `evidence.verify_report`
- `evidence.failed_command`
- `proposed_correction`
- `impact.requires_replan`
- `approval_state`

### F-005: Missing Acceptance (FAIL)
Purpose: enforce non-empty `Acceptance`.

Given:
- Story without actionable acceptance criteria.

Expected:
- Bridge rejects with:
  - `code`: `MISSING_REQUIRED_FIELD`
  - `field`: `Acceptance`
  - `task_id`: `<id>`

### F-006: Multi-Repo Scope (PASS)
Purpose: ensure scope model supports multi-repo plans.

Given:
- Task 001 targets repo `main`.
- Task 002 targets repo `infra`.
- No overlapping scope dimensions.

Expected:
- Parallelism recommendation can remain `TEAM_ELIGIBLE`.
- Output preserves repo-specific scope declarations.

## 4. Failure Payload Standard
All fixture failures should normalize to:
```json
{
  "status": "error",
  "code": "SCOPE_CONFLICT",
  "message": "Task scopes overlap without dependency ordering",
  "details": {
    "tasks": ["001", "002"],
    "dimension": "config_paths",
    "intersection": ["infra/terraform/main.tf"]
  }
}
```

## 5. Acceptance Criteria for Fixture Pack
1. Every PASS fixture has deterministic expected output.
2. Every FAIL fixture has deterministic normalized error payload.
3. At least one fixture covers each architect-mandated improvement:
- scope field generalization
- full assessment passthrough
- phase 4.5 feedback loop
4. Fixtures are tool-agnostic (usable by bash, node, or python harness later).

## 6. Suggested Next Execution Step (Post-Approval)
After architect approval, implement a small harness that:
1. Loads fixture input.
2. Runs adapter/bridge.
3. Compares normalized output or error against expected artifact.
4. Fails CI on any drift.

