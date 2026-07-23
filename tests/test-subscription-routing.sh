#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: every model call is pinned to prepaid Claude subscription auth.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME_REAL="$(dirname "${SCRIPT_DIR}")"
RUNNER="${SPECTRA_HOME_REAL}/bin/spectra-agent-run.sh"
MANIFEST="${SPECTRA_HOME_REAL}/config/agent-runtimes.tsv"

PASS=0
FAIL=0
tmp_dir=""
cleanup() { [[ -n "${tmp_dir}" ]] && rm -rf "${tmp_dir}"; }
trap cleanup EXIT
tmp_dir=$(mktemp -d)

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

fixture_bin="${tmp_dir}/bin"
fixture_log="${tmp_dir}/claude.log"
mkdir -p "${fixture_bin}"
cat > "${fixture_bin}/claude" <<'CLAUDE'
#!/usr/bin/env bash
set -euo pipefail
clean=true
for key in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_CUSTOM_HEADERS \
    ANTHROPIC_AWS_API_KEY ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_FOUNDRY_API_KEY \
    ANTHROPIC_FOUNDRY_AUTH_TOKEN ANTHROPIC_VERTEX_BASE_URL AWS_BEARER_TOKEN_BEDROCK \
    CLAUDE_CODE_USE_ANTHROPIC_AWS CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX \
    CLAUDE_CODE_USE_FOUNDRY CLAUDE_CODE_USE_MANTLE; do
    if [[ -n "${!key:-}" ]]; then clean=false; fi
done
settings_guard=false
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--settings" ]]; then
        next=$((i + 1))
        settings_value="${!next:-}"
        if [[ "${settings_value}" == *'"apiKeyHelper":""'* \
           && "${settings_value}" == *'"ANTHROPIC_API_KEY":""'* \
           && "${settings_value}" == *'"ANTHROPIC_FOUNDRY_API_KEY":""'* \
           && "${settings_value}" == *'"CLAUDE_CODE_USE_VERTEX":""'* ]]; then
            settings_guard=true
        fi
    fi
done
if [[ " $* " == *" auth status "* ]]; then
    printf 'auth_env=%s settings_guard=%s oauth=%s\n' \
        "${clean}" "${settings_guard}" "${CLAUDE_CODE_OAUTH_TOKEN:-missing}" >> "${FAKE_CLAUDE_LOG}"
    printf '{"loggedIn":true,"authMethod":"%s","subscriptionType":%s}\n' \
        "${FAKE_AUTH_METHOD:-claude.ai}" "${FAKE_SUBSCRIPTION_JSON:-\"max\"}"
    exit 0
fi
printf 'run_env=%s settings_guard=%s oauth=%s args=' \
    "${clean}" "${settings_guard}" "${CLAUDE_CODE_OAUTH_TOKEN:-missing}" >> "${FAKE_CLAUDE_LOG}"
printf '%q ' "$@" >> "${FAKE_CLAUDE_LOG}"
printf '\n' >> "${FAKE_CLAUDE_LOG}"
printf '%s\n' 'fixture agent result'
CLAUDE
chmod +x "${fixture_bin}/claude"

export PATH="${fixture_bin}:${PATH}"
export FAKE_CLAUDE_LOG="${fixture_log}"

echo "  Test: runner and runtime manifest exist"
if [[ -x "${RUNNER}" && -f "${MANIFEST}" ]]; then
    pass "subscription runner and manifest present"
else
    fail "subscription runner or manifest missing"
fi

echo "  Test: manifest covers every SPECTRA agent exactly once"
manifest_agents=$(awk -F'|' 'NF && $1 !~ /^#/ {print $1}' "${MANIFEST}" | sort)
definition_agents=$(find "${SPECTRA_HOME_REAL}/agents" -maxdepth 1 -type f -name 'spectra-*.md' \
    -printf '%f\n' | sed 's/\.md$//' | sort)
if [[ "${manifest_agents}" == "${definition_agents}" ]] \
   && [[ $(printf '%s\n' "${manifest_agents}" | wc -l) -eq 7 ]]; then
    pass "all seven agents have one runtime declaration"
else
    fail "manifest/definition coverage differs"
fi

echo "  Test: every runtime is subscription-only Claude CLI"
if awk -F'|' 'NF && $1 !~ /^#/ {
        if ($2 != "claude_cli" || $3 != "subscription" || $4 != "claude.ai" || $6 != "claude-subscription") exit 1
    }' "${MANIFEST}"; then
    pass "all agent rows bind to prepaid subscription auth"
else
    fail "manifest contains a metered or ambiguous runtime"
fi

echo "  Test: --check verifies subscription auth"
check_output=$("${RUNNER}" --check)
if grep -q 'billing=subscription auth=claude.ai plan=max agents=7' <<< "${check_output}"; then
    pass "subscription check reports driver, auth, plan, and coverage"
else
    fail "unexpected subscription check: ${check_output}"
fi

echo "  Test: API credentials are stripped from auth and agent processes"
: > "${fixture_log}"
agent_output=$(ANTHROPIC_API_KEY=api-secret \
    ANTHROPIC_AUTH_TOKEN=token-secret \
    ANTHROPIC_BASE_URL=https://metered.invalid \
    ANTHROPIC_CUSTOM_HEADERS=billing-override \
    ANTHROPIC_AWS_API_KEY=aws-api-secret \
    ANTHROPIC_FOUNDRY_API_KEY=foundry-api-secret \
    ANTHROPIC_FOUNDRY_AUTH_TOKEN=foundry-token-secret \
    AWS_BEARER_TOKEN_BEDROCK=bedrock-api-secret \
    CLAUDE_CODE_OAUTH_TOKEN=subscription-oauth \
    CLAUDE_CODE_USE_ANTHROPIC_AWS=1 \
    CLAUDE_CODE_USE_BEDROCK=1 \
    CLAUDE_CODE_USE_VERTEX=1 \
    CLAUDE_CODE_USE_FOUNDRY=1 \
    CLAUDE_CODE_USE_MANTLE=1 \
    ANTHROPIC_BEDROCK_BASE_URL=https://bedrock.invalid \
    ANTHROPIC_VERTEX_BASE_URL=https://vertex.invalid \
    ANTHROPIC_FOUNDRY_BASE_URL=https://foundry.invalid \
    "${RUNNER}" spectra-builder -p 'test prompt')
if [[ "${agent_output}" == "fixture agent result" ]] \
   && [[ $(grep -c '^auth_env=true settings_guard=true oauth=subscription-oauth$' "${fixture_log}") -eq 1 ]] \
   && grep -q '^run_env=true settings_guard=true oauth=subscription-oauth args=' "${fixture_log}" \
   && grep -q -- '--agent spectra-builder --model opus -p test\\ prompt ' "${fixture_log}"; then
    set +e
    injected_output=$("${RUNNER}" spectra-builder -p test --settings '{"env":{"ANTHROPIC_API_KEY":"injected"}}' 2>&1)
    injected_exit=$?
    set -e
    if [[ ${injected_exit} -ne 0 ]] && grep -q 'may not override subscription routing' <<< "${injected_output}"; then
        pass "shell/settings billing overrides are blocked while subscription OAuth is retained"
    else
        fail "caller-supplied settings were not rejected"
    fi
else
    fail "credential/settings guard or argument forwarding failed"
fi

echo "  Test: non-subscription auth fails closed"
set +e
bad_auth_output=$(FAKE_AUTH_METHOD=apiKey "${RUNNER}" --check 2>&1)
bad_auth_exit=$?
set -e
if [[ ${bad_auth_exit} -ne 0 ]] && grep -q "not the required claude.ai subscription" <<< "${bad_auth_output}"; then
    pass "API-key auth is rejected"
else
    fail "API-key auth was not rejected"
fi

echo "  Test: missing subscription type fails closed"
set +e
no_plan_output=$(FAKE_SUBSCRIPTION_JSON=null "${RUNNER}" --check 2>&1)
no_plan_exit=$?
set -e
if [[ ${no_plan_exit} -ne 0 ]] && grep -q 'no subscription type' <<< "${no_plan_output}"; then
    pass "missing prepaid plan is rejected"
else
    fail "missing prepaid plan was not rejected"
fi

echo "  Test: undeclared agent fails closed"
set +e
unknown_output=$("${RUNNER}" spectra-unknown -p test 2>&1)
unknown_exit=$?
set -e
if [[ ${unknown_exit} -ne 0 ]] && grep -q 'not declared' <<< "${unknown_output}"; then
    pass "undeclared agent is rejected"
else
    fail "undeclared agent was not rejected"
fi

echo "  Test: manifest billing, model parity, duplicates, and absence fail closed"
bad_manifest="${tmp_dir}/bad-runtimes.tsv"
sed 's/spectra-planner|claude_cli|subscription/spectra-planner|openai_api|per-token/' \
    "${MANIFEST}" > "${bad_manifest}"
set +e
bad_manifest_output=$(SPECTRA_AGENT_RUNTIME_MANIFEST="${bad_manifest}" "${RUNNER}" --check 2>&1)
bad_manifest_exit=$?
set -e
model_drift_manifest="${tmp_dir}/model-drift-runtimes.tsv"
sed 's/spectra-planner|claude_cli|subscription|claude.ai|opus|/spectra-planner|claude_cli|subscription|claude.ai|sonnet|/' \
    "${MANIFEST}" > "${model_drift_manifest}"
set +e
model_drift_output=$(SPECTRA_AGENT_RUNTIME_MANIFEST="${model_drift_manifest}" "${RUNNER}" --check 2>&1)
model_drift_exit=$?
duplicate_manifest="${tmp_dir}/duplicate-runtimes.tsv"
cp "${MANIFEST}" "${duplicate_manifest}"
awk -F'|' '$1 == "spectra-planner" {print; exit}' "${MANIFEST}" >> "${duplicate_manifest}"
duplicate_output=$(SPECTRA_AGENT_RUNTIME_MANIFEST="${duplicate_manifest}" "${RUNNER}" --check 2>&1)
duplicate_exit=$?
missing_output=$(SPECTRA_AGENT_RUNTIME_MANIFEST="${tmp_dir}/missing.tsv" "${RUNNER}" --check 2>&1)
missing_exit=$?
set -e
if [[ ${bad_manifest_exit} -ne 0 ]] && grep -q 'forbidden driver' <<< "${bad_manifest_output}" \
   && [[ ${model_drift_exit} -ne 0 ]] && grep -q 'model mismatch' <<< "${model_drift_output}" \
   && [[ ${duplicate_exit} -ne 0 ]] && grep -q 'duplicate agent runtime' <<< "${duplicate_output}" \
   && [[ ${missing_exit} -ne 0 ]] && grep -q 'manifest is missing' <<< "${missing_output}"; then
    pass "metered, drifted, duplicate, and missing manifests are rejected"
else
    fail "one or more invalid manifest cases were accepted"
fi

echo "  Test: every SPECTRA execution site uses the subscription runner"
bare_calls=$(rg -n '(^|[[:space:]])claude[[:space:]]+--agent' \
    "${SPECTRA_HOME_REAL}/bin" "${SPECTRA_HOME_REAL}/lib" \
    -g '*.sh' -g '!spectra-agent-run.sh' || true)
runner_calls=$(rg -l 'spectra-agent-run\.sh.*spectra-(planner|builder|verifier|auditor|reviewer|scout|oracle)' \
    "${SPECTRA_HOME_REAL}/bin" "${SPECTRA_HOME_REAL}/lib" -g '*.sh' | wc -l)
if [[ -z "${bare_calls}" && ${runner_calls} -ge 5 ]]; then
    pass "no bare Claude agent invocation remains"
else
    fail "bare calls remain or routing coverage is too small: ${bare_calls}"
fi

echo "  Test: every agent advertises its subscription binding"
metadata_count=$(rg -l 'billing: subscription' "${SPECTRA_HOME_REAL}"/agents/spectra-*.md | wc -l)
compat_count=$(rg -l 'Invoked only through spectra-agent-run\.sh' "${SPECTRA_HOME_REAL}"/agents/spectra-*.md | wc -l)
if [[ ${metadata_count} -eq 7 && ${compat_count} -eq 7 ]]; then
    pass "all agent contracts name the prepaid route"
else
    fail "agent subscription metadata incomplete (${metadata_count}/7, ${compat_count}/7)"
fi

echo "  Test: billing documentation preserves required distinctions"
routing_doc="${SPECTRA_HOME_REAL}/docs/SUBSCRIPTION_ROUTING.md"
if grep -q 'txwos-media-mcp.*not a subscription precedent' "${routing_doc}" \
   && grep -q 'billing-enabled `GEMINI_API_KEY`' "${routing_doc}" \
   && grep -q '`google-flow-media` browser workflow' "${routing_doc}" \
   && grep -q 'same-lineage' "${routing_doc}" \
   && grep -q 'does not mean.*unlimited' "${routing_doc}" \
   && grep -q 'legacy.*informational' "${routing_doc}" \
   && grep -q 'does not meter or enforce USD spend' "${routing_doc}" \
   && grep -q 'Linear uses `LINEAR_API_KEY`' "${routing_doc}" \
   && grep -q 'Slack uses a webhook' "${routing_doc}" \
   && ! rg -q -i '\$0|different model architecture|minimal cost' \
        "${routing_doc}" "${SPECTRA_HOME_REAL}/README.md" "${SPECTRA_HOME_REAL}/SKILL.md" \
        "${SPECTRA_HOME_REAL}/agents"; then
    pass "media, integration, lineage, quota, and legacy-budget claims are explicit"
else
    fail "subscription billing documentation drifted or regained a false claim"
fi

echo ""
echo "  subscription-routing: ${PASS} passed, ${FAIL} failed"
echo "SPECTRA_TEST_RESULT suite=subscription-routing pass=${PASS} fail=${FAIL} skip=0 total=$((PASS + FAIL))"

[[ ${FAIL} -eq 0 ]]
