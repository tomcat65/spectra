# Phase A Audit: codex's Plan Schema Normalization

**Auditor:** claude-cli
**Date:** 2026-02-10
**Subject:** Review of codex's Phase A implementation against proposed canonical plan.md schema

---

## 1. What codex Changed (10 files)

### New
| File | Purpose |
|------|---------|
| `bin/spectra-plan-validate.sh` | Plan schema validator (148 lines) |

### Modified
| File | Change Summary |
|------|---------------|
| `bin/spectra-plan.sh` | Updated prompt template to emit canonical format; wired validator as acceptance gate |
| `bin/spectra-verify.sh` | Major rewrite: new `normalize_task_id()`, `find_task_header_line()`, `get_task_section()` functions; schema validation gate at entry |
| `bin/spectra-loop-legacy.sh` | Added `validate_plan_contract()` gate; updated `count_tasks()` and `next_task()` for canonical format; backward compat fallbacks |
| `bin/spectra-loop-v3.sh` | Added `validate_plan_contract()` gate; updated progress counting with fallback |
| `bin/spectra-team-prompt.sh` | Updated parse guidance from `- [ ] Task N:` to `- [ ] NNN:` under `## Task NNN:` |
| `templates/.spectra/plan.md.tmpl` | Full rewrite to canonical schema template |
| `agents/spectra-planner.md` | Updated format examples + fixed `.spectra/plans/plan.md` → `.spectra/plan.md` path bug |
| `README.md` | Added `spectra-plan-validate.sh` to directory listing |
| `SPECTRA_COMPLETE.md` | Updated task format to match canonical schema |

---

## 2. Schema Comparison

### Proposed (claude-desktop brainstorm)
```markdown
## Task {N}: {title}
Status: [ ] pending | [x] complete | [!] stuck
Level: {0-4}
Files:
  - owns: path/to/file.ts
  - touches: path/to/other.ts
Verify: {shell command}
Wiring:
  - {import path} → {call site} → {assertion}
Max-iterations: {3}
Acceptance:
  - {criterion 1}
  - {criterion 2}
```

### Implemented (codex)
```markdown
## Task NNN: Title
- [ ] NNN: Title
- AC: acceptance criteria
- Files: comma-separated paths
- Verify: `command`
- Risk: low|medium|high
- Max iterations: N
- File ownership:
  - owns: [files]
  - reads: [files]
- Wiring proof:
  - CLI: command path
  - Integration: cross-module assertion
```

### Field-by-field Comparison

| Field | Proposed | codex Built | Verdict |
|-------|----------|-------------|---------|
| Task header | `## Task {N}:` | `## Task NNN:` | **Match** — codex enforces 3-digit zero-pad, good |
| Status | `Status:` line with pending/complete/stuck | Checkbox `[ ]`/`[x]` only | **Gap** — no `[!]` stuck indicator |
| Level | Per-task `Level:` field | Not implemented | **Gap** — project-level only |
| Files (ownership) | `owns:` + `touches:` | `owns:` + `reads:` | **Divergence** — `reads` ≠ `touches` semantically |
| Verify | Bare command | Backtick-wrapped `\`cmd\`` | **codex better** — explicit delimiter, easier to parse |
| Wiring | `{import} → {call} → {assertion}` | `CLI:` + `Integration:` sub-fields | **codex better** — structured, machine-parseable |
| Max iterations | `Max-iterations:` (hyphenated) | `Max iterations:` (space) | **Trivial** — need to pick one |
| Acceptance | Multi-line criteria list | Single-line `AC:` | **Gap** — single line too constraining |
| Risk | Not in proposal | `Risk: low\|medium\|high` | **codex addition** — good, needed for risk-first |
| Checkbox | Not explicit | `- [ ] NNN:` required | **codex addition** — good, dual header+checkbox |

---

## 3. Issues Found

### Issue 1: CRITICAL — Wiring proof required for ALL levels
The validator mandates `- Wiring proof:` for every task regardless of level. Level 0 bug fixes and Level 1 small features often don't have cross-module wiring to prove. This will cause false validation failures.

**Fix:** Make wiring proof conditional on Level 2+ (like File ownership is conditional on Level 3+).

### Issue 2: SIGNIFICANT — Single-line AC is too constraining
`- AC: single line` cannot express multiple acceptance criteria. Many tasks from stories have 3-5 criteria. The proposal had a proper list format.

**Fix:** Allow multi-line AC with sub-items:
```markdown
- AC:
  - criterion 1
  - criterion 2
```
Or keep single-line for simple tasks but don't reject multi-line.

### Issue 3: SIGNIFICANT — `reads:` vs `touches:` semantic mismatch
`reads:` means "this task only reads this file." But `touches:` (from the proposal) means "this task modifies this file but doesn't own it" — e.g., adding an import to a shared `index.ts`. These are different operations. `reads:` is SIGN-005-safe (no conflict), but `touches:` might conflict.

**Fix:** Use three categories: `owns:`, `touches:`, `reads:` — with SIGN-005 applying to both `owns:` and `touches:`.

### Issue 4: MODERATE — No `[!]` stuck state
The STUCK signal workflow writes to `signals/STUCK`, but there's no way to mark individual tasks as stuck in plan.md. The proposal included `[!]` but codex didn't implement it.

**Fix:** Support `- [!] NNN:` as stuck indicator, parsed by verifier and loop.

### Issue 5: MODERATE — Risk field unused
The validator checks for `Risk:` but no consumer uses it. The legacy loop's risk-first ordering still relies on `.risk-order` file generated separately, not from parsing Risk fields.

**Fix:** Wire `Risk:` into the legacy loop's risk ordering (replace `.risk-order` file generation).

### Issue 6: MINOR — No test fixtures
codex built the validator but not the contract tests. The validator itself is untested. One malformed regex could silently pass bad plans.

**Fix:** This is Phase B work. Not blocking, but track it.

### Issue 7: MINOR — Canonical agent not updated
codex updated `agents/spectra-planner.md` in the repo copy but NOT the canonical agent at `~/.claude/agents/spectra-planner.md`. The canonical copy still has the old format + wrong path.

**Fix:** Sync canonical agent definition.

---

## 4. What codex Got RIGHT

1. **Backward compatibility fallbacks** — Every consumer has a fallback for old-format plans. This means v3.1 plans still work during migration. Well done.

2. **Validator as separate script** — Clean separation. Can be called independently, from CI, or as a pre-commit hook.

3. **Structured wiring proof** — `CLI:` + `Integration:` is better than the proposal's freeform arrow notation. Machine-parseable.

4. **Risk field addition** — Not in the original proposal but essential for SPECTRA's risk-first execution model.

5. **Fixed the path bug** — `.spectra/plans/plan.md` → `.spectra/plan.md` was a real inconsistency. Good catch and fix.

6. **Zero-padded IDs enforced** — Consistent 3-digit format prevents sorting issues.

7. **Verify command in backticks** — Explicit delimiters make extraction trivial with regex.

---

## 5. Proposed FINAL Canonical Schema

Merges the best of the proposal, codex's implementation, and claude-desktop's additional improvements.

```markdown
# SPECTRA Execution Plan

## Project: {name}
## Level: {0-4}
## Generated: {date}
## Source: .spectra/stories/

---

## Task 001: {title}
- [ ] 001: {title}
- AC:
  - {criterion 1}
  - {criterion 2}
- Files: {comma-separated paths}
- Verify: `{command that exits 0 on success}`
- Risk: {low|medium|high}
- Max-iterations: {3|5|8|10}
- Scope: {code|infra|docs|config|multi-repo}
- File-ownership:                          # Level 3+ only
  - owns: [{files this task creates/modifies}]
  - touches: [{files this task modifies but doesn't own}]
  - reads: [{files this task only reads}]
- Wiring-proof:                            # Level 2+ only
  - CLI: {exact command path to exercise}
  - Integration: {cross-module/pipeline assertion}

## Task 002: {title}
- [ ] 002: {title}
...

---

## Parallelism Assessment                  # Level 3+ only
- Independent tasks: [001, 003]
- Sequential dependencies: [001 → 002, 003 → 004]
- Recommendation: {TEAM_ELIGIBLE|SEQUENTIAL_ONLY}
```

### Schema Rules

1. **Header + Checkbox:** `## Task NNN:` and `- [ ] NNN:` must match. Checkbox carries state.
2. **Checkbox states:** `[ ]` pending, `[x]` complete, `[!]` stuck
3. **IDs:** 3-digit zero-padded, strictly increasing
4. **AC:** Multi-line list with `  - ` sub-items (at least one required)
5. **Verify:** Backtick-wrapped shell command, must exit 0 on success
6. **Risk:** Exactly one of `low`, `medium`, `high`
7. **Max-iterations:** Hyphenated key. Values: 3 (trivial), 5 (setup), 8 (feature), 10 (complex)
8. **Scope:** Task domain — `code` (default), `infra`, `docs`, `config`, `multi-repo`
9. **File-ownership:** Required at Level 3+. Three categories:
   - `owns:` — SIGN-005 exclusive, no two tasks may own the same file
   - `touches:` — SIGN-005 shared, conflict detection required
   - `reads:` — No conflict, read-only access
10. **Wiring-proof:** Required at Level 2+. Structured sub-fields.
11. **Parallelism Assessment:** Required at Level 3+.

### Changes from codex's Implementation

| Change | Reason |
|--------|--------|
| `AC:` → multi-line list | Single line too constraining for real stories |
| Add `[!]` stuck state | Aligns with STUCK signal workflow |
| `reads:` → `owns:` + `touches:` + `reads:` | Three-tier file access model for accurate SIGN-005 |
| `Max iterations:` → `Max-iterations:` | Hyphenated for consistent field naming |
| Add `Scope:` field | claude-desktop's suggestion: supports infra/docs/config/multi-repo |
| Wiring-proof conditional on Level 2+ | Don't require wiring proof for bug fixes |
| File-ownership conditional on Level 3+ | Already conditional in codex's impl, keep it |

### Changes from Original Proposal

| Change | Reason |
|--------|--------|
| Drop `Status:` line | Checkbox state `[ ]/[x]/[!]` is sufficient, no redundant field |
| Drop per-task `Level:` | Project-level is sufficient; per-task level adds noise |
| Keep codex's `Risk:` | Essential for risk-first execution ordering |
| Keep codex's structured wiring | `CLI:` + `Integration:` is better than freeform arrows |
| Keep codex's backtick verify | Explicit delimiters > bare text |

---

## 6. Recommendation

1. **Accept codex's structural work** (validator, consumer updates, backward compat fallbacks) — the architecture is sound.
2. **Apply the 7 fixes** listed in Section 3 before merging.
3. **Adopt the final schema** from Section 5 as the canonical contract.
4. **Sync canonical agent** at `~/.claude/agents/spectra-planner.md`.
5. **Proceed to Phase B** (contract tests + golden fixtures) to prove the schema works end-to-end.
6. **Accept codex's offer** to draft `bmad-output-schema.md` for Phase D prep — parallel track doesn't block A+B.

**Do NOT merge codex's changes as-is.** The 7 issues (especially #1 wiring-for-all-levels and #2 single-line-AC) will cause immediate problems in real usage.
