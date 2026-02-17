#!/usr/bin/env bash
# SPECTRA lib/loop-git.sh — Git branch, commit, and hook management
#
# Contract:
#   Globals required: BRANCH_NAME, DRY_RUN, RESUME, SPECTRA_HOME, SPECTRA_DIR
#   Functions required: (none)
#
# Exports:
#   setup_branch(), commit_task(), install_precommit_hook()

setup_branch() {
    if [[ "$RESUME" == true ]] && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        local existing
        existing=$(git branch --list 'spectra/run-*' | tail -1 | tr -d ' *' || true)
        if [[ -n "$existing" ]]; then
            BRANCH_NAME="$existing"
            echo "  Resuming on existing branch: ${BRANCH_NAME}"
            if [[ "$DRY_RUN" == false ]]; then
                git checkout "${BRANCH_NAME}" 2>/dev/null || true
            fi
        fi
    fi

    if [[ -z "$BRANCH_NAME" ]]; then
        BRANCH_NAME="spectra/run-$(date +%Y%m%d-%H%M%S)"
        if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
            if [[ "$DRY_RUN" == false ]]; then
                git checkout -b "${BRANCH_NAME}" 2>/dev/null || true
                echo "  Branch: ${BRANCH_NAME}"
            fi
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
