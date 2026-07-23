#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA v5.5 Verification Gate                                  ║
# ║  4-Step Audit: Verify → Regression → Evidence Chain → Wiring     ║
# ║  Auto-logs PASS/FAIL to lessons-learned.md                       ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Usage: spectra-verify [--task N] [--slack] [--no-wiring-proof]
#
# This script provides automated verification as a complement to the
# spectra-verifier subagent. It can run standalone or as a pre-check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-$(dirname "${SCRIPT_DIR}")}"
SPECTRA_DIR=".spectra"
LOGS_DIR="${SPECTRA_DIR}/logs"
PLAN_FILE="${SPECTRA_DIR}/plan.md"
PLAN_VALIDATOR="${SPECTRA_HOME}/bin/spectra-plan-validate.sh"

USE_SLACK=false
USE_WIRING_PROOF=true
FULL_SWEEP=false
TASK_OVERRIDE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --task)            TASK_OVERRIDE="$2"; shift 2 ;;
        --slack)           USE_SLACK=true; shift ;;
        --no-wiring-proof) USE_WIRING_PROOF=false; shift ;;
        --full-sweep)      FULL_SWEEP=true; shift ;;
        -h|--help)
            cat <<EOF
SPECTRA v5.5 Verification Gate

Usage: spectra-verify [OPTIONS]

Options:
  --task N             Verify specific task number
  --slack              Send Slack notification on PASS/FAIL
  --no-wiring-proof    Skip wiring proof checks (not recommended)
  --full-sweep         Full 4-step audit + cross-task wiring proof
  -h, --help           Show this help

4-Step Audit:
  1. Task verify command — exact CLI command from plan.md
  2. Full regression suite — all tests must pass
  3. Evidence chain — git commit matches task convention
  4. Wiring proof — dead imports, pipeline coverage, dependencies

Runtime signal:
  5. Runtime/deploy probe — set SPECTRA_RUNTIME_PROBE=1 to probe a live
     health endpoint or smoke command. A configured probe also runs
     automatically for tasks whose Scope is infra or deploy. It is advisory
     unless verify.yaml runtime.blocking: true or the blocking env override.
     See bin/spectra-runtime-probe.sh and verify.yaml runtime: block.
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Verify project
if [[ ! -f "${PLAN_FILE}" ]]; then
    echo "Error: No ${PLAN_FILE} found."
    exit 1
fi

mkdir -p "${LOGS_DIR}"

# Source env
if [[ -f "${SPECTRA_HOME}/.env" ]]; then
    # RATIONALE: .env is optional runtime configuration outside the checked source graph.
    # shellcheck disable=SC1091
    set +u; source "${SPECTRA_HOME}/.env"; set -u
fi

# Validate plan contract before parsing
if [[ -x "${PLAN_VALIDATOR}" ]]; then
    if ! "${PLAN_VALIDATOR}" --file "${PLAN_FILE}" --quiet; then
        echo "Error: plan.md failed schema validation. Regenerate with 'spectra-plan' or fix manually."
        exit 1
    fi
fi

normalize_task_id() {
    local raw="$1"
    if [[ ! "$raw" =~ ^[0-9]{1,3}$ ]]; then
        return 1
    fi
    printf "%03d" "$((10#${raw}))"
}

find_task_header_line() {
    local task_id="$1"
    grep -nP "^## Task ${task_id}:" "${PLAN_FILE}" 2>/dev/null | head -1 | cut -d: -f1 || true
}

get_task_section() {
    local task_id="$1"
    local start_line next_line end_line

    start_line=$(find_task_header_line "${task_id}")
    if [[ -n "${start_line}" ]]; then
        next_line=$(grep -nE '^## Task [0-9]{3}:' "${PLAN_FILE}" 2>/dev/null | awk -F: -v start="${start_line}" '$1 > start {print $1; exit}')
        if [[ -n "${next_line}" ]]; then
            end_line=$((next_line - 1))
            sed -n "${start_line},${end_line}p" "${PLAN_FILE}"
        else
            sed -n "${start_line},\$p" "${PLAN_FILE}"
        fi
        return
    fi

    # Compatibility fallback for non-header task blocks
    start_line=$(grep -nE "^- \\[[ xX!]\\] ${task_id}:" "${PLAN_FILE}" 2>/dev/null | head -1 | cut -d: -f1 || true)
    if [[ -n "${start_line}" ]]; then
        next_line=$(grep -nE '^- \[[ xX]\] [0-9]{3}:' "${PLAN_FILE}" 2>/dev/null | awk -F: -v start="${start_line}" '$1 > start {print $1; exit}')
        if [[ -n "${next_line}" ]]; then
            end_line=$((next_line - 1))
            sed -n "${start_line},${end_line}p" "${PLAN_FILE}"
        else
            sed -n "${start_line},\$p" "${PLAN_FILE}"
        fi
    fi
}

reset_profile_contract() {
    DEP_MANIFESTS=()
    TEST_PATTERNS=()
    FILE_EXTENSION=""
    SKIP_IMPORTS=""
    REGRESSION_CMD=""
    unset -f extract_dependency_modules 2>/dev/null || true
    unset -f dependency_module_declared 2>/dev/null || true
}

detect_project_languages() {
    DETECTED_LANG=""
    DETECTED_LANGS=()

    if [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" || -f "setup.cfg" || -f "Pipfile" || -f "pytest.ini" ]]; then
        DETECTED_LANGS+=("python")
    fi
    if [[ -f "package.json" ]]; then
        DETECTED_LANGS+=("javascript")
    fi
    if [[ -f "go.mod" ]]; then
        DETECTED_LANGS+=("go")
    fi
    if [[ -f "Cargo.toml" ]]; then
        DETECTED_LANGS+=("rust")
    fi
    if [[ -f "Makefile" ]] && compgen -G "bin/*.sh" > /dev/null && compgen -G "tests/*.sh" > /dev/null; then
        DETECTED_LANGS+=("bash")
    fi

    if [[ ${#DETECTED_LANGS[@]} -gt 0 ]]; then
        DETECTED_LANG="${DETECTED_LANGS[0]}"
    fi
}

format_detected_languages() {
    if [[ ${#DETECTED_LANGS[@]} -eq 1 ]] && [[ -n "${DETECTED_LANG}" ]]; then
        echo "${DETECTED_LANG}"
        return 0
    fi
    local IFS=", "
    echo "${DETECTED_LANGS[*]}"
}

load_language_profile() {
    local lang="$1"

    reset_profile_contract
    LANG_PROFILE="${SPECTRA_HOME}/lang-profiles/${lang}.profile"
    if [[ -f "${LANG_PROFILE}" ]]; then
        # shellcheck source=/dev/null
        source "${LANG_PROFILE}"
        return 0
    fi
    return 1
}

fallback_regression_cmd_for_language() {
    case "$1" in
        rust) echo "cargo test" ;;
        go) echo "go test ./..." ;;
        *) return 1 ;;
    esac
}

summarize_regression_output() {
    local output="$1"
    local summary=""

    summary=$(echo "${output}" | grep -oP '\d+ passed' | head -1 || true)
    if [[ -n "${summary}" ]]; then
        echo "${summary}"
        return 0
    fi

    summary=$(echo "${output}" | grep -oP '# pass \K\d+' | head -1 || true)
    if [[ -n "${summary}" ]]; then
        echo "${summary} pass"
        return 0
    fi

    echo "command succeeded"
}

collect_test_files() {
    local pattern
    for pattern in "${TEST_PATTERNS[@]}"; do
        find . -name "${pattern}" 2>/dev/null
    done | grep -v __pycache__ | sort -u || true
}

dependency_manifest_path() {
    local manifest
    for manifest in "${DEP_MANIFESTS[@]}"; do
        if [[ -f "${manifest}" ]]; then
            echo "${manifest}"
            return 0
        fi
    done
    return 1
}

run_python_wiring_checks() {
    local test_file imports imported_symbol usage_count project_imports invoked
    mapfile -t TEST_FILES < <(collect_test_files)

    for test_file in "${TEST_FILES[@]}"; do
        imports=$(grep -oP 'from\s+\S+\s+import\s+\K\w+' "${test_file}" 2>/dev/null || true)
        for imported_symbol in ${imports}; do
            if [[ "${imported_symbol}" =~ ^(${SKIP_IMPORTS})$ ]]; then
                continue
            fi
            usage_count=$(grep -c "${imported_symbol}" "${test_file}" 2>/dev/null || echo "0")
            if [[ "${usage_count}" -le 1 ]]; then
                echo "  ⚠  SIGN-001: Dead import '${imported_symbol}' in ${test_file}"
                WIRING_ISSUES=$((WIRING_ISSUES + 1))
            fi
        done

        if echo "${test_file}" | grep -qi "integration"; then
            echo "  → Integration test: ${test_file}"
            project_imports=$(grep -oP 'from\s+\w+\s+import\s+\K\w+' "${test_file}" 2>/dev/null || true)
            for imported_symbol in ${project_imports}; do
                if [[ "${imported_symbol}" =~ ^(patch|MagicMock|Mock|pytest|unittest)$ ]]; then
                    continue
                fi
                invoked=$(grep -cP "${imported_symbol}\s*\(" "${test_file}" 2>/dev/null || echo "0")
                if [[ "${invoked}" -eq 0 ]]; then
                    echo "  ⚠  SIGN-001: '${imported_symbol}' imported but never invoked in ${test_file}"
                    WIRING_ISSUES=$((WIRING_ISSUES + 1))
                fi
            done
        fi
    done
}

run_javascript_wiring_checks() {
    local test_file issue_type symbol
    mapfile -t TEST_FILES < <(collect_test_files)

    for test_file in "${TEST_FILES[@]}"; do
        while IFS='|' read -r issue_type symbol; do
            [[ -n "${issue_type}" ]] || continue
            case "${issue_type}" in
                dead)
                    echo "  ⚠  SIGN-001: Dead import '${symbol}' in ${test_file}"
                    WIRING_ISSUES=$((WIRING_ISSUES + 1))
                    ;;
                uninvoked)
                    echo "  ⚠  SIGN-001: '${symbol}' imported but never invoked in ${test_file}"
                    WIRING_ISSUES=$((WIRING_ISSUES + 1))
                    ;;
            esac
        done < <(python3 - "${test_file}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")
integration = "integration" in str(path).lower()
imports: list[tuple[str, str]] = []
body_lines: list[str] = []


def add_symbol(kind: str, symbol: str) -> None:
    if symbol and symbol != "default":
        imports.append((kind, symbol))


def parse_import_clause(clause: str) -> None:
    clause = clause.strip()
    if not clause:
        return

    if clause.startswith("{") and clause.endswith("}"):
        inner = clause[1:-1].strip()
        if not inner:
            return
        for part in inner.split(","):
            item = part.strip()
            if not item or item.startswith("type "):
                continue
            alias = re.split(r"\s+as\s+", item)
            add_symbol("named", alias[-1].strip())
        return

    if clause.startswith("* as "):
        add_symbol("namespace", clause[5:].strip())
        return

    if "," in clause:
        head, tail = clause.split(",", 1)
        add_symbol("default", head.strip())
        parse_import_clause(tail.strip())
        return

    add_symbol("default", clause)


for line in text.splitlines():
    stripped = line.strip()
    matched_import = False

    if stripped.startswith("import ") and " from " in stripped:
        match = re.match(r'import\s+(type\s+)?(.+?)\s+from\s+[\'"]([^\'"]+)[\'"]', stripped)
        if match:
            spec = match.group(3)
            if spec.startswith((".", "..")):
                parse_import_clause(match.group(2))
            matched_import = True

    if not matched_import:
        match = re.match(r'(?:const|let|var)\s+\{([^}]+)\}\s*=\s*require\([\'"]([^\'"]+)[\'"]\)', stripped)
        if match:
            spec = match.group(2)
            if spec.startswith((".", "..")):
                for part in match.group(1).split(","):
                    item = part.strip()
                    if not item:
                        continue
                    alias = item.split(":")
                    add_symbol("named", alias[-1].strip())
            matched_import = True

    if not matched_import:
        match = re.match(r'(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\([\'"]([^\'"]+)[\'"]\)', stripped)
        if match:
            spec = match.group(2)
            if spec.startswith((".", "..")):
                add_symbol("default", match.group(1))
            matched_import = True

    if not matched_import:
        body_lines.append(line)

body = "\n".join(body_lines)
seen: set[tuple[str, str]] = set()
for kind, symbol in imports:
    key = (kind, symbol)
    if key in seen:
        continue
    seen.add(key)

    if not re.search(rf'\b{re.escape(symbol)}\b', body):
        print(f"dead|{symbol}")
        continue

    if integration:
        if kind == "namespace":
            invoked = re.search(rf'\b{re.escape(symbol)}\s*\.', body)
        else:
            invoked = re.search(rf'\b{re.escape(symbol)}\s*\(|\bnew\s+{re.escape(symbol)}\s*\(|\b{re.escape(symbol)}\s*\.', body)
        if not invoked:
            print(f"uninvoked|{symbol}")
PY
)
    done
}

run_javascript_cli_boundary_check() {
    local has_subprocess_tests="false"
    local cli_name cli_path

    mapfile -t TEST_FILES < <(collect_test_files)
    if [[ ${#TEST_FILES[@]} -gt 0 ]]; then
        if grep -Eq 'child_process|node:child_process|spawnSync?\(|execSync?\(|execa|cross-spawn' "${TEST_FILES[@]}" 2>/dev/null; then
            has_subprocess_tests="true"
        fi
    fi

    while IFS='|' read -r cli_name cli_path; do
        [[ -n "${cli_name}" ]] || continue
        if [[ "${has_subprocess_tests}" != "true" ]]; then
            echo "  ⚠  SIGN-002: CLI entry point ${cli_path} (${cli_name}) has no subprocess-level tests"
            WIRING_ISSUES=$((WIRING_ISSUES + 1))
        fi
    done < <(python3 - <<'PY'
import json
from pathlib import Path

package_json = Path("package.json")
if not package_json.exists():
    raise SystemExit(0)

data = json.loads(package_json.read_text(encoding="utf-8"))
bin_field = data.get("bin")
if isinstance(bin_field, str):
    print(f"{data.get('name', 'package')}|{bin_field}")
elif isinstance(bin_field, dict):
    for name, path in sorted(bin_field.items()):
        print(f"{name}|{path}")
PY
)
}

run_cli_boundary_check() {
    local cli_entry_files entry_point cli_cmds subprocess_tests

    [[ -n "${FILE_EXTENSION:-}" ]] || return 0
    cli_entry_files=$(find . \( -name "__main__.${FILE_EXTENSION}" -o -name "cli.${FILE_EXTENSION}" \) 2>/dev/null | grep -v __pycache__ || true)
    [[ -n "${cli_entry_files}" ]] || return 0

    for entry_point in ${cli_entry_files}; do
        cli_cmds=$(grep -oP "add_parser\(['\"](\K[^'\"]+)" "${entry_point}" 2>/dev/null || true)
        if [[ -z "${cli_cmds}" ]]; then
            cli_cmds=$(grep -oP "command=['\"](\K[^'\"]+)" "${entry_point}" 2>/dev/null || true)
        fi
        subprocess_tests=$(grep -rl "subprocess" tests/ 2>/dev/null | head -5 || true)
        if [[ -z "${subprocess_tests}" ]] && [[ -n "${cli_cmds}" ]]; then
            echo "  ⚠  SIGN-002: CLI entry point ${entry_point} has no subprocess-level tests"
            WIRING_ISSUES=$((WIRING_ISSUES + 1))
        fi
    done
}

run_dependency_verification() {
    local dep_file module_name

    dep_file=$(dependency_manifest_path || true)
    [[ -n "${dep_file}" ]] || return 0

    if ! declare -f extract_dependency_modules >/dev/null 2>&1 || ! declare -f dependency_module_declared >/dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue
        if dependency_module_declared "${module_name}" "${dep_file}"; then
            continue
        fi
        echo "  ⚠  Missing dependency: '${module_name}' imported but not in ${dep_file}"
        WIRING_ISSUES=$((WIRING_ISSUES + 1))
        [[ -z "${FAILURE_TYPE}" ]] && FAILURE_TYPE="missing_dependency"
    done < <(extract_dependency_modules)
}

run_language_wiring_checks() {
    local lang="$1"

    echo "  → ${lang}: wiring proof"
    case "${lang}" in
        python) run_python_wiring_checks ;;
        javascript)
            run_javascript_wiring_checks
            run_javascript_cli_boundary_check
            ;;
    esac
    run_cli_boundary_check
    run_dependency_verification
}

# ── Find task to verify ──
if [[ -n "$TASK_OVERRIDE" ]]; then
    if ! TASK_ID=$(normalize_task_id "${TASK_OVERRIDE}"); then
        echo "Error: --task must be a numeric ID (e.g. 1 or 001)"
        exit 1
    fi
    TASK_LINE=$(find_task_header_line "${TASK_ID}")
else
    # Find most recently checked task in canonical checkbox format (skip [!] stuck).
    LAST_CHECKED=$(grep -nE '^\- \[[xX]\] [0-9]{3}:' "${PLAN_FILE}" | tail -1 || echo "")
    if [[ -z "$LAST_CHECKED" ]]; then
        echo "  No completed tasks to verify."
        exit 0
    fi
    TASK_LINE=$(echo "$LAST_CHECKED" | cut -d: -f1)
    TASK_ID=$(echo "$LAST_CHECKED" | grep -oP '^\d+:\- \[[xX]\] \K[0-9]{3}' || echo "")
fi

if [[ -z "${TASK_ID:-}" ]]; then
    echo "Error: Could not determine task ID to verify."
    exit 1
fi

if [[ -z "${TASK_LINE:-}" ]]; then
    TASK_LINE=$(find_task_header_line "${TASK_ID}")
fi

TASK_SECTION="$(get_task_section "${TASK_ID}")"
if [[ -z "${TASK_SECTION}" ]]; then
    echo "Error: Could not locate task block for Task ${TASK_ID}."
    exit 1
fi

# ── Verification depth ──
VERIFICATION_DEPTH="full"

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
VERIFY_CMD=$(echo "$TASK_SECTION" | grep -oP "(?:Verify|verify):\s*\`\K[^\`]+" | head -1 || true)

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

detect_project_languages
if [[ ${#DETECTED_LANGS[@]} -gt 0 ]]; then
    echo "  Languages detected: $(format_detected_languages)"
else
    echo "  Languages detected: none"
fi

# ══════════════════════════════════════════
# Step 2: Full Regression Suite
# ══════════════════════════════════════════
echo "  [2/4] Full regression suite..."

REGRESSION_RUNS=0
for lang in "${DETECTED_LANGS[@]}"; do
    REGRESSION_CMD=""
    if load_language_profile "${lang}"; then
        echo "  → ${lang}: profile loaded"
    else
        echo "  WARNING: No language profile for '${lang}'. Using fallback detection."
        echo "  SIGN-010: Language Blindspot — create ${SPECTRA_HOME}/lang-profiles/${lang}.profile"
    fi

    if [[ -z "${REGRESSION_CMD:-}" ]]; then
        REGRESSION_CMD=$(fallback_regression_cmd_for_language "${lang}" || true)
    fi

    if [[ -z "${REGRESSION_CMD:-}" ]]; then
        continue
    fi

    REGRESSION_RUNS=$((REGRESSION_RUNS + 1))
    echo "     Command: ${REGRESSION_CMD}"
    set +e
    REGRESSION_OUTPUT=$(eval "${REGRESSION_CMD}" 2>&1)
    REGRESSION_EXIT=$?
    set -e

    if [[ ${REGRESSION_EXIT} -ne 0 ]]; then
        VERIFY_PASS=false
        FAIL_REASONS="${FAIL_REASONS}\n  - Step 2 FAIL (${lang}): regression suite failed (exit ${REGRESSION_EXIT})"
        [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="test_failure"
        echo "  ❌ ${lang}: Regression failed"
        echo "     $(echo "${REGRESSION_OUTPUT}" | tail -3)"
    else
        PASS_COUNT=$(summarize_regression_output "${REGRESSION_OUTPUT}")
        echo "  ✅ ${lang}: Regression passed (${PASS_COUNT})"
    fi
done

if [[ ${REGRESSION_RUNS} -eq 0 ]]; then
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

    # Check commit convention: feat(task-N) or fix(task-N), allow zero-padded/unpadded IDs
    TASK_ID_INT=$((10#${TASK_ID}))
    if echo "$LAST_COMMIT_MSG" | grep -qiP "(feat|fix)\(.*task.*(${TASK_ID}|${TASK_ID_INT})"; then
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
    WIRING_RUNS=0

    if [[ ${#DETECTED_LANGS[@]} -eq 0 ]]; then
        echo "  WARNING: No language detected (no manifest files found). Skipping wiring proof."
    fi

    for lang in "${DETECTED_LANGS[@]}"; do
        if ! load_language_profile "${lang}"; then
            echo "  WARNING: No language profile for '${lang}'. Wiring proof may be incomplete."
            continue
        fi
        WIRING_RUNS=$((WIRING_RUNS + 1))
        run_language_wiring_checks "${lang}"
    done

    if [[ ${WIRING_RUNS} -eq 0 ]]; then
        echo "  ⚠  Step 4: No profile-backed wiring proof executed"
    elif [[ $WIRING_ISSUES -gt 0 ]]; then
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
# Step 5: Runtime/Deploy Probe (explicit or scope-aware, advisory by default)
# ══════════════════════════════════════════
# Loads optional runtime config from .spectra/verify.yaml `runtime:` block.
# Explicit SPECTRA_PROBE_* env vars take precedence over verify.yaml values.
# Sets PROBE_BLOCKING (default false): advisory failures warn but do not gate.
load_runtime_probe_config() {
    local blocking_env_set="false"
    PROBE_BLOCKING="false"
    if [[ -n "${SPECTRA_RUNTIME_PROBE_BLOCKING+x}" ]]; then
        blocking_env_set="true"
        case "${SPECTRA_RUNTIME_PROBE_BLOCKING}" in
            1|true|yes|TRUE|YES) PROBE_BLOCKING="true" ;;
            *) PROBE_BLOCKING="false" ;;
        esac
    fi
    local vf="${SPECTRA_DIR}/verify.yaml"
    [[ -f "${vf}" ]] || return 0
    local block
    block=$(awk '/^runtime:/{f=1;next} /^[^[:space:]#]/{f=0} f{print}' "${vf}")
    [[ -n "${block}" ]] || return 0

    local v
    v=$(echo "${block}" | grep -oP '^\s*url:\s*"?\K[^"#]*' | head -1 | sed 's/[[:space:]]*$//' || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_URL:-}" ]] && export SPECTRA_PROBE_URL="${v}"
    v=$(echo "${block}" | grep -oP '^\s*expect_status:\s*\K[0-9]+' | head -1 || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_EXPECT_STATUS:-}" ]] && export SPECTRA_PROBE_EXPECT_STATUS="${v}"
    v=$(echo "${block}" | grep -oP '^\s*expect_body:\s*"?\K[^"#]*' | head -1 | sed 's/[[:space:]]*$//' || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_EXPECT_BODY:-}" ]] && export SPECTRA_PROBE_EXPECT_BODY="${v}"
    v=$(echo "${block}" | grep -oP '^\s*command:\s*"?\K[^"#]*' | head -1 | sed 's/[[:space:]]*$//' || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_COMMAND:-}" ]] && export SPECTRA_PROBE_COMMAND="${v}"
    v=$(echo "${block}" | grep -oP '^\s*retries:\s*\K[0-9]+' | head -1 || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_RETRIES:-}" ]] && export SPECTRA_PROBE_RETRIES="${v}"
    v=$(echo "${block}" | grep -oP '^\s*interval:\s*\K[0-9]+' | head -1 || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_INTERVAL:-}" ]] && export SPECTRA_PROBE_INTERVAL="${v}"
    v=$(echo "${block}" | grep -oP '^\s*timeout:\s*\K[0-9]+' | head -1 || true)
    [[ -n "${v}" && -z "${SPECTRA_PROBE_TIMEOUT:-}" ]] && export SPECTRA_PROBE_TIMEOUT="${v}"
    if [[ "${blocking_env_set}" != "true" ]]; then
        v=$(echo "${block}" | grep -oP '^\s*blocking:\s*\K\S+' | head -1 || true)
        case "${v}" in 1|true|yes|TRUE|YES) PROBE_BLOCKING="true" ;; esac
    fi
    return 0
}

runtime_probe_enabled() {
    # An explicit env setting always wins, including a false/zero disable.
    if [[ -n "${SPECTRA_RUNTIME_PROBE+x}" ]]; then
        case "${SPECTRA_RUNTIME_PROBE}" in
            1|true|yes|TRUE|YES) return 0 ;;
            *) return 1 ;;
        esac
    fi

    # Otherwise, infra/deploy tasks automatically consume a configured probe.
    if ! echo "${TASK_SECTION}" | grep -qiE '^[[:space:]]*-[[:space:]]*Scope:[[:space:]]*(infra|deploy)([[:space:]]|$)'; then
        return 1
    fi
    [[ -n "${SPECTRA_PROBE_URL:-}" || -n "${SPECTRA_PROBE_COMMAND:-}" ]]
}

PROBE_SCRIPT="${SPECTRA_HOME}/bin/spectra-runtime-probe.sh"
PROBE_BLOCKING="false"
load_runtime_probe_config
if runtime_probe_enabled; then
    echo "  [5] Runtime/deploy probe..."
    if [[ -x "${PROBE_SCRIPT}" ]]; then
        set +e
        "${PROBE_SCRIPT}"
        PROBE_EXIT=$?
        set -e
        if [[ ${PROBE_EXIT} -eq 0 ]]; then
            echo "  ✅ Step 5: Runtime probe passed"
        elif [[ "${PROBE_BLOCKING}" == "true" ]]; then
            VERIFY_PASS=false
            if [[ ${PROBE_EXIT} -eq 2 ]]; then
                FAIL_REASONS="${FAIL_REASONS}\n  - Step 5 FAIL: runtime probe could not reach target (blocking)"
                [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="external_blocker"
            else
                FAIL_REASONS="${FAIL_REASONS}\n  - Step 5 FAIL: runtime probe assertion failed (blocking)"
                [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="test_failure"
            fi
        else
            echo "  ⚠  Step 5: Runtime probe failed (exit ${PROBE_EXIT}) — advisory, not gating verdict"
        fi
    else
        if [[ "${PROBE_BLOCKING}" == "true" ]]; then
            VERIFY_PASS=false
            FAIL_REASONS="${FAIL_REASONS}\n  - Step 5 FAIL: runtime probe script missing at ${PROBE_SCRIPT} (blocking)"
            [[ -z "$FAILURE_TYPE" ]] && FAILURE_TYPE="external_blocker"
        else
            echo "  WARNING: runtime probe enabled but script not found at ${PROBE_SCRIPT}"
        fi
    fi
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
