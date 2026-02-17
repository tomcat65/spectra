#!/usr/bin/env bash
# SPECTRA lib/loop-build.sh — Build prompt generators and parallel build orchestration
#
# Contract:
#   Globals required:
#     build_prompt():     TASK_IDS[], TASK_TITLES[]
#     preflight_prompt(): (none)
#     parallel_build():   TASK_IDS[], RETRY_COUNTS[], LOGS_DIR, SIGNALS_DIR,
#                         DRY_RUN, BUILDER_TIMEOUT
#
# Exports:
#   build_prompt(), preflight_prompt(), parallel_build()

build_prompt() {
    local idx="$1"
    local iteration="${2:-1}"
    local task_id="${TASK_IDS[$idx]}"
    local title="${TASK_TITLES[$idx]}"
    local preflight_advisory="${3:-}"

    local prompt="Implement Task ${task_id}: ${title}."
    prompt+=" Read CLAUDE.md for project context."
    prompt+=" Read .spectra/plan.md section '## Task ${task_id}' for full acceptance criteria and file ownership."
    prompt+=" Read .spectra/guardrails.md for active Signs."

    if [[ "$iteration" -gt 1 ]]; then
        prompt+=" This is retry ${iteration}. Read .spectra/logs/task-${task_id}-verify.md for the failure report. Fix the specific issues."
    fi

    if [[ -n "$preflight_advisory" ]]; then
        prompt+=" Pre-flight advisory: ${preflight_advisory}"
    fi

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

preflight_prompt() {
    local task_id="$1"

    local prompt="Scan codebase for active Sign violations before Task ${task_id} build. Output your report with an 'Advisory for Builder' section if violations found."

    # Enforce prompt budget (<500 bytes)
    if [[ ${#prompt} -gt 480 ]]; then
        prompt="${prompt:0:477}..."
    fi
    echo "$prompt"
}

parallel_build() {
    local batch=("$@")
    local -a pids=()
    local -a batch_task_ids=()

    for idx in "${batch[@]}"; do
        local task_id="${TASK_IDS[$idx]}"
        local iteration="${RETRY_COUNTS[$idx]:-1}"
        batch_task_ids+=("$task_id")

        # Calculate diminishing budget
        local budget=50
        case $iteration in
            1) budget=50 ;;
            2) budget=35 ;;
            3) budget=25 ;;
            *) budget=20 ;;
        esac

        # Read preflight advisory if exists
        local advisory=""
        if [[ -f "${LOGS_DIR}/task-${task_id}-preflight.md" ]]; then
            advisory=$(grep -A5 "Advisory for Builder" "${LOGS_DIR}/task-${task_id}-preflight.md" 2>/dev/null | head -3 || echo "")
        fi

        local prompt_text
        prompt_text=$(build_prompt "$idx" "$iteration" "$advisory")

        echo "  Spawning builder for Task ${task_id} (iter ${iteration}, budget ${budget})..."

        if [[ "$DRY_RUN" == true ]]; then
            echo "    [DRY RUN] Prompt (${#prompt_text} bytes): ${prompt_text:0:120}..."
            continue
        fi

        timeout "${BUILDER_TIMEOUT}" \
            claude --agent spectra-builder -p --permission-mode acceptEdits \
            "${prompt_text}" > "${LOGS_DIR}/task-${task_id}-build.log" 2>&1 &
        pids+=($!)
    done

    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    # Wait for all builders and track exit statuses
    local failed=false
    local -a builder_exits=()
    for i in "${!pids[@]}"; do
        local _bx=0
        wait "${pids[$i]}" || _bx=$?
        builder_exits+=("$_bx")
        if [[ "$_bx" -eq 124 ]]; then
            echo "  TIMEOUT: Builder for Task ${batch_task_ids[$i]} killed after ${BUILDER_TIMEOUT}s"
            echo "TIMEOUT" > "${SIGNALS_DIR}/TIMEOUT_${batch_task_ids[$i]}"
            failed=true
        elif [[ "$_bx" -ne 0 ]]; then
            echo "  Builder for Task ${batch_task_ids[$i]} exited non-zero (${_bx})"
            failed=true
        fi
    done

    # Check for STUCK signal from any builder
    if [[ -f "${SIGNALS_DIR}/STUCK" ]]; then
        return 1
    fi

    # Detect infra failures (bad CLI flags, missing commands, etc.)
    for i in "${!batch_task_ids[@]}"; do
        local _tid="${batch_task_ids[$i]}"
        local _exit="${builder_exits[$i]:-0}"
        local _log="${LOGS_DIR}/task-${_tid}-build.log"
        if [[ "$_exit" -ne 0 ]] && [[ -f "$_log" ]]; then
            if grep -qiE 'error: unknown option|unknown flag|unrecognized option|command not found' "$_log" 2>/dev/null; then
                echo "  INFRA_FAILURE: Task ${_tid} builder hit CLI/infra error (exit ${_exit})"
                echo "INFRA_FAILURE" > "${SIGNALS_DIR}/INFRA_FAIL_${_tid}"
            fi
        fi
    done

    $failed && return 1
    return 0
}
