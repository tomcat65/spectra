# SPECTRA Improvement Plan

## Honest Baseline

SPECTRA is rated **7/10** at the start of this program. It is useful on trusted
WSL workstations and has strong workflow discipline, but test volume alone does
not prove autonomous engineering reliability. Promotion requires measured
reductions in false completion, false STUCK outcomes, environment failures, and
human rescue—not another feature count.

## Promotion Gates

SPECTRA may claim **8/10** only after all of these are true:

1. Local and GitHub lint execute the same repository-owned implementation.
2. A preflight doctor reports required, recommended, and unsafe conditions in
   both human-readable and machine-readable form.
3. Negative-path tests prove parity checks reject rogue/missing modules,
   duplicate wiring, and unjustified ShellCheck suppressions.
4. Runtime probes can prove the observed deployment belongs to the intended
   source revision, not merely that an endpoint returns 200.
5. Task, verdict, retry, and signal state have one typed canonical model with a
   backwards-compatible migration path.
6. A controlled corpus of at least ten representative projects records human
   interventions, false-STUCK rate, first-pass rate, elapsed time, and cost
   against a simpler agent-plus-CI baseline.

SPECTRA may claim **9/10** only when the benchmark shows a material improvement
without weaker correctness, security, or release evidence. A 10/10 claim is not
credible for an evolving autonomous engineering system.

## Execution Program

### P0 — Trust and Parity (execute now)

- Replace duplicated workflow lint logic with one canonical repository script.
- Add a doctor that distinguishes hard blockers from optional capabilities and
  exposes JSON for automation.
- Add deterministic failure-injection tests for parity and doctor behavior.
- Gate: focused tests, ShellCheck ratchet, and the complete aggregate suite pass.

### P1 — Typed State Core

- Define a versioned state schema for task status, verdict, failure type,
  retries, signals, and evidence references.
- Make Markdown a rendered/operator-facing view rather than the source parsed
  by multiple regular expressions.
- Migrate one state transition at a time with dual-read comparison; never
  perform a flag-day rewrite.
- Gate: golden replay of existing plans and checkpoints yields identical task
  selection and retry outcomes.

### P2 — Deployment Provenance and Safer Runtime Evidence

- Add expected revision/artifact identity assertions to runtime probes.
- Separate endpoint checks from trusted smoke commands and record bounded,
  redacted evidence.
- Gate: fixtures reject a healthy endpoint serving the wrong revision and
  classify timeouts, authentication failures, and assertion failures distinctly.

### P3 — Real Elicitation

- Add an interactive question loop that identifies ambiguous success criteria,
  conflicting constraints, unresolved decisions, and unowned approvals.
- Keep deterministic validation as the final gate; an LLM interview cannot
  waive structural completeness.
- Gate: ambiguity fixtures require resolution and completed contracts remain
  idempotent.

### P4 — Controlled Benchmark

- Run SPECTRA and a minimal baseline against the same pinned repository/tasks.
- Store immutable task definitions, model/provider/version, cost, elapsed time,
  interventions, test evidence, and final diff review.
- Publish the raw results, including regressions and failures. Do not promote
  the rating from anecdotal wins.

## Stop Rules

- Do not combine P1–P4 into one pull request.
- Do not increase permissions or production access to improve benchmark scores.
- Do not count structural grep assertions as end-to-end behavioral evidence.
- Do not change the public rating until its promotion gates are demonstrated.
