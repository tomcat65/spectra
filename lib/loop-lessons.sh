#!/usr/bin/env bash
# SPECTRA lib/loop-lessons.sh — Continuous Learning System (Phase 9)
#
# Contract:
#   Globals required: SPECTRA_DIR, SPECTRA_HOME
#   Functions required: (none)
#
# Exports:
#   lesson_write(), lesson_read_snapshot(), lesson_search(),
#   compute_fingerprint(), sanitize_lesson(), compact_snapshot(),
#   lesson_check_promotion(), lesson_promote(), lesson_demote(),
#   ensure_lessons_dir(), check_schema_version(), migrate_lessons(),
#   inject_active_lessons(), spectra_upgrade_project(),
#   guardrails_dedup_check()
#
# Storage: Append-only JSONL + flock (no mutable JSON)
# Dedup: Normalized fingerprints {area}/{error_code}/{primary_file}
# Schema: ~/.spectra/lessons/schema-version (integer, starts at 1)

LESSONS_HOME="${SPECTRA_HOME}/lessons"
LESSONS_SCHEMA_VERSION=1

# ── Directory + schema bootstrap ──

ensure_lessons_dir() {
    mkdir -p "${LESSONS_HOME}/projects"
    if [[ ! -f "${LESSONS_HOME}/schema-version" ]]; then
        echo "${LESSONS_SCHEMA_VERSION}" > "${LESSONS_HOME}/schema-version"
    fi
}

check_schema_version() {
    ensure_lessons_dir
    local current
    current=$(cat "${LESSONS_HOME}/schema-version" 2>/dev/null || echo "0")
    if [[ "${current}" -lt "${LESSONS_SCHEMA_VERSION}" ]]; then
        migrate_lessons "${current}" "${LESSONS_SCHEMA_VERSION}"
    fi
}

migrate_lessons() {
    local from_version="$1" to_version="$2"
    local v="${from_version}"
    while [[ "${v}" -lt "${to_version}" ]]; do
        local next=$((v + 1))
        local fn="migrate_v${v}_to_v${next}"
        if declare -f "${fn}" > /dev/null 2>&1; then
            echo "  Migrating lessons schema v${v} → v${next}..."
            "${fn}"
        fi
        v="${next}"
    done
    echo "${to_version}" > "${LESSONS_HOME}/schema-version"
}

# ── Fingerprinting ──

compute_fingerprint() {
    local area="${1:-unknown}"
    local error_code="${2:-unknown}"
    local primary_file="${3:-unknown}"

    # Normalize: lowercase, strip leading paths, collapse whitespace
    area=$(echo "${area}" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '_')
    error_code=$(echo "${error_code}" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '_')
    primary_file=$(basename "${primary_file}" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")

    echo "${area}/${error_code}/${primary_file}"
}

# ── Sanitization / Redaction ──

sanitize_lesson() {
    local text="$1"
    # Redact absolute paths → {PROJECT_ROOT}/...
    text=$(echo "${text}" | sed -E 's|/home/[^ ]*(/[^ ]*)|{PROJECT_ROOT}\1|g')
    text=$(echo "${text}" | sed -E 's|/Users/[^ ]*(/[^ ]*)|{PROJECT_ROOT}\1|g')
    text=$(echo "${text}" | sed -E 's|/tmp/[^ ]*(/[^ ]*)|{TMP}\1|g')
    # Redact common secret patterns
    text=$(echo "${text}" | sed -E 's/(sk-|xoxb-|xoxp-|ghp_|ghs_|AKIA)[A-Za-z0-9_-]+/[REDACTED]/g')
    # Redact email-like patterns
    text=$(echo "${text}" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[USER]/g')
    echo "${text}"
}

json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes, then control chars
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "${str}"
}

# ── Prompt injection guard (SIGN-010 candidate) ──
# Lessons flow: project → framework → new projects → agent context.
# A malicious lesson could embed prompt injection to hijack agent behavior.
# This function strips dangerous patterns before propagation.

sanitize_for_propagation() {
    local text="$1"
    # Strip XML-like tags that could inject system/assistant/user context
    text=$(echo "${text}" | sed -E 's/<\/?system-reminder[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?system[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?assistant[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?user[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?human[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?tool_use[^>]*>//g')
    text=$(echo "${text}" | sed -E 's/<\/?antml:[^>]*>//g')
    # Strip common prompt injection patterns
    text=$(echo "${text}" | sed -E 's/[Ii]gnore (all |previous |prior |above )*instructions?//g')
    text=$(echo "${text}" | sed -E 's/[Yy]ou are now //g')
    text=$(echo "${text}" | sed -E 's/[Nn]ew (system )?prompt://g')
    text=$(echo "${text}" | sed -E 's/IMPORTANT:.*[Oo]verride//g')
    # Strip shell injection patterns (backticks, $(), eval)
    # RATIONALE: single quotes intentional — we match literal backticks, not expansions
    # shellcheck disable=SC2016
    text=$(echo "${text}" | sed -E 's/`[^`]*`/[CODE_STRIPPED]/g')
    text=$(echo "${text}" | sed -E 's/\$\([^)]*\)/[CMD_STRIPPED]/g')
    text="${text//eval /}"
    # Cap length to prevent context flooding
    text=$(echo "${text}" | cut -c1-500)
    echo "${text}"
}

# Validate a JSONL lesson entry is safe for propagation
# Returns 0 if safe, 1 if rejected
validate_lesson_entry() {
    local entry="$1"

    # Reject entries with suspiciously long fields (>500 chars per field)
    local detail
    detail=$(echo "${entry}" | grep -oP '"detail":"\K[^"]*' || echo "")
    if [[ ${#detail} -gt 500 ]]; then
        return 1
    fi

    # Reject entries containing XML tags in any field (including fingerprint)
    if echo "${entry}" | grep -qiP '<(system|assistant|user|human|antml:)'; then
        return 1
    fi

    # Reject entries with shell injection patterns in any field
    # RATIONALE: single quotes intentional — matching literal shell patterns, not expanding
    # shellcheck disable=SC2016
    if echo "${entry}" | grep -qP '\$\(|`.*`|;\s*(rm|curl|wget|eval)\b'; then
        return 1
    fi

    # Reject entries with prompt injection patterns in fingerprint or any field
    if echo "${entry}" | grep -qiP 'ignore (all |previous |prior |above )*instructions?'; then
        return 1
    fi

    # Reject fingerprints longer than 200 chars (normal: ~30-60)
    local fp
    fp=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]*' || echo "")
    if [[ ${#fp} -gt 200 ]]; then
        return 1
    fi

    return 0
}

# Read lessons safe for propagation (filtered + sanitized)
lessons_for_propagation() {
    local min_status="${1:-CONFIRMED}"  # CONFIRMED, PROMOTED, or SIGN

    ensure_lessons_dir

    local status_regex
    case "${min_status}" in
        CONFIRMED) status_regex="CONFIRMED|PROMOTED|SIGN" ;;
        PROMOTED)  status_regex="PROMOTED|SIGN" ;;
        SIGN)      status_regex="SIGN" ;;
        *)         status_regex="CONFIRMED|PROMOTED|SIGN" ;;
    esac

    # Collect entries, dedup by fingerprint (keep highest-status record)
    local dedup_dir
    dedup_dir=$(mktemp -d)

    for project_dir in "${LESSONS_HOME}/projects"/*/; do
        local snapshot="${project_dir}lessons.snapshot"
        local jsonl="${project_dir}lessons.jsonl"
        local source="${snapshot}"
        [[ -f "${source}" ]] || source="${jsonl}"
        [[ -f "${source}" ]] || continue

        while IFS= read -r entry; do
            # Only entries at or above minimum status
            local status
            status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")
            if ! echo "${status}" | grep -qP "^(${status_regex})$"; then
                continue
            fi

            # Validate entry is safe
            if ! validate_lesson_entry "${entry}"; then
                echo "  WARN: Rejected suspicious lesson entry (prompt injection guard)" >&2
                continue
            fi

            # Dedup by fingerprint: keep highest-status entry
            local fp fp_hash existing_status
            fp=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]+' || echo "")
            [[ -z "${fp}" ]] && continue
            fp_hash=$(echo "${fp}" | md5sum | cut -d' ' -f1)

            if [[ -f "${dedup_dir}/${fp_hash}" ]]; then
                existing_status=$(grep -oP '"status":"\K[^"]+' "${dedup_dir}/${fp_hash}" || echo "")
                # Status priority: SIGN > PROMOTED > CONFIRMED
                local existing_rank=0 new_rank=0
                case "${existing_status}" in CONFIRMED) existing_rank=1 ;; PROMOTED) existing_rank=2 ;; SIGN) existing_rank=3 ;; esac
                case "${status}" in CONFIRMED) new_rank=1 ;; PROMOTED) new_rank=2 ;; SIGN) new_rank=3 ;; esac
                [[ ${new_rank} -le ${existing_rank} ]] && continue
            fi
            echo "${entry}" > "${dedup_dir}/${fp_hash}"
        done < "${source}"
    done

    # Emit deduplicated entries
    for fp_file in "${dedup_dir}"/*; do
        [[ -f "${fp_file}" ]] || continue
        cat "${fp_file}"
    done
    rm -rf "${dedup_dir}"
}

# ── JSONL append with flock ──

lesson_flock_append() {
    local jsonl_file="$1"
    local json_line="$2"
    local lock_file="${jsonl_file}.lock"

    mkdir -p "$(dirname "${jsonl_file}")"
    (
        flock -x -w 10 200 || { echo "ERROR: Could not acquire lock on ${lock_file}" >&2; return 1; }
        echo "${json_line}" >> "${jsonl_file}"
    ) 200>"${lock_file}"
}

# ── Core write ──

lesson_write() {
    local project="$1"
    local area="$2"
    local error_code="$3"
    local primary_file="$4"
    local command="${5:-}"
    local detail="${6:-}"
    local severity="${7:-medium}"
    local run_id="${8:-}"
    local task_id="${9:-}"
    local verifier_output="${10:-}"
    local oracle_class="${11:-}"

    ensure_lessons_dir

    local fingerprint
    fingerprint=$(compute_fingerprint "${area}" "${error_code}" "${primary_file}")

    # Sanitize and JSON-escape all string fields
    detail=$(json_escape "$(sanitize_lesson "${detail}")")
    verifier_output=$(json_escape "$(sanitize_lesson "${verifier_output}")")
    command=$(json_escape "${command}")

    local project_dir="${LESSONS_HOME}/projects/${project}"
    mkdir -p "${project_dir}"
    local jsonl_file="${project_dir}/lessons.jsonl"
    local lock_file="${jsonl_file}.lock"

    # Compute adaptive TTL
    local ttl
    case "${severity}" in
        low)      ttl=3 ;;
        medium)   ttl=5 ;;
        high)     ttl=10 ;;
        critical) ttl=999 ;;  # effectively never expires
        *)        ttl=5 ;;
    esac

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Dedup + write inside single flock critical section to prevent race
    (
        flock -x -w 10 200 || { echo "ERROR: Could not acquire lock on ${lock_file}" >&2; return 1; }

        if [[ -f "${jsonl_file}" ]] && grep -q "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null; then
            # Increment recurrence instead of duplicating
            printf '{"action":"increment","fingerprint":"%s","timestamp":"%s","run_id":"%s"}\n' \
                "${fingerprint}" "${timestamp}" "${run_id}" >> "${jsonl_file}"
        else
            # Create new entry
            printf '{"action":"create","fingerprint":"%s","status":"TEMP","severity":"%s","area":"%s","error_code":"%s","command":"%s","primary_file":"%s","detail":"%s","recurrence_count":1,"distinct_projects":["%s"],"prevention_count":0,"false_positive_count":0,"ttl":%d,"ttl_base":%d,"projects_since_last":0,"timestamp":"%s","evidence":{"source_run_id":"%s","project":"%s","task_id":"%s","verifier_output":"%s","oracle_class":"%s"}}\n' \
                "${fingerprint}" "${severity}" "${area}" "${error_code}" "${command}" \
                "${primary_file}" "${detail}" "${project}" \
                "${ttl}" "${ttl}" "${timestamp}" \
                "${run_id}" "${project}" "${task_id}" "${verifier_output}" "${oracle_class}" >> "${jsonl_file}"
        fi
    ) 200>"${lock_file}"

    # Cross-project correlation: check other projects for same fingerprint
    local match_count=0
    local matched_projects=()
    for other_dir in "${LESSONS_HOME}/projects"/*/; do
        local other_project
        other_project=$(basename "${other_dir}")
        [[ "${other_project}" == "${project}" ]] && continue
        local other_file="${other_dir}lessons.jsonl"
        if [[ -f "${other_file}" ]] && grep -q "\"fingerprint\":\"${fingerprint}\"" "${other_file}" 2>/dev/null; then
            match_count=$((match_count + 1))
            matched_projects+=("${other_project}")
        fi
    done

    # Auto-promote to CONFIRMED if seen in 2+ projects
    if [[ ${match_count} -ge 1 ]]; then
        local promote_line
        promote_line=$(printf '{"action":"promote","fingerprint":"%s","from":"TEMP","to":"CONFIRMED","reason":"cross_project_recurrence","distinct_projects":["%s","%s"],"timestamp":"%s"}' \
            "${fingerprint}" "${project}" "$(IFS=','; echo "${matched_projects[*]}")" "${timestamp}")
        lesson_flock_append "${jsonl_file}" "${promote_line}"
    fi
}

# ── Search / Read ──

lesson_search() {
    local fingerprint="$1"
    local scope="${2:-all}"  # "all" or project name

    ensure_lessons_dir

    if [[ "${scope}" == "all" ]]; then
        for project_dir in "${LESSONS_HOME}/projects"/*/; do
            local jsonl_file="${project_dir}lessons.jsonl"
            if [[ -f "${jsonl_file}" ]]; then
                grep "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null || true
            fi
        done
    else
        local jsonl_file="${LESSONS_HOME}/projects/${scope}/lessons.jsonl"
        if [[ -f "${jsonl_file}" ]]; then
            grep "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null || true
        fi
    fi
}

lesson_read_snapshot() {
    local project="$1"
    local snapshot_file="${LESSONS_HOME}/projects/${project}/lessons.snapshot"
    if [[ -f "${snapshot_file}" ]]; then
        cat "${snapshot_file}"
    else
        # Fall back to JSONL
        local jsonl_file="${LESSONS_HOME}/projects/${project}/lessons.jsonl"
        if [[ -f "${jsonl_file}" ]]; then
            cat "${jsonl_file}"
        fi
    fi
}

# ── Snapshot compaction (post-run only) ──

compact_snapshot() {
    local project="$1"
    local jsonl_file="${LESSONS_HOME}/projects/${project}/lessons.jsonl"
    local snapshot_file="${LESSONS_HOME}/projects/${project}/lessons.snapshot"

    [[ -f "${jsonl_file}" ]] || return 0

    local lock_file="${jsonl_file}.lock"
    (
        flock -x -w 10 200 || { echo "ERROR: Could not acquire lock for compaction" >&2; return 1; }

        # Build compacted state by replaying JSONL
        # Use a temp file, then atomic move
        local tmp_snapshot="${snapshot_file}.tmp.$$"
        true > "${tmp_snapshot}"

        # Track fingerprint states via temp files (bash-native, no jq dependency)
        local state_dir
        state_dir=$(mktemp -d)

        while IFS= read -r line; do
            local action fingerprint
            action=$(echo "${line}" | grep -oP '"action":"\K[^"]+' || echo "unknown")
            fingerprint=$(echo "${line}" | grep -oP '"fingerprint":"\K[^"]+' || echo "")

            [[ -z "${fingerprint}" ]] && continue

            local fp_hash
            fp_hash=$(echo "${fingerprint}" | md5sum | cut -d' ' -f1)

            case "${action}" in
                create)
                    echo "${line}" > "${state_dir}/${fp_hash}"
                    ;;
                increment)
                    # Update recurrence count in the stored entry
                    if [[ -f "${state_dir}/${fp_hash}" ]]; then
                        local stored current_count new_count
                        stored=$(cat "${state_dir}/${fp_hash}")
                        current_count=$(echo "${stored}" | grep -oP '"recurrence_count":\K[0-9]+' || echo "1")
                        new_count=$((current_count + 1))
                        # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
                        # shellcheck disable=SC2001
                        stored=$(echo "${stored}" | sed "s/\"recurrence_count\":${current_count}/\"recurrence_count\":${new_count}/")
                        echo "${stored}" > "${state_dir}/${fp_hash}"
                    fi
                    ;;
                promote)
                    local new_status
                    new_status=$(echo "${line}" | grep -oP '"to":"\K[^"]+' || echo "")
                    if [[ -f "${state_dir}/${fp_hash}" ]] && [[ -n "${new_status}" ]]; then
                        local stored old_status
                        stored=$(cat "${state_dir}/${fp_hash}")
                        old_status=$(echo "${stored}" | grep -oP '"status":"\K[^"]+' || echo "TEMP")
                        # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
                        # shellcheck disable=SC2001
                        stored=$(echo "${stored}" | sed "s/\"status\":\"${old_status}\"/\"status\":\"${new_status}\"/")
                        echo "${stored}" > "${state_dir}/${fp_hash}"
                    fi
                    ;;
                demote)
                    if [[ -f "${state_dir}/${fp_hash}" ]]; then
                        local stored
                        stored=$(cat "${state_dir}/${fp_hash}")
                        # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
                        # shellcheck disable=SC2001
                        stored=$(echo "${stored}" | sed 's/"status":"[^"]*"/"status":"DEMOTED"/')
                        echo "${stored}" > "${state_dir}/${fp_hash}"
                    fi
                    ;;
                ttl_advance)
                    # Restore persisted projects_since_last from prior compaction
                    if [[ -f "${state_dir}/${fp_hash}" ]]; then
                        local stored psl_event
                        stored=$(cat "${state_dir}/${fp_hash}")
                        psl_event=$(echo "${line}" | grep -oP '"projects_since_last":\K[0-9]+' || echo "0")
                        # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
                        # shellcheck disable=SC2001
                        stored=$(echo "${stored}" | sed "s/\"projects_since_last\":[0-9]*/\"projects_since_last\":${psl_event}/")
                        echo "${stored}" > "${state_dir}/${fp_hash}"
                    fi
                    ;;
            esac
        done < "${jsonl_file}"

        # Write compacted entries: advance projects_since_last, check TTL, exclude EXPIRED
        # Collect ttl_advance events to persist psl progression in JSONL
        local ttl_events_file="${snapshot_file}.ttl_events.$$"
        true > "${ttl_events_file}"

        for fp_file in "${state_dir}"/*; do
            [[ -f "${fp_file}" ]] || continue
            local entry status severity_val ttl_base_val recurrence_val psl_val fp_in_entry
            entry=$(cat "${fp_file}")
            status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "TEMP")
            fp_in_entry=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]+' || echo "")

            # Skip already expired
            [[ "${status}" == "EXPIRED" ]] && continue

            # Advance projects_since_last counter
            psl_val=$(echo "${entry}" | grep -oP '"projects_since_last":\K[0-9]+' || echo "0")
            psl_val=$((psl_val + 1))
            # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
            # shellcheck disable=SC2001
            entry=$(echo "${entry}" | sed "s/\"projects_since_last\":[0-9]*/\"projects_since_last\":${psl_val}/")

            # Check adaptive TTL for TEMP entries
            if [[ "${status}" == "TEMP" ]]; then
                severity_val=$(echo "${entry}" | grep -oP '"severity":"\K[^"]+' || echo "medium")
                ttl_base_val=$(echo "${entry}" | grep -oP '"ttl_base":\K[0-9]+' || echo "5")
                recurrence_val=$(echo "${entry}" | grep -oP '"recurrence_count":\K[0-9]+' || echo "1")

                local ext_per effective_ttl
                case "${severity_val}" in
                    low)      ext_per=1 ;;
                    medium)   ext_per=2 ;;
                    high)     ext_per=3 ;;
                    critical) ext_per=999 ;;
                    *)        ext_per=2 ;;
                esac
                effective_ttl=$((ttl_base_val + (recurrence_val - 1) * ext_per))

                if [[ ${psl_val} -ge ${effective_ttl} ]]; then
                    # RATIONALE: bash ${//} unreliable with JSON special chars; sed is safer here
                    # shellcheck disable=SC2001
                    entry=$(echo "${entry}" | sed 's/"status":"TEMP"/"status":"EXPIRED"/')
                    continue  # skip expired entries from snapshot
                fi
            fi

            echo "${entry}" >> "${tmp_snapshot}"

            # Record ttl_advance event to persist psl in JSONL for next compaction
            if [[ -n "${fp_in_entry}" ]]; then
                local advance_ts
                advance_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                printf '{"action":"ttl_advance","fingerprint":"%s","projects_since_last":%d,"timestamp":"%s"}\n' \
                    "${fp_in_entry}" "${psl_val}" "${advance_ts}" >> "${ttl_events_file}"
            fi
        done

        rm -rf "${state_dir}"
        mv "${tmp_snapshot}" "${snapshot_file}"

        # Append ttl_advance events to JSONL so next replay picks up psl progression
        if [[ -s "${ttl_events_file}" ]]; then
            cat "${ttl_events_file}" >> "${jsonl_file}"
        fi
        rm -f "${ttl_events_file}"
    ) 200>"${lock_file}"
}

# ── Promotion checks ──

lesson_check_promotion() {
    local fingerprint="$1"

    ensure_lessons_dir

    local total_recurrence=0
    local distinct_projects=()

    for project_dir in "${LESSONS_HOME}/projects"/*/; do
        local project_name jsonl_file
        project_name=$(basename "${project_dir}")
        jsonl_file="${project_dir}lessons.jsonl"
        [[ -f "${jsonl_file}" ]] || continue

        if grep -q "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null; then
            distinct_projects+=("${project_name}")
            # Count recurrences in this project
            local increments
            increments=$(grep -c "\"fingerprint\":\"${fingerprint}\".*\"action\":\"increment\"" "${jsonl_file}" 2>/dev/null | tr -dc '0-9' || true)
            increments=${increments:-0}
            total_recurrence=$((total_recurrence + 1 + increments))
        fi
    done

    local project_count=${#distinct_projects[@]}

    # TEMP → CONFIRMED: recurrence >= 2, distinct_projects >= 2
    if [[ ${total_recurrence} -ge 2 ]] && [[ ${project_count} -ge 2 ]]; then
        echo "CONFIRMED"
        return 0
    fi

    echo "TEMP"
    return 0
}

lesson_promote() {
    local fingerprint="$1"
    local from_status="$2"
    local to_status="$3"
    local reason="${4:-manual}"
    local project="${5:-}"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Write promotion record to the specified project, or all projects that have this fingerprint
    if [[ -n "${project}" ]]; then
        local jsonl_file="${LESSONS_HOME}/projects/${project}/lessons.jsonl"
        if [[ -f "${jsonl_file}" ]]; then
            local promote_line
            promote_line=$(printf '{"action":"promote","fingerprint":"%s","from":"%s","to":"%s","reason":"%s","timestamp":"%s"}' \
                "${fingerprint}" "${from_status}" "${to_status}" "${reason}" "${timestamp}")
            lesson_flock_append "${jsonl_file}" "${promote_line}"
        fi
    else
        for project_dir in "${LESSONS_HOME}/projects"/*/; do
            local jsonl_file="${project_dir}lessons.jsonl"
            [[ -f "${jsonl_file}" ]] || continue
            if grep -q "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null; then
                local promote_line
                promote_line=$(printf '{"action":"promote","fingerprint":"%s","from":"%s","to":"%s","reason":"%s","timestamp":"%s"}' \
                    "${fingerprint}" "${from_status}" "${to_status}" "${reason}" "${timestamp}")
                lesson_flock_append "${jsonl_file}" "${promote_line}"
            fi
        done
    fi

    # If promoting to SIGN, also append to global-signs.jsonl
    if [[ "${to_status}" == "SIGN" ]]; then
        local sign_line
        sign_line=$(printf '{"fingerprint":"%s","promoted_from":"%s","reason":"%s","timestamp":"%s"}' \
            "${fingerprint}" "${from_status}" "${reason}" "${timestamp}")
        lesson_flock_append "${LESSONS_HOME}/global-signs.jsonl" "${sign_line}"
    fi
}

lesson_demote() {
    local fingerprint="$1"
    local reason="$2"
    local evidence_run_ids="${3:-}"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    for project_dir in "${LESSONS_HOME}/projects"/*/; do
        local jsonl_file="${project_dir}lessons.jsonl"
        [[ -f "${jsonl_file}" ]] || continue
        if grep -q "\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null; then
            local demote_line
            demote_line=$(printf '{"action":"demote","fingerprint":"%s","reason":"%s","evidence_run_ids":"%s","timestamp":"%s"}' \
                "${fingerprint}" "${reason}" "${evidence_run_ids}" "${timestamp}")
            lesson_flock_append "${jsonl_file}" "${demote_line}"
        fi
    done
}

# ── Adaptive TTL check ──

lesson_check_ttl() {
    local fingerprint="$1"
    local project="$2"

    # Read from snapshot (effective state with persisted psl), fall back to JSONL
    local snapshot_file="${LESSONS_HOME}/projects/${project}/lessons.snapshot"
    local jsonl_file="${LESSONS_HOME}/projects/${project}/lessons.jsonl"
    local effective_entry=""

    if [[ -f "${snapshot_file}" ]]; then
        effective_entry=$(grep "\"fingerprint\":\"${fingerprint}\"" "${snapshot_file}" 2>/dev/null | head -1 || echo "")
        if [[ -z "${effective_entry}" ]]; then
            # Snapshot exists but entry is absent — check if it was ever created
            if [[ -f "${jsonl_file}" ]] && grep -q "\"action\":\"create\".*\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null; then
                # Entry was created but expired during compaction
                echo "EXPIRED"
                return 0
            fi
            return 0  # never existed
        fi
    elif [[ -f "${jsonl_file}" ]]; then
        effective_entry=$(grep "\"action\":\"create\".*\"fingerprint\":\"${fingerprint}\"" "${jsonl_file}" 2>/dev/null | head -1 || echo "")
    fi
    [[ -z "${effective_entry}" ]] && return 0

    local status
    status=$(echo "${effective_entry}" | grep -oP '"status":"\K[^"]+' || echo "TEMP")
    # Already expired in snapshot
    [[ "${status}" == "EXPIRED" ]] && { echo "EXPIRED"; return 0; }
    # TTL expiry only applies to TEMP entries — CONFIRMED/PROMOTED/SIGN are retained
    [[ "${status}" != "TEMP" ]] && { echo "ALIVE"; return 0; }

    local ttl_base severity recurrence_count
    ttl_base=$(echo "${effective_entry}" | grep -oP '"ttl_base":\K[0-9]+' || echo "5")
    severity=$(echo "${effective_entry}" | grep -oP '"severity":"\K[^"]+' || echo "medium")
    recurrence_count=$(echo "${effective_entry}" | grep -oP '"recurrence_count":\K[0-9]+' || echo "1")

    # Adaptive TTL: base + extension per recurrence
    local extension_per
    case "${severity}" in
        low)      extension_per=1 ;;
        medium)   extension_per=2 ;;
        high)     extension_per=3 ;;
        critical) echo "ALIVE"; return 0 ;;  # never expires
        *)        extension_per=2 ;;
    esac

    local effective_ttl=$((ttl_base + (recurrence_count - 1) * extension_per))
    local projects_since
    projects_since=$(echo "${effective_entry}" | grep -oP '"projects_since_last":\K[0-9]+' || echo "0")

    if [[ ${projects_since} -ge ${effective_ttl} ]]; then
        echo "EXPIRED"
    else
        echo "ALIVE"
    fi
}

# ── Live lessons injection (Phase 10 — bidirectional feed) ──
# Merges project-local + global CONFIRMED+ lessons into lessons-active.md
# Called before each builder task so lessons are always current.

inject_active_lessons() {
    local project_name="${1}"
    local project_spectra_dir="${2}"   # {project}/.spectra/
    local output_file="${project_spectra_dir}/lessons-active.md"
    local date_str
    date_str=$(date -u +%Y-%m-%d)

    ensure_lessons_dir

    # Collect project-local CONFIRMED+ entries
    local project_entries=()
    local project_snapshot="${LESSONS_HOME}/projects/${project_name}/lessons.snapshot"
    local project_jsonl="${LESSONS_HOME}/projects/${project_name}/lessons.jsonl"
    local project_source="${project_snapshot}"
    [[ -f "${project_source}" ]] || project_source="${project_jsonl}"

    if [[ -f "${project_source}" ]]; then
        while IFS= read -r entry; do
            local status
            status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")
            if echo "${status}" | grep -qP '^(CONFIRMED|PROMOTED|SIGN)$'; then
                validate_lesson_entry "${entry}" && project_entries+=("${entry}")
            fi
        done < "${project_source}"
    fi

    # Collect global CONFIRMED+ entries from ALL other projects
    local global_entries=()
    for other_dir in "${LESSONS_HOME}/projects"/*/; do
        [[ -d "${other_dir}" ]] || continue
        local other_project
        other_project=$(basename "${other_dir}")
        [[ "${other_project}" == "${project_name}" ]] && continue

        local other_source="${other_dir}lessons.snapshot"
        [[ -f "${other_source}" ]] || other_source="${other_dir}lessons.jsonl"
        [[ -f "${other_source}" ]] || continue

        while IFS= read -r entry; do
            local status
            status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")
            if echo "${status}" | grep -qP '^(CONFIRMED|PROMOTED|SIGN)$'; then
                validate_lesson_entry "${entry}" && global_entries+=("${entry}")
            fi
        done < "${other_source}"
    done

    # Dedup by fingerprint (keep highest-status entry)
    local dedup_dir
    dedup_dir=$(mktemp -d)

    _dedup_entry() {
        local entry="$1" source_tag="$2"
        local fp fp_hash status new_rank existing_status existing_rank
        fp=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]+' || echo "")
        [[ -z "${fp}" ]] && return
        fp_hash=$(echo "${fp}" | md5sum | cut -d' ' -f1)

        case "$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")" in
            CONFIRMED) new_rank=1 ;; PROMOTED) new_rank=2 ;; SIGN) new_rank=3 ;; *) new_rank=0 ;;
        esac

        if [[ -f "${dedup_dir}/${fp_hash}" ]]; then
            existing_rank=$(head -1 "${dedup_dir}/${fp_hash}" | cut -d'|' -f1)
            [[ ${new_rank} -le ${existing_rank} ]] && return
        fi
        echo "${new_rank}|${source_tag}|${entry}" > "${dedup_dir}/${fp_hash}"
    }

    for entry in "${project_entries[@]+"${project_entries[@]}"}"; do
        [[ -n "${entry}" ]] && _dedup_entry "${entry}" "project"
    done
    for entry in "${global_entries[@]+"${global_entries[@]}"}"; do
        [[ -n "${entry}" ]] && _dedup_entry "${entry}" "global"
    done

    # Collect entries, then sort by status rank (SIGN=3 > PROMOTED=2 > CONFIRMED=1)
    # so cap at 15/10 drops lowest-priority first
    local project_lines=() global_lines=()
    for fp_file in "${dedup_dir}"/*; do
        [[ -f "${fp_file}" ]] || continue
        local line source_tag
        line=$(cat "${fp_file}")
        source_tag=$(echo "${line}" | cut -d'|' -f2)
        if [[ "${source_tag}" == "project" ]]; then
            project_lines+=("${line}")
        else
            global_lines+=("${line}")
        fi
    done
    rm -rf "${dedup_dir}"

    # Sort descending by rank (field 1) so higher-priority lessons survive the cap
    local sorted_project=() sorted_global=()
    if [[ ${#project_lines[@]} -gt 0 ]]; then
        mapfile -t sorted_project < <(printf '%s\n' "${project_lines[@]}" | sort -t'|' -k1 -rn)
        project_lines=("${sorted_project[@]}")
    fi
    if [[ ${#global_lines[@]} -gt 0 ]]; then
        mapfile -t sorted_global < <(printf '%s\n' "${global_lines[@]}" | sort -t'|' -k1 -rn)
        global_lines=("${sorted_global[@]}")
    fi

    # Write lessons-active.md
    {
        echo "# Active Lessons — ${project_name} (${date_str})"
        echo "> Generated from project history + global institutional memory."
        echo "> Builder: treat these as hard guardrails, not suggestions."
        echo ""

        if [[ ${#project_lines[@]} -gt 0 ]]; then
            echo "## From This Project (CONFIRMED+)"
            local count=0
            for line in "${project_lines[@]}"; do
                [[ ${count} -ge 15 ]] && break
                local entry fp detail recurrence status
                entry=$(echo "${line}" | cut -d'|' -f3-)
                fp=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]+' || echo "unknown")
                detail=$(echo "${entry}" | grep -oP '"detail":"\K[^"]*' || echo "")
                recurrence=$(echo "${entry}" | grep -oP '"recurrence_count":\K[0-9]+' || echo "1")
                status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")
                detail=$(sanitize_for_propagation "${detail}")
                echo "- [${fp}] ${detail} — seen ${recurrence}x (${status})"
                count=$((count + 1))
            done
            echo ""
        fi

        if [[ ${#global_lines[@]} -gt 0 ]]; then
            echo "## From Global Memory (CONFIRMED+ across all projects)"
            local count=0
            for line in "${global_lines[@]}"; do
                [[ ${count} -ge 10 ]] && break
                local entry fp detail num_projects status
                entry=$(echo "${line}" | cut -d'|' -f3-)
                fp=$(echo "${entry}" | grep -oP '"fingerprint":"\K[^"]+' || echo "unknown")
                detail=$(echo "${entry}" | grep -oP '"detail":"\K[^"]*' || echo "")
                num_projects=$(echo "${entry}" | grep -oP '"distinct_projects":\[' >/dev/null 2>&1 && \
                    echo "${entry}" | grep -oP '"distinct_projects":\[[^\]]*\]' | tr ',' '\n' | wc -l || echo "1")
                status=$(echo "${entry}" | grep -oP '"status":"\K[^"]+' || echo "")
                detail=$(sanitize_for_propagation "${detail}")
                echo "- [${fp}] ${detail} — ${num_projects} project(s) (${status})"
                count=$((count + 1))
            done
            echo ""
        fi

        if [[ ${#project_lines[@]} -eq 0 ]] && [[ ${#global_lines[@]} -eq 0 ]]; then
            echo "No active lessons yet. Lessons accumulate as the project runs."
            echo ""
        fi
    } > "${output_file}"
}

# ── Brownfield project upgrade (Phase 10) ──
# Non-destructive upgrade for pre-Phase10 projects.
# Idempotent: skips if VERSION marker already matches current version.
# NEVER touches: plan.md, signals/, logs/, CLAUDE.md, checkpoints/

SPECTRA_CURRENT_VERSION="v5.5"

spectra_upgrade_project() {
    local project_spectra_dir="${1}"   # {project}/.spectra/
    local project_name="${2:-}"

    # Idempotent: skip if VERSION already matches
    if [[ -f "${project_spectra_dir}/VERSION" ]]; then
        local existing_version
        existing_version=$(cat "${project_spectra_dir}/VERSION" 2>/dev/null || echo "")
        if [[ "${existing_version}" == "${SPECTRA_CURRENT_VERSION}" ]]; then
            return 0
        fi
    fi

    # 1. Backup guardrails.md before touching it
    if [[ -f "${project_spectra_dir}/guardrails.md" ]]; then
        cp "${project_spectra_dir}/guardrails.md" \
           "${project_spectra_dir}/guardrails.md.pre-v10" 2>/dev/null || true

        # 2. Strip lessons section from guardrails.md (preserve SIGNs)
        # Only strip content within a "# Lessons" / "## Lessons" heading scope.
        # Bullets outside that section are preserved even if they match status patterns.
        # Idempotent: safe to run multiple times
        local tmp_guardrails="${project_spectra_dir}/guardrails.md.tmp.$$"
        awk '
            /^#+ *Lessons/ { in_lessons=1; skip=1; next }
            /^#/ && !/^#+ *Lessons/ { in_lessons=0; skip=0 }
            in_lessons && /^- \*\*\[(CONFIRMED|PROMOTED|SIGN)\]/ { skip=1 }
            !skip { print }
        ' "${project_spectra_dir}/guardrails.md" > "${tmp_guardrails}"
        # Remove trailing blank lines
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${tmp_guardrails}" 2>/dev/null || true
        mv "${tmp_guardrails}" "${project_spectra_dir}/guardrails.md"
    fi

    # 3. Generate initial lessons-active.md
    if [[ -n "${project_name}" ]]; then
        inject_active_lessons "${project_name}" "${project_spectra_dir}" 2>/dev/null || true
    fi

    # 4. Write VERSION marker
    echo "${SPECTRA_CURRENT_VERSION}" > "${project_spectra_dir}/VERSION"
}

# ── Guardrails dedup helper ──

guardrails_dedup_check() {
    local warning_text="$1"
    local guardrails_file="${2:-${SPECTRA_DIR}/guardrails.md}"

    # Check if this exact warning text already exists in guardrails
    if [[ -f "${guardrails_file}" ]] && grep -qF -- "${warning_text}" "${guardrails_file}" 2>/dev/null; then
        return 1  # duplicate — skip
    fi
    return 0  # not a duplicate — safe to append
}
