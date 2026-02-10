# SPECTRA Global Guardrails — Cross-Project Signs
# Auto-propagated to new projects by spectra-init.
# Updated by spectra-loop when lessons are promoted (TEMP -> PROMOTED).

### SIGN-001: Integration tests must invoke what they import
> "Every integration test must invoke every pipeline step it imports — importing a module without calling it is dead code in a test."

### SIGN-002: CLI commands need subprocess-level tests
> "CLI commands must have subprocess-level tests that prove real execution, not just class-level unit tests."

### SIGN-003: Lessons must generalize, not just fix
> "If the spec says A -> B -> C -> D and your test skips B, you've written a unit test with extra steps — not an integration test."

### SIGN-004: Lead Drift
> "Team lead must not write code. If lead implements, escalate immediately."

### SIGN-005: File Collision
> "No two teammates may edit the same file. Task decomposition must assign file ownership."

### SIGN-006: Stale Task
> "If task stays in-progress >10 minutes without output, lead must nudge or reassign."

### SIGN-007: Silent Failure
> "Teammate errors must be surfaced to lead via mailbox. Silent swallowing is a system fault."

### SIGN-008: Research Before STUCK
> "Before declaring STUCK on any external blocker (dependency install, build error, missing package, environment issue), the builder must spend at least one research cycle using web search or documentation lookup. Most tooling failures have known solutions — a 30-second search beats a full STUCK escalation."
