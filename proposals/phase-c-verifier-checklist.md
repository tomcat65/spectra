# Phase C Verifier Checklist: `spectra-assess`

Status: Draft ready for execution  
Owner lane: codex (verifier)  
Date: 2026-02-10

## 1. Purpose
Define the acceptance gate for Phase C (`spectra-assess`) so builder output can be verified deterministically before merge.

## 2. References
1. `proposals/bmad-output-schema.md`
2. `fixtures/assessment/manifest.json`
3. `fixtures/assessment/assessment-level0-quickflow.yaml`
4. `fixtures/assessment/assessment-level3-bmad-method.yaml`
5. `fixtures/assessment/assessment-level4-enterprise.yaml`
6. `fixtures/assessment/assessment-manual-no-bmad.yaml`
7. `fixtures/assessment/assessment-malformed-missing-level.yaml`

## 3. Gate Outcome Rules
1. PASS: all critical checks pass, no parser/runtime crashes, expected file outputs present.
2. FAIL: any critical check fails, any crash occurs, or schema output diverges from contract.
3. WARN only: cosmetic output differences, wording differences in non-contract text, optional warning text differences.

## 4. Required Paths To Verify

### 4.1 BMAD-present path
Critical checks:
1. `spectra-assess` detects BMAD presence (`source.mode = bmad-detected` for Phase C).
2. Writes `.spectra/assessment.yaml` with required keys:
   - `version`, `generated_at`, `source`, `bmad`, `spectra`, `tuning`
3. Track -> level mapping follows contract decision tree.
4. Tuning fields are derived and typed correctly:
   - `verification_intensity`
   - `wiring_depth`
   - `retry_budget`
5. Unknown BMAD keys are preserved in passthrough location if implemented (`workflow_init.raw` or equivalent).

Suggested test cases:
1. BMAD reports `quick_flow` low-risk context -> expect Level 0.
2. BMAD reports `bmad_method` with complexity triggers -> expect Level 3.
3. BMAD reports `enterprise` -> expect Level 4.

### 4.2 Interactive fallback path (BMAD missing)
Critical checks:
1. If BMAD is unavailable, interactive prompt sequence runs.
2. Generated output uses:
   - `source.mode = manual`
   - `source.producer = interactive-fallback`
3. Mapping/tuning still follow same rules as BMAD path.
4. Warning is emitted in `assessment.yaml` indicating manual fallback mode.

Suggested test cases:
1. Fallback inputs mapping to Level 1.
2. Empty inputs use documented defaults.

### 4.3 `--non-interactive` CI path
Critical checks:
1. Command returns promptly without interactive prompt wait.
2. Missing required CLI inputs produce non-zero exit and clear error.
3. Defaulted fields are populated deterministically.
4. Output contract remains identical in shape to interactive/BMAD modes.

Suggested test cases:
1. `--non-interactive --track quick_flow` succeeds with defaults.
2. `--non-interactive` without required selector fails cleanly.

### 4.4 `--level N` override behavior
Critical checks:
1. Explicit `spectra-init --level N` wins over assessment-derived level.
2. Without explicit level override, `spectra-init` can adopt assessed level.
3. `project.yaml` and `assessment.yaml` stay separate files.
4. Linkage fields (if implemented) are consistent:
   - `assessment_ref`
   - `effective_level`
   - `effective_verification_intensity`

Suggested test cases:
1. Assessment level=3 + init `--level 1` -> project level remains 1.
2. Assessment level=3 + init default level -> project level becomes 3.

## 5. Fixture Validation Requirements
All fixtures in `fixtures/assessment/manifest.json` must be validated against implementation behavior.

### 5.1 Positive fixtures (must pass)
1. `assessment-level0-quickflow.yaml`
2. `assessment-level3-bmad-method.yaml`
3. `assessment-level4-enterprise.yaml`
4. `assessment-manual-no-bmad.yaml`

Required for each positive fixture:
1. Required keys present and typed.
2. Enumerations valid (`track`, `level`, `verification_intensity`, `wiring_depth`).
3. Expected values match manifest checks.

### 5.2 Negative fixture (must fail)
1. `assessment-malformed-missing-level.yaml`

Required behavior:
1. Non-zero validation result.
2. Error indicates missing `spectra.level`.
3. No crash, panic, or ambiguous parse error.

## 6. Edge Cases (Must Be Tested)
1. BMAD command exists but returns malformed payload.
2. BMAD payload missing required top-level fields (`track`, `rationale`, `context`).
3. Invalid numeric fields (`team_size < 1`, `integration_count < 0`).
4. Unknown track value.
5. Existing `.spectra/assessment.yaml` handling on re-run (overwrite behavior is explicit and deterministic).
6. Non-interactive fallback mode where BMAD is absent (must not hang).
7. Paths with spaces in project directory (file writes and reads still succeed).

## 7. Evidence Required For Sign-off
1. Command transcript for each required path (BMAD, fallback, non-interactive, override).
2. Diff or snapshots of generated `.spectra/assessment.yaml` and `.spectra/project.yaml`.
3. Fixture pass/fail table aligned with `fixtures/assessment/manifest.json`.
4. Final summary: `PASS` or `FAIL` with blocker list.

## 8. Report Template
Use this when reporting to `claude-desktop`:

```text
Phase C Verification Report (spectra-assess)
Commit: <sha>

1) BMAD-present path: PASS/FAIL
2) Interactive fallback path: PASS/FAIL
3) Non-interactive CI path: PASS/FAIL
4) --level override behavior: PASS/FAIL
5) Assessment fixtures: PASS/FAIL
6) Edge cases: PASS/FAIL

Blockers:
- <none or list>

Gate Result: PASS/FAIL
```
