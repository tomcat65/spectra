---
name: spectra
description: >
  AI-driven software engineering methodology (SPECTRA v5.4). Orchestrates
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
  version: "5.4"
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
spectra-init    # scaffold .spectra/ in your project
spectra-loop    # start the build loop
spectra-quick   # ad-hoc single task (skips planning)
```

## Agents

| Agent | Model | Role |
|-------|-------|------|
| spectra-planner | opus | Planning artifacts (constitution, PRD, plan.md) |
| spectra-builder | opus | Implements one task per session from plan.md |
| spectra-verifier | opus | Independent 4-step verification with wiring proof |
| spectra-auditor | haiku | Fast pre-flight Sign violation scanner |
| spectra-reviewer | sonnet | Adversarial cross-model plan validation |
| spectra-scout | haiku | Brownfield discovery and risk manifest |
| spectra-oracle | haiku | Failure classification (3 turns max) |

## Key Concepts

- **Signs** — Known bug patterns (9 active). See `guardrails-global.md`
- **Wiring Proof** — 5-check verification that code is actually connected
- **Clean Context** — Each builder session starts fresh, state lives in files
- **Scale Levels** — 0 (micro) to 4 (enterprise), right-sized planning depth

## Reference

- `SPECTRA_METHOD.md` — Full methodology reference
- `guardrails-global.md` — Active Signs and guardrails
- `agents/references/` — Signs taxonomy, failure types, report templates
