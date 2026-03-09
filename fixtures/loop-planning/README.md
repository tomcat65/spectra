# Loop Planning Fixtures

Test fixtures for Tasks 001-004 of the SPECTRA framework-origin dogfood plan.
These support scaffolding for planning persistence, reviewer gate, preflight/RECONCILE,
and init drift test suites.

## Fixture Cases

### Plan Artifacts
- `happy-path-plan.md` — Valid Level 3 plan with all required fields (ownership, wiring, AC)
- `malformed-planner-output.md` — Planner output missing required structure (no checkbox lines, no AC)
- `validation-fail-plan.md` — Plan with structural defects that spectra-plan-validate.sh should reject

### Reviewer Artifacts
- `review-approved.md` — Reviewer verdict: APPROVED
- `review-approved-warnings.md` — Reviewer verdict: APPROVED_WITH_WARNINGS (with warning lines)
- `review-rejected.md` — Reviewer verdict: REJECTED (with rejection reason)

### Signal Artifacts
- `reconcile-signal.txt` — Sample RECONCILE signal content (assessment drift scenario)

## Usage

Tests use these fixtures read-only. Runtime state is created in temp directories via mktemp.
No fixture file should be mutated by any test.
