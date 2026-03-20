#!/usr/bin/env bash
# SPECTRA lib/loop-git.sh — Git branch, commit, and hook management
#
# Contract:
#   Globals required: BRANCH_NAME, DRY_RUN, RESUME, FRESH_BRANCH,
#                     SPECTRA_HOME, SPECTRA_DIR, CHECKPOINT_FILE
#   Functions required: (none)
#
# Exports:
#   setup_branch(), commit_task(), install_precommit_hook()

setup_branch() {
    # Skip branch management if not in a git repo
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        [[ -z "$BRANCH_NAME" ]] && BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
        return
    fi

    # --fresh flag: always create a new branch, ignore checkpoint/existing
    if [[ "${FRESH_BRANCH:-false}" == true ]]; then
        BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
        if [[ "$DRY_RUN" == false ]]; then
            git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
            echo "  Branch: ${BRANCH_NAME} (fresh)"
        fi
        return
    fi

    # Strategy 1: --resume flag — check existing branches
    if [[ "$RESUME" == true ]]; then
        local existing
        existing=$(git branch --list 'spectra/run-*' | tail -1 | tr -d ' *' || true)
        if [[ -n "$existing" ]]; then
            BRANCH_NAME="$existing"
            echo "  Resuming on existing branch: ${BRANCH_NAME}"
            if [[ "$DRY_RUN" == false ]]; then
                git checkout "${BRANCH_NAME}" 2>/dev/null || true
            fi
            return
        fi
    fi

    # Strategy 2: Checkpoint has a branch — reuse it if it still exists
    # This covers --skip-planning without --resume (the common restart case)
    if [[ -z "$BRANCH_NAME" ]] && [[ -f "${CHECKPOINT_FILE:-}" ]]; then
        local cp_branch=""
        if command -v jq &>/dev/null; then
            cp_branch=$(jq -r '.branch // ""' "${CHECKPOINT_FILE}" 2>/dev/null || echo "")
        else
            cp_branch=$(grep -oP '"branch":\s*"\K[^"]*' "${CHECKPOINT_FILE}" 2>/dev/null || echo "")
        fi
        if [[ -n "$cp_branch" ]] && git rev-parse --verify "$cp_branch" &>/dev/null; then
            BRANCH_NAME="$cp_branch"
            echo "  Reusing previous run branch from checkpoint: ${BRANCH_NAME}"
            echo "  (pass --fresh to force a new branch)"
            if [[ "$DRY_RUN" == false ]]; then
                git checkout "${BRANCH_NAME}" 2>/dev/null || true
            fi
            return
        fi
    fi

    # Strategy 3: No checkpoint, no resume — create new branch
    if [[ -z "$BRANCH_NAME" ]]; then
        BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
        if [[ "$DRY_RUN" == false ]]; then
            git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
            echo "  Branch: ${BRANCH_NAME}"
        fi
    fi
}

commit_task() {
    local task_id="$1" task_title="$2"
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        git add -A 2>/dev/null || true
        git commit -m "feat(task-${task_id}): ${task_title}" 2>/dev/null || true
    fi
}

install_precommit_hook() {
    if [[ "$DRY_RUN" == false ]] && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        local hook_src="${SPECTRA_HOME}/hooks/pre-commit"
        local hook_dst=".git/hooks/pre-commit"
        if [[ -f "$hook_src" ]] && [[ ! -e "$hook_dst" ]]; then
            mkdir -p .git/hooks
            ln -s "$hook_src" "$hook_dst" 2>/dev/null || true
            echo "  Installed pre-commit hook: ${hook_dst} -> ${hook_src}"
        fi
    fi
}
