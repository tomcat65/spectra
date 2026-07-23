#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: canonical local/GitHub CI lint parity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_ROOT="$(dirname "${SCRIPT_DIR}")"
LINT="${SPECTRA_ROOT}/scripts/spectra-ci-lint.sh"
WORKFLOW="${SPECTRA_ROOT}/.github/workflows/spectra-ci.yml"
MANIFEST="${SPECTRA_ROOT}/config/loop-modules.txt"

PASS=0
FAIL=0
SKIP=0
pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT

make_fixture() {
    local root="$1" module
    mkdir -p "${root}/bin" "${root}/lib" "${root}/config" \
        "${root}/scripts" "${root}/agents/scripts" "${root}/hooks"
    cp "${LINT}" "${root}/scripts/spectra-ci-lint.sh"
    cp "${SPECTRA_ROOT}/bin/spectra-loop.sh" "${root}/bin/spectra-loop.sh"
    cp "${MANIFEST}" "${root}/config/loop-modules.txt"
    while IFS= read -r module; do
        [[ -n "${module}" && "${module}" != \#* ]] || continue
        cp "${SPECTRA_ROOT}/lib/${module}.sh" "${root}/lib/${module}.sh"
    done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${MANIFEST}")
    chmod +x "${root}/scripts/spectra-ci-lint.sh"
}

echo "  Test: canonical lint script exists and is executable"
if [[ -x "${LINT}" ]]; then pass "canonical lint executable"; else fail "canonical lint missing"; fi

echo "  Test: canonical module manifest contains every current loop module"
manifest_count=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${MANIFEST}" | wc -l)
disk_count=$(find "${SPECTRA_ROOT}/lib" -maxdepth 1 -type f -name 'loop-*.sh' | wc -l)
if [[ ${manifest_count} -eq ${disk_count} && ${manifest_count} -gt 0 ]]; then
    pass "manifest count matches disk (${disk_count})"
else
    fail "manifest=${manifest_count} disk=${disk_count}"
fi

echo "  Test: --help documents all canonical lint modes"
help_out=$("${LINT}" --help)
if echo "${help_out}" | grep -q -- '--modules' && echo "${help_out}" | grep -q -- '--actionlint'; then
    pass "help documents modes"
else
    fail "help incomplete"
fi

echo "  Test: GitHub workflow delegates every lint gate to canonical script"
delegated=0
for mode in syntax modules shellcheck ratchet rationale actionlint; do
    grep -q "spectra-ci-lint.sh --${mode}" "${WORKFLOW}" && delegated=$((delegated + 1))
done
if [[ ${delegated} -eq 6 ]] && ! grep -q 'EXPECTED_MODULES=' "${WORKFLOW}" \
   && grep -q 'sha256sum -c' "${WORKFLOW}"; then
    pass "workflow has no duplicated lint implementation"
else
    fail "delegated=${delegated}/6 or stale inline inventory"
fi

echo "  Test: canonical syntax gate passes current repository"
if "${LINT}" --syntax >/dev/null; then pass "syntax gate passes"; else fail "syntax gate failed"; fi

echo "  Test: canonical module gate passes current repository"
if "${LINT}" --modules >/dev/null; then pass "module gate passes"; else fail "module gate failed"; fi

echo "  Test: canonical rationale gate passes current repository"
if "${LINT}" --rationale >/dev/null; then pass "rationale gate passes"; else fail "rationale gate failed"; fi

echo "  Test: rogue on-disk module is rejected"
fixture_rogue="${tmp_root}/rogue"; make_fixture "${fixture_rogue}"
printf '%s\n' '#!/usr/bin/env bash' > "${fixture_rogue}/lib/loop-rogue.sh"
set +e; SPECTRA_CI_ROOT="${fixture_rogue}" "${LINT}" --modules >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "rogue module rejected"; else fail "rogue module rc=${rc}"; fi

echo "  Test: manifest module missing on disk is rejected"
fixture_missing="${tmp_root}/missing"; make_fixture "${fixture_missing}"
rm -f "${fixture_missing}/lib/loop-verdict.sh"
set +e; SPECTRA_CI_ROOT="${fixture_missing}" "${LINT}" --modules >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "missing module rejected"; else fail "missing module rc=${rc}"; fi

echo "  Test: duplicate module source is rejected"
fixture_duplicate="${tmp_root}/duplicate"; make_fixture "${fixture_duplicate}"
printf '%s\n' 'source "${SPECTRA_HOME}/lib/loop-verdict.sh"' >> "${fixture_duplicate}/bin/spectra-loop.sh"
set +e; SPECTRA_CI_ROOT="${fixture_duplicate}" "${LINT}" --modules >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "duplicate source rejected"; else fail "duplicate source rc=${rc}"; fi

echo "  Test: suppression without RATIONALE is rejected"
fixture_rationale="${tmp_root}/rationale"; make_fixture "${fixture_rationale}"
cat > "${fixture_rationale}/scripts/bad.sh" <<'BAD'
#!/usr/bin/env bash
# shellcheck disable=SC2086
echo $value
BAD
set +e; SPECTRA_CI_ROOT="${fixture_rationale}" "${LINT}" --rationale >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 1 ]]; then pass "unjustified suppression rejected"; else fail "rationale rc=${rc}"; fi

echo "  Test: missing required lint tool returns environment error"
set +e; SHELLCHECK_BIN="/definitely/missing-shellcheck" "${LINT}" --shellcheck >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "missing tool -> exit 2"; else fail "missing tool rc=${rc}"; fi

echo "  Test: missing actionlint returns environment error"
set +e; ACTIONLINT_BIN="/definitely/missing-actionlint" "${LINT}" --actionlint >/dev/null 2>&1; rc=$?; set -e
if [[ ${rc} -eq 2 ]]; then pass "missing actionlint -> exit 2"; else fail "missing actionlint rc=${rc}"; fi

echo ""
echo "  ci-parity: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=ci-parity pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"
[[ ${FAIL} -eq 0 ]]
