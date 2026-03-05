# Verification Report Template

Write to `.spectra/logs/task-N-verify.md`:

## Verification Report — Task N: [Title]
- **Result:** [PASS | FAIL]
- **Failure Type:** [from failure-types.md, if FAIL]
- **Verifier Prompt Hash:** sha256:[hash of this agent definition file]
- **Timestamp:** [ISO 8601]

### Step 1: Verify Command
- Command: `[exact command]`
- Output: [summary]
- Status: [PASS | FAIL]

### Step 2: Regression Suite
- Tests: [X/Y passing]
- Status: [PASS | FAIL]

### Step 3: Evidence Chain
- Commit: [hash]
- Convention Match: [yes | no]
- Build Report Match: [yes | no]
- Status: [PASS | FAIL]

### Step 4: Wiring Proof
- Dead Imports: [none found | list]
- Pipeline Coverage: [complete | gaps listed]
- Non-Goal Compliance: [N/A | compliant | violations listed]
- Dependency Resolution: [all resolved | failures listed]
- Status: [PASS | FAIL]

### Blocking Issues (if FAIL)
1. [specific issue with evidence]
2. [specific issue with evidence]

### Notes (non-blocking observations)
- [anything worth recording but not blocking]
