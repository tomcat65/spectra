# Plan Bridge Golden Fixtures

These fixtures validate the approved SPECTRA v4 canonical `plan.md` schema.

Coverage:
- 3 valid plans (`valid-level0.md`, `valid-level2.md`, `valid-level4.md`)
- 3 malformed plans (`invalid-ownership-overlap.md`, `invalid-missing-wiring-level2.md`, `invalid-ac-format.md`)

Notes:
- Fixtures are verifier artifacts only (no runtime code changes).
- Validation expectations are documented in `manifest.json`.
