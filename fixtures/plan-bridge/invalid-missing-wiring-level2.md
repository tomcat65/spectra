# SPECTRA Execution Plan

## Project: Invalid Missing Wiring
## Level: 2
## Generated: 2026-02-10
## Source: .spectra/stories/

---

## Task 001: Add signup API
- [ ] 001: Add signup API
- AC:
  - POST /signup creates account.
  - Duplicate email returns 409.
- Files: src/signup/controller.ts, src/signup/service.ts
- Verify: `npm test -- signup`
- Risk: medium
- Max-iterations: 8
- Scope: code

