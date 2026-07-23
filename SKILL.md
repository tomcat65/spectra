---
name: spectra
description: >
  AI-driven software engineering methodology (SPECTRA v5.5). Orchestrates
  multi-agent development: discovery, planning, building, verification,
  and institutional memory across the full project lifecycle.
  Use when: user says "start a new project", "build X feature", "initialize
  SPECTRA", "help me develop", or asks to run spectra-loop.
  Use when: user needs structured software development with planning, execution
  gates, and self-correcting verification loops.
  Do NOT use for: single-file edits, non-software tasks, or one-shot requests
  (use spectra-quick.sh for ad-hoc tasks).
compatibility: >
  Claude Code with Bash tools in WSL Ubuntu.
  Requires SPECTRA installation and .spectra/ directory in project.
  Install: git clone https://github.com/tomcat65/spectra && ./install.sh
metadata:
  version: "5.5"
  author: tomcat65
  framework: SPECTRA
  github: https://github.com/tomcat65/spectra
---

# SPECTRA — AI Software Engineering Methodology

Systematic Planning, Execution via Clean-context loops, Tracking & verification with Real-time Agent orchestration.

## 7-Phase Lifecycle

Discovery → Scale Assessment → Specification → Execution → Verification → Delivery → Retrospective

## Quick Start

```bash
spectra-doctor.sh  # report environment blockers and safety warnings
spectra-init.sh    # scaffold .spectra/ in your project
spectra-elicit.sh  # complete/check the goal contract before planning
spectra-loop.sh    # start the build loop
spectra-quick.sh   # ad-hoc single task (skips planning)
```

## Agents

| Agent | Model | Role |
|-------|-------|------|
| spectra-planner | opus | Planning artifacts (constitution, PRD, plan.md) |
| spectra-builder | opus | Implements one task per session from plan.md |
| spectra-verifier | opus | Independent 4-step verification plus optional runtime signal |
| spectra-auditor | haiku | Fast pre-flight Sign violation scanner |
| spectra-reviewer | sonnet | Adversarial cross-model plan validation |
| spectra-scout | haiku | Brownfield discovery and risk manifest |
| spectra-oracle | haiku | Failure classification (3 turns max) |

## Key Concepts

- **Signs** — Known bug patterns (10 active). See `guardrails-global.md`
- **Goal Contract** — Required decisions and measurable outcomes in `.spectra/goals.md`
- **Wiring Proof** — 5-check verification that code is actually connected
- **Runtime Probe** — Bounded endpoint/command evidence for infra and deploy tasks
- **CI Parity** — Local and GitHub lint call the same repository-owned gate
- **Clean Context** — Each builder session starts fresh, state lives in files
- **Scale Levels** — 0 (micro) to 4 (enterprise), right-sized planning depth
- **Feedback Loops** — Per-task metrics, adaptive retry, auto-profile selection from execution history

## Reference

- `SPECTRA_METHOD.md` — Full methodology reference
- `guardrails-global.md` — Active Signs and guardrails
- `agents/references/` — Signs taxonomy, failure types, report templates
- `docs/SPECTRA_IMPROVEMENT_PLAN.md` — Evidence gates for future rating promotion
