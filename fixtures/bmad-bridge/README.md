# BMAD Bridge Fixtures (Phase D)

These fixtures define acceptance tests for `spectra-plan --from-bmad`.

## Coverage
1. Level 2 happy path with clear architecture ownership hints.
2. Level 3 path with one story split into multiple tasks (1:N).
3. Level 3 path with vague architecture and best-effort ownership mapping.
4. No `assessment.yaml` path (warn + default Level 2).
5. Malformed BMAD artifacts:
- missing stories heading
- empty stories section
- missing stories file

## Fixture Layout
Each fixture case contains:
1. `input/` BMAD artifacts consumed by the bridge.
2. `expected/` expected bridge outcome (`plan.md`, warning text, or `error.json`).

## Notes
1. These are verifier artifacts only.
2. Error codes in malformed cases are contract targets for Phase D implementation.
3. See `manifest.json` for per-case expectations.
