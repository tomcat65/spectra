# SPECTRA Framework Origin Constitution

- This repository is the SPECTRA framework source of truth; every change must improve downstream framework consumers, not just the origin repo.
- Framework runtime, templates, tests, and documentation must describe the same behavior before any task is considered complete.
- Control-plane work is test-first where practical: add or tighten fixtures and regression coverage before widening behavior.
- Builder and verifier remain separate roles. ECC integrations must not collapse role separation or introduce hidden memory dependencies.
- New automation must remain file-backed, inspectable, and reversible. Opt-in is preferred for features that could alter current operator flow.
- Do not spend ceremony on speculative architecture. Fix runtime truth, then add leverage.
