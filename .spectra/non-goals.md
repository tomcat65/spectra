# Non-Goals

- No broad rewrite of SPECTRA into a different orchestration model.
- No breaking CLI renames or silent behavior changes without matching documentation and migration notes.
- No ECC feature lands before baseline hardening tasks 001 through 006 are complete.
- No agent is allowed to wear two hats; builder, reviewer, verifier, and auditor remain distinct.
- No memory-only session behavior for builder or verifier. Fresh-context execution remains the default doctrine.
