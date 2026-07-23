#!/usr/bin/env bash
set -euo pipefail

# SPECTRA environment and safety preflight.
# Default mode fails only on hard blockers. --strict also fails on recommended
# capability gaps and safety warnings. --json never requires jq or Python.

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-${SCRIPT_DIR%/*}}"
PROJECT_ROOT="."
OUTPUT_JSON=false
STRICT=false

usage() {
    cat <<'USAGE'
Usage: spectra-doctor.sh [PROJECT_ROOT] [OPTIONS]

Options:
  --json       Emit a machine-readable report
  --strict     Treat recommended capability gaps and safety warnings as failure
  -h, --help   Show this help

Exit codes:
  0  Required environment is usable (and no warnings under --strict)
  1  A required capability is missing, or --strict found warnings
  2  Invalid arguments or project path
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) OUTPUT_JSON=true; shift ;;
        --strict) STRICT=true; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) PROJECT_ROOT="$1"; shift ;;
    esac
done

if [[ ! -d "${PROJECT_ROOT}" ]]; then
    echo "ERROR: project root does not exist: ${PROJECT_ROOT}" >&2
    exit 2
fi
PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
SPECTRA_HOME="$(cd "${SPECTRA_HOME}" && pwd)"

CHECK_IDS=()
CHECK_LEVELS=()
CHECK_STATUSES=()
CHECK_DETAILS=()
REQUIRED_FAILURES=0
WARNINGS=0

add_check() {
    local id="$1" level="$2" status="$3" detail="$4"
    CHECK_IDS+=("${id}")
    CHECK_LEVELS+=("${level}")
    CHECK_STATUSES+=("${status}")
    CHECK_DETAILS+=("${detail}")
    if [[ "${status}" == "fail" ]]; then
        REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
    fi
    if [[ "${status}" == "warn" ]]; then
        WARNINGS=$((WARNINGS + 1))
    fi
}

check_command() {
    local id="$1" level="$2" command_name="$3" description="$4"
    if command -v "${command_name}" >/dev/null 2>&1; then
        add_check "${id}" "${level}" "pass" "${description}: $(command -v "${command_name}")"
    elif [[ "${level}" == "required" ]]; then
        add_check "${id}" "${level}" "fail" "${description} is missing"
    else
        add_check "${id}" "${level}" "warn" "${description} is missing"
    fi
}

if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    add_check "bash" "required" "pass" "Bash ${BASH_VERSION}"
else
    add_check "bash" "required" "fail" "Bash 4+ required; found ${BASH_VERSION}"
fi

check_command "git" "required" "git" "Git"
check_command "timeout" "required" "timeout" "GNU timeout"
check_command "sed" "required" "sed" "sed"
check_command "awk" "required" "awk" "awk"
check_command "find" "required" "find" "find"
check_command "mktemp" "required" "mktemp" "mktemp"
check_command "flock" "required" "flock" "flock"
check_command "claude" "required" "claude" "Claude Code CLI"

AGENT_RUNNER="${SPECTRA_HOME}/bin/spectra-agent-run.sh"
if [[ -x "${AGENT_RUNNER}" ]] && command -v claude >/dev/null 2>&1; then
    subscription_report=""
    if subscription_report=$("${AGENT_RUNNER}" --check 2>/dev/null); then
        add_check "claude-subscription" "required" "pass" "${subscription_report}"
    else
        add_check "claude-subscription" "required" "fail" "Claude CLI is not verified on a prepaid claude.ai subscription"
    fi
else
    add_check "claude-subscription" "required" "fail" "Subscription-only agent launcher or Claude CLI is missing"
fi

MODEL_API_ENV_VARS=(
    ANTHROPIC_API_KEY
    ANTHROPIC_AUTH_TOKEN
    ANTHROPIC_BASE_URL
    ANTHROPIC_CUSTOM_HEADERS
    ANTHROPIC_AWS_API_KEY
    ANTHROPIC_AWS_BASE_URL
    ANTHROPIC_AWS_WORKSPACE_ID
    ANTHROPIC_BEDROCK_BASE_URL
    ANTHROPIC_BEDROCK_MANTLE_BASE_URL
    ANTHROPIC_FOUNDRY_API_KEY
    ANTHROPIC_FOUNDRY_AUTH_TOKEN
    ANTHROPIC_FOUNDRY_BASE_URL
    ANTHROPIC_FOUNDRY_RESOURCE
    ANTHROPIC_VERTEX_BASE_URL
    ANTHROPIC_VERTEX_PROJECT_ID
    ANTHROPIC_WORKSPACE_ID
    AWS_BEARER_TOKEN_BEDROCK
    CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST
    CLAUDE_CODE_USE_ANTHROPIC_AWS
    CLAUDE_CODE_USE_BEDROCK
    CLAUDE_CODE_USE_FOUNDRY
    CLAUDE_CODE_USE_MANTLE
    CLAUDE_CODE_USE_VERTEX
    CLAUDE_CODE_SKIP_BEDROCK_AUTH
    CLAUDE_CODE_SKIP_VERTEX_AUTH
    OPENAI_API_KEY
    GEMINI_API_KEY
    GOOGLE_API_KEY
    GOOGLE_GENAI_API_KEY
)
declared_model_api_vars=()
for model_api_var in "${MODEL_API_ENV_VARS[@]}"; do
    if [[ -n "${!model_api_var:-}" ]]; then
        declared_model_api_vars+=("${model_api_var}")
    fi
done
if [[ ${#declared_model_api_vars[@]} -gt 0 ]]; then
    add_check "model-api-environment" "safety" "warn" \
        "Model API/auth override variables are set (${declared_model_api_vars[*]}); SPECTRA strips Claude overrides, but remove ambient per-token credentials"
else
    add_check "model-api-environment" "safety" "pass" "No ambient model API/auth override variables are set"
fi

if command -v grep >/dev/null 2>&1 && printf 'pcre\n' | grep -qP '^pcre$' 2>/dev/null; then
    add_check "grep-pcre" "required" "pass" "grep supports -P"
else
    add_check "grep-pcre" "required" "fail" "GNU grep with PCRE (-P) is required"
fi

check_command "jq" "recommended" "jq" "jq (ratchet and JSON tooling)"
check_command "python3" "recommended" "python3" "Python 3 (typed helper fast path)"
check_command "curl" "recommended" "curl" "curl (URL runtime probes and integrations)"
check_command "gh" "recommended" "gh" "GitHub CLI"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck_version=""
    while IFS= read -r line; do
        case "${line}" in version:*) shellcheck_version="${line#version: }" ;; esac
    done < <(shellcheck --version 2>/dev/null || true)
    baseline_version=""
    if command -v jq >/dev/null 2>&1 && [[ -f "${SPECTRA_HOME}/shellcheck-baseline.json" ]]; then
        baseline_version=$(jq -r '.shellcheck_version // empty' "${SPECTRA_HOME}/shellcheck-baseline.json" 2>/dev/null || true)
    fi
    if [[ -n "${baseline_version}" && "${shellcheck_version}" != "${baseline_version}" ]]; then
        add_check "shellcheck" "recommended" "warn" "ShellCheck ${shellcheck_version}; baseline requires ${baseline_version}"
    else
        add_check "shellcheck" "recommended" "pass" "ShellCheck ${shellcheck_version:-version unknown}"
    fi
else
    add_check "shellcheck" "recommended" "warn" "ShellCheck is missing"
fi

ACTIONLINT="${ACTIONLINT_BIN:-actionlint}"
if { [[ "${ACTIONLINT}" == */* ]] && [[ -x "${ACTIONLINT}" ]]; } \
   || { [[ "${ACTIONLINT}" != */* ]] && command -v "${ACTIONLINT}" >/dev/null 2>&1; } \
   || [[ -x "${SPECTRA_HOME}/actionlint" ]]; then
    add_check "actionlint" "recommended" "pass" "actionlint available"
else
    add_check "actionlint" "recommended" "warn" "actionlint is missing; exact local CI lint cannot complete"
fi

check_env_permissions() {
    local file="$1" id="$2" mode
    [[ -f "${file}" ]] || return 0
    if ! command -v stat >/dev/null 2>&1; then
        add_check "${id}" "safety" "warn" "Cannot inspect ${file}: stat is missing"
        return 0
    fi
    mode=$(stat -c '%a' "${file}" 2>/dev/null || true)
    if [[ "${mode}" =~ ^[0-7]*00$ ]]; then
        add_check "${id}" "safety" "pass" "${file} permissions are ${mode}"
    else
        add_check "${id}" "safety" "warn" "${file} permissions are ${mode:-unknown}; remove group/other access"
    fi
}

check_env_permissions "${SPECTRA_HOME}/.env" "spectra-env-permissions"
if [[ "${PROJECT_ROOT}/.env" != "${SPECTRA_HOME}/.env" ]]; then
    check_env_permissions "${PROJECT_ROOT}/.env" "project-env-permissions"
fi

check_model_api_key_file() {
    local file="$1" id="$2"
    [[ -f "${file}" ]] || return 0
    if grep -Eq '^[[:space:]]*(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|ANTHROPIC_CUSTOM_HEADERS|ANTHROPIC_AWS_API_KEY|ANTHROPIC_AWS_BASE_URL|ANTHROPIC_AWS_WORKSPACE_ID|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_BEDROCK_MANTLE_BASE_URL|ANTHROPIC_FOUNDRY_API_KEY|ANTHROPIC_FOUNDRY_AUTH_TOKEN|ANTHROPIC_FOUNDRY_BASE_URL|ANTHROPIC_FOUNDRY_RESOURCE|ANTHROPIC_VERTEX_BASE_URL|ANTHROPIC_VERTEX_PROJECT_ID|ANTHROPIC_WORKSPACE_ID|AWS_BEARER_TOKEN_BEDROCK|CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST|CLAUDE_CODE_USE_ANTHROPIC_AWS|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_FOUNDRY|CLAUDE_CODE_USE_MANTLE|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_SKIP_BEDROCK_AUTH|CLAUDE_CODE_SKIP_VERTEX_AUTH|OPENAI_API_KEY|GEMINI_API_KEY|GOOGLE_API_KEY|GOOGLE_GENAI_API_KEY)=' "${file}"; then
        add_check "${id}" "safety" "warn" "${file} declares a model API/auth override; remove it to preserve subscription-only routing"
    else
        add_check "${id}" "safety" "pass" "${file} has no model API/auth override declarations"
    fi
}

check_model_api_key_file "${SPECTRA_HOME}/.env" "spectra-model-api-keys"
if [[ "${PROJECT_ROOT}/.env" != "${SPECTRA_HOME}/.env" ]]; then
    check_model_api_key_file "${PROJECT_ROOT}/.env" "project-model-api-keys"
fi

VERIFY_FILE="${PROJECT_ROOT}/.spectra/verify.yaml"
if [[ -f "${VERIFY_FILE}" ]] && command -v grep >/dev/null 2>&1; then
    runtime_command=$(awk '/^runtime:/{f=1;next} /^[^[:space:]#]/{f=0} f{print}' "${VERIFY_FILE}" 2>/dev/null \
        | grep -oP '^\s*command:\s*"?\K[^"#]*' | head -1 | sed 's/[[:space:]]*$//' || true)
    if [[ -n "${runtime_command}" ]]; then
        add_check "runtime-command" "safety" "warn" "verify.yaml contains a trusted shell command; review before enabling probes"
    fi
fi

if command -v git >/dev/null 2>&1 && git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C "${PROJECT_ROOT}" status --porcelain 2>/dev/null || true)" ]]; then
        add_check "worktree" "info" "pass" "Git worktree has local changes; preserve them during SPECTRA runs"
    else
        add_check "worktree" "info" "pass" "Git worktree is clean"
    fi
fi

overall="pass"
if [[ ${REQUIRED_FAILURES} -gt 0 ]]; then
    overall="fail"
elif [[ ${WARNINGS} -gt 0 ]]; then
    overall="warn"
fi

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "${value}"
}

if [[ "${OUTPUT_JSON}" == "true" ]]; then
    printf '{"status":"%s","strict":%s,"projectRoot":"%s","spectraHome":"%s","summary":{"requiredFailures":%d,"warnings":%d,"checks":%d},"checks":[' \
        "${overall}" "${STRICT}" "$(json_escape "${PROJECT_ROOT}")" "$(json_escape "${SPECTRA_HOME}")" \
        "${REQUIRED_FAILURES}" "${WARNINGS}" "${#CHECK_IDS[@]}"
    for ((i=0; i<${#CHECK_IDS[@]}; i++)); do
        [[ ${i} -gt 0 ]] && printf ','
        printf '{"id":"%s","level":"%s","status":"%s","detail":"%s"}' \
            "$(json_escape "${CHECK_IDS[$i]}")" "$(json_escape "${CHECK_LEVELS[$i]}")" \
            "$(json_escape "${CHECK_STATUSES[$i]}")" "$(json_escape "${CHECK_DETAILS[$i]}")"
    done
    printf ']}\n'
else
    echo "SPECTRA Doctor"
    echo "  project: ${PROJECT_ROOT}"
    echo "  install: ${SPECTRA_HOME}"
    echo ""
    for ((i=0; i<${#CHECK_IDS[@]}; i++)); do
        case "${CHECK_STATUSES[$i]}" in
            pass) marker="PASS" ;;
            warn) marker="WARN" ;;
            fail) marker="FAIL" ;;
        esac
        printf '  %-4s %-13s %-24s %s\n' "${marker}" "${CHECK_LEVELS[$i]}" "${CHECK_IDS[$i]}" "${CHECK_DETAILS[$i]}"
    done
    echo ""
    echo "Result: ${overall^^} (${REQUIRED_FAILURES} required failure(s), ${WARNINGS} warning(s))"
fi

if [[ ${REQUIRED_FAILURES} -gt 0 ]]; then
    exit 1
fi
if [[ "${STRICT}" == "true" && ${WARNINGS} -gt 0 ]]; then
    exit 1
fi
exit 0
