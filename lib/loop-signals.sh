#!/usr/bin/env bash
# SPECTRA lib/loop-signals.sh — Signal and status file management
#
# Contract:
#   Globals required: SIGNALS_DIR, SPECTRA_DIR, BRANCH_NAME, PASS_HISTORY,
#                     LOGS_DIR, SLACK_WEBHOOK_URL (optional)
#   Functions required: elapsed() — must be defined before sourcing
#
# Exports:
#   write_signal(), write_progress(), write_status(), write_batch_status(),
#   signal_stuck(), signal_complete(), write_final_report()

write_signal() {
    local signal_name="$1" signal_value="$2"
    echo "${signal_value}" > "${SIGNALS_DIR}/${signal_name}"
}

write_progress() {
    local total=0 done=0 stuck=0
    if [[ -f "${SPECTRA_DIR}/plan.md" ]]; then
        total=$(grep -cE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        total=${total:-0}
        done=$(grep -cE '^\- \[[xX]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        done=${done:-0}
        stuck=$(grep -cE '^\- \[!\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
        stuck=${stuck:-0}
        if [[ "$total" -eq 0 ]]; then
            total=$(grep -c '^\- \[.\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            total=${total:-0}
            done=$(grep -c '^\- \[[xX]\]' "${SPECTRA_DIR}/plan.md" 2>/dev/null | tr -dc '0-9' || true)
            done=${done:-0}
            stuck=0
        fi
        write_signal "PROGRESS" "${done}/${total} tasks (${stuck} stuck)"
    fi
}

write_status() {
    local task_num="$1" task_title="$2" iteration="$3" max_iter="$4"
    local agent="${5:-idle}" pass_history="${6:-}"
    cat > "${SIGNALS_DIR}/STATUS" <<EOF
## SPECTRA v5.0 Run Status
- Current Task: ${task_num}
- Task Title: ${task_title}
- Iteration: ${iteration} / ${max_iter}
- Elapsed Time: $(elapsed)
- Pass History: ${pass_history}
- Current Agent: ${agent}
- Last Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

write_batch_status() {
    local batch_desc="$1" agent="${2:-idle}"
    cat > "${SIGNALS_DIR}/STATUS" <<EOF
## SPECTRA v5.0 Run Status
- Current Batch: ${batch_desc}
- Elapsed Time: $(elapsed)
- Pass History: ${PASS_HISTORY}
- Current Agent: ${agent}
- Last Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

write_final_report() {
    cat > "${LOGS_DIR}/final-report.md" <<EOF
## SPECTRA v5.0 Final Report
- Branch: ${BRANCH_NAME}
- Elapsed: $(elapsed)
- Pass History: ${PASS_HISTORY:-none}
- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

signal_stuck() {
    local reason="$1"
    cat > "${SIGNALS_DIR}/STUCK" <<EOF
## SPECTRA STUCK Signal
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Elapsed: $(elapsed)
- Reason: ${reason}
- Branch: ${BRANCH_NAME}
- Recovery: Human intervention required
EOF
    write_signal "PHASE" "stuck"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "  STUCK — Execution halted"
    echo "  Reason: ${reason}"
    echo "  Branch preserved: ${BRANCH_NAME}"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA STUCK: ${reason} (branch: ${BRANCH_NAME})\"}" > /dev/null 2>&1 || true
    fi

    write_final_report
    exit 1
}

signal_complete() {
    cat > "${SIGNALS_DIR}/COMPLETE" <<EOF
## SPECTRA Complete
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Elapsed: $(elapsed)
- Branch: ${BRANCH_NAME}
- Pass History: ${PASS_HISTORY}
EOF
    write_signal "PHASE" "complete"
    write_signal "AGENT" "none"
    write_progress
    echo ""
    echo "  COMPLETE — All tasks passed"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"SPECTRA COMPLETE: All tasks passed (branch: ${BRANCH_NAME}, elapsed: $(elapsed))\"}" > /dev/null 2>&1 || true
    fi
}
