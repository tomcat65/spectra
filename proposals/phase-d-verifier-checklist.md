# Phase D Verifier Checklist: `spectra-plan --from-bmad`

Status: Draft ready for execution  
Owner lane: codex (verifier)  
Date: 2026-02-10

## 1. Purpose
Define acceptance gates for the BMAD bridge in Phase D. The bridge passes if BMAD artifacts can be transformed into canonical `plan.md` that validates under the approved Phase A schema and rule set.

## 2. References
1. `proposals/bmad-output-schema.md`
2. `proposals/phase-c-verifier-checklist.md`
3. `bin/spectra-plan.sh`
4. `bin/spectra-plan-validate.sh`
5. `fixtures/bmad-bridge/` (golden + malformed fixtures to be added)

## 3. Gate Outcome Rules
1. PASS: all critical checks pass and no runtime/parser crash occurs.
2. FAIL: any critical check fails, output plan is invalid, or contract fields are missing.
3. WARN only: non-contract wording/format differences that still validate and preserve semantics.

## 4. Critical Verification Areas

### 4.1 Canonical plan output validity
Critical checks:
1. `--from-bmad` generates `.spectra/plan.md` in canonical schema format.
2. Generated plan passes `bin/spectra-plan-validate.sh`.
3. Task IDs, checkbox state, AC format, and key names conform to Phase A schema.

### 4.2 Level-conditional field population
Critical checks:
1. Level is read from `.spectra/assessment.yaml` unless overridden.
2. If `.spectra/assessment.yaml` is missing, bridge emits a warning and defaults to Level 2.
3. Generated fields match level requirements:
   - Level 0: minimal required fields only.
   - Level 2+: includes Wiring proof.
   - Level 3+: includes File-ownership and Parallelism Assessment.
4. No required field for the effective level is omitted.

### 4.3 Graceful degradation by BMAD artifact availability
Critical checks:
1. Missing Stories: hard FAIL (non-zero exit, actionable error).
2. Missing PRD: soft degradation (warn), still produce valid plan if Stories + minimum context are present.
3. Missing Architecture: soft degradation (warn), still produce valid plan for Levels <3; Level 3+ behavior must be explicit and deterministic.
4. Story-to-task ratio supports `1:N`; at least one complex story can be split into 2+ plan tasks.

### 4.4 `--dry-run` behavior
Critical checks:
1. `--dry-run` prints generated plan to stdout.
2. `--dry-run` does not write or modify `.spectra/plan.md`.
3. Exit code reflects generation success/failure.

### 4.5 Fuzzy parsing robustness
Critical checks:
1. Two PRD format variants for the same project both parse successfully.
2. Both variants generate valid plan output passing validator.
3. Core semantics (task intent and acceptance criteria coverage) remain consistent.

### 4.6 Parallelism Assessment generation (Level 3+)
Critical checks:
1. Level 3+ plans include a `Parallelism Assessment` section.
2. Dependencies and parallel groups are internally consistent with generated tasks.
3. Validator accepts generated dependency declarations.

### 4.7 File-ownership derivation + SIGN-005 compatibility
Critical checks:
1. `owns:` claims derived from architecture are conflict-free across tasks.
2. For vague architecture with no ownership signals, bridge applies best-effort behavior deterministically (for example empty ownership lists plus warning) without crashing.
3. `touches:` overlaps require explicit dependency or produce expected WARN behavior.
4. `reads:` overlaps do not create false conflicts.
5. Final plan behavior matches `spectra-plan-validate.sh` SIGN-005 rules.

## 5. Test Matrix (minimum gate set)
1. D1 Canonical happy path: full BMAD set (PRD+Architecture+Stories) -> valid plan + validator PASS.
2. D2 Level 0 population: assessment level 0 -> minimal schema only, validator PASS.
3. D3 Level 3 population: assessment level 3 -> includes Wiring, File-ownership, Parallelism, validator PASS.
4. D4 Missing Stories: bridge FAILs with non-zero and clear error.
5. D5 Missing PRD: bridge succeeds with warning and validator PASS.
6. D6 Missing Architecture: deterministic behavior per level contract; no crash.
7. D7 Dry run: stdout output present, no file write.
8. D8 Fuzzy PRD format A: valid plan + validator PASS.
9. D9 Fuzzy PRD format B: valid plan + validator PASS.
10. D10 Ownership stress case: overlapping ownership patterns produce expected FAIL/WARN/PASS under SIGN-005.
11. D11 No assessment path: warning emitted and Level 2 defaults applied.
12. D12 Story split path: one story maps to 2+ generated tasks.

## 6. Required Evidence for Sign-off
1. Command transcript for each D1-D10 check.
2. Generated plan snapshots (or diffs) for success cases.
3. Validator output per case (exit code + key findings).
4. Summary matrix with expected vs actual.

## 7. Report Template
Use this when reporting Phase D gate results:

```text
Phase D Verification Report (spectra-plan --from-bmad)
Commit: <sha>

1) Canonical plan validity: PASS/FAIL
2) Level-conditional population: PASS/FAIL
3) Graceful degradation behavior: PASS/FAIL
4) Dry-run behavior: PASS/FAIL
5) Fuzzy parsing robustness: PASS/FAIL
6) Parallelism Assessment (L3+): PASS/FAIL
7) Ownership/SIGN-005 alignment: PASS/FAIL

Fixture matrix:
- D1 ... D10 with expected vs actual

Blockers:
- <none or list>

Gate Result: PASS/FAIL
```
