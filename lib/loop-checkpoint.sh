#!/usr/bin/env bash
# SPECTRA lib/loop-checkpoint.sh — Checkpoint save/restore and plan checksum
#
# Contract:
#   Globals required: CHECKPOINT_FILE, TASK_IDS[], TASK_STATUS[], RETRY_COUNTS[],
#                     FAILURE_TYPES[], PASS_HISTORY, BRANCH_NAME, SPECTRA_DIR,
#                     SIGNALS_DIR, ELAPSED_OFFSET, PLAN_CHECKSUM
#   Functions required: elapsed_seconds(), write_signal() — must be defined before sourcing
#
# Exports:
#   write_checkpoint(), restore_checkpoint(),
#   compute_plan_structure_checksum(), verify_plan_checksum()

write_checkpoint() {
    local -a completed=() stuck_list=()
    local retry_json="{}" failure_json="{}"

    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        case "${TASK_STATUS[$i]}" in
            complete) completed+=("\"${TASK_IDS[$i]}\"") ;;
            stuck)    stuck_list+=("\"${TASK_IDS[$i]}\"") ;;
        esac
    done

    # Build retry counts JSON
    local retry_pairs=()
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local rc="${RETRY_COUNTS[$i]:-0}"
        if [[ "$rc" -gt 0 ]]; then
            retry_pairs+=("\"${TASK_IDS[$i]}\": ${rc}")
        fi
    done
    if [[ ${#retry_pairs[@]} -gt 0 ]]; then
        retry_json="{ $(IFS=', '; echo "${retry_pairs[*]}") }"
    fi

    # Build failure types JSON
    local fail_pairs=()
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local ft="${FAILURE_TYPES[$i]:-}"
        if [[ -n "$ft" ]]; then
            fail_pairs+=("\"${TASK_IDS[$i]}\": \"${ft}\"")
        fi
    done
    if [[ ${#fail_pairs[@]} -gt 0 ]]; then
        failure_json="{ $(IFS=', '; echo "${fail_pairs[*]}") }"
    fi

    local completed_json="[$(IFS=', '; echo "${completed[*]+"${completed[*]}"}")]"
    local stuck_json="[$(IFS=', '; echo "${stuck_list[*]+"${stuck_list[*]}"}")]"

    cat > "${CHECKPOINT_FILE}" <<EOF
{
  "version": "5.0",
  "completed": ${completed_json},
  "stuck": ${stuck_json},
  "in_progress": [],
  "retry_counts": ${retry_json},
  "pass_history": "${PASS_HISTORY}",
  "failure_types": ${failure_json},
  "elapsed_seconds": $(elapsed_seconds),
  "branch": "${BRANCH_NAME}",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

restore_checkpoint() {
    if [[ ! -f "${CHECKPOINT_FILE}" ]]; then
        echo "  No checkpoint found. Starting fresh."
        return 1
    fi

    echo "  Restoring from checkpoint..."

    local checkpoint
    checkpoint=$(cat "${CHECKPOINT_FILE}")

    # Checkpoint is the source of truth for task state on resume.
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        TASK_STATUS[$i]="pending"
    done

    # Extract completed tasks
    local completed_str=""
    local stuck_str=""
    if command -v jq &>/dev/null; then
        completed_str=$(echo "$checkpoint" | jq -r '.completed[]' 2>/dev/null || echo "")
        stuck_str=$(echo "$checkpoint" | jq -r '.stuck[]' 2>/dev/null || echo "")
        PASS_HISTORY=$(echo "$checkpoint" | jq -r '.pass_history // ""' 2>/dev/null || echo "")
        ELAPSED_OFFSET=$(echo "$checkpoint" | jq -r '.elapsed_seconds // 0' 2>/dev/null || echo "0")
        BRANCH_NAME=$(echo "$checkpoint" | jq -r '.branch // ""' 2>/dev/null || echo "")

        # Restore retry counts
        local retry_keys
        retry_keys=$(echo "$checkpoint" | jq -r '.retry_counts | keys[]' 2>/dev/null || echo "")
        for key in $retry_keys; do
            local val
            val=$(echo "$checkpoint" | jq -r ".retry_counts[\"${key}\"]" 2>/dev/null || echo "0")
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$key" ]]; then
                    RETRY_COUNTS[$i]="$val"
                    break
                fi
            done
        done

        # Restore failure types
        local fail_keys
        fail_keys=$(echo "$checkpoint" | jq -r '.failure_types | keys[]' 2>/dev/null || echo "")
        for key in $fail_keys; do
            local val
            val=$(echo "$checkpoint" | jq -r ".failure_types[\"${key}\"]" 2>/dev/null || echo "")
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$key" ]]; then
                    FAILURE_TYPES[$i]="$val"
                    break
                fi
            done
        done
    else
        # Fallback: grep-based parsing
        completed_str=$(echo "$checkpoint" | awk '/"completed"[[:space:]]*:/,/\]/' | grep -oP '"\K[0-9]{3}(?=")' || echo "")
        stuck_str=$(echo "$checkpoint" | awk '/"stuck"[[:space:]]*:/,/\]/' | grep -oP '"\K[0-9]{3}(?=")' || echo "")
        PASS_HISTORY=$(echo "$checkpoint" | grep -oP '"pass_history":\s*"\K[^"]*' || echo "")
        ELAPSED_OFFSET=$(echo "$checkpoint" | grep -oP '"elapsed_seconds":\s*\K[0-9]+' || echo "0")
        BRANCH_NAME=$(echo "$checkpoint" | grep -oP '"branch":\s*"\K[^"]*' || echo "")

        # Restore retry counts from retry_counts object.
        local retry_block retry_pair retry_key retry_val
        retry_block=$(echo "$checkpoint" | awk '/"retry_counts"[[:space:]]*:/,/\}/')
        while IFS= read -r retry_pair; do
            retry_key=$(echo "$retry_pair" | grep -oP '"\K[0-9]{3}(?=")' || echo "")
            retry_val=$(echo "$retry_pair" | grep -oP ':\s*\K[0-9]+' || echo "")
            if [[ -z "$retry_key" ]] || [[ -z "$retry_val" ]]; then
                continue
            fi
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$retry_key" ]]; then
                    RETRY_COUNTS[$i]="$retry_val"
                    break
                fi
            done
        done < <(echo "$retry_block" | grep -oP '"[0-9]{3}"\s*:\s*[0-9]+' || true)

        # Restore failure types from failure_types object.
        local failure_block failure_pair failure_key failure_val
        failure_block=$(echo "$checkpoint" | awk '/"failure_types"[[:space:]]*:/,/\}/')
        while IFS= read -r failure_pair; do
            failure_key=$(echo "$failure_pair" | grep -oP '"\K[0-9]{3}(?=")' || echo "")
            failure_val=$(echo "$failure_pair" | grep -oP ':\s*"\K[^"]+' || echo "")
            if [[ -z "$failure_key" ]] || [[ -z "$failure_val" ]]; then
                continue
            fi
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [[ "${TASK_IDS[$i]}" == "$failure_key" ]]; then
                    FAILURE_TYPES[$i]="$failure_val"
                    break
                fi
            done
        done < <(echo "$failure_block" | grep -oP '"[0-9]{3}"\s*:\s*"[^"]+"' || true)
    fi

    # Update TASK_STATUS from checkpoint completed list
    for task_id in $completed_str; do
        for ((i=0; i<${#TASK_IDS[@]}; i++)); do
            if [[ "${TASK_IDS[$i]}" == "$task_id" ]]; then
                TASK_STATUS[$i]="complete"
                break
            fi
        done
    done

    # Also restore stuck tasks
    for task_id in $stuck_str; do
        for ((i=0; i<${#TASK_IDS[@]}; i++)); do
            if [[ "${TASK_IDS[$i]}" == "$task_id" ]]; then
                TASK_STATUS[$i]="stuck"
                break
            fi
        done
    done

    local completed_count=0 stuck_count=0
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        case "${TASK_STATUS[$i]}" in
            complete) completed_count=$((completed_count + 1)) ;;
            stuck)    stuck_count=$((stuck_count + 1)) ;;
        esac
    done

    echo "  Checkpoint restored: ${completed_count} complete, ${stuck_count} stuck"
    echo "  Pass history: ${PASS_HISTORY:-none}"
    echo "  Elapsed offset: ${ELAPSED_OFFSET}s"
    echo "  Branch: ${BRANCH_NAME}"

    return 0
}

compute_plan_structure_checksum() {
    # Strip mutable lines: checkbox state, trailing constraint appendages
    # Keep: ## Task headers, - AC:, - Files:, - Verify:, - Risk:, - Scope:, etc.
    grep -vE '^\- \[[ xX!]\] [0-9]{3}:' "${SPECTRA_DIR}/plan.md" 2>/dev/null \
        | sha256sum | cut -d' ' -f1
}

verify_plan_checksum() {
    if [[ -z "${PLAN_CHECKSUM}" ]]; then
        return 0  # No checksum to verify (e.g., dry-run without plan file)
    fi
    local current
    current=$(compute_plan_structure_checksum)
    if [[ "${current}" != "${PLAN_CHECKSUM}" ]]; then
        echo ""
        echo "  PLAN LOCK VIOLATION: plan.md structure was modified during execution!"
        echo "  Expected: ${PLAN_CHECKSUM:0:16}..."
        echo "  Got:      ${current:0:16}..."
        echo "  Halting to prevent stale-plan execution."
        echo ""
        write_signal "PLAN_LOCK_FAIL" "plan.md structural checksum mismatch at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 1
    fi
    return 0
}
