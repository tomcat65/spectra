# Wiring Proof Checklist — 5 Mandatory Checks

Before EVERY commit, verify all five:

- [ ] **CLI paths** — every CLI command has subprocess-level tests that prove real execution
- [ ] **Import invocation** — every imported module is actually called somewhere (no dead imports)
- [ ] **Pipeline completeness** — integration tests exercise the full chain, not just individual units
- [ ] **Error boundaries** — exceptions at CLI boundary produce clean user messages, not tracebacks
- [ ] **Dependencies declared** — every import has its package in requirements.txt / pyproject.toml / package.json

If ANY check fails, fix it before committing. Do not rely on the verifier to catch what you should prevent.
