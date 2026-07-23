#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: Opt-in runtime/deploy probe (spectra-runtime-probe.sh)
# Validates command/HTTP probe modes, exit-code contract (0 pass / 1 assert /
# 2 connect-or-unconfigured), and verifier Step 5 opt-in gating.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_DIR="$(dirname "${SCRIPT_DIR}")"
PROBE="${SPECTRA_DIR}/bin/spectra-runtime-probe.sh"
VERIFY="${SPECTRA_DIR}/bin/spectra-verify.sh"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# ── Test 1: script exists and is executable ──
echo "  Test: spectra-runtime-probe.sh exists and is executable"
if [[ -x "${PROBE}" ]]; then pass "exists and executable"; else fail "not found/executable"; fi

# ── Test 2: --help exits 0 with Usage ──
echo "  Test: --help exits 0 with Usage"
set +e; out=$("${PROBE}" --help 2>&1); rc=$?; set -e
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q 'Usage'; then pass "--help ok"; else fail "--help rc=${rc}"; fi

# ── Test 3: --self-test passes ──
echo "  Test: --self-test passes"
set +e; "${PROBE}" --self-test >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "self-test passed"; else fail "self-test rc=${rc}"; fi

# ── Test 4: command-mode pass -> exit 0 ──
echo "  Test: command-mode success exits 0"
set +e; "${PROBE}" --command "true" --retries 1 >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "command pass -> 0"; else fail "expected 0 got ${rc}"; fi

# ── Test 5: command-mode assertion failure -> exit 1 ──
echo "  Test: command-mode failure exits 1"
set +e; "${PROBE}" --command "false" --retries 2 --interval 1 >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "command fail -> 1"; else fail "expected 1 got ${rc}"; fi

# ── Test 6: no config -> exit 2 ──
echo "  Test: no url/command exits 2"
set +e; env -u SPECTRA_PROBE_URL -u SPECTRA_PROBE_COMMAND "${PROBE}" --retries 1 >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "unconfigured -> 2"; else fail "expected 2 got ${rc}"; fi

# ── Test 7: unknown option -> exit 2 ──
echo "  Test: unknown option exits 2"
set +e; "${PROBE}" --bogus >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "unknown opt -> 2"; else fail "expected 2 got ${rc}"; fi

# ── Test 8: env var config drives the probe (SPECTRA_PROBE_COMMAND) ──
echo "  Test: SPECTRA_PROBE_COMMAND env drives probe"
set +e; SPECTRA_PROBE_COMMAND="true" SPECTRA_PROBE_RETRIES=1 "${PROBE}" >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 0 ]]; then pass "env command -> 0"; else fail "expected 0 got ${rc}"; fi

# ── Test 9: a hung command is bounded and classified as unreachable ──
echo "  Test: command timeout exits 2 without hanging"
started=${SECONDS}
set +e; "${PROBE}" --command "sleep 3" --timeout 1 --retries 1 >/dev/null 2>&1; rc=$?; set -e
elapsed=$((SECONDS - started))
if [[ ${rc} -eq 2 && ${elapsed} -lt 3 ]]; then
    pass "timeout -> 2 in ${elapsed}s"
else
    fail "timeout rc=${rc} elapsed=${elapsed}s"
fi

# ── Tests 10-11: HTTP-mode pass/mismatch against a local server ──
echo "  Test: HTTP-mode pass against local server"
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    srv_dir=$(mktemp -d); echo "probe-ok-body" > "${srv_dir}/index.html"
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
    ( cd "${srv_dir}" && exec python3 -m http.server "${port}" --bind 127.0.0.1 ) >/dev/null 2>&1 &
    srv_pid=$!
    ok=""
    for _ in $(seq 1 20); do
        if curl -sS -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then ok=1; break; fi
        sleep 0.3
    done
    if [[ -n "${ok}" ]]; then
        set +e
        "${PROBE}" --url "http://127.0.0.1:${port}/" --expect-status 200 --expect-body "probe-ok-body" --retries 5 --interval 1 >/dev/null 2>&1
        rc=$?
        set -e
        if [[ ${rc} -eq 0 ]]; then pass "http pass -> 0"; else fail "http expected 0 got ${rc}"; fi

        echo "  Test: HTTP-mode status mismatch exits 1"
        set +e
        "${PROBE}" --url "http://127.0.0.1:${port}/" --expect-status 503 --retries 1 >/dev/null 2>&1
        rc=$?
        set -e
        if [[ ${rc} -eq 1 ]]; then pass "http status-mismatch -> 1"; else fail "http expected 1 got ${rc}"; fi
    else
        echo "  SKIP  local server did not come up"; SKIP=$((SKIP + 1))
        echo "  SKIP  http status-mismatch (no server)"; SKIP=$((SKIP + 1))
    fi
    kill "${srv_pid}" >/dev/null 2>&1 || true
    wait "${srv_pid}" 2>/dev/null || true
    rm -rf "${srv_dir}"
else
    echo "  SKIP  python3/curl unavailable"; SKIP=$((SKIP + 1))
    echo "  SKIP  http status-mismatch (no tools)"; SKIP=$((SKIP + 1))
fi

# ── Test 12: verifier wires explicit + scope-aware Step 5 activation ──
echo "  Test: spectra-verify.sh has explicit and scope-aware activation"
if grep -q 'runtime_probe_enabled' "${VERIFY}" && grep -q 'infra|deploy' "${VERIFY}"; then
    pass "verifier Step 5 activation wired"
else
    fail "verifier Step 5 not wired"
fi

# ── Test 13: verifier defaults to advisory (non-blocking) ──
echo "  Test: probe defaults to advisory in verifier"
if grep -q 'PROBE_BLOCKING="false"' "${VERIFY}"; then pass "advisory default"; else fail "no advisory default"; fi

# ── Test 14: verify.yaml template documents runtime + timeout ──
echo "  Test: verify.yaml.template has runtime block"
if grep -q '^runtime:' "${SPECTRA_DIR}/templates/verify.yaml.template" \
   && grep -q '^[[:space:]]*timeout:' "${SPECTRA_DIR}/templates/verify.yaml.template"; then
    pass "runtime block + timeout present"
else
    fail "runtime block or timeout missing"
fi

# ── Test 15: environment-driven standalone config is present ──
echo "  Test: SPECTRA_HOME not required (probe is standalone)"
if grep -q 'SPECTRA_PROBE_URL' "${PROBE}"; then pass "env-driven config present"; else fail "missing env config"; fi

# ── End-to-end verifier Step 5 (advisory vs blocking) ──
# Builds a minimal schema-valid project and runs the real verifier so the
# advisory-default and blocking-gate behavior is exercised, not just grepped.
# (Regression guard: a string-only test once missed that env blocking did not
# actually gate the verdict because "1" != "true".)
make_min_project() {
    local p="$1"
    mkdir -p "${p}/.spectra" "${p}/src"
    cat > "${p}/.spectra/plan.md" <<'PLAN'
# SPECTRA Execution Plan

## Project: probe-e2e
## Level: 0
## Generated: 2026-06-15

---

## Task 001: trivial
- [x] 001: trivial
- AC:
  - prints ok
- Files: src/app.sh
- Verify: `true`
- Risk: low
- Max-iterations: 3
- Scope: code
PLAN
    echo 'echo ok' > "${p}/src/app.sh"
    ( cd "${p}" && git init -q && git config user.email t@t.co && git config user.name t \
        && git add -A && git commit -qm "feat(task-001): trivial" ) >/dev/null 2>&1
}

if command -v git >/dev/null 2>&1; then
    e2e_root=$(mktemp -d)

    # Test 16: advisory default — a failing probe must NOT gate the verdict.
    echo "  Test: verifier advisory — failing probe does not gate"
    p14="${e2e_root}/p14"; make_min_project "${p14}"
    set +e
    out=$( cd "${p14}" && SPECTRA_HOME="${SPECTRA_DIR}" SPECTRA_RUNTIME_PROBE=1 \
           SPECTRA_PROBE_COMMAND="false" SPECTRA_PROBE_RETRIES=1 \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q 'advisory'; then
        pass "advisory failing probe -> verdict PASS"
    else
        fail "advisory rc=${rc} (expected 0, non-gating)"
    fi

    # Test 17: blocking via env — a failing probe MUST gate to FAIL.
    echo "  Test: verifier blocking via env — failing probe gates to FAIL"
    p15="${e2e_root}/p15"; make_min_project "${p15}"
    set +e
    out=$( cd "${p15}" && SPECTRA_HOME="${SPECTRA_DIR}" SPECTRA_RUNTIME_PROBE=1 \
           SPECTRA_RUNTIME_PROBE_BLOCKING=1 SPECTRA_PROBE_COMMAND="false" SPECTRA_PROBE_RETRIES=1 \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q 'Step 5 FAIL'; then
        pass "blocking(env) failing probe -> verdict FAIL"
    else
        fail "blocking(env) rc=${rc} (expected 1, gating)"
    fi

    # Test 18: blocking via verify.yaml — a failing probe MUST gate to FAIL.
    echo "  Test: verifier blocking via verify.yaml — failing probe gates"
    p16="${e2e_root}/p16"; make_min_project "${p16}"
    cat > "${p16}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: "false"
  retries: 1
  blocking: true
YAML
    set +e
    out=$( cd "${p16}" && SPECTRA_HOME="${SPECTRA_DIR}" SPECTRA_RUNTIME_PROBE=1 \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q 'Step 5 FAIL'; then
        pass "blocking(yaml) failing probe -> verdict FAIL"
    else
        fail "blocking(yaml) rc=${rc} (expected 1, gating)"
    fi

    # Test 19: explicit false env override wins over YAML blocking: true.
    echo "  Test: blocking=false env overrides verify.yaml blocking=true"
    p19="${e2e_root}/p19"; make_min_project "${p19}"
    cat > "${p19}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: "false"
  retries: 1
  blocking: true
YAML
    set +e
    out=$( cd "${p19}" && SPECTRA_HOME="${SPECTRA_DIR}" SPECTRA_RUNTIME_PROBE=1 \
           SPECTRA_RUNTIME_PROBE_BLOCKING=false \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q 'advisory'; then
        pass "blocking env false -> advisory PASS"
    else
        fail "blocking env false rc=${rc} (expected 0)"
    fi

    # Test 20: configured probes auto-run for infra scope without enable env.
    echo "  Test: infra scope automatically runs configured probe"
    p20="${e2e_root}/p20"; make_min_project "${p20}"
    sed -i 's/- Scope: code/- Scope: infra/' "${p20}/.spectra/plan.md"
    cat > "${p20}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: "false"
  retries: 1
  blocking: false
YAML
    set +e
    out=$( cd "${p20}" && env -u SPECTRA_RUNTIME_PROBE SPECTRA_HOME="${SPECTRA_DIR}" \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q 'Runtime/deploy probe' \
       && echo "${out}" | grep -q 'advisory'; then
        pass "infra scope auto-ran advisory probe"
    else
        fail "infra auto-probe rc=${rc}"
    fi

    # Test 21: explicit disable wins over infra/deploy scope auto-activation.
    echo "  Test: SPECTRA_RUNTIME_PROBE=0 disables infra auto-probe"
    p21="${e2e_root}/p21"; make_min_project "${p21}"
    sed -i 's/- Scope: code/- Scope: deploy/' "${p21}/.spectra/plan.md"
    cat > "${p21}/.spectra/verify.yaml" <<'YAML'
runtime:
  command: "false"
  retries: 1
  blocking: true
YAML
    set +e
    out=$( cd "${p21}" && SPECTRA_HOME="${SPECTRA_DIR}" SPECTRA_RUNTIME_PROBE=0 \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 0 ]] && ! echo "${out}" | grep -q 'Runtime/deploy probe'; then
        pass "explicit zero disabled auto-probe"
    else
        fail "explicit disable rc=${rc}"
    fi

    # Test 22: a requested blocking probe fails closed if its script is absent.
    echo "  Test: missing runtime probe script fails closed when blocking"
    p22="${e2e_root}/p22"; make_min_project "${p22}"
    missing_home="${e2e_root}/missing-home"; mkdir -p "${missing_home}/bin"
    set +e
    out=$( cd "${p22}" && SPECTRA_HOME="${missing_home}" SPECTRA_RUNTIME_PROBE=1 \
           SPECTRA_RUNTIME_PROBE_BLOCKING=1 SPECTRA_PROBE_COMMAND=true \
           bash "${SPECTRA_DIR}/bin/spectra-verify.sh" --task 001 --no-wiring-proof 2>&1 )
    rc=$?
    set -e
    if [[ ${rc} -eq 1 ]] && echo "${out}" | grep -q 'runtime probe script missing'; then
        pass "missing blocking probe -> verdict FAIL"
    else
        fail "missing blocking probe rc=${rc}"
    fi

    rm -rf "${e2e_root}"
else
    for reason in advisory blocking-env blocking-yaml blocking-override infra-auto explicit-disable missing-script; do
        echo "  SKIP  ${reason} e2e (git unavailable)"; SKIP=$((SKIP + 1))
    done
fi

# ══════════════════════════════════════════
echo ""
echo "  runtime-probe: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=runtime-probe pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

[[ ${FAIL} -eq 0 ]]
