# SPECTRA v5.0 Audit Report

## Re-Audit (2026-02-11) — Post-Fix Verification

Overall Verdict: **PASS**

This section is the current verdict and supersedes the older baseline section results below.

### Original Findings Status

1. Finding 1 (HIGH) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:1238`, `bin/spectra-loop-v5.sh:1240`, `bin/spectra-loop-v5.sh:1242`
- Verification: Empty ready-batch now checks remaining count and raises STUCK only when `remaining > 0` (deadlock), preventing silent early exit.

2. Finding 2 (HIGH) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:954`, `bin/spectra-loop-v5.sh:998`, `bin/spectra-loop-v5.sh:1004`
- Verification: `restore_checkpoint()` now resets all task states to `pending` first, restores only from checkpoint arrays, and has robust non-`jq` fallback parsing for `completed`, `stuck`, `retry_counts`, and `failure_types`.

3. Finding 3 (HIGH) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:642`, `bin/spectra-loop-v5.sh:652`
- Verification: `next_batch()` now treats unknown dependency IDs as unmet (`dep_found=false` => `deps_met=false`), fail-closed.

4. Finding 4 (MEDIUM) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:752`, `bin/spectra-loop-v5.sh:766`, `bin/spectra-loop-v5.sh:778`
- Verification: Prompt budget guards are present in `build_prompt()`, `verify_prompt()`, and `preflight_prompt()` with truncation to `480` chars max (`477 + "..."`).

5. Finding 5 (MEDIUM) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:597`
- Verification: `parse_dependencies()` now supports explicit list syntax (`Task NNN depends on NNN, NNN, NNN`) via dedicated `elif` branch.

6. Finding 6 (MEDIUM) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:1289`
- Verification: Build-phase `write_batch_status` is now gated behind `DRY_RUN == false`; dry-run no longer writes `STATUS` during Step B.

7. Finding 7 (LOW) — **VERIFIED FIXED**
- File: `bin/spectra-loop-v5.sh:142`, `bin/spectra-loop-v5.sh:1366`, `bin/spectra-loop-v5.sh:1411`, `bin/spectra-loop-v5.sh:1425`, `bin/spectra-loop-v5.sh:1436`
- Verification: GNU/BSD-compatible `sed_inplace()` helper added and all 4 checkbox updates migrated off raw `sed -i`.

### Re-Run Checklist (A–F)

- A. Architecture Compliance: **PASS**
- B. Correctness of New Functions: **PASS**
- C. Legacy Feature Preservation: **PASS**
- D. Edge Cases and Safety: **PASS**
- E. Bash Safety: **PASS**
- F. `spectra-oracle.md` Agent Review: **PASS**

### Regression Checks

- Syntax: `bash -n /home/tomcat65/.spectra/bin/spectra-loop-v5.sh` -> PASS
- Prompt truncation behavior:
  - Under-limit prompt is unchanged (`len_short:12` observed in spot check).
  - Over-limit prompt truncates to `480` (`len_long:480` observed in spot check).
- `sed_inplace` targets:
  - PASS checkbox update: `bin/spectra-loop-v5.sh:1366`
  - STUCK checkbox updates: `bin/spectra-loop-v5.sh:1411`, `bin/spectra-loop-v5.sh:1425`, `bin/spectra-loop-v5.sh:1436`
- Dependency parsing compatibility:
  - Chain notation regex still matches (`Tasks 001 → 002 → 003`).
  - Explicit list regex matches (`Task 015 depends on 001, 002, 003`).
  - `depends on all` branch still matches (`Task 015 depends on all above`).
- Deadlock false-positive guard:
  - STUCK only emitted on empty batch when `remaining > 0`.
  - When all tasks are complete (`remaining == 0`), loop exits normally to Phase 5.

### Fresh-Eyes Pass

- No new CRITICAL/HIGH/MEDIUM issues found in this re-audit.
- No regressions identified from the post-audit patch set.

Date: 2026-02-11
Scope:
- Primary: `bin/spectra-loop-v5.sh`
- Agent: `/home/tomcat65/.claude/agents/spectra-oracle.md`
- Reference-only: `bin/spectra-loop-legacy.sh`, `bin/spectra-loop.sh`

## Section Results
- A. Architecture Compliance: **FAIL** (1 open MEDIUM)
- B. Correctness of New Functions: **FAIL** (1 open MEDIUM)
- C. Legacy Feature Preservation: **PASS**
- D. Edge Cases and Safety: **FAIL** (1 open MEDIUM)
- E. Bash Safety: **FAIL** (1 open LOW)
- F. `spectra-oracle.md` Agent Review: **PASS**

## Findings

### Finding 1 — HIGH (Fixed)
- File: `bin/spectra-loop-v5.sh:1193`, `bin/spectra-loop-v5.sh:1197`
- Issue: Empty-ready-batch condition (`next_batch` returns empty) previously broke the loop silently even when tasks remained due to unmet deps, instead of emitting STUCK/deadlock.
- Impact: Execution could end with incomplete plan and no explicit deadlock signal.
- Fix Applied:
```bash
if [[ -z "$BATCH_STR" ]]; then
    read _TOTAL _DONE _REMAINING _STUCK <<< $(count_tasks)
    if [[ $_REMAINING -gt 0 ]]; then
        signal_stuck "Dependency deadlock: ${_REMAINING} task(s) remain but none are ready..."
    fi
fi
```

### Finding 2 — HIGH (Fixed)
- File: `bin/spectra-loop-v5.sh:909`, `bin/spectra-loop-v5.sh:953`, `bin/spectra-loop-v5.sh:954`
- Issue: `restore_checkpoint()` did not strictly reset task state before restore; with non-`jq` fallback it also parsed all `"NNN"` tokens globally (including retry/failure keys), corrupting restored completion state.
- Impact: Resume could become nondeterministic and violate checkpoint-as-source-of-truth.
- Fix Applied:
```bash
for ((i=0; i<${#TASK_IDS[@]}; i++)); do
    TASK_STATUS[$i]="pending"
done
completed_str=$(...completed array only...)
stuck_str=$(...stuck array only...)
```
Also added fallback restoration for `retry_counts` and `failure_types` object blocks.

### Finding 3 — HIGH (Fixed)
- File: `bin/spectra-loop-v5.sh:614`, `bin/spectra-loop-v5.sh:624`
- Issue: `next_batch()` treated unknown dependency IDs as satisfied.
- Impact: Task could execute before true prerequisites were met if dependency text drifted from task IDs.
- Fix Applied:
```bash
local dep_found=false
...
if [[ "$dep_found" == false ]]; then
    deps_met=false
fi
```

### Finding 4 — MEDIUM (Open)
- File: `bin/spectra-loop-v5.sh:711`, `bin/spectra-loop-v5.sh:720`, `bin/spectra-loop-v5.sh:761`
- Issue: Prompt budget claim (`<500 bytes`) is not enforced in code. `build_prompt()` appends task title + retry text + preflight advisory without byte cap.
- Impact: Can exceed architecture budget under long titles/advisories.
- Suggested Fix:
```bash
max_bytes=480
if (( ${#prompt} > max_bytes )); then
    prompt="${prompt:0:max_bytes}"
fi
```
(Apply similarly to verifier/preflight prompt generators if strict cap is required.)

### Finding 5 — MEDIUM (Open)
- File: `bin/spectra-loop-v5.sh:572`
- Issue: `parse_dependencies()` comment claims support for `depends on X, Y, Z`, but implementation only handles chain notation and `depends on all above`.
- Impact: Plans using explicit list syntax will silently miss dependencies.
- Suggested Fix:
```bash
if [[ "$line" =~ Task\ ([0-9]{3}).*depends\ on\ ([0-9]{3}(,\s*[0-9]{3})+) ]]; then
  # split and append deps into TASK_DEPS[]
fi
```

### Finding 6 — MEDIUM (Open)
- File: `bin/spectra-loop-v5.sh:1244`
- Issue: Dry-run isolation is incomplete. `write_batch_status` executes even in dry-run, writing `.spectra/signals/STATUS`.
- Impact: Violates dry-run no-write expectation for signals.
- Suggested Fix:
```bash
if [[ "$DRY_RUN" == false ]]; then
    write_batch_status "${batch_desc}" "builder"
fi
```

### Finding 7 — LOW (Open)
- File: `bin/spectra-loop-v5.sh:1319`, `bin/spectra-loop-v5.sh:1364`, `bin/spectra-loop-v5.sh:1378`, `bin/spectra-loop-v5.sh:1389`
- Issue: `sed -i` is GNU-specific; BSD/macOS requires `sed -i ''`.
- Impact: Non-portable checkbox updates on macOS.
- Suggested Fix:
```bash
sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}
```

## Checklist Mapping Notes

### A. Architecture Compliance
- A1 No LLM orchestration APIs (`spectra-lead`, TeamCreate/TaskCreate/TaskUpdate/SendMessage/TeamDelete, `spectra-team-prompt.sh`): PASS (none found).
- A2 Prompt pointers/no heavy artifact injection: PASS.
- A2 strict `<500` budget enforcement: FAIL (Finding 4).
- A3 Bash-only orchestration: PASS.
- A4 Checkpoint restore as source of truth: PASS after Finding 2 fix.
- A5 Verification sequential after parallel build: PASS (`parallel_build` then single-task verify loop).

### B. Correctness of New Functions
- `parse_plan()`: PASS for sample task format (task header, checkbox, risk, max-iterations, verify, owns/touches).
- `parse_dependencies()` chain + `depends on all above`: PASS.
- `parse_dependencies()` explicit list syntax: FAIL (Finding 5).
- `next_batch()` deps + conflicts + risk ordering + empty return: PASS after Finding 3 fix.
- `parallel_build()`: PASS (`&`, `wait`, STUCK check, diminishing budget, per-task logs).
- `write_checkpoint()/restore_checkpoint()`: PASS after Finding 2 fix.
- `oracle_classify()`: PASS (3-turn oracle, enum validation, verifier fallback, dry-run short-circuit).

### C. Legacy Feature Preservation
All requested behaviors/functions are present and wired: PASS.

### D. Edge Cases and Safety
- Resume without checkpoint: PASS (graceful fresh start).
- Empty ready batch deadlock: PASS after Finding 1 fix.
- All tasks complete: PASS (Phase 5 path reached).
- Single remaining task verify depth full: PASS (`_REMAINING <= 1`).
- Dry-run no signal/checkpoint/complete writes: FAIL (Finding 6: STATUS write).
- Previous STUCK signal blocks run: PASS.
- Plan checkbox updates for PASS/STUCK: PASS (line-based `sed` updates).

### E. Bash Safety
- `set -euo pipefail`: PASS.
- `set +e` / non-fatal handling around claude calls: PASS (uses `set +e` where needed and `|| true` wrappers).
- Array/subshell safety: PASS (file redirection loops, guarded array usage).
- Signal/checkpoint race risk: PASS (single-writer checkpoint path).
- `sed -i` portability: FAIL (Finding 7).

### F. `spectra-oracle.md` Review
- Tools restricted to `Read`, `Grep`: PASS.
- `maxTurns: 3`: PASS.
- `model: haiku`: PASS.
- Single-word output instruction clarity: PASS.

## Syntax Validation
- `bash -n /home/tomcat65/.spectra/bin/spectra-loop-v5.sh` -> PASS
