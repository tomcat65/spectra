# BMAD -> SPECTRA Interface Contract (Phase C Draft)

Status: Draft for architect review  
Owner lane: codex (verifier/contract writer)  
Date: 2026-02-10

## 1. Scope
This contract defines the BMAD assessment interface consumed by `spectra-assess` and the output contract written to `.spectra/assessment.yaml`.

This document answers:
1. BMAD `*workflow-init` output format.
2. Track -> Level mapping decision tree.
3. Tuning derivation for verification behavior.
4. Fallback behavior when BMAD is not available.
5. `project.yaml` vs `assessment.yaml` file boundary recommendation.

## 2. BMAD `*workflow-init` Output Format (Input Contract)
`spectra-assess` must normalize `*workflow-init` output into this typed shape before mapping:

```yaml
workflow_init:
  track: quick_flow | bmad_method | enterprise          # required
  confidence: 0.0-1.0                                   # optional, default 0.5
  rationale: string                                     # required
  context:                                              # required object
    language: string                                    # optional, default "unknown"
    framework: string                                   # optional, default "unknown"
    domain: string                                      # required, default "general"
    team_size: integer >= 1                             # required, default 2
    integration_count: integer >= 0                     # required, default 0
    risk_factors: [string, ...]                         # required, default []
    compliance: [string, ...]                           # optional, default []
    blast_radius: low | medium | high                   # required, default medium
```

Validation rules:
1. `track`, `rationale`, and `context` are required.
2. Missing required context fields are filled with defaults and marked in `assessment.yaml.warnings`.
3. Unknown keys are preserved under `workflow_init.raw` for passthrough traceability.

## 3. `assessment.yaml` Output Contract
`spectra-assess` must emit `.spectra/assessment.yaml` using this shape:

```yaml
version: 1
generated_at: "2026-02-10T19:00:00Z"
source:
  mode: bmad-detected | manual
  producer: workflow-init | interactive-fallback
bmad:
  track: quick_flow | bmad_method | enterprise
  confidence: 0.0-1.0
  rationale: string
  context:
    language: string
    framework: string
    domain: string
    team_size: integer
    integration_count: integer
    risk_factors: [string, ...]
    compliance: [string, ...]
    blast_radius: low | medium | high
spectra:
  level: 0 | 1 | 2 | 3 | 4
  execution_mode: sequential | teams
  mapping_reason: string
tuning:
  verification_intensity: low | medium | high | exhaustive
  wiring_depth: none | basic | full
  retry_budget: integer
warnings: [string, ...]    # optional
```

## 4. Track -> Level Mapping Rules (Decision Tree)
The mapping must be deterministic.

### 4.1 Quick Flow -> Level 0 or 1
1. If all are true, map to Level 0:
- `track = quick_flow`
- `blast_radius = low`
- `integration_count <= 1`
- `team_size <= 2`
- `risk_factors` is empty
2. Otherwise map to Level 1.

### 4.2 BMad Method -> Level 2 or 3
1. Compute `complexity_triggers`:
- `integration_count >= 3`
- `team_size >= 5`
- `blast_radius = high`
- `risk_factors` contains any of: `security`, `regulatory`, `payments`, `data-migration`, `multi-service`
- `compliance` not empty
2. If any trigger is true, map to Level 3.
3. Else map to Level 2.

### 4.3 Enterprise -> Level 4
If `track = enterprise`, always map to Level 4.

## 5. Tuning Derivation Rules
These values are derived from mapped level + context.

### 5.1 Risk Score
`risk_score` is additive:
1. `+2` each for risk factors: `security`, `privacy`, `regulatory`, `payments`, `auth`, `data-loss`.
2. `+1` each for risk factors: `external-api`, `migration`, `concurrency`, `infra-change`.
3. `+1` if `domain` in `fintech`, `healthcare`, `government`, `security`.
4. `+1` if `team_size >= 5`.
5. `+1` if mapped level >= 3.

### 5.2 `verification_intensity`
1. `exhaustive` if level = 4 or `risk_score >= 8`.
2. `high` if level = 3 or `risk_score >= 5`.
3. `medium` if level = 2 or `risk_score >= 3`.
4. `low` otherwise.

### 5.3 `wiring_depth`
1. `none` for Level 0 with `integration_count <= 1`.
2. `basic` for Level 1, or Level 2 with `integration_count <= 2`.
3. `full` for Level >= 3, or `integration_count >= 3`, or if risk factors include `security` or `regulatory`.

### 5.4 `retry_budget`
1. `2` when intensity is `low`.
2. `3` when intensity is `medium`.
3. `4` when intensity is `high`.
4. `5` when intensity is `exhaustive`.
5. Clamp final value to range `[2, 5]`.

## 6. Fallback Behavior (No BMAD Installed)
If BMAD is unavailable, `spectra-assess` must run interactive fallback.

Prompt sequence:
1. `Select planning track` (`quick_flow`, `bmad_method`, `enterprise`; default `bmad_method`).
2. `Project blast radius` (`low`, `medium`, `high`; default `medium`).
3. `How many external integrations?` (integer; default `1`).
4. `Risk factors` (comma-separated; default empty).
5. `Team size` (integer; default `2`).
6. `Domain` (string; default `general`).
7. `Compliance requirements` (comma-separated; default empty).

Fallback rules:
1. Apply the same mapping and tuning rules from sections 4 and 5.
2. Write `source.mode = manual` and `source.producer = interactive-fallback`.
3. Add warning: `BMAD unavailable; assessment derived from manual answers`.
4. In non-interactive mode, use defaults above and emit warning: `non-interactive fallback defaults used`.

Phase C note:
1. BMAD presence detection without full BMAD payload parsing should use `source.mode = bmad-detected`.
2. Full BMAD data extraction can promote mode semantics in a later phase.

## 7. `project.yaml` vs `assessment.yaml` Recommendation
Recommendation: keep two files.

Rationale:
1. `project.yaml` is stable runtime configuration and integration toggles (`agents`, `cost`, `integrations`, `verification`).
2. `assessment.yaml` is derived analysis/tuning output and should be regenerable without mutating operational config.
3. Separating reduces churn and merge conflicts during reassessment.
4. Keeps backward compatibility with existing scripts that already read `project.yaml`.

Minimal linkage contract:
```yaml
# in .spectra/project.yaml
assessment_ref: .spectra/assessment.yaml
effective_level: 3
effective_verification_intensity: high
```

## 8. Phase C Fixture Set (Verifier)
Required fixture files:
1. `fixtures/assessment/assessment-level0-quickflow.yaml`
2. `fixtures/assessment/assessment-level3-bmad-method.yaml`
3. `fixtures/assessment/assessment-level4-enterprise.yaml`
4. `fixtures/assessment/assessment-manual-no-bmad.yaml`
5. `fixtures/assessment/assessment-malformed-missing-level.yaml`
