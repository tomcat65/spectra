#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Agent Routing Tests
# Validates YAML frontmatter triggers, exclusions, compatibility, and metadata
# for all 7 agents.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"
AGENTS_DIR="${SPECTRA_HOME}/agents"

PASS=0
FAIL=0

assert_pass() {
    PASS=$((PASS + 1))
    echo "  PASS  $1"
}

assert_fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL  $1"
}

AGENTS=("spectra-planner" "spectra-builder" "spectra-verifier" "spectra-auditor" "spectra-reviewer" "spectra-scout" "spectra-oracle")

# ══════════════════════════════════════════
# Test group 1: All agents have trigger phrases
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if [[ ! -f "${file}" ]]; then
        assert_fail "${agent} agent file exists"
        continue
    fi

    # Check for "Use when:" trigger
    if grep -q 'Use when:' "${file}"; then
        assert_pass "${agent} has 'Use when:' trigger"
    else
        assert_fail "${agent} has 'Use when:' trigger"
    fi
done

# ══════════════════════════════════════════
# Test group 2: All agents have exclusion phrases
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if grep -q 'Do NOT use' "${file}"; then
        assert_pass "${agent} has 'Do NOT use' exclusion"
    else
        assert_fail "${agent} has 'Do NOT use' exclusion"
    fi
done

# ══════════════════════════════════════════
# Test group 3: All agents have compatibility field
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if grep -q '^compatibility:' "${file}"; then
        assert_pass "${agent} has compatibility field"
    else
        assert_fail "${agent} has compatibility field"
    fi
done

# ══════════════════════════════════════════
# Test group 4: All agents have metadata.framework = SPECTRA
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if grep -q 'framework: SPECTRA' "${file}"; then
        assert_pass "${agent} has metadata.framework = SPECTRA"
    else
        assert_fail "${agent} has metadata.framework = SPECTRA"
    fi
done

# ══════════════════════════════════════════
# Test group 5: All agents have metadata.version = "5.4"
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if grep -q 'version: "5.4"' "${file}"; then
        assert_pass "${agent} has metadata.version = 5.4"
    else
        assert_fail "${agent} has metadata.version = 5.4"
    fi
done

# ══════════════════════════════════════════
# Test group 6: Each agent has correct metadata.role
# ══════════════════════════════════════════

declare -A EXPECTED_ROLES=(
    ["spectra-planner"]="planner"
    ["spectra-builder"]="builder"
    ["spectra-verifier"]="verifier"
    ["spectra-auditor"]="auditor"
    ["spectra-reviewer"]="reviewer"
    ["spectra-scout"]="scout"
    ["spectra-oracle"]="oracle"
)

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    expected_role="${EXPECTED_ROLES[${agent}]}"
    if grep -q "role: ${expected_role}" "${file}"; then
        assert_pass "${agent} has metadata.role = ${expected_role}"
    else
        assert_fail "${agent} has metadata.role = ${expected_role}"
    fi
done

# ══════════════════════════════════════════
# Test group 7: Agent-specific trigger content validation
# ══════════════════════════════════════════

# Planner triggers on planning, not implementation
if grep -q 'plan this' "${AGENTS_DIR}/spectra-planner.md"; then
    assert_pass "planner triggers on 'plan this'"
else
    assert_fail "planner triggers on 'plan this'"
fi

if grep -q 'Do NOT use for:.*implementation' "${AGENTS_DIR}/spectra-planner.md"; then
    assert_pass "planner excludes implementation"
else
    assert_fail "planner excludes implementation"
fi

# Builder triggers on unchecked tasks
if grep -q 'unchecked task' "${AGENTS_DIR}/spectra-builder.md"; then
    assert_pass "builder triggers on unchecked tasks"
else
    assert_fail "builder triggers on unchecked tasks"
fi

if grep -q 'Do NOT use for:.*planning' "${AGENTS_DIR}/spectra-builder.md"; then
    assert_pass "builder excludes planning"
else
    assert_fail "builder excludes planning"
fi

# Verifier triggers on verification, not implementation
if grep -q 'wiring proof' "${AGENTS_DIR}/spectra-verifier.md"; then
    assert_pass "verifier triggers on wiring proof"
else
    assert_fail "verifier triggers on wiring proof"
fi

if grep -q 'Do NOT use for:.*implementation' "${AGENTS_DIR}/spectra-verifier.md"; then
    assert_pass "verifier excludes implementation"
else
    assert_fail "verifier excludes implementation"
fi

# Auditor triggers pre-task, not post-verification
if grep -q 'pre-flight' "${AGENTS_DIR}/spectra-auditor.md"; then
    assert_pass "auditor triggers on pre-flight"
else
    assert_fail "auditor triggers on pre-flight"
fi

if grep -q 'Do NOT use for:.*post-verification' "${AGENTS_DIR}/spectra-auditor.md"; then
    assert_pass "auditor excludes post-verification"
else
    assert_fail "auditor excludes post-verification"
fi

# Oracle triggers on STUCK only
if grep -q 'STUCK signal' "${AGENTS_DIR}/spectra-oracle.md"; then
    assert_pass "oracle triggers on STUCK signal"
else
    assert_fail "oracle triggers on STUCK signal"
fi

if grep -q 'Do NOT use for:.*plan review' "${AGENTS_DIR}/spectra-oracle.md"; then
    assert_pass "oracle excludes plan review"
else
    assert_fail "oracle excludes plan review"
fi

# Scout triggers on brownfield discovery
if grep -q 'brownfield' "${AGENTS_DIR}/spectra-scout.md"; then
    assert_pass "scout triggers on brownfield"
else
    assert_fail "scout triggers on brownfield"
fi

if grep -q 'Do NOT use for:.*greenfield' "${AGENTS_DIR}/spectra-scout.md"; then
    assert_pass "scout excludes greenfield with no code"
else
    assert_fail "scout excludes greenfield with no code"
fi

# Reviewer triggers on adversarial validation
if grep -q 'adversarial' "${AGENTS_DIR}/spectra-reviewer.md"; then
    assert_pass "reviewer triggers on adversarial validation"
else
    assert_fail "reviewer triggers on adversarial validation"
fi

if grep -q 'Do NOT use for:.*implementation' "${AGENTS_DIR}/spectra-reviewer.md"; then
    assert_pass "reviewer excludes implementation"
else
    assert_fail "reviewer excludes implementation"
fi

# ══════════════════════════════════════════
# Test group 8: All agents have orchestrator metadata
# ══════════════════════════════════════════

for agent in "${AGENTS[@]}"; do
    file="${AGENTS_DIR}/${agent}.md"
    if grep -q 'orchestrator: spectra-loop.sh' "${file}"; then
        assert_pass "${agent} has orchestrator = spectra-loop.sh"
    else
        assert_fail "${agent} has orchestrator = spectra-loop.sh"
    fi
done

# ══════════════════════════════════════════
# Summary
# ══════════════════════════════════════════
echo ""
echo "  agent-routing: ${PASS} passed, ${FAIL} failed"

[[ "${FAIL}" -eq 0 ]] || exit 1
