# Assessment Fixtures

These fixtures validate the Phase C `spectra-assess` contract in `proposals/bmad-output-schema.md`.

Coverage:
- 4 valid `assessment.yaml` samples (Level 0, Level 3, Level 4, manual fallback)
- 1 malformed sample (`assessment-malformed-missing-level.yaml`)

Validation intent:
- Confirm deterministic track -> level mapping artifacts
- Confirm tuning fields are present and typed
- Confirm fallback metadata (`source.mode`, warnings) is preserved
- Confirm malformed files fail schema checks
