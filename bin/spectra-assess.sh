#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Assessment — BMAD Adapter
# Maps BMAD *workflow-init output (or interactive fallback) to .spectra/assessment.yaml.
# Zero runtime coupling. Runs BEFORE spectra-loop, not during.
#
# Usage: spectra-assess [--non-interactive] [--track TRACK] [--force]
#
# Three-tier BMAD detection:
#   1. BMAD CLI (command -v bmad)
#   2. BMAD artifacts directory (bmad/ or .bmad/)
#   3. Interactive fallback (5-7 prompts)

SPECTRA_DIR=".spectra"
OUTPUT_FILE="${SPECTRA_DIR}/assessment.yaml"

# ── Defaults ──
NON_INTERACTIVE=false
FORCE=false
OVERRIDE_TRACK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --force)           FORCE=true; shift ;;
        --track)           OVERRIDE_TRACK="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
SPECTRA Assessment — BMAD Adapter

Usage: spectra-assess [OPTIONS]

Maps project characteristics to SPECTRA Level + tuning parameters.
Writes .spectra/assessment.yaml.

Options:
  --non-interactive  Skip prompts, use defaults (requires --track)
  --track TRACK      Override track (quick_flow|bmad_method|enterprise)
  --force            Overwrite existing assessment.yaml without confirmation
  -h, --help         Show this help

BMAD Detection (checked in order):
  1. BMAD CLI: command -v bmad
  2. BMAD directory: bmad/ or .bmad/ in project root
  3. Interactive fallback: 7 prompts with sensible defaults
EOF
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Guard: .spectra directory ──
mkdir -p "${SPECTRA_DIR}"

# ── Guard: existing assessment ──
if [[ -f "${OUTPUT_FILE}" ]] && [[ "${FORCE}" == false ]]; then
    if [[ "${NON_INTERACTIVE}" == true ]]; then
        echo "Error: ${OUTPUT_FILE} exists. Use --force to overwrite." >&2
        exit 1
    fi
    read -r -p "  ${OUTPUT_FILE} exists. Overwrite? [y/N]: " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "  Aborted."
        exit 0
    fi
fi

# ══════════════════════════════════════════
# BMAD DETECTION
# ══════════════════════════════════════════

SOURCE_MODE="manual"
SOURCE_PRODUCER="interactive-fallback"
BMAD_CONFIDENCE="0.5"

# Tier 1: BMAD CLI
if command -v bmad &>/dev/null; then
    SOURCE_MODE="bmad"
    SOURCE_PRODUCER="workflow-init"
    BMAD_CONFIDENCE="0.9"
    # TODO: Parse bmad *workflow-init output when BMAD CLI exists
    echo "  BMAD CLI detected. (Structured parsing not yet implemented — using interactive fallback)"
    SOURCE_MODE="manual"
    SOURCE_PRODUCER="interactive-fallback"
    BMAD_CONFIDENCE="0.5"
# Tier 2: BMAD artifacts directory
elif [[ -d "bmad" ]] || [[ -d ".bmad" ]]; then
    SOURCE_MODE="bmad"
    SOURCE_PRODUCER="bmad-artifacts"
    BMAD_CONFIDENCE="0.7"
    # TODO: Parse BMAD artifact files when directory exists
    echo "  BMAD directory detected. (Artifact parsing not yet implemented — using interactive fallback)"
    SOURCE_MODE="manual"
    SOURCE_PRODUCER="interactive-fallback"
    BMAD_CONFIDENCE="0.5"
fi

# ══════════════════════════════════════════
# COLLECT INPUT (interactive or defaults)
# ══════════════════════════════════════════

# Auto-detect non-TTY stdin and switch to non-interactive
if [[ "${NON_INTERACTIVE}" == false ]] && ! [[ -t 0 ]]; then
    NON_INTERACTIVE=true
fi

# Defaults
TRACK="${OVERRIDE_TRACK:-bmad_method}"
BLAST_RADIUS="medium"
INTEGRATION_COUNT=1
RISK_FACTORS_RAW=""
TEAM_SIZE=2
DOMAIN="general"
LANGUAGE="unknown"
FRAMEWORK="unknown"
COMPLIANCE_RAW=""

if [[ "${NON_INTERACTIVE}" == false ]] && [[ "${SOURCE_PRODUCER}" == "interactive-fallback" ]]; then
    echo ""
    echo "  SPECTRA Assessment — Interactive"
    echo "  ────────────────────────────────"
    echo "  Press Enter to accept [default]."
    echo ""

    read -r -p "  Planning track? [quick_flow/bmad_method/enterprise] (${TRACK}): " input
    [[ -n "${input}" ]] && TRACK="${input}"

    read -r -p "  Language? [typescript/python/go/rust/java/bash/other] (${LANGUAGE}): " input
    [[ -n "${input}" ]] && LANGUAGE="${input}"

    read -r -p "  Framework? [next/nest/express/django/fastapi/spring-boot/gin/none] (${FRAMEWORK}): " input
    [[ -n "${input}" ]] && FRAMEWORK="${input}"

    read -r -p "  Domain? [web/api/mobile/infra/data/fintech/healthcare/general] (${DOMAIN}): " input
    [[ -n "${input}" ]] && DOMAIN="${input}"

    read -r -p "  Blast radius? [low/medium/high] (${BLAST_RADIUS}): " input
    [[ -n "${input}" ]] && BLAST_RADIUS="${input}"

    read -r -p "  External integrations count? (${INTEGRATION_COUNT}): " input
    [[ -n "${input}" ]] && INTEGRATION_COUNT="${input}"

    read -r -p "  Team size? (${TEAM_SIZE}): " input
    [[ -n "${input}" ]] && TEAM_SIZE="${input}"

    read -r -p "  Risk factors? (comma-separated: security,auth,payments,external-api,migration,regulatory,data-loss,concurrency,infra-change,multi-service) or none: " input
    [[ -n "${input}" && "${input}" != "none" ]] && RISK_FACTORS_RAW="${input}"

    read -r -p "  Compliance requirements? (comma-separated: soc2,pci-dss,hipaa,gdpr) or none: " input
    [[ -n "${input}" && "${input}" != "none" ]] && COMPLIANCE_RAW="${input}"
elif [[ "${NON_INTERACTIVE}" == true ]] && [[ -z "${OVERRIDE_TRACK}" ]]; then
    echo "Warning: --non-interactive without --track; using default track 'bmad_method'" >&2
fi

# Ensure numeric
INTEGRATION_COUNT=$((INTEGRATION_COUNT + 0))
TEAM_SIZE=$((TEAM_SIZE + 0))

# ══════════════════════════════════════════
# PARSE RISK FACTORS AND COMPLIANCE
# ══════════════════════════════════════════

declare -a RISK_FACTORS=()
if [[ -n "${RISK_FACTORS_RAW}" ]]; then
    IFS=',' read -ra RISK_FACTORS <<< "${RISK_FACTORS_RAW}"
    # Trim whitespace
    for i in "${!RISK_FACTORS[@]}"; do
        RISK_FACTORS[$i]=$(echo "${RISK_FACTORS[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    done
fi

declare -a COMPLIANCE=()
if [[ -n "${COMPLIANCE_RAW}" ]]; then
    IFS=',' read -ra COMPLIANCE <<< "${COMPLIANCE_RAW}"
    for i in "${!COMPLIANCE[@]}"; do
        COMPLIANCE[$i]=$(echo "${COMPLIANCE[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    done
fi

# ══════════════════════════════════════════
# TRACK → LEVEL MAPPING (codex's decision tree)
# ══════════════════════════════════════════

LEVEL=1
MAPPING_REASON=""
EXEC_MODE="sequential"

has_risk_factor() {
    local target="$1"
    for rf in "${RISK_FACTORS[@]+"${RISK_FACTORS[@]}"}"; do
        [[ "${rf}" == "${target}" ]] && return 0
    done
    return 1
}

case "${TRACK}" in
    quick_flow)
        # Level 0 if ALL: blast_radius=low, integration_count<=1, team_size<=2, no risk factors
        if [[ "${BLAST_RADIUS}" == "low" ]] && \
           [[ "${INTEGRATION_COUNT}" -le 1 ]] && \
           [[ "${TEAM_SIZE}" -le 2 ]] && \
           [[ ${#RISK_FACTORS[@]} -eq 0 ]]; then
            LEVEL=0
            MAPPING_REASON="quick_flow + low blast radius + no risk factors + <=1 integration"
        else
            LEVEL=1
            MAPPING_REASON="quick_flow but not level-0-safe because"
            [[ "${BLAST_RADIUS}" != "low" ]] && MAPPING_REASON="${MAPPING_REASON} blast_radius is ${BLAST_RADIUS}"
            [[ "${INTEGRATION_COUNT}" -gt 1 ]] && MAPPING_REASON="${MAPPING_REASON}, integration_count=${INTEGRATION_COUNT}"
            [[ "${TEAM_SIZE}" -gt 2 ]] && MAPPING_REASON="${MAPPING_REASON}, team_size=${TEAM_SIZE}"
            [[ ${#RISK_FACTORS[@]} -gt 0 ]] && MAPPING_REASON="${MAPPING_REASON}, has risk factors"
        fi
        ;;
    bmad_method)
        # Check complexity triggers for Level 3
        TRIGGERS=0
        TRIGGER_REASONS=""
        if [[ "${INTEGRATION_COUNT}" -ge 3 ]]; then
            TRIGGERS=$((TRIGGERS + 1))
            TRIGGER_REASONS="${TRIGGER_REASONS}integrations>=${INTEGRATION_COUNT}, "
        fi
        if [[ "${TEAM_SIZE}" -ge 5 ]]; then
            TRIGGERS=$((TRIGGERS + 1))
            TRIGGER_REASONS="${TRIGGER_REASONS}team_size>=${TEAM_SIZE}, "
        fi
        if [[ "${BLAST_RADIUS}" == "high" ]]; then
            TRIGGERS=$((TRIGGERS + 1))
            TRIGGER_REASONS="${TRIGGER_REASONS}blast_radius=high, "
        fi
        for high_rf in security regulatory payments data-migration multi-service; do
            if has_risk_factor "${high_rf}"; then
                TRIGGERS=$((TRIGGERS + 1))
                TRIGGER_REASONS="${TRIGGER_REASONS}risk:${high_rf}, "
                break
            fi
        done
        if [[ ${#COMPLIANCE[@]} -gt 0 ]]; then
            TRIGGERS=$((TRIGGERS + 1))
            TRIGGER_REASONS="${TRIGGER_REASONS}compliance set, "
        fi

        if [[ "${TRIGGERS}" -gt 0 ]]; then
            LEVEL=3
            EXEC_MODE="teams"
            MAPPING_REASON="bmad_method with complexity triggers (${TRIGGER_REASONS%%, })"
        else
            LEVEL=2
            MAPPING_REASON="bmad_method without complexity triggers"
        fi
        ;;
    enterprise)
        LEVEL=4
        EXEC_MODE="teams"
        MAPPING_REASON="enterprise track always maps to level 4"
        ;;
    *)
        echo "Error: Unknown track '${TRACK}'. Use quick_flow, bmad_method, or enterprise." >&2
        exit 1
        ;;
esac

# ══════════════════════════════════════════
# RISK SCORE CALCULATION
# ══════════════════════════════════════════

RISK_SCORE=0

# +2 each for high-severity risk factors
for rf in security privacy regulatory payments auth data-loss; do
    has_risk_factor "${rf}" && RISK_SCORE=$((RISK_SCORE + 2))
done

# +1 each for medium-severity risk factors
for rf in external-api migration concurrency infra-change; do
    has_risk_factor "${rf}" && RISK_SCORE=$((RISK_SCORE + 1))
done

# +1 if domain is high-risk
case "${DOMAIN}" in
    fintech|healthcare|government|security) RISK_SCORE=$((RISK_SCORE + 1)) ;;
esac

# +1 if team_size >= 5
[[ "${TEAM_SIZE}" -ge 5 ]] && RISK_SCORE=$((RISK_SCORE + 1))

# +1 if mapped level >= 3
[[ "${LEVEL}" -ge 3 ]] && RISK_SCORE=$((RISK_SCORE + 1))

# ══════════════════════════════════════════
# TUNING DERIVATION
# ══════════════════════════════════════════

# verification_intensity
if [[ "${LEVEL}" -eq 4 ]] || [[ "${RISK_SCORE}" -ge 8 ]]; then
    VERIFICATION_INTENSITY="exhaustive"
elif [[ "${LEVEL}" -eq 3 ]] || [[ "${RISK_SCORE}" -ge 5 ]]; then
    VERIFICATION_INTENSITY="high"
elif [[ "${LEVEL}" -eq 2 ]] || [[ "${RISK_SCORE}" -ge 3 ]]; then
    VERIFICATION_INTENSITY="medium"
else
    VERIFICATION_INTENSITY="low"
fi

# wiring_depth
if [[ "${LEVEL}" -eq 0 ]] && [[ "${INTEGRATION_COUNT}" -le 1 ]]; then
    WIRING_DEPTH="none"
elif [[ "${LEVEL}" -eq 1 ]] || { [[ "${LEVEL}" -eq 2 ]] && [[ "${INTEGRATION_COUNT}" -le 2 ]]; }; then
    WIRING_DEPTH="basic"
else
    WIRING_DEPTH="full"
fi
# Override to full if risk factors include security or regulatory
if has_risk_factor "security" || has_risk_factor "regulatory"; then
    WIRING_DEPTH="full"
fi
# Override to full if integration_count >= 3
[[ "${INTEGRATION_COUNT}" -ge 3 ]] && WIRING_DEPTH="full"

# retry_budget (based on verification_intensity, clamped [2,5])
case "${VERIFICATION_INTENSITY}" in
    low)        RETRY_BUDGET=2 ;;
    medium)     RETRY_BUDGET=3 ;;
    high)       RETRY_BUDGET=4 ;;
    exhaustive) RETRY_BUDGET=5 ;;
esac

# ══════════════════════════════════════════
# BUILD WARNINGS
# ══════════════════════════════════════════

declare -a WARNINGS=()
if [[ "${SOURCE_PRODUCER}" == "interactive-fallback" ]]; then
    WARNINGS+=("BMAD unavailable; assessment derived from manual answers")
fi
if [[ "${NON_INTERACTIVE}" == true ]] && [[ -z "${OVERRIDE_TRACK}" ]]; then
    WARNINGS+=("non-interactive fallback defaults used")
fi

# ══════════════════════════════════════════
# WRITE assessment.yaml
# ══════════════════════════════════════════

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build risk_factors YAML array
RF_YAML=""
if [[ ${#RISK_FACTORS[@]} -gt 0 ]]; then
    for rf in "${RISK_FACTORS[@]}"; do
        RF_YAML="${RF_YAML}
      - ${rf}"
    done
else
    RF_YAML=" []"
fi

# Build compliance YAML array
COMP_YAML=""
if [[ ${#COMPLIANCE[@]} -gt 0 ]]; then
    for c in "${COMPLIANCE[@]}"; do
        COMP_YAML="${COMP_YAML}
      - ${c}"
    done
else
    COMP_YAML=" []"
fi

# Build warnings YAML array
WARN_YAML=""
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    WARN_YAML="
warnings:"
    for w in "${WARNINGS[@]}"; do
        WARN_YAML="${WARN_YAML}
  - \"${w}\""
    done
fi

cat > "${OUTPUT_FILE}" <<EOF
version: 1
generated_at: "${GENERATED_AT}"
source:
  mode: ${SOURCE_MODE}
  producer: ${SOURCE_PRODUCER}
bmad:
  track: ${TRACK}
  confidence: ${BMAD_CONFIDENCE}
  rationale: "${MAPPING_REASON}"
  context:
    language: ${LANGUAGE}
    framework: ${FRAMEWORK}
    domain: ${DOMAIN}
    team_size: ${TEAM_SIZE}
    integration_count: ${INTEGRATION_COUNT}
    risk_factors:${RF_YAML}
    compliance:${COMP_YAML}
    blast_radius: ${BLAST_RADIUS}
spectra:
  level: ${LEVEL}
  execution_mode: ${EXEC_MODE}
  mapping_reason: "${MAPPING_REASON}"
tuning:
  verification_intensity: ${VERIFICATION_INTENSITY}
  wiring_depth: ${WIRING_DEPTH}
  retry_budget: ${RETRY_BUDGET}${WARN_YAML}
EOF

# ══════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════

echo ""
echo "  SPECTRA Assessment Complete"
echo "  ────────────────────────────────"
echo "  Track:       ${TRACK}"
echo "  Level:       ${LEVEL}"
echo "  Exec Mode:   ${EXEC_MODE}"
echo "  Reason:      ${MAPPING_REASON}"
echo "  ────────────────────────────────"
echo "  Verification: ${VERIFICATION_INTENSITY}"
echo "  Wiring:       ${WIRING_DEPTH}"
echo "  Retry Budget: ${RETRY_BUDGET}"
echo "  Risk Score:   ${RISK_SCORE}"
echo "  ────────────────────────────────"
echo "  Output: ${OUTPUT_FILE}"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    for w in "${WARNINGS[@]}"; do
        echo "  Warning: ${w}"
    done
fi
echo ""
