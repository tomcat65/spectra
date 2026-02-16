# SPECTRA v4.1 Fix Brief — Post-Run Lessons

> Generated: 2026-02-11
> Source: First live SPECTRA Level 3 run on HB-APDAS Phase 8 (15 tasks, 8 completed before context limit)
> Repo: /home/tomcat65/.spectra (https://github.com/tomcat65/spectra)

## Run Summary
- **Project:** HB-APDAS Phase 8 (voice AI, Vapi Squads + Conv Intelligence + Eval Framework)
- **Level:** 3 (Agent Teams, parallel builders)
- **Result:** 8/15 tasks PASSED with commits, 2 in-progress when context limit hit
- **Positive:** Team prompt architecture works — proper build→verify cycles, parallel execution, signal writes
- **Negative:** 13 bugs discovered across scripts, agents, and UX

---

## Bug List (Priority Order)

### P0 — Blocking / Caused Failures

#### BUG #2: spectra-plan.sh stuffs 48KB+ into shell variable
- **File:** `bin/spectra-plan.sh` (line ~320-389)
- **Problem:** Entire BMAD content (PRD + architecture + stories + constitution) concatenated into `PLAN_PROMPT` variable, then passed as `claude -p "${PLAN_PROMPT}"`. Agent hangs for 10+ minutes, produces no output.
- **Fix:** Replace inline prompt injection with file-path-based approach. Pass only instructions and file paths to `-p`, let the planner agent use its Read/Grep/Glob tools to read files from disk.
- **Implementation:**
  ```bash
  # OLD (broken):
  PLAN_PROMPT="... ${PRD_CONTENT} ... ${ARCH_CONTENT} ... ${STORIES_CONTENT} ..."
  claude --agent spectra-planner -p "${PLAN_PROMPT}" > .spectra/plan.md.new
  
  # NEW (fixed):
  PLAN_PROMPT="OUTPUT COMPLETE RAW MARKDOWN TO STDOUT starting with '# SPECTRA Execution Plan'.
  No summary, no commentary, no permission requests.
  
  Read these files:
  $(for f in ${STORY_FILES}; do echo "- $f"; done)
  $([ -n "${PRD_FILE}" ] && echo "- ${PRD_FILE}")
  $([ -n "${ARCH_FILE}" ] && echo "- ${ARCH_FILE}")
  - .spectra/assessment.yaml
  - .spectra/constitution.md
  
  Generate Level ${PROJECT_LEVEL} canonical plan.md. ${LEVEL_INSTRUCTIONS}"
  claude --agent spectra-planner --output-format text -p "${PLAN_PROMPT}" > .spectra/plan.md.new
  ```

#### BUG #3: Planner agent produces summaries instead of raw markdown
- **File:** `~/.claude/agents/spectra-planner.md`
- **Problem:** Agent has `permissionMode: plan` (no Write tool). Script captures stdout via `>` redirect, but agent doesn't know it should dump raw markdown — produces summaries, asks for write permission, or generates commentary.
- **Fix:** Add explicit stdout instruction to agent definition:
  ```markdown
  ## Critical Output Rule
  You ALWAYS output raw markdown directly to stdout. Never summarize. Never ask for write permission.
  Never wrap output in code fences. Start your response with the first line of the document
  (e.g., `# SPECTRA Execution Plan`) and end with the last line. No preamble, no postamble.
  Your stdout IS the file content — the calling script captures it via redirect.
  ```

#### BUG #10: plan.md checkboxes never updated
- **File:** `bin/spectra-team-prompt.sh`
- **Problem:** After 8 tasks PASSED with commits, all checkboxes in plan.md still show `[ ]`. Lead agent wrote signals but never updated plan.md itself.
- **Fix:** Add explicit instruction in Phase 2 Step D (Parse Result):
  ```markdown
  ### Step D.1: Update Plan Checkpoint
  After PASS, update plan.md checkbox via Bash:
  ```bash
  sed -i 's/^- \[ \] NNN:/- [x] NNN:/' .spectra/plan.md
  ```
  After STUCK, update plan.md checkbox via Bash:
  ```bash
  sed -i 's/^- \[ \] NNN:/- [!] NNN:/' .spectra/plan.md
  ```
  This is MANDATORY. The plan.md checkboxes are the source of truth for resume.
  ```

#### BUG #11: Context limit exhausted at 200 turns
- **File:** `bin/spectra-loop-v3.sh`
- **Problem:** 200 max_turns is insufficient for 15-task Level 3 plans. Each task uses ~10-15 turns. 15 × 12 = 180 minimum, no room for retries.
- **Fix:** Scale max_turns dynamically based on task count:
  ```bash
  TASK_COUNT=$(grep -c '^\- \[ \] [0-9]' .spectra/plan.md)
  DYNAMIC_MAX_TURNS=$(( TASK_COUNT * 15 + 50 ))
  MAX_TURNS=${MAX_TURNS:-$DYNAMIC_MAX_TURNS}
  ```

#### BUG #12: Silent exit on context limit
- **File:** `bin/spectra-loop-v3.sh`
- **Problem:** When claude exits due to context limit, script exits silently. No indication of incomplete state.
- **Fix:** After claude exits, check for COMPLETE signal. If absent:
  ```bash
  if [[ ! -f "${SIGNALS_DIR}/COMPLETE" ]]; then
      DONE=$(grep -c '^\- \[x\]' .spectra/plan.md 2>/dev/null || echo 0)
      TOTAL=$(grep -c '^\- \[.\]' .spectra/plan.md 2>/dev/null || echo 0)
      echo "⚠  Session ended without COMPLETE signal (${DONE}/${TOTAL} tasks done)"
      echo "  Resume: spectra-loop --skip-planning --resume"
      write_signal "PHASE" "interrupted"
      write_signal "STATUS" "Session interrupted at ${DONE}/${TOTAL} tasks. Resume with --skip-planning."
      # Slack notification
      if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
          curl -s -X POST "${SLACK_WEBHOOK_URL}" \
              -d "{\"text\":\"⚠️ SPECTRA session interrupted: ${DONE}/${TOTAL} tasks complete. Resume needed.\"}" > /dev/null 2>&1
      fi
  fi
  ```

### P1 — UX / Usability

#### BUG #4: No progress indication during plan generation
- **File:** `bin/spectra-plan.sh`
- **Problem:** User sees blank screen for 5-10+ minutes while planner agent works.
- **Fix:** Add background progress indicator:
  ```bash
  # Start background progress indicator
  show_progress() {
      local pid=$1
      local steps=("Parsing stories" "Reading PRD" "Reading architecture" "Generating plan" "Generating plan" "Generating plan" "Validating")
      local pcts=(10 20 30 50 60 70 90)
      local i=0
      while kill -0 "$pid" 2>/dev/null; do
          if [[ $i -lt ${#steps[@]} ]]; then
              printf "\r  [%3d%%] %s..." "${pcts[$i]}" "${steps[$i]}"
              ((i++))
          else
              printf "\r  [%3d%%] Generating plan (still working)..." 80
          fi
          sleep 10
      done
      printf "\r  [100%%] Done.                              \n"
  }
  
  claude --agent spectra-planner --output-format text -p "${PLAN_PROMPT}" > .spectra/plan.md.new &
  CLAUDE_PID=$!
  show_progress $CLAUDE_PID
  wait $CLAUDE_PID
  ```
- **Slack:** Send notification at start and finish of plan generation.

#### BUG #6: No timeout on claude invocation
- **File:** `bin/spectra-plan.sh`
- **Problem:** If agent hangs, user must manually find and kill the process.
- **Fix:** Wrap claude call with timeout (default 5 minutes, configurable):
  ```bash
  PLAN_TIMEOUT=${PLAN_TIMEOUT:-300}
  timeout "${PLAN_TIMEOUT}" claude --agent spectra-planner --output-format text -p "${PLAN_PROMPT}" > .spectra/plan.md.new
  if [[ $? -eq 124 ]]; then
      echo "⚠  Plan generation timed out after ${PLAN_TIMEOUT}s. Try again or increase PLAN_TIMEOUT."
      exit 1
  fi
  ```

#### BUG #7: Silent failure on 0-byte output
- **File:** `bin/spectra-plan.sh`
- **Problem:** If claude errors out, `>` redirect creates 0-byte file and script may continue.
- **Fix:** Check file after generation:
  ```bash
  if [[ ! -s .spectra/plan.md.new ]]; then
      echo "⚠  Plan generation produced empty output. Claude may have errored."
      echo "  Check: claude --agent spectra-planner -p 'test' to verify agent works."
      rm -f .spectra/plan.md.new
      exit 1
  fi
  ```

#### BUG #8: File-ownership format mismatch
- **Files:** `~/.claude/agents/spectra-planner.md` AND `bin/spectra-plan-validate.sh`
- **Problem:** Validator expects `- owns: [file1, file2]` with brackets. Planner generates `- owns: file1, file2` without brackets. Also `(none)` vs `[]`.
- **Fix (both sides):**
  1. In planner agent: Add to instructions: "File-ownership lists MUST use square brackets: `- owns: [file1.py, file2.py]`. Use `[]` for empty lists, never `(none)`."
  2. In validator: Add normalization as fallback (accept both formats).

### P2 — Cosmetic / Branding

#### BUG #1: spectra-init.sh says v1.2
- **File:** `bin/spectra-init.sh`
- **Problem:** Version strings throughout say "v1.2" instead of "v4.1"
- **Fix:** `sed -i 's/v1\.2/v4.1/g' bin/spectra-init.sh`
- **Also update:** `project.yaml` template: `spectra_version: "4.1"`

#### BUG #9: spectra-loop-v3.sh naming
- **File:** `bin/spectra-loop-v3.sh`
- **Problem:** v3 in filename confuses users running v4.x
- **Fix:** Rename to `spectra-loop.sh`. Update symlink. Keep `spectra-loop-legacy.sh` as-is. Update all internal version strings to v4.1.

#### BUG #5: --dry-run still calls full agent
- **File:** `bin/spectra-plan.sh`
- **Problem:** `--dry-run` runs the full planner agent. Should preview the prompt only.
- **Fix:** Two modes:
  - `--dry-run` = run agent but print to stdout (current behavior, keep it)
  - `--show-prompt` = print assembled prompt WITHOUT invoking claude (new flag)

### P3 — Nice to Have

#### LESSON: Resume should reuse branch
- **File:** `bin/spectra-loop-v3.sh` (or new `spectra-loop.sh`)
- **Problem:** Each `--skip-planning` re-run creates a new `spectra/run-*` branch.
- **Fix:** Detect existing `spectra/run-*` branch and offer to reuse:
  ```bash
  EXISTING_BRANCH=$(git branch --list 'spectra/run-*' | tail -1 | tr -d ' ')
  if [[ -n "$EXISTING_BRANCH" ]]; then
      echo "  Found existing run branch: $EXISTING_BRANCH"
      echo "  Reuse? [Y/n]"
      read -r REUSE
      [[ "$REUSE" != "n" ]] && RUN_BRANCH="$EXISTING_BRANCH"
  fi
  ```

#### LESSON: Verifier should catch test ordering pollution
- **File:** `~/.claude/agents/spectra-verifier.md`
- **Fix:** Add to verification protocol: "Run the task's specific test file BOTH in isolation (`pytest tests/test_foo.py`) AND in full suite (`pytest tests/`). If isolation passes but full suite fails, flag as TEST_POLLUTION and report which test files interfere."

---

## Files to Modify

| File | Bugs Fixed |
|------|-----------|
| `bin/spectra-plan.sh` | #2, #4, #6, #7, #5 |
| `bin/spectra-loop-v3.sh` → `bin/spectra-loop.sh` | #9, #11, #12, resume lesson |
| `bin/spectra-init.sh` | #1 |
| `bin/spectra-team-prompt.sh` | #10 |
| `bin/spectra-plan-validate.sh` | #8 (fallback normalization) |
| `~/.claude/agents/spectra-planner.md` | #3, #8 |
| `~/.claude/agents/spectra-verifier.md` | test pollution lesson |
| `README.md` | Version references |

## Verification

After all fixes:
1. `bash -n` all .sh files
2. Run plan-validate fixtures: `spectra-plan-validate.sh --file fixtures/plan-bridge/valid-level*.md`
3. Test spectra-plan with a real BMAD project (use HB-APDAS bmad/ artifacts)
4. Test spectra-loop resume flow
5. Verify Slack notifications fire at milestones
