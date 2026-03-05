# SPECTRA Failure Type Classification

Every FAIL report MUST include a `failure_type` from this taxonomy:

| Failure Type | Description |
|-------------|-------------|
| `test_failure` | Assertion error, logic bug, flaky test |
| `missing_dependency` | ModuleNotFoundError, unresolved import |
| `wiring_gap` | Integration test missing pipeline step, dead import |
| `architecture_mismatch` | Wrong approach entirely, fundamental design issue |
| `ambiguous_spec` | Cannot determine correct behavior from plan.md |
| `verifier_non_determinism` | Verification results inconsistent across runs |
| `external_blocker` | Missing API key, service down, environment issue |

**Classify honestly.** The loop uses your classification to decide retry vs. STUCK. Misclassification wastes tokens or blocks unnecessarily.
