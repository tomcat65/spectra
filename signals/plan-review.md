## Plan Review — Bug Fix Analysis: Bug 1 (Planner Output Format) and Bug 2 (Pre-commit Assertion Scope)
Verdict: APPROVED_WITH_WARNINGS
Reviewer Model: sonnet
Reviewer Prompt Hash: sha256:spectra-reviewer-agent-definition-2026-03-19
Timestamp: 2026-03-19T00:00:00Z

---

## Bug 1: Planner Output Format — bypassPermissions Fix

### Findings

**F1-1 (CONFIRMED SAFE — Q3): The Bash tool concern is real but bounded.**
The planner's YAML restricts tools to Read, Grep, Glob, Bash. `bypassPermissions`
removes the approval gate for each tool call. With Bash available, the planner CAN
execute destructive commands without prompts. However: the planner's system prompt
says "Research only — cannot modify source code" and the agent instructions contain
"You are a Planner... you generate planning artifacts." Bash with bypassPermissions
grants rm, git push, curl, etc. without any gate. The mitigation is that the planner
is Opus running a planning prompt — it would need to decide to be malicious or
hallucinate a destructive command. This is a trust-in-the-model assumption, not a
hard constraint.

RISK: If a prompt injection attack reaches the planner via a story file or discovery
report that contains adversarial content (e.g., a story file that says "first run
`rm -rf .`"), bypassPermissions removes the last human checkpoint. With `plan` mode,
that command would need approval. With `bypassPermissions`, it executes silently.

SEVERITY: Medium. Unlikely under normal use. Real attack surface if story files or
discovery.md are untrusted.

**F1-2 (REAL BUG IN DIAGNOSIS): The proposed fix may not solve the root cause.**
The analysis assumes the planner outputs conversational text because `plan` mode
causes approval prompts that interrupt the output stream. This is plausible but
unverified. The actual cause could be:
- The planner's "Critical Output Rule" is too late in its instructions and gets
  overridden by the model's default summarization behavior
- `--output-format text` is not sufficient to suppress markdown preamble when the
  model treats the task as "explaining what I'm about to do"
- The planner succeeds in generating a plan but then appends a confirmation message

If the root cause is instruction-following rather than permission prompts,
`bypassPermissions` fixes nothing. The conversational text will still appear.

RECOMMENDATION: Before shipping this fix, verify the root cause by testing with a
real planner invocation and checking WHETHER approval prompts actually appear in the
stdout stream. If no approval prompts are observed, the fix is the wrong remedy.

**F1-3 (TEST IMPACT — Q5): Test 5 in test-loop-planning.sh is safe.**
Test 5 (line 101) checks: `grep -qP 'spectra-planner.*plan\.md\.new'`
The proposed change preserves both `spectra-planner` and `plan.md.new` in the
invocation. The added flag `--permission-mode bypassPermissions` appears between
them, so the grep still matches. Test 5 will NOT break.

**F1-4 (SCOUT PARITY — Q2): The scout invocation at line 84 has a DIFFERENT risk profile.**
The planner generates plan.md — a planning artifact. The scout generates discovery.md
— also a planning artifact. Both use `plan` mode + stdout redirect.

However, the scout is haiku, not opus. Haiku is cheaper and faster, but the
trust-in-the-model argument for bypassPermissions is weaker for a cheaper, smaller
model. Additionally, the scout invocation at line 84 already has `2>/dev/null` which
discards stderr, so if the scout emits permission prompts to stderr, those are already
silenced. The stdout redirect captures the report. The question is whether permission
prompts appear on STDOUT, not stderr.

If permission prompts go to stderr (which is the standard Claude CLI behavior), the
scout's existing `2>/dev/null` already suppresses them from contaminating the output
file. Adding bypassPermissions to the scout would be consistent but the failure mode
differs. Verify which stream permission prompts use before applying the scout fix.

**F1-5 (YAML VS CLI — Q4): Only update the CLI invocation, not the YAML.**
Changing `permissionMode: plan` in the YAML affects ALL invocations, including
direct user invocations via `claude --agent spectra-planner`. The plan permission
mode is a useful safety guarantee when a user runs the planner interactively. The
CLI override is the right approach: it scopes the permission bypass to the automated
capture path only, preserving the interactive safety checkpoint.

**F1-6 (MISSING: output validation after bypassPermissions)**
Even after the fix, the post-generation check at line 488 only validates non-empty
output (`[[ ! -s .spectra/plan.md.new ]]`). If the planner outputs a permission
acknowledgment ("I'll proceed without asking for confirmation") as its first line
before the plan, the file is non-empty and passes the check — but plan-validate.sh
will then reject it. The fix to the root problem exists downstream (the validator),
but there is no explicit check that the FIRST LINE of plan.md.new is `# SPECTRA`
or a valid plan header. This means a broken run still fails, just later and with a
less informative error message.

---

## Bug 2: Pre-commit Assertion Scope Fix

### Findings

**F2-1 (CORRECT DIAGNOSIS, INCOMPLETE FIX — Q1): Scoping to [x] tasks only creates a false-pass gap.**
The proposed fix scopes Section 5 assertions to tasks marked `[x]`. For a task
currently executing (in-progress, marked `[ ]`), its own assertions would NOT be
evaluated at wiring-gate time. This means: a builder could complete a task, the
wiring gate runs, and the task's own GREP/CALLSITE assertions are skipped because
the checkbox hasn't been marked `[x]` yet.

The wiring gate runs BEFORE the verifier marks the task complete (the loop marks
`[x]` only on PASS). So "scope to [x] AND current task" is the correct definition.
The proposal acknowledges this in the question but the proposed fix says "scope to
[x] tasks". The answer to Q1 is: NO, [x]-only is insufficient. Must include current
task.

**F2-2 (UNADDRESSED — Q2): Plan header assertions have no task anchor.**
Section 5 reads ALL assertions matching the pattern from the entire plan.md file.
If a plan has global wiring assertions in a header section (not under any `## Task`
block), the scoping logic must define what "belongs to" a task. If header assertions
are always evaluated, they may reference files that don't exist yet. If they're
dropped, they may never be evaluated. The fix proposal does not define this case.

**F2-3 (REAL RISK — Q6): Scoping too narrowly creates false-pass scenarios.**
Consider a scenario: Task 3 has a NOT_EXISTS assertion on a file that Task 5 will
create. At Task 3 time, the file doesn't exist — PASS. At commit time after Task 5,
the pre-commit hook (scoped to [x] tasks) re-evaluates Task 3's assertion — but the
file now exists — FAIL. This is correct behavior. But the proposal changes the
pre-commit to scope only to [x] tasks. If Task 3 is already [x] when Task 5 creates
the forbidden file, the pre-commit hook will catch it. That part is fine.

However: the loop's wiring gate (loop-wiring.sh line 22) runs at the END of each
task, after git add -A. With `--task N` scoping, it only evaluates task N's
assertions plus [x] tasks. A NOT_EXISTS assertion from a PRIOR completed task would
be re-evaluated at each subsequent task's wiring gate. That's correct. The risk is
actually the OPPOSITE case: if assertions are scoped too tightly, an assertion from
task N that should catch a regression introduced in task M will not fire during task
M's wiring gate.

**F2-4 (STUCK TASKS — Q5): [!] task assertions should be evaluated.**
A stuck task is one that attempted execution and failed. Its assertions should still
be evaluated — they represent wiring requirements that must hold even if the task
couldn't complete. Excluding [!] from assertion scope could hide wiring violations
from half-completed stuck tasks. The fix must specify that [!] assertions are
included in scope (equivalent to completed for verification purposes).

**F2-5 (STANDALONE USE CASE — Q4): The --task parameter breaks the documented standalone contract.**
When no `--task` is given, the proposal evaluates only [x] tasks. But in standalone
use (manual `spectra-verify-wiring.sh .`), the user's intent is to verify the
CURRENT state of the project. A user running this manually after building task 4 of
8 would see only tasks 1-4 evaluated. They would NOT see failures from tasks 5-8
assertions even if they happened to create files that conflict. This is a behavior
change with no warning. The help text (`--help` at line 16) would need updating, and
a `--all` flag should be provided for users who want the original all-assertions
behavior.

**F2-6 (IMPLEMENTATION GAP): loop-wiring.sh does not pass task_id to the script.**
loop-wiring.sh line 22 calls `"${SPECTRA_HOME}/bin/spectra-verify-wiring.sh" .`
with no task scoping. The proposed fix says "update loop-wiring.sh to pass --task
$task_id." The function signature at line 11 accepts `local task_id="$1"` — so the
task_id IS available. The change is mechanical but it IS a required wiring change
that needs a test verifying the argument is passed. Without the test, this is a
wiring gap under SIGN-001.

**F2-7 (REGRESSION TEST SPECIFICATION IS INCOMPLETE):**
The proposal specifies a multi-task plan test where future tasks have assertions on
non-existent files. That tests the false-failure case. It does NOT test:
- That [x] task assertions ARE still evaluated (false-pass prevention)
- That the current in-progress task's assertions ARE evaluated
- That [!] task assertions are included
- That plan-header assertions are handled consistently

The regression test spec needs four cases, not one.

**F2-8 (PRE-COMMIT HOOK RE-ENABLE IS PREMATURE):**
The pre-commit hook comment (hooks/pre-commit line 5-9) explicitly notes it was
patched 2026-03-19 because the wiring script evaluates ALL assertions including
unbuilt tasks. The proposed fix adds task scoping to resolve this. But the pre-commit
hook has no access to "which task is currently in progress" — git hooks don't receive
SPECTRA task context. The proposed "when no --task is given, only evaluate [x] tasks"
behavior makes the pre-commit hook safe to re-enable ONLY if the [x]-scoped behavior
is sufficient for pre-commit purposes. However, this means the pre-commit hook will
NEVER evaluate the current (in-progress) task's assertions at commit time — only the
loop's wiring gate does. This is an acceptable split, but it must be explicitly
documented. The hook re-enable is safe, but document that the hook is a regression
guard ([x] tasks only) while the loop gate is the completeness check ([x] + current).

---

### Warnings

W1: The bypassPermissions fix for Bug 1 must be verified to actually address the
root cause. If permission prompts do not appear on stdout, the fix is a no-op that
adds an unnecessary security relaxation. Verify empirically before shipping.

W2: The scout invocation at line 84 already discards stderr via `2>/dev/null`. If
Claude CLI permission prompts go to stderr (not stdout), the scout problem may not
exist. Audit the output streams before applying bypassPermissions to the scout.

W3: Bug 2 fix must scope assertions to "[x] tasks + current task" not just "[x]
tasks" — the current task's assertions must be evaluated during its own wiring gate
or the gate has no value for the task being built.

W4: [!] (stuck) task assertions must be included in scope. Excluding them creates
a silent regression gap for partially-completed work.

W5: The standalone spectra-verify-wiring.sh behavior change (no --task now evaluates
only [x] tasks, not all tasks) must be documented in --help output and a --all flag
provided to restore original behavior for manual use.

W6: The regression test spec for Bug 2 needs four cases (false-failure, false-pass
prevention, current-task inclusion, stuck-task inclusion) not one.

### Enforced

These warnings should be appended to guardrails.md before executing either fix:

> GUARDRAIL: When adding bypassPermissions to any agent invocation that also exposes
> Bash tool access, require empirical verification that permission prompts actually
> appear on stdout (not stderr) before treating the fix as addressing the root cause.

> GUARDRAIL: spectra-verify-wiring.sh --task scoping must include [x] tasks, [!]
> tasks, AND the specified current task. Scoping to [x]-only silently skips the
> task being verified.

> GUARDRAIL: Any change to spectra-verify-wiring.sh standalone behavior (no --task
> flag) must preserve the --all flag to restore original all-assertions behavior for
> manual debugging.
