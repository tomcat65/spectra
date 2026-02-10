# Phase D: `spectra-plan --from-bmad` — Implementation Proposal

**Status:** Proposal for architect approval
**Author:** claude-cli (builder)
**Date:** 2026-02-10
**References:**
- `proposals/bmad-output-schema.md` (codex's contract)
- `proposals/phase-d-verifier-checklist.md` (codex's D1-D10 gate)
- `proposals/plan-bridge-acceptance-fixtures.md` (fixture design)
- `bin/spectra-plan.sh` (current implementation)
- `bin/spectra-plan-validate.sh` (v4 canonical schema validator)

---

## 1. Problem

`spectra-plan` currently reads only `.spectra/stories/*.md` and sends them to the planner agent for plan.md generation. Projects using BMAD have richer artifacts (PRD, architecture, stories) in a `bmad/` or `.bmad/` directory that contain acceptance criteria, architectural decisions, component structures, and dependency information that should inform plan generation.

Phase C's `spectra-assess` already detects BMAD presence and sets `source.mode: bmad-detected` with the warning: *"Full artifact parsing requires spectra-plan --from-bmad (Phase D)"*. This phase fulfills that promise.

## 2. Design Decisions

### 2.1 LLM-Assisted Parsing (not pure regex)

BMAD artifacts are free-form markdown. Pure bash regex would be brittle and break on format variations. Instead, `--from-bmad` collects all BMAD artifacts as context and sends them to `spectra-planner` with an augmented prompt. This is the same pattern as the existing story-based flow but with richer context.

**Rationale:** codex's D8/D9 tests explicitly require "fuzzy parsing robustness" — two PRD format variants must both produce valid output. Only LLM parsing can handle this reliably.

### 2.2 BMAD Artifact Discovery (3-tier, mirroring assess)

```
Tier 1: bmad/ directory (conventional)
Tier 2: .bmad/ directory (hidden)
Tier 3: --bmad-dir PATH (explicit override)
```

Within the discovered directory, look for:
- `prd.md` or `PRD.md` or `*prd*.md` — Product requirements
- `architecture.md` or `*arch*.md` — Architecture document
- `stories/*.md` or `*.story.md` — Individual stories

If no stories are found in the BMAD dir, fall back to `.spectra/stories/*.md` (hybrid mode).

### 2.3 Graceful Degradation (codex's 4.3 gate)

| Missing Artifact | Behavior | Exit Code |
|-----------------|----------|-----------|
| Stories (none anywhere) | Hard FAIL with actionable error | 1 |
| PRD | WARN, proceed (stories provide AC context) | 0 |
| Architecture | WARN, proceed for L0-L2; WARN for L3+ (file ownership will be best-effort) | 0 |

### 2.4 `--dry-run` Support (codex's 4.4 gate)

`--dry-run` prints the generated plan to stdout and does NOT write `.spectra/plan.md`. Exit code reflects generation + validation success/failure.

### 2.5 Level Source Priority

1. `--level N` flag (explicit override, highest priority)
2. `.spectra/assessment.yaml` `spectra.level` field
3. `.spectra/project.yaml` `level` field
4. Default: 1

This matches the existing priority chain in `spectra-plan.sh`.

## 3. Implementation Plan

### 3.1 Modified File: `bin/spectra-plan.sh` (~80 lines added)

Add three new flags to argument parser:
```
--from-bmad       Enable BMAD artifact bridge (main feature)
--bmad-dir PATH   Explicit BMAD directory path
--dry-run         Print plan to stdout, don't write file
```

New code blocks:

**A. BMAD directory discovery** (~15 lines)
```bash
BMAD_DIR=""
FROM_BMAD=false
DRY_RUN=false

# In arg parser:
--from-bmad)  FROM_BMAD=true; shift ;;
--bmad-dir)   BMAD_DIR="$2"; FROM_BMAD=true; shift 2 ;;
--dry-run)    DRY_RUN=true; shift ;;
```

**B. BMAD artifact collection** (~25 lines)
```bash
if [[ "${FROM_BMAD}" == true ]]; then
    # Auto-discover BMAD dir if not explicit
    if [[ -z "${BMAD_DIR}" ]]; then
        if [[ -d "bmad" ]]; then BMAD_DIR="bmad"
        elif [[ -d ".bmad" ]]; then BMAD_DIR=".bmad"
        else echo "Error: --from-bmad but no bmad/ or .bmad/ found. Use --bmad-dir."; exit 1
        fi
    fi

    # Collect PRD
    PRD_CONTENT=""
    PRD_FILE=$(find "${BMAD_DIR}" -maxdepth 1 -iname "*prd*" -name "*.md" | head -1)
    if [[ -n "${PRD_FILE}" ]]; then
        PRD_CONTENT=$(cat "${PRD_FILE}")
    else
        echo "  WARN: No PRD found in ${BMAD_DIR}. Proceeding without PRD context."
    fi

    # Collect Architecture
    ARCH_CONTENT=""
    ARCH_FILE=$(find "${BMAD_DIR}" -maxdepth 1 -iname "*arch*" -name "*.md" | head -1)
    if [[ -n "${ARCH_FILE}" ]]; then
        ARCH_CONTENT=$(cat "${ARCH_FILE}")
    else
        echo "  WARN: No architecture doc in ${BMAD_DIR}."
    fi

    # Collect Stories (BMAD dir first, fallback to .spectra/stories)
    STORIES_CONTENT=""
    BMAD_STORIES=$(find "${BMAD_DIR}" -name "*.md" -path "*/stories/*" -o -name "*.story.md" | sort)
    if [[ -z "${BMAD_STORIES}" ]]; then
        BMAD_STORIES=$(find "${BMAD_DIR}" -name "*.md" ! -iname "*prd*" ! -iname "*arch*" ! -name "README.md" | sort)
    fi
    STORY_COUNT=$(echo "${BMAD_STORIES}" | grep -c . || echo "0")

    if [[ "${STORY_COUNT}" -eq 0 ]]; then
        # Fallback: .spectra/stories/
        BMAD_STORIES=$(find .spectra/stories -name "*.md" -not -name ".gitkeep" 2>/dev/null | sort)
        STORY_COUNT=$(echo "${BMAD_STORIES}" | grep -c . || echo "0")
    fi

    if [[ "${STORY_COUNT}" -eq 0 ]]; then
        echo "Error: No stories found in ${BMAD_DIR}/ or .spectra/stories/. Cannot generate plan."
        exit 1
    fi

    for story in ${BMAD_STORIES}; do
        STORIES_CONTENT="${STORIES_CONTENT}
--- $(basename "$story") ---
$(cat "$story")
"
    done
fi
```

**C. Augmented planner prompt for BMAD mode** (~30 lines)

When `FROM_BMAD=true`, the prompt includes additional context sections:

```bash
BMAD_CONTEXT=""
if [[ "${FROM_BMAD}" == true ]]; then
    BMAD_CONTEXT="
## Product Requirements Document (from BMAD)
${PRD_CONTENT:-Not available — derive acceptance criteria from stories alone.}

## Architecture Document (from BMAD)
${ARCH_CONTENT:-Not available — derive file paths from stories and project conventions.}

## BMAD Bridge Instructions
You are generating a plan from BMAD artifacts. Additional rules:
1. Extract acceptance criteria from PRD user stories AND from individual story files.
2. If architecture.md defines component structure, use it for File-ownership derivation.
3. If architecture.md defines API contracts/data models, reference them in Wiring-proof Integration.
4. Map PRD non-functional requirements to Risk assessment (security/performance concerns = high risk).
5. Each BMAD story should map to 1-3 plan tasks (split by logical unit of work).
6. Preserve BMAD story IDs in task titles where possible (e.g., 'US-1: ...' -> 'Task 001: US-1 ...').
"
fi
```

The BMAD context is injected into the existing PLAN_PROMPT between the Constitution and Stories sections.

**D. Dry-run output routing** (~10 lines)

```bash
# After generation + validation:
if [[ "${DRY_RUN}" == true ]]; then
    cat .spectra/plan.md.new
    rm .spectra/plan.md.new
    echo "" >&2
    echo "  [dry-run] Plan printed to stdout. No files modified." >&2
else
    mv .spectra/plan.md.new .spectra/plan.md
    # ... existing success output
fi
```

### 3.2 Test Fixtures: `fixtures/bmad-bridge/` (NEW)

Create golden BMAD artifact sets that codex can use for D1-D10 verification:

```
fixtures/bmad-bridge/
├── golden-full/                    # D1: full BMAD set (PRD+Arch+Stories)
│   ├── bmad/
│   │   ├── prd.md                 # Sample PRD with 3 user stories
│   │   ├── architecture.md        # Component structure + tech stack
│   │   └── stories/
│   │       ├── 001-auth-setup.md
│   │       └── 002-api-endpoints.md
│   └── .spectra/
│       ├── assessment.yaml        # Level 3 assessment
│       └── project.yaml
├── minimal-stories-only/           # D5: Missing PRD — stories only
│   ├── bmad/
│   │   └── stories/
│   │       └── 001-simple-feature.md
│   └── .spectra/
│       ├── assessment.yaml        # Level 1 assessment
│       └── project.yaml
├── no-stories/                     # D4: no stories at all → FAIL
│   ├── bmad/
│   │   ├── prd.md
│   │   └── architecture.md
│   └── .spectra/
│       └── project.yaml
├── level0-assessment/              # D2: Level 0 → minimal fields
│   ├── bmad/
│   │   └── stories/
│   │       └── 001-hotfix.md
│   └── .spectra/
│       ├── assessment.yaml        # Level 0 assessment
│       └── project.yaml
├── level3-with-arch/               # D3: Level 3 → Wiring + Ownership + Parallelism
│   ├── bmad/
│   │   ├── prd.md
│   │   ├── architecture.md
│   │   └── stories/
│   │       ├── 001-service-a.md
│   │       ├── 002-service-b.md
│   │       └── 003-shared-config.md
│   └── .spectra/
│       ├── assessment.yaml        # Level 3 assessment
│       └── project.yaml
└── manifest.json                   # Fixture expectations for each scenario
```

### 3.3 Signal File: RECONCILE (Phase 4.5 Infrastructure)

Per codex's fixture F-004, define the reconciliation signal spec. This is infrastructure only — the actual feedback loop runs in a later phase.

Create `.spectra/signals/RECONCILE` when the planner detects assessment drift:

```
# Written by spectra-plan when assessment.yaml tuning != plan defaults
signal: RECONCILE
timestamp: 2026-02-10T20:30:00Z
reason: assessment_drift
details: "assessment.yaml retry_budget=4 but plan generated with Max-iterations=5 for 2 tasks"
```

This is a **write-only signal** for now — no consumer reads it in Phase D. It establishes the contract for Phase 4.5's correction loop.

## 4. Files Changed

| File | Action | Lines |
|------|--------|-------|
| `bin/spectra-plan.sh` | Modified | +80 |
| `fixtures/bmad-bridge/golden-full/bmad/prd.md` | New | ~40 |
| `fixtures/bmad-bridge/golden-full/bmad/architecture.md` | New | ~30 |
| `fixtures/bmad-bridge/golden-full/bmad/stories/001-auth-setup.md` | New | ~15 |
| `fixtures/bmad-bridge/golden-full/bmad/stories/002-api-endpoints.md` | New | ~15 |
| `fixtures/bmad-bridge/golden-full/.spectra/assessment.yaml` | New | ~25 |
| `fixtures/bmad-bridge/golden-full/.spectra/project.yaml` | New | ~15 |
| `fixtures/bmad-bridge/minimal-stories-only/...` | New | ~30 |
| `fixtures/bmad-bridge/no-stories/...` | New | ~20 |
| `fixtures/bmad-bridge/level0-assessment/...` | New | ~25 |
| `fixtures/bmad-bridge/level3-with-arch/...` | New | ~60 |
| `fixtures/bmad-bridge/manifest.json` | New | ~50 |

**Total: ~1 modified file + ~15 new fixture files, ~400 lines**

## 5. Open Questions for Architect

### Q1: BMAD story-to-task mapping ratio
Should we enforce 1:1 (each BMAD story = exactly 1 plan task) or allow 1:N (planner splits complex stories)?

**My recommendation:** Allow 1:N. The planner prompt says "split by logical unit of work." Codex's D1 test checks valid output, not cardinality.

### Q2: Architecture-derived file ownership for Level 3+
When architecture.md defines component structure (e.g., `src/auth/`, `src/api/`), should the bridge prompt instruct the planner to derive `owns:` from these paths, or leave ownership as best-effort?

**My recommendation:** Instruct the planner to derive from architecture when available, with a "best-effort" caveat. The validator will catch real SIGN-005 violations.

### Q3: RECONCILE signal — write in this phase or defer?
codex's F-004 defines the Phase 4.5 correction object. Should we implement the signal file write in Phase D, or just document the spec and defer implementation?

**My recommendation:** Write the signal file infrastructure (the signal write) in Phase D. It's ~10 lines, establishes the contract, and satisfies F-004's fixture expectation for the "correction object exists" test. The consumer that reads it is a later phase.

### Q4: --from-bmad without assessment.yaml
If `--from-bmad` is called but no `assessment.yaml` exists (user skipped `spectra-assess`), should we auto-run assessment or hard-fail?

**My recommendation:** Soft warn + default to Level 2 (bmad_method without triggers). Auto-running assess would be surprising side-effect behavior. The user can always run `spectra-assess` first.

## 6. Verification Alignment

Mapping to codex's D1-D10 gate:

| Test | Fixture | Coverage |
|------|---------|----------|
| D1 | `golden-full/` | Full BMAD → valid plan + validator PASS |
| D2 | `level0-assessment/` | Level 0 → minimal fields |
| D3 | `level3-with-arch/` | Level 3 → Wiring + Ownership + Parallelism |
| D4 | `no-stories/` | Missing stories → exit 1 |
| D5 | `minimal-stories-only/` | Missing PRD → warn + PASS |
| D6 | Architecture missing | `golden-full/` with arch removed → deterministic |
| D7 | Any fixture with `--dry-run` | stdout + no file write |
| D8/D9 | Fuzzy PRD | Covered by LLM parsing (two PRD variants in golden-full) |
| D10 | Overlap stress | `level3-with-arch/` stories with shared files |

## 7. Estimated Cost

Single `claude --agent spectra-planner` invocation per plan generation. BMAD context adds ~500-2000 tokens to the prompt (PRD + architecture text). Well within per-task budget.
