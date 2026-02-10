#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Preflight — Verify .env integration tokens
# Runs once on first use, then only when .env changes (hash-based).
# Usage: spectra-preflight [--force]
#   --force   Run even if .env hash matches previous verification

SPECTRA_HOME="${HOME}/.spectra"
ENV_FILE="${SPECTRA_HOME}/.env"
VERIFIED_FILE="${SPECTRA_HOME}/.env.verified"
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
    esac
done

# ── Guard: .env must exist ──
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "PREFLIGHT SKIP: No .env found at ${ENV_FILE}"
    exit 0
fi

# ── Hash check: skip if .env unchanged since last verification ──
CURRENT_HASH=$(sha256sum "${ENV_FILE}" | cut -d' ' -f1)

if [[ "$FORCE" == false ]] && [[ -f "${VERIFIED_FILE}" ]]; then
    STORED_HASH=$(cat "${VERIFIED_FILE}" 2>/dev/null || echo "")
    if [[ "${CURRENT_HASH}" == "${STORED_HASH}" ]]; then
        exit 0
    fi
fi

echo "╔══════════════════════════════════════════╗"
echo "║        SPECTRA Preflight Check            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Source env
set +u; source "${ENV_FILE}"; set -u

PASS=0
FAIL=0
SKIP=0

# ── Test Linear API Key ──
if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.linear.app/graphql" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${LINEAR_API_KEY}" \
        -d '{"query":"{ viewer { id } }"}' \
        --max-time 10 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "  LINEAR_API_KEY        OK (200)"
        PASS=$((PASS + 1))
    else
        echo "  LINEAR_API_KEY        FAIL (HTTP ${HTTP_CODE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  LINEAR_API_KEY        SKIP (not set)"
    SKIP=$((SKIP + 1))
fi

# ── Test Linear Team ID (only if API key works) ──
if [[ -n "${LINEAR_TEAM_ID:-}" ]] && [[ -n "${LINEAR_API_KEY:-}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.linear.app/graphql" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${LINEAR_API_KEY}" \
        -d "{\"query\":\"{ team(id: \\\"${LINEAR_TEAM_ID}\\\") { id name } }\"}" \
        --max-time 10 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "  LINEAR_TEAM_ID        OK (200)"
        PASS=$((PASS + 1))
    else
        echo "  LINEAR_TEAM_ID        FAIL (HTTP ${HTTP_CODE})"
        FAIL=$((FAIL + 1))
    fi
elif [[ -z "${LINEAR_TEAM_ID:-}" ]]; then
    echo "  LINEAR_TEAM_ID        SKIP (not set)"
    SKIP=$((SKIP + 1))
fi

# ── Test Slack Webhook ──
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    # Slack webhooks don't have a dry-run mode. Use an empty payload to test
    # without posting a visible message — Slack returns 400 for empty body
    # but that confirms the URL is valid and reachable.
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${SLACK_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d '{}' \
        --max-time 10 2>/dev/null || echo "000")
    # 200 = posted, 400 = valid URL but bad payload (expected), both mean the webhook works
    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "400" ]]; then
        echo "  SLACK_WEBHOOK_URL     OK (reachable)"
        PASS=$((PASS + 1))
    else
        echo "  SLACK_WEBHOOK_URL     FAIL (HTTP ${HTTP_CODE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SLACK_WEBHOOK_URL     SKIP (not set)"
    SKIP=$((SKIP + 1))
fi

# ── Test GitHub Token ──
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/user" \
        --max-time 10 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "  GITHUB_TOKEN          OK (200)"
        PASS=$((PASS + 1))
    else
        echo "  GITHUB_TOKEN          FAIL (HTTP ${HTTP_CODE})"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  GITHUB_TOKEN          SKIP (not set)"
    SKIP=$((SKIP + 1))
fi

echo ""
echo "  Result: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

# ── Verdict ──
if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "  Preflight FAILED. Fix .env tokens before launching SPECTRA."
    echo "  Re-run: spectra-preflight --force"
    exit 1
fi

# ── Store verified hash ──
echo "${CURRENT_HASH}" > "${VERIFIED_FILE}"
echo "  Preflight PASSED. Stored verification hash."
