# BMAD -> SPECTRA Output Schema Contract (Draft)

**Status:** Draft for review (no implementation changes)  
**Owner lane:** codex (contract/verification)  
**Date:** 2026-02-10

## 1. Purpose
Define the interface contract between BMAD planning output and SPECTRA execution input, so adapter/bridge behavior is testable and deterministic.

This contract covers:
- `spectra-assess` adapter output (full assessment passthrough)
- `spectra-plan --from-bmad` bridge output (`plan.md` canonical task model)
- Phase 4.5 feedback object for planning artifact corrections

## 2. Core Requirements
1. Preserve full BMAD assessment context, not only track -> level.
2. Use one canonical task shape with explicit required fields:
- `Acceptance`
- `Wiring`
- `Max-iterations`
- `Status`
- `Level`
3. Generalize SIGN-005 conflict detection from file-level to scope-level.
4. Support Phase 4.5 planning corrections as a structured object.

## 3. Adapter Contract (`spectra-assess`)

### 3.1 Input
BMAD `*workflow-init` result plus project metadata.

### 3.2 Output Object
```json
{
  "assessment_id": "asmt_20260210_001",
  "generated_at": "2026-02-10T18:00:00Z",
  "bmad": {
    "track": "bmad-method",
    "workflow": "greenfield-service",
    "confidence": 0.86,
    "rationale": "multi-service backend with external integrations",
    "full_context": {
      "language": "typescript",
      "framework": "nestjs",
      "runtime": "node20",
      "domain": "fintech",
      "risk_factors": ["regulatory", "external-api-dependency"],
      "non_functional_drivers": ["availability", "auditability"],
      "team_topology": "single-team",
      "delivery_horizon": "4-8-weeks"
    }
  },
  "spectra": {
    "level": 3,
    "execution_mode": "teams",
    "risk_first": true
  }
}
```

### 3.3 Rules
1. `bmad.full_context` is mandatory and must be passed through intact.
2. `spectra.level` must include mapping rationale (traceable to BMAD assessment).
3. Any omitted `full_context` field is a contract failure.

## 4. Bridge Contract (`spectra-plan --from-bmad`)

### 4.1 Input Bundle
```json
{
  "assessment": { "...": "object from section 3" },
  "artifacts": {
    "constitution": "markdown",
    "prd": "markdown",
    "architecture": "markdown",
    "stories": [
      {
        "story_id": "ST-001",
        "title": "Implement customer onboarding",
        "acceptance_criteria": ["...", "..."],
        "dependencies": []
      }
    ]
  }
}
```

### 4.2 Canonical Task Model
```json
{
  "id": "001",
  "title": "Implement customer onboarding API",
  "Status": "todo",
  "Level": 3,
  "Acceptance": [
    "POST /onboarding validates required fields",
    "Happy path persists customer profile"
  ],
  "Files": ["src/onboarding/controller.ts", "src/onboarding/service.ts"],
  "Verify": "npm test -- onboarding",
  "Wiring": {
    "cli": ["npm run lint", "npm test -- onboarding"],
    "integration": [
      "controller -> service -> repository call chain asserted"
    ],
    "dependencies": ["zod", "prisma"]
  },
  "Risk": "medium",
  "Max-iterations": 8,
  "scope": {
    "repos": ["main"],
    "code_paths": ["src/onboarding/**"],
    "config_paths": ["prisma/schema.prisma"],
    "infra": [],
    "docs_sections": ["prd#onboarding", "architecture#onboarding-flow"],
    "external_contracts": ["customer-service:v1"]
  },
  "blocked_by": []
}
```

### 4.3 Plan Envelope
```json
{
  "plan_version": "v1",
  "project_level": 3,
  "assessment_context": { "...": "adapter output" },
  "tasks": ["...canonical task objects..."],
  "parallelism_assessment": {
    "independent_tasks": ["001", "003"],
    "sequential_dependencies": ["001->002", "002->004"],
    "recommendation": "TEAM_ELIGIBLE"
  }
}
```

## 5. Scope-Level Conflict Rules (SIGN-005 Generalized)
Conflict exists if two runnable tasks overlap in any scope dimension:
1. Same repo and intersecting `code_paths`.
2. Same `config_paths`.
3. Same infra target.
4. Same docs section.
5. Same external contract version.

If overlap exists and no dependency ordering is declared, bridge must fail validation.

## 6. Phase 4.5 Feedback Contract (Planning Artifact Correction)

### 6.1 Correction Object
```json
{
  "correction_id": "corr_20260210_017",
  "task_id": "004",
  "source": "spectra-verifier",
  "created_at": "2026-02-10T18:15:00Z",
  "target_artifact": "architecture",
  "target_ref": "architecture#event-ingestion-flow",
  "issue_type": "wiring_gap",
  "severity": "high",
  "evidence": {
    "verify_report": ".spectra/logs/task-004-verify.md",
    "failed_command": "npm test -- ingestion-integration",
    "observed_behavior": "handler bypasses normalization step"
  },
  "original_statement": "Pipeline is A->B->C",
  "proposed_correction": "Pipeline is A->B->B1(normalization)->C",
  "impact": {
    "requires_replan": true,
    "affected_tasks": ["005", "006"]
  },
  "approval_state": "pending_architect_review"
}
```

### 6.2 Rules
1. Phase 4.5 output is append-only; no silent mutation of planning artifacts.
2. Correction must reference concrete evidence (report path + failing command).
3. `requires_replan=true` requires explicit architect approval before task continuation.

## 7. Markdown Rendering Contract for `plan.md`
Canonical markdown task block:

```markdown
## Task 001: Implement customer onboarding API
- [ ] 001: Implement customer onboarding API
- Status: todo
- Level: 3
- Acceptance: POST /onboarding validates required fields; Happy path persists customer profile
- Files: src/onboarding/controller.ts, src/onboarding/service.ts
- Verify: `npm test -- onboarding`
- Wiring: CLI=npm run lint|npm test -- onboarding; Integration=controller->service->repository
- Risk: medium
- Max-iterations: 8
- Scope: repos=main; code=src/onboarding/**; config=prisma/schema.prisma; docs=prd#onboarding
```

## 8. Validation Checklist (Verifier Lane)
1. Full assessment passthrough object present.
2. Every task contains `Status`, `Level`, `Acceptance`, `Wiring`, `Max-iterations`, and `scope`.
3. Scope conflict detection passes for all parallel-eligible tasks.
4. Phase 4.5 correction object schema validates and links to evidence.
5. Markdown rendering round-trips to canonical model without field loss.

