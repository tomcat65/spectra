#!/usr/bin/env bash
set -euo pipefail

# SPECTRA subscription-only agent launcher.
# Every model invocation passes through this boundary so shell or Claude
# settings cannot silently switch the operator's prepaid subscription to a
# per-token/API-provider route.

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
SPECTRA_HOME="${SPECTRA_HOME:-${SCRIPT_DIR%/*}}"
RUNTIME_MANIFEST="${SPECTRA_AGENT_RUNTIME_MANIFEST:-${SPECTRA_HOME}/config/agent-runtimes.tsv}"

# Claude settings env entries override the parent shell. The final --settings
# argument therefore clears billing/provider routes a second time, including
# apiKeyHelper. This is deliberately separate from subscription OAuth variables
# (CLAUDE_CODE_OAUTH_TOKEN / REFRESH_TOKEN), which are valid prepaid auth.
MODEL_BILLING_OVERRIDES=(
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
)
SUBSCRIPTION_GUARD_SETTINGS='{"apiKeyHelper":"","env":{"ANTHROPIC_API_KEY":"","ANTHROPIC_AUTH_TOKEN":"","ANTHROPIC_BASE_URL":"","ANTHROPIC_CUSTOM_HEADERS":"","ANTHROPIC_AWS_API_KEY":"","ANTHROPIC_AWS_BASE_URL":"","ANTHROPIC_AWS_WORKSPACE_ID":"","ANTHROPIC_BEDROCK_BASE_URL":"","ANTHROPIC_BEDROCK_MANTLE_BASE_URL":"","ANTHROPIC_FOUNDRY_API_KEY":"","ANTHROPIC_FOUNDRY_AUTH_TOKEN":"","ANTHROPIC_FOUNDRY_BASE_URL":"","ANTHROPIC_FOUNDRY_RESOURCE":"","ANTHROPIC_VERTEX_BASE_URL":"","ANTHROPIC_VERTEX_PROJECT_ID":"","ANTHROPIC_WORKSPACE_ID":"","AWS_BEARER_TOKEN_BEDROCK":"","CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST":"","CLAUDE_CODE_USE_ANTHROPIC_AWS":"","CLAUDE_CODE_USE_BEDROCK":"","CLAUDE_CODE_USE_FOUNDRY":"","CLAUDE_CODE_USE_MANTLE":"","CLAUDE_CODE_USE_VERTEX":"","CLAUDE_CODE_SKIP_BEDROCK_AUTH":"","CLAUDE_CODE_SKIP_VERTEX_AUTH":""}}'

usage() {
    cat <<'USAGE'
Usage:
  spectra-agent-run.sh --check
  spectra-agent-run.sh AGENT [CLAUDE_ARGS...]

Policy:
  - AGENT must be declared in config/agent-runtimes.tsv.
  - The declared driver must be claude_cli with subscription billing.
  - Claude auth must resolve to claude.ai with an active subscription type.
  - Per-token keys, credential helpers, and alternate provider routes are
    cleared in both the shell environment and Claude settings.
  - Subscription OAuth tokens are allowed; caller-supplied settings, agents,
    primary models, and bare mode are rejected.
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

clean_claude_env() {
    (
        unset "${MODEL_BILLING_OVERRIDES[@]}"
        exec "$@"
    )
}

reject_routing_overrides() {
    local argument
    for argument in "$@"; do
        case "${argument}" in
            --agent|--agent=*|--agents|--agents=*|--bare|--betas|--betas=*|\
            --model|--model=*|--setting-sources|--setting-sources=*|--settings|--settings=*)
                fail "caller may not override subscription routing with: ${argument}"
                ;;
        esac
    done
}

manifest_rows() {
    awk -F'|' 'NF && $1 !~ /^#/ {print}' "${RUNTIME_MANIFEST}"
}

validate_manifest() {
    [[ -f "${RUNTIME_MANIFEST}" ]] || fail "agent runtime manifest is missing: ${RUNTIME_MANIFEST}"
    [[ "$(head -1 "${RUNTIME_MANIFEST}")" == "# schema=spectra-agent-runtime/v1" ]] \
        || fail "unsupported or missing agent runtime schema"

    local -A seen=()
    local row agent driver billing auth_method model plan extra
    local count=0
    while IFS= read -r row; do
        IFS='|' read -r agent driver billing auth_method model plan extra <<< "${row}"
        if [[ -z "${agent}" || -z "${driver}" || -z "${billing}" || -z "${auth_method}" \
              || -z "${model}" || -z "${plan}" || -n "${extra:-}" ]]; then
            fail "invalid agent runtime row: ${row}"
        fi
        [[ -z "${seen[${agent}]+x}" ]] || fail "duplicate agent runtime: ${agent}"
        seen["${agent}"]=1
        [[ "${driver}" == "claude_cli" ]] || fail "${agent} uses forbidden driver: ${driver}"
        [[ "${billing}" == "subscription" ]] || fail "${agent} uses forbidden billing: ${billing}"
        [[ "${auth_method}" == "claude.ai" ]] || fail "${agent} uses forbidden auth: ${auth_method}"
        [[ "${plan}" == "claude-subscription" ]] || fail "${agent} has no prepaid plan binding"

        local definition="${SPECTRA_HOME}/agents/${agent}.md"
        [[ -f "${definition}" ]] || fail "agent definition is missing: ${definition}"
        local declared_model
        declared_model=$(awk '/^model:[[:space:]]*/ {print $2; exit}' "${definition}")
        [[ "${declared_model}" == "${model}" ]] \
            || fail "${agent} model mismatch: manifest=${model}, definition=${declared_model:-missing}"
        count=$((count + 1))
    done < <(manifest_rows)

    local definition_count
    definition_count=$(find "${SPECTRA_HOME}/agents" -maxdepth 1 -type f -name 'spectra-*.md' | wc -l)
    [[ ${count} -eq ${definition_count} ]] \
        || fail "runtime manifest covers ${count}/${definition_count} SPECTRA agents"
}

lookup_agent() {
    local requested="$1"
    local matches
    matches=$(manifest_rows | awk -F'|' -v agent="${requested}" '$1 == agent {print}')
    [[ -n "${matches}" ]] || fail "agent is not declared in the subscription manifest: ${requested}"
    [[ $(printf '%s\n' "${matches}" | wc -l) -eq 1 ]] \
        || fail "agent has multiple runtime declarations: ${requested}"
    printf '%s\n' "${matches}"
}

verify_subscription_auth() {
    local claude_bin="$1"
    local auth_status auth_method subscription_type
    if ! auth_status=$(clean_claude_env "${claude_bin}" --settings \
        "${SUBSCRIPTION_GUARD_SETTINGS}" auth status 2>/dev/null); then
        fail "Claude authentication check failed; sign in with 'claude auth login'"
    fi
    auth_method=$(printf '%s\n' "${auth_status}" \
        | sed -n 's/.*"authMethod":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    subscription_type=$(printf '%s\n' "${auth_status}" \
        | sed -n 's/.*"subscriptionType":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [[ "${auth_method}" == "claude.ai" ]] \
        || fail "Claude auth is '${auth_method:-unknown}', not the required claude.ai subscription"
    [[ -n "${subscription_type}" ]] \
        || fail "Claude auth has no subscription type; refusing possible per-token billing"
    SPECTRA_SUBSCRIPTION_TYPE="${subscription_type}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

validate_manifest

claude_bin=$(command -v claude 2>/dev/null || true)
[[ -n "${claude_bin}" ]] || fail "Claude Code CLI is missing"
verify_subscription_auth "${claude_bin}"

if [[ "${1:-}" == "--check" ]]; then
    agent_count=$(manifest_rows | wc -l)
    printf 'SPECTRA_AGENT_RUNTIME driver=claude_cli billing=subscription auth=claude.ai plan=%s agents=%d\n' \
        "${SPECTRA_SUBSCRIPTION_TYPE}" "${agent_count}"
    exit 0
fi

if [[ $# -eq 0 ]]; then
    usage
    exit 2
fi

agent="$1"
shift
runtime_row=$(lookup_agent "${agent}")
IFS='|' read -r _agent _driver _billing _auth_method model _plan <<< "${runtime_row}"
reject_routing_overrides "$@"

clean_claude_env "${claude_bin}" --settings "${SUBSCRIPTION_GUARD_SETTINGS}" \
    --agent "${agent}" --model "${model}" "$@"
