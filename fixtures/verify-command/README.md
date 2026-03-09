# Verify Command Detection Fixtures

These fixtures support `tests/test-verify-command-detection.sh` (Task 005).

Each subdirectory simulates a repo root with specific manifest files to test
that `spectra-verify.sh` selects the correct regression command based on
language detection rather than defaulting to Python.

## Fixture Layout

- `python-repo/` — pyproject.toml present → expect `python -m pytest -q`
- `js-repo/` — package.json present → expect `npm test`
- `rust-repo/` — Cargo.toml present → expect `cargo test`
- `go-repo/` — go.mod present → expect `go test ./...`
- `bash-repo/` — bin/*.sh + tests/*.sh + Makefile → expect `bash tests/run-tests.sh`
- `tests-only/` — bare `tests/` directory, no manifest → expect no regression command (NOT pytest)
- `ambiguous-repo/` — both pyproject.toml AND package.json → Python wins (first match)

## Key Invariant

A `tests/` directory alone MUST NOT trigger `python -m pytest`. The old
behavior was Python-biased: any repo with a `tests/` folder got pytest.
