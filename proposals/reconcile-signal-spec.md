# RECONCILE Signal Specification (Phase D)

Status: Draft for implementation alignment  
Owner lane: codex (verifier/contract writer)  
Date: 2026-02-10

## 1. Purpose
`RECONCILE` is a verifier signal that captures a planning-to-execution gap requiring amendment of BMAD planning artifacts.

The signal is written by `spectra-verifier` when runtime evidence shows the current plan/architecture/spec is incomplete, ambiguous, or contradictory.

## 2. File Path
`.spectra/signals/RECONCILE`

## 3. Canonical Record Format
The signal file stores one YAML document per open reconcile event.
Multiple events are represented as multi-document YAML separated by `---`.

Canonical 10-line record:

```yaml
version: 1
timestamp: "2026-02-10T20:45:00Z"
task_id: "003"
gap_type: wiring_gap
description: "Retry handler calls adapter not described in architecture"
source_artifact: "bmad/architecture.md#payments-flow"
suggested_amendment: "Add retry adapter wiring and ownership note"
retry_count: 2
severity: warn
status: open
```

## 4. Field Definitions
1. `version`: schema version (`1`).
2. `timestamp`: UTC ISO-8601 write time.
3. `task_id`: SPECTRA task id (`NNN`) that exposed the gap.
4. `gap_type`: one of:
- `wiring_gap`
- `spec_ambiguity`
- `architecture_mismatch`
5. `description`: concise gap summary from verifier evidence.
6. `source_artifact`: artifact path (optionally with section anchor) that is missing or conflicting.
7. `suggested_amendment`: minimal planning correction to resolve the gap.
8. `retry_count`: verifier-observed retry count for this task at signal time.
9. `severity`: `warn` or `error`.
10. `status`: `open`, `accepted`, or `resolved`.

## 5. Write Semantics
1. Write trigger is edge-triggered: emit when a new gap is first detected.
2. If the same open gap recurs for the same `task_id + gap_type + source_artifact`, update `timestamp`, `retry_count`, and `description` in place.
3. When planner/builder applies amendment and verifier confirms closure, set `status: resolved`.
4. When architect accepts a mitigation without artifact change, set `status: accepted`.

## 6. Trigger Conditions
`spectra-verifier` writes `RECONCILE` when any condition is true:
1. **Wiring gap not in architecture**:
- Wiring proof or integration evidence requires a call path not documented in architecture.
2. **Ambiguous spec causing retries**:
- Same task retries >=2 due to unclear acceptance or missing constraints.
3. **Architecture mismatch**:
- Implemented module boundaries or ownership differ from architecture/stories assumptions.

## 7. Operational Policy
1. `severity: error` if verifier cannot complete task validation without amendment.
2. `severity: warn` if task can proceed but planning artifacts are now stale.
3. Presence of any `open` `error` record should block final task completion.

## 8. Example Multi-Event File
```yaml
version: 1
timestamp: "2026-02-10T21:00:00Z"
task_id: "002"
gap_type: wiring_gap
description: "Publisher retry path is not represented in architecture sequence"
source_artifact: "bmad/architecture.md#event-pipeline"
suggested_amendment: "Add retry sequence and ownership note for retry module"
retry_count: 1
severity: warn
status: open
---
version: 1
timestamp: "2026-02-10T21:04:00Z"
task_id: "004"
gap_type: spec_ambiguity
description: "Acceptance criteria lacks deterministic timeout threshold"
source_artifact: "bmad/stories.md#story-st-204"
suggested_amendment: "Add explicit timeout threshold and failure behavior"
retry_count: 3
severity: error
status: open
```
