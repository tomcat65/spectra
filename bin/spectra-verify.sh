#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v1.2 Verification Gate                                  ║
# ║  4-Step Audit: Verify → Regression → Evidence Chain → Wiring     ║
# ║  Auto-logs PASS/FAIL to lessons-learned.md                       ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-verify [--task N] [--linear] [--slack] [--no-wiring-proof]
#
# This script provides automated verification as a complement to the
# spectra-verifier subagent. It can run standalone or as a pre-check.

SPECTRA_HOME="${HOME}/.spectra"
SPECTRA_DIR=".spectra"
LOGS_DIR="${SPECTRA_DIR}/logs"

USE_LINEAR=false
USE_SLACK=false
USE_WIRING_PROOF=true
GRADUATED=false
FULL_SWEEP=false
TASK_OVERRIDE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --task)            TASK_OVERRIDE="$2"; shift 2 ;;
        --linear)          USE_LINEAR=true; shift ;;
        --slack)           USE_SLACK=true; shift ;;
        --no-wiring-proof) USE_WIRING_PROOF=false; shift ;;
        --graduated)       GRADUATED=true; shift ;;
        --full-sweep)      FULL_SWEEP=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA v1.2 Verification Gate

Usage: spectra-verify [OPTIONS]

Options:
  --task N             Verify specific task number
  --linear             Update Linear on PASS/FAIL
  --slack              Send Slack notification on PASS/FAIL
  --no-wiring-proof    Skip wiring proof checks (not recommended)
  --graduated          Auto-determine verification depth by task position
  --full-sweep         Full 4-step audit + cross-task wiring proof (final task)
  -h, --help           Show this help

4-Step Audit:
  1. Task verify command — exact CLI command from plan.md
  2. Full regression suite — all tests must pass
  3. Evidence chain — git commit matches task convention
  4. Wiring proof — dead imports, pipeline coverage, dependencies
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Verify project
if [[ ! -f "${SPECTRA_DIR}/plan.md" ]]; then
    echo "Error: No .spectra/plan.md found."
    exit 1
fi

mkdir -p "${LOGS_DIR}"

# Source env
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# ── Find task to verify ──
if [[ -n "$TASK_OVERRIDE" ]]; then
    TASK_ID="$TASK_OVERRIDE"
    TASK_LINE=$(grep -n "Task ${TASK_ID}" "${SPECTRA_DIR}/plan.md" | head -1 | cut -d: -f1 || echo "")
else
    # Find most recently checked task
    LAST_CHECKED=$(grep -n '^\- \[x\]' "${SPECTRA_DIR}/plan.md" | tail -1 || echo "")
    if [[ -z "$LAST_CHECKED" ]]; then
        echo "  No completed tasks to verify."
        exit 0
    fi
    TASK_LINE=$(echo "$LAST_CHECKED" | cut -d: -f1)
    TASK_ID=$(sed -n "1,${TASK_LINE}p" "${SPECTRA_DIR}/plan.md" | grep -oP 'Task \K\d+' | tail -1 || echo "0")
fi

# ── Graduated verification: determine depth ──
VERIFICATION_DEPTH="full"
if [[ "$GRADUATED" == true ]]; then
    TOTAL_TASKS=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null || echo "0")
    # Find position of current task among all tasks
    TASK_POSITION=$(grep -n '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | grep -n "Task.*${TASK_ID}\|${TASK_ID}:" | head -1 | cut -d: -f1 || echo "$TOTAL_TASKS")

    if [[ "$TASK_POSITION" -eq "$TOTAL_TASKS" ]]; then
        VERIFICATION_DEPTH="full-sweep"
        FULL_SWEEP=true
    else
        # Check if this task modifies files also modified by prior tasks
        TASK_FILES=$(sed -n "/Task ${TASK_ID}/,/^## Task/p" "${SPECTRA_DIR}/plan.md" 2>/dev/null | grep -oP 'owns:\s*\K.*' | tr -d '[]' | tr ',' '\n' | xargs || echo "")
        FILE_OVERLAP=false
        for f in $TASK_FILES; do
            # Check if any prior completed task also owns this file
            if sed -n "1,/Task ${TASK_ID}/p" "${SPECTRA_DIR}/plan.md" 2>/dev/null | grep -q "$f" 2>/dev/null; then
                FILE_OVERLAP=true
                break
            fi
        done
        if [[ "$FILE_OVERLAP" == true ]]; then
            VERIFICATION_DEPTH="full"
        else
            VERIFICATION_DEPTH="graduated"
            USE_WIRING_PROOF=false
        fi
    fi
fi

if [[ "$FULL_SWEEP" == true ]]; then
    VERIFICATION_DEPTH="full-sweep"
    USE_WIRING_PROOF=true
fi

echo "╔══════════════════════════════════════════╗"
echo "║  SPECTRA Verification — Task ${TASK_ID}            ║"
echo "╚══════════════════════════════════════════╝"
echo "  Verification Depth: ${VERIFICATION_DEPTH}"

# ── Extract verify command from plan.md ──
VERIFY_CMD=""
# Look in lines following the task header for Verify: `command`
TASK_SECTION=$(sed -n "/Task ${TASK_ID}/,/^## Task/p" "${SPECTRA_DIR}/plan.md" | head -20)
VERIFY_CMD=$(echo "$TASK_SECTION" | grep -oP '(?:Verify|verify):\s*`\K[^`]+' | head -1 || true)

VERIFY_PASS=true
FAIL_REASONS=""
FAILURE_TYPE=""

# ══════════════════════════════════════════
# Step 1: Task Verify Command
# ══════════════════════════════════════════
echo "  [1/4] Task verify command..."

if [[ -z "$VERIFY_CMD" ]]; then
    echo "  ⚠  No verify command found for Task ${TASK_ID}. Skipping step 1."
else
    echo "        Command: ${VERIFY_CMD}"
    set +e
    VERIFY_OUTPUT=$(eval "$VERIFY_CMD" 2>&1)
    VERIFY_EXIT=$?
    set -e

    if [[ $VERIFY_EXIT -ne 0 ]]; then
        VERIFY_PASS=false
        FAIL_REASONS="${FAIL_REASONS}\n  - Step 1 FAIL: verify command exited ${VERIFY_EXIT}"
        FAILURE_TYPE="test_failure"
        echo "  ❌ Step 1: Verify command failed (exit ${VERIFY_EXIT})"
        echo "     Output: $(echo "$VERIFY_OUTPUT" | tail -3)"
    else
        echo "  ✅ Step 1: Verify command passed"
    fi
fi

# ══════════════════════════════════════════
# Step 2: Full Regression Suite
# ══════════════════════════════════════════
echo "  [2/4] Full regression suite..."

REGRESSION_CMD=""
if [[ -f "pytest.ini" || -f "setup.cfg" || -f "pyproject.toml" || -d "tests" ]]; then
    REGRESSION_CMD="python -m pytest -q 2>&1"
elif [[ -f "package.json" ]]; then
    REGRESSION_CMD="npm test 2>&1"
elif [[ -f "Cargo.toml" ]]; then
    REGRESSION_CMD="cargo test 2>&1"
fi

if [[ -n "$REGRESSION_CMD" ]]; then
    set +e
    REGRESSION_OUTPUT=$(eval "$REGRESSION_CMD")
    REGRESSION_EXIT=$?
    set -e

    if [[ $REGRESSION_EXIT -ne 0 ]]; then
        VERIFY_PASS=false
        FAIL_REASONS="${FAIL_REASONS}\n  - Step 2 FAIL: regression suite failed (exit ${REGRESSION_EXIT})"
        [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="test_failure"
        echo "  ❌ Step 2: Regression failed"
        echo "     $(echo "$REGRESSION_OUTPUT" | tail -3)"
    else
        PASS_COUNT=$(echo "$REGRESSION_OUTPUT" | grep -oP '\d+ passed' | head -1 || echo "? passed")
        echo "  ✅ Step 2: Regression passed (${PASS_COUNT})"
    fi
else
    echo "  ⚠  Step 2: No test framework detected. Skipping."
fi

# ══════════════════════════════════════════
# Step 3: Evidence Chain
# ══════════════════════════════════════════
echo "  [3/4] Evidence chain..."

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    LAST_COMMIT_HASH=$(git log -1 --pretty=format:"%H" 2>/dev/null || echo "")
    LAST_COMMIT_SHORT=$(git log -1 --pretty=format:"%h" 2>/dev/null || echo "")
    LAST_COMMIT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

    # Check commit convention: feat(task-N) or fix(task-N)
    if echo "$LAST_COMMIT_MSG" | grep -qiP "(feat|fix)\(.*task.*${TASK_ID}"; then
        echo "  ✅ Step 3: Commit matches convention — ${LAST_COMMIT_SHORT}: ${LAST_COMMIT_MSG}"
    else
        echo "  ⚠  Step 3: Commit doesn't match task ${TASK_ID} convention"
        echo "     Last commit: ${LAST_COMMIT_SHORT}: ${LAST_COMMIT_MSG}"
        # Non-blocking warning, not a FAIL
    fi

    # Cross-check with build report if it exists
    if [[ -f "${LOGS_DIR}/task-${TASK_ID}-build.md" ]]; then
        REPORT_HASH=$(grep -oP 'Commit:\s*\K\S+' "${LOGS_DIR}/task-${TASK_ID}-build.md" | head -1 || echo "")
        if [[ -n "$REPORT_HASH" ]] && [[ "$REPORT_HASH" != "$LAST_COMMIT_HASH" ]] && [[ "$REPORT_HASH" != "$LAST_COMMIT_SHORT" ]]; then
            echo "  ⚠  Step 3: Build report commit (${REPORT_HASH}) doesn't match HEAD (${LAST_COMMIT_SHORT})"
        fi
    fi
else
    echo "  ⚠  Step 3: Not a git repo. Skipping evidence chain."
fi

# ══════════════════════════════════════════
# Step 4: Wiring Proof
# ══════════════════════════════════════════
if [[ "$USE_WIRING_PROOF" == true ]]; then
    echo "  [4/4] Wiring proof checks..."
    WIRING_ISSUES=0

    # ── 4a: Dead import detection in test files ──
    TEST_FILES=$(find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -v __pycache__ || true)
    if [[ -n "$TEST_FILES" ]]; then
        for TEST_FILE in $TEST_FILES; do
            # Find project imports (skip stdlib/test utilities)
            IMPORTS=$(grep -oP 'from\s+\S+\s+import\s+\K\w+' "$TEST_FILE" 2>/dev/null || true)
            for IMPORT in $IMPORTS; do
                # Skip common utilities
                if [[ "$IMPORT" =~ ^(patch|MagicMock|Mock|pytest|unittest|mock|subprocess|os|sys|json|tempfile|shutil|pathlib|Path|Any|Dict|List|Optional|call|PropertyMock|fixture)$ ]]; then
                    continue
                fi
                # Check usage count (must appear more than just the import line)
                USAGE_COUNT=$(grep -c "${IMPORT}" "$TEST_FILE" 2>/dev/null || echo "0")
                if [[ "$USAGE_COUNT" -le 1 ]]; then
                    echo "  ⚠  SIGN-001: Dead import '${IMPORT}' in ${TEST_FILE}"
                    WIRING_ISSUES=$((WIRING_ISSUES + 1))
                fi
            done

            # ── 4b: Integration test pipeline check ──
            if echo "$TEST_FILE" | grep -qi "integration"; then
                echo "  → Integration test: ${TEST_FILE}"
                # Check that imported pipeline modules are actually invoked
                PROJECT_IMPORTS=$(grep -oP 'from\s+\w+\s+import\s+\K\w+' "$TEST_FILE" 2>/dev/null || true)
                for PI in $PROJECT_IMPORTS; do
                    if [[ "$PI" =~ ^(patch|MagicMock|Mock|pytest|unittest)$ ]]; then continue; fi
                    # Look for invocation (parentheses after the name)
                    INVOKED=$(grep -cP "${PI}\s*\(" "$TEST_FILE" 2>/dev/null || echo "0")
                    if [[ "$INVOKED" -eq 0 ]]; then
                        echo "  ⚠  SIGN-001: '${PI}' imported but never invoked in ${TEST_FILE}"
                        WIRING_ISSUES=$((WIRING_ISSUES + 1))
                    fi
                done
            fi
        done
    fi

    # ── 4c: CLI boundary check (SIGN-002) ──
    ENTRY_POINTS=$(find . -name "__main__.py" -o -name "cli.py" 2>/dev/null | grep -v __pycache__ || true)
    if [[ -n "$ENTRY_POINTS" ]]; then
        for EP in $ENTRY_POINTS; do
            # Extract CLI commands/subcommands
            CLI_CMDS=$(grep -oP "add_parser\(['\"](\K[^'\"]+)" "$EP" 2>/dev/null || true)
            if [[ -z "$CLI_CMDS" ]]; then
                CLI_CMDS=$(grep -oP "command=['\"](\K[^'\"]+)" "$EP" 2>/dev/null || true)
            fi
            # Check for subprocess tests
            SUBPROCESS_TESTS=$(grep -rl "subprocess" tests/ 2>/dev/null | head -5 || true)
            if [[ -z "$SUBPROCESS_TESTS" ]] && [[ -n "$CLI_CMDS" ]]; then
                echo "  ⚠  SIGN-002: CLI entry point ${EP} has no subprocess-level tests"
                WIRING_ISSUES=$((WIRING_ISSUES + 1))
            fi
        done
    fi

    # ── 4d: Dependency verification ──
    if [[ -f "requirements.txt" ]]; then
        # Quick check: try importing all source modules
        SRC_IMPORTS=$(find . -name "*.py" -not -path "./tests/*" -not -path "./.spectra/*" -not -name "test_*" 2>/dev/null | \
            xargs grep -hoP '^import\s+\K\w+|^from\s+\K\w+' 2>/dev/null | sort -u || true)
        for MOD in $SRC_IMPORTS; do
            # Skip stdlib
            if python3 -c "import ${MOD}" 2>/dev/null; then continue; fi
            if ! grep -qi "${MOD}" requirements.txt 2>/dev/null; then
                echo "  ⚠  Missing dependency: '${MOD}' imported but not in requirements.txt"
                WIRING_ISSUES=$((WIRING_ISSUES + 1))
                [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="missing_dependency"
            fi
        done
    fi

    if [[ $WIRING_ISSUES -gt 0 ]]; then
        echo "  ⚠  ${WIRING_ISSUES} wiring issue(s) found"
        if [[ $WIRING_ISSUES -ge 3 ]]; then
            VERIFY_PASS=false
            FAIL_REASONS="${FAIL_REASONS}\n  - Step 4 FAIL: ${WIRING_ISSUES} wiring issues (threshold: 3)"
            [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="wiring_gap"
        fi
    else
        echo "  ✅ Step 4: Wiring proof passed"
    fi
else
    echo "  [4/4] Wiring proof skipped (--no-wiring-proof)"
fi

# ══════════════════════════════════════════
# VERDICT
# ══════════════════════════════════════════

echo ""
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write structured verification report
cat > "${LOGS_DIR}/task-${TASK_ID}-verify-script.md" <<EOF
## Verification Report (Script) — Task ${TASK_ID}
- **Result:** $(if $VERIFY_PASS; then echo "PASS"; else echo "FAIL"; fi)
- **Failure Type:** ${FAILURE_TYPE:-N/A}
- **Timestamp:** ${TIMESTAMP}
- **Verify Command:** \`${VERIFY_CMD:-none}\`
$(if ! $VERIFY_PASS; then echo -e "\n### Blocking Issues${FAIL_REASONS}"; fi)
EOF

if [[ "$VERIFY_PASS" == true ]]; then
    echo "  ✅ PASS — Task ${TASK_ID} verified"

    # Slack
    if [[ "$USE_SLACK" == true ]] && [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"✅ SPECTRA PASS: Task ${TASK_ID} (commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown'))\"}" > /dev/null 2>&1 || true
    fi

    # Log
    {
        echo ""
        echo "### $(date +%Y-%m-%d) Task ${TASK_ID} — PASS (script verify)"
    } >> "${SPECTRA_DIR}/lessons-learned.md" 2>/dev/null || true

    exit 0
else
    echo "  ❌ FAIL — Task ${TASK_ID}"
    echo -e "  Failure type: ${FAILURE_TYPE:-unknown}"
    echo -e "  Reasons:${FAIL_REASONS}"

    # Slack
    if [[ "$USE_SLACK" == true ]] && [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"❌ SPECTRA FAIL: Task ${TASK_ID} — ${FAILURE_TYPE:-unknown}\"}" > /dev/null 2>&1 || true
    fi

    # Log
    {
        echo ""
        echo "### $(date +%Y-%m-%d) Task ${TASK_ID} — FAIL (script verify)"
        echo "- **Failure Type:** ${FAILURE_TYPE:-unknown}"
        echo -e "- **Reasons:**${FAIL_REASONS}"
    } >> "${SPECTRA_DIR}/lessons-learned.md" 2>/dev/null || true

    exit 1
fi
