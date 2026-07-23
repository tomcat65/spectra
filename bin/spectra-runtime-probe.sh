#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  SPECTRA Runtime Probe — live runtime/deploy-state verification   ║
# ║  Opt-in 5th signal: proves the deployed/running artifact behaves. ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# The 4-step verifier proves the code is correct and wired. It does NOT prove
# a *running* deployment is healthy. This probe closes that gap: it hits a live
# health endpoint or runs a smoke command and asserts the observed behavior.
#
# It is OPT-IN and ADVISORY BY DEFAULT — live state is flaky (cold starts,
# networks), so a failed probe must not silently STUCK a run. The verifier only
# invokes it when SPECTRA_RUNTIME_PROBE=1, and only gates the verdict when
# blocking is explicitly requested.
#
# Usage: spectra-runtime-probe.sh [--url URL] [--expect-status N]
#                                 [--expect-body STR] [--command CMD]
#                                 [--retries N] [--interval SECONDS]
#                                 [--timeout SECONDS]
#                                 [--self-test] [--help]
#
# Config precedence: CLI flags > environment variables > built-in defaults.
# Env vars: SPECTRA_PROBE_URL, SPECTRA_PROBE_EXPECT_STATUS,
#           SPECTRA_PROBE_EXPECT_BODY, SPECTRA_PROBE_COMMAND,
#           SPECTRA_PROBE_RETRIES, SPECTRA_PROBE_INTERVAL,
#           SPECTRA_PROBE_TIMEOUT
#
# Exit codes (consumed by the verifier for failure-type classification):
#   0 — probe passed
#   1 — connected/ran but assertion failed   (-> test_failure: real regression)
#   2 — could not connect / no probe defined  (-> external_blocker)

URL="${SPECTRA_PROBE_URL:-}"
EXPECT_STATUS="${SPECTRA_PROBE_EXPECT_STATUS:-200}"
EXPECT_BODY="${SPECTRA_PROBE_EXPECT_BODY:-}"
COMMAND="${SPECTRA_PROBE_COMMAND:-}"
RETRIES="${SPECTRA_PROBE_RETRIES:-5}"
INTERVAL="${SPECTRA_PROBE_INTERVAL:-2}"
TIMEOUT_SECONDS="${SPECTRA_PROBE_TIMEOUT:-30}"
SELF_TEST=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)           URL="$2"; shift 2 ;;
        --expect-status) EXPECT_STATUS="$2"; shift 2 ;;
        --expect-body)   EXPECT_BODY="$2"; shift 2 ;;
        --command)       COMMAND="$2"; shift 2 ;;
        --retries)       RETRIES="$2"; shift 2 ;;
        --interval)      INTERVAL="$2"; shift 2 ;;
        --timeout)       TIMEOUT_SECONDS="$2"; shift 2 ;;
        --self-test)     SELF_TEST=true; shift ;;
        -h|--help)
            sed -n '17,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *)   echo "Unexpected argument: $1" >&2; exit 2 ;;
    esac
done

# ── HTTP probe: one attempt. Echoes nothing; returns 0 pass / 1 assert-fail /
#    2 connect-fail. EXPECT_STATUS=0 means "any status, just must connect". ──
_http_attempt() {
    local body_file http_code curl_exit
    body_file="$(mktemp)"
    # -s silent, -S show errors, -L follow redirects, write status to stdout.
    http_code="$(curl -sS -L -o "${body_file}" -w '%{http_code}' \
                 --max-time 10 "${URL}" 2>/dev/null)" && curl_exit=0 || curl_exit=$?

    if [[ "${curl_exit}" -ne 0 ]]; then
        rm -f "${body_file}"
        return 2   # could not connect
    fi

    if [[ "${EXPECT_STATUS}" != "0" && "${http_code}" != "${EXPECT_STATUS}" ]]; then
        echo "    status ${http_code} != expected ${EXPECT_STATUS}"
        rm -f "${body_file}"
        return 1
    fi

    if [[ -n "${EXPECT_BODY}" ]] && ! grep -qF -- "${EXPECT_BODY}" "${body_file}"; then
        echo "    body does not contain expected substring: ${EXPECT_BODY}"
        rm -f "${body_file}"
        return 1
    fi

    rm -f "${body_file}"
    return 0
}

# ── Run the configured probe with retry/backoff. ──
run_probe() {
    if [[ -z "${URL}" && -z "${COMMAND}" ]]; then
        echo "  runtime-probe: no --url or --command configured — nothing to probe"
        return 2
    fi

    if ! [[ "${RETRIES}" =~ ^[1-9][0-9]*$ ]]; then RETRIES=5; fi
    if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]]; then INTERVAL=2; fi
    if ! [[ "${TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then TIMEOUT_SECONDS=30; fi

    local attempt=1 rc=2 command_exit=0
    while [[ "${attempt}" -le "${RETRIES}" ]]; do
        if [[ -n "${COMMAND}" ]]; then
            # Bound smoke commands so a hung deploy check cannot hang verification.
            if ! command -v timeout >/dev/null 2>&1; then
                echo "  runtime-probe: timeout utility not available for command probe"
                return 2
            fi
            if timeout "${TIMEOUT_SECONDS}" bash -c "${COMMAND}" >/dev/null 2>&1; then
                command_exit=0
            else
                command_exit=$?
            fi
            if [[ "${command_exit}" -eq 0 ]]; then
                rc=0
            elif [[ "${command_exit}" -eq 124 ]]; then
                echo "    command timed out after ${TIMEOUT_SECONDS}s"
                rc=2
            else
                rc=1
            fi
        else
            if ! command -v curl >/dev/null 2>&1; then
                echo "  runtime-probe: curl not available for URL probe"
                return 2
            fi
            _http_attempt; rc=$?
        fi

        if [[ "${rc}" -eq 0 ]]; then
            echo "  ✅ runtime-probe passed (attempt ${attempt}/${RETRIES})"
            return 0
        fi

        # A hard assertion failure (rc=1) on a command probe is deterministic —
        # retrying will not change it. Connection failures (rc=2) and HTTP
        # assertion failures are retried to absorb cold-start latency.
        if [[ -n "${COMMAND}" && "${rc}" -eq 1 ]]; then
            break
        fi

        if [[ "${attempt}" -lt "${RETRIES}" ]]; then
            sleep "${INTERVAL}"
        fi
        attempt=$((attempt + 1))
    done

    if [[ "${rc}" -eq 1 ]]; then
        echo "  ❌ runtime-probe: assertion failed (deployed artifact misbehaved)"
        return 1
    fi
    echo "  ❌ runtime-probe: could not reach target after ${RETRIES} attempt(s)"
    return 2
}

# ── Self-test: exercises command + HTTP modes with no external dependency. ──
if [[ "${SELF_TEST}" == true ]]; then
    fails=0

    # 1) command-mode pass
    COMMAND="true"; URL=""; RETRIES=1
    if ! run_probe >/dev/null; then echo "SELF-TEST FAIL: command pass"; fails=$((fails + 1)); fi

    # 2) command-mode assertion failure -> exit 1
    COMMAND="false"; RETRIES=2
    set +e; run_probe >/dev/null; rc=$?; set -e
    if [[ "${rc}" -ne 1 ]]; then echo "SELF-TEST FAIL: command fail rc=${rc} (want 1)"; fails=$((fails + 1)); fi

    # 3) command timeout -> exit 2
    COMMAND="sleep 2"; RETRIES=1; TIMEOUT_SECONDS=1
    set +e; run_probe >/dev/null; rc=$?; set -e
    if [[ "${rc}" -ne 2 ]]; then echo "SELF-TEST FAIL: command timeout rc=${rc} (want 2)"; fails=$((fails + 1)); fi

    # 4) no config -> exit 2
    COMMAND=""; URL=""
    set +e; run_probe >/dev/null; rc=$?; set -e
    if [[ "${rc}" -ne 2 ]]; then echo "SELF-TEST FAIL: no-config rc=${rc} (want 2)"; fails=$((fails + 1)); fi

    # 5) HTTP-mode pass against a local server (skip if python3/curl absent)
    if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
        # Pick a free port via the OS, then serve on it (tiny benign race).
        port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null || echo "")"
        if [[ -n "${port}" ]]; then
            srv_dir="$(mktemp -d)"; echo "spectra-ok" > "${srv_dir}/index.html"
            ( cd "${srv_dir}" && exec python3 -m http.server "${port}" --bind 127.0.0.1 ) >/dev/null 2>&1 &
            srv_pid=$!

            COMMAND=""; URL="http://127.0.0.1:${port}/"; EXPECT_STATUS=200
            EXPECT_BODY="spectra-ok"; RETRIES=15; INTERVAL=1
            set +e; run_probe >/dev/null; rc=$?; set -e
            if [[ "${rc}" -ne 0 ]]; then echo "SELF-TEST FAIL: http pass rc=${rc}"; fails=$((fails + 1)); fi

            # wrong expected status -> exit 1
            EXPECT_STATUS=503; EXPECT_BODY=""; RETRIES=1
            set +e; run_probe >/dev/null; rc=$?; set -e
            if [[ "${rc}" -ne 1 ]]; then echo "SELF-TEST FAIL: http status-mismatch rc=${rc} (want 1)"; fails=$((fails + 1)); fi

            kill "${srv_pid}" >/dev/null 2>&1 || true
            wait "${srv_pid}" 2>/dev/null || true
            rm -rf "${srv_dir}"
        else
            echo "  (self-test: could not allocate a port; skipping HTTP checks)"
        fi
    else
        echo "  (self-test: python3/curl unavailable; skipping HTTP checks)"
    fi

    if [[ "${fails}" -eq 0 ]]; then
        echo "  ✅ spectra-runtime-probe self-test passed"
        exit 0
    fi
    echo "  ❌ spectra-runtime-probe self-test: ${fails} failure(s)"
    exit 1
fi

run_probe
exit $?
