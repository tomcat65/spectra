#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: environment/safety doctor human and JSON contracts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_ROOT="$(dirname "${SCRIPT_DIR}")"
DOCTOR="${SPECTRA_ROOT}/bin/spectra-doctor.sh"

PASS=0
FAIL=0
SKIP=0
pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT

# GitHub's test runner does not install Claude Code. Provide a deterministic
# executable fixture so this suite tests doctor behavior rather than CI image
# composition; the explicit PATH=/nonexistent case below still proves failure.
fixture_bin="${tmp_root}/bin"; mkdir -p "${fixture_bin}"
cat > "${fixture_bin}/claude" <<'CLAUDE'
#!/usr/bin/env bash
if [[ " $* " == *" auth status "* ]]; then
    printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}'
    exit 0
fi
echo "claude fixture"
CLAUDE
chmod +x "${fixture_bin}/claude"
export PATH="${fixture_bin}:${PATH}"

echo "  Test: spectra-doctor.sh exists and is executable"
if [[ -x "${DOCTOR}" ]]; then pass "doctor executable"; else fail "doctor missing"; fi

echo "  Test: --help documents JSON, strict, and exit codes"
help_out=$("${DOCTOR}" --help)
if echo "${help_out}" | grep -q -- '--json' && echo "${help_out}" | grep -q -- '--strict' \
   && echo "${help_out}" | grep -q 'Exit codes'; then
    pass "help contract complete"
else
    fail "help contract incomplete"
fi

echo "  Test: default doctor succeeds when required capabilities exist"
set +e; report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" --json); rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "default allows recommended gaps"; else fail "default rc=${rc}"; fi

echo "  Test: JSON report is valid and closed over its check count"
if echo "${report}" | jq -e '.status == "warn" and (.checks | length) == .summary.checks' >/dev/null; then
    pass "JSON contract valid"
else
    fail "invalid JSON contract"
fi

echo "  Test: required tools are distinguished from recommended tools"
if echo "${report}" | jq -e '.checks[] | select(.id == "git" and .level == "required")' >/dev/null \
   && echo "${report}" | jq -e '.checks[] | select(.id == "actionlint" and .level == "recommended")' >/dev/null \
   && echo "${report}" | jq -e '.checks[] | select(.id == "claude-subscription" and .status == "pass")' >/dev/null; then
    pass "capability levels present"
else
    fail "capability levels missing"
fi

echo "  Test: ambient model API keys are warned and never exposed"
set +e
api_env_report=$(ANTHROPIC_API_KEY=secret-sentinel ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" --json)
rc=$?
set -e
if [[ ${rc} -eq 0 ]] \
   && echo "${api_env_report}" | jq -e '.checks[] | select(.id == "model-api-environment" and .status == "warn")' >/dev/null \
   && ! echo "${api_env_report}" | grep -q 'secret-sentinel'; then
    pass "ambient API override is reported without its value"
else
    fail "ambient API override handling rc=${rc}"
fi

echo "  Test: strict mode fails on a deterministic recommended gap"
set +e; ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" --strict --json >/dev/null; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "strict warning -> exit 1"; else fail "strict rc=${rc}"; fi

echo "  Test: missing required toolchain fails even outside strict mode"
set +e; missing_report=$(env PATH=/nonexistent /usr/bin/bash "${DOCTOR}" --json); rc=$?; set -e
if [[ ${rc} -eq 1 ]] && echo "${missing_report}" | jq -e '.status == "fail" and .summary.requiredFailures > 0' >/dev/null; then
    pass "required gaps -> failure"
else
    fail "required gap rc=${rc}"
fi

echo "  Test: unsafe project .env permissions are reported without exposing content"
project_env="${tmp_root}/project-env"; mkdir -p "${project_env}"
printf '%s\n' 'TOP_SECRET_SENTINEL=do-not-print' > "${project_env}/.env"
chmod 644 "${project_env}/.env"
set +e; env_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" "${project_env}" --json); rc=$?; set -e
if [[ ${rc} -eq 0 ]] && echo "${env_report}" | jq -e '.checks[] | select(.id == "project-env-permissions" and .status == "warn")' >/dev/null \
   && ! echo "${env_report}" | grep -q 'TOP_SECRET_SENTINEL'; then
    pass "unsafe permissions reported, secret redacted"
else
    fail "env safety report rc=${rc}"
fi

echo "  Test: safe project .env permissions pass"
chmod 600 "${project_env}/.env"
safe_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" "${project_env}" --json)
if echo "${safe_report}" | jq -e '.checks[] | select(.id == "project-env-permissions" and .status == "pass")' >/dev/null; then
    pass "safe permissions pass"
else
    fail "safe permissions not recognized"
fi

echo "  Test: model API declarations in project .env are warned without exposing values"
printf '%s\n' 'GEMINI_API_KEY=gemini-secret-sentinel' > "${project_env}/.env"
chmod 600 "${project_env}/.env"
model_key_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" "${project_env}" --json)
if echo "${model_key_report}" | jq -e '.checks[] | select(.id == "project-model-api-keys" and .status == "warn")' >/dev/null \
   && ! echo "${model_key_report}" | grep -q 'gemini-secret-sentinel'; then
    pass "project model API declaration is reported without its value"
else
    fail "project model API declaration warning missing"
fi

echo "  Test: configured runtime shell command is surfaced as a safety warning"
project_runtime="${tmp_root}/project-runtime"; mkdir -p "${project_runtime}/.spectra"
cat > "${project_runtime}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: "curl -fsS http://127.0.0.1/health"
YAML
runtime_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" "${project_runtime}" --json)
if echo "${runtime_report}" | jq -e '.checks[] | select(.id == "runtime-command" and .status == "warn")' >/dev/null; then
    pass "runtime command warning present"
else
    fail "runtime command warning missing"
fi

echo "  Test: empty documented runtime command does not produce a false warning"
project_empty_runtime="${tmp_root}/project-empty-runtime"; mkdir -p "${project_empty_runtime}/.spectra"
cat > "${project_empty_runtime}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: ""              # e.g. "curl -fsS localhost/health"
YAML
empty_runtime_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}" "${project_empty_runtime}" --json)
if ! echo "${empty_runtime_report}" | jq -e '.checks[] | select(.id == "runtime-command")' >/dev/null; then
    pass "empty runtime command ignored"
else
    fail "empty runtime command produced warning"
fi

echo "  Test: human report includes result and capability categories"
human_report=$(ACTIONLINT_BIN=/definitely/missing "${DOCTOR}")
if echo "${human_report}" | grep -q '^Result: WARN' && echo "${human_report}" | grep -q 'required'; then
    pass "human report contract"
else
    fail "human report incomplete"
fi

echo "  Test: invalid project path exits 2"
set +e; "${DOCTOR}" "${tmp_root}/does-not-exist" --json >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "invalid path -> exit 2"; else fail "invalid path rc=${rc}"; fi

echo ""
echo "  doctor: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=doctor pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"
[[ ${FAIL} -eq 0 ]]
