# SPECTRA Signs Taxonomy

Known bug patterns. The most dangerous bugs because all unit tests pass.

## SIGN-001: Import Without Invocation
> Every integration test must invoke every pipeline step it imports — importing a module without calling it is dead code in a test.

**How to check:** For every `import` or `from X import Y` in test files, grep for at least one call-site invocation of that module/class/function. If imported but never called → FAIL.

## SIGN-002: CLI Boundary Blindness
> CLI commands must have subprocess-level tests that prove real execution, not just class-level unit tests.

**How to check:** For every CLI command wired in `__main__.py` or equivalent entry point, verify a corresponding subprocess test exists that runs the actual command and asserts clean output + correct exit code. Class tests alone are insufficient.

## SIGN-003: Lesson Decay
> If a lesson was learned from a previous FAIL, verify the builder applied it.

**How to check:** Read `.spectra/logs/` for any prior fail reports on this task. If the builder was retrying after a FAIL, verify the specific fix the verifier requested is actually present in the new code.

## SIGN-005: File Ownership Conflict
> No two teammates may edit the same file in parallel tasks.

**How to check:** Check if the current task's file ownership overlaps with other in-progress tasks. Flag if detected.

## SIGN-009: Test Ordering Pollution
> Tests that pass in isolation but fail in the full suite indicate test pollution — shared state leaking between test files.

**How to check:** Run the task's specific test file BOTH in isolation (`pytest tests/test_foo.py`) AND in full suite (`pytest tests/`). If isolation passes but full suite fails, flag as TEST_POLLUTION and report which test files interfere.
