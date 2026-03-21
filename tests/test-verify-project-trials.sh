#!/usr/bin/env bash
set -euo pipefail

# SPECTRA Test: external verifier project trials
# Encodes scratch-project regressions:
# 1. Clean Python project passes full-sweep verification
# 2. JavaScript stdlib imports do not trigger false dependency failures
# 3. Polyglot repos sweep all detected languages and fail on broken frontend tests
# 4. JavaScript dead project imports in tests emit SIGN-001
# 5. JavaScript CLI entry points without subprocess tests emit SIGN-002

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRA_HOME="$(dirname "${SCRIPT_DIR}")"
INIT_SCRIPT="${SPECTRA_HOME}/bin/spectra-init.sh"
PLAN_EXTRACT="${SPECTRA_HOME}/bin/plan-extract.sh"
VERIFY_SCRIPT="${SPECTRA_HOME}/bin/spectra-verify.sh"

PASS=0
FAIL=0
SKIP=0

tmp_root=""
cleanup() { [[ -n "${tmp_root}" ]] && rm -rf "${tmp_root}"; }
trap cleanup EXIT
tmp_root=$(mktemp -d)

setup_git_repo() {
    git init -q .
    git config user.name "Codex"
    git config user.email "codex@example.com"
}

init_spectra_project() {
    local project_name="$1"
    SPECTRA_SKIP_PATH_SETUP=true bash "${INIT_SCRIPT}" --name "${project_name}" --level 1 --no-commit </dev/null > /dev/null 2>&1
}

extract_plan_json() {
    bash "${PLAN_EXTRACT}" --file .spectra/plan.md --output .spectra/plan.json > /dev/null 2>&1
}

commit_fixture() {
    local message="$1"
    git add .
    git commit -qm "${message}"
}

# ══════════════════════════════════════════
# Test 1: Clean Python repo passes verifier full sweep
# ══════════════════════════════════════════
echo "  Test: clean Python project passes full-sweep verification"

(
    case_dir="${tmp_root}/python-clean"
    mkdir -p "${case_dir}"
    cd "${case_dir}"
    setup_git_repo
    mkdir -p src tests

    cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "python-clean"
version = "0.1.0"
EOF

    : > src/__init__.py
    cat > src/mathlib.py <<'EOF'
def add(a: int, b: int) -> int:
    return a + b
EOF

    cat > tests/test_mathlib.py <<'EOF'
from src.mathlib import add


def test_add() -> None:
    assert add(2, 3) == 5
EOF

    init_spectra_project "python-clean"
    cat > .spectra/plan.md <<'EOF'
# SPECTRA Execution Plan

## Project: python-clean
## Level: 1
## Generated: 2026-03-13
## Source: manual

---

## Task 001: Ship add helper
- [x] 001: Ship add helper
- AC:
  - add returns the sum of two integers.
  - pytest passes.
- Files: src/mathlib.py, tests/test_mathlib.py
- Verify: `python3 -m pytest -q`
- Risk: low
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [src/mathlib.py]
  - touches: [tests/test_mathlib.py]
  - reads: []
- Wiring-proof:
  - CLI: python3 -m pytest -q
  - Integration: add is imported by tests and exercised with a real assertion.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Recommendation: SEQUENTIAL_REQUIRED
EOF

    extract_plan_json
    commit_fixture "feat(task-1): ship add helper"

    set +e
    output=$(bash "${VERIFY_SCRIPT}" --task 1 --full-sweep 2>&1)
    exit_code=$?
    set -e

    if [[ ${exit_code} -eq 0 ]] && echo "${output}" | grep -q '✅ PASS'; then
        echo "  PASS  clean Python project passes full-sweep verification"
    else
        echo "  FAIL  clean Python project failed verification"
        echo "        output: $(echo "${output}" | tail -6 | tr '\n' ' ')"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 2: JS stdlib imports do not trigger dependency false positives
# ══════════════════════════════════════════
echo "  Test: JavaScript stdlib imports do not trigger missing dependency warning"

(
    case_dir="${tmp_root}/javascript-stdlib"
    mkdir -p "${case_dir}"
    cd "${case_dir}"
    setup_git_repo
    mkdir -p src tests

    cat > package.json <<'EOF'
{
  "name": "javascript-stdlib",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF

    cat > src/math.js <<'EOF'
import path from 'node:path';

export function add(a, b) {
    if (!path.sep) {
        throw new Error('path unavailable');
    }
    return a + b;
}
EOF

    cat > tests/math.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { add } from '../src/math.js';

test('add sums two numbers', () => {
    assert.equal(add(2, 3), 5);
});
EOF

    init_spectra_project "javascript-stdlib"
    cat > .spectra/plan.md <<'EOF'
# SPECTRA Execution Plan

## Project: javascript-stdlib
## Level: 1
## Generated: 2026-03-13
## Source: manual

---

## Task 001: Ship JS add helper
- [x] 001: Ship JS add helper
- AC:
  - add returns the sum of two numbers.
  - node tests pass.
- Files: src/math.js, tests/math.test.js
- Verify: `npm test`
- Risk: low
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [src/math.js]
  - touches: [tests/math.test.js]
  - reads: []
- Wiring-proof:
  - CLI: npm test
  - Integration: tests import add from src/math.js and exercise the exported function.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Recommendation: SEQUENTIAL_REQUIRED
EOF

    extract_plan_json
    commit_fixture "feat(task-1): ship js add helper"

    set +e
    output=$(bash "${VERIFY_SCRIPT}" --task 1 --full-sweep 2>&1)
    exit_code=$?
    set -e

    if [[ ${exit_code} -eq 0 ]] && ! echo "${output}" | grep -q "Missing dependency: 'path'"; then
        echo "  PASS  JavaScript stdlib imports do not trigger missing dependency warning"
    else
        echo "  FAIL  JavaScript stdlib verification regressed"
        echo "        output: $(echo "${output}" | tail -8 | tr '\n' ' ')"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 3: Polyglot repo sweeps both Python and JavaScript
# ══════════════════════════════════════════
echo "  Test: polyglot repo fails verification when frontend regression fails"

(
    case_dir="${tmp_root}/polyglot-blindspot"
    mkdir -p "${case_dir}"
    cd "${case_dir}"
    setup_git_repo
    mkdir -p backend tests frontend/src frontend/tests

    cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "polyglot-blindspot"
version = "0.1.0"
EOF

    cat > package.json <<'EOF'
{
  "name": "polyglot-blindspot",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "test": "node --test frontend/tests/*.test.js"
  }
}
EOF

    : > backend/__init__.py
    cat > backend/app.py <<'EOF'
def health() -> dict[str, str]:
    return {"status": "ok"}
EOF

    cat > tests/test_backend.py <<'EOF'
from backend.app import health


def test_health() -> None:
    assert health() == {"status": "ok"}
EOF

    cat > frontend/src/ui.js <<'EOF'
export function title() {
    return 'broken';
}
EOF

    cat > frontend/tests/ui.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { title } from '../src/ui.js';

test('frontend title is ready', () => {
    assert.equal(title(), 'ready');
});
EOF

    init_spectra_project "polyglot-blindspot"
    cat > .spectra/plan.md <<'EOF'
# SPECTRA Execution Plan

## Project: polyglot-blindspot
## Level: 1
## Generated: 2026-03-13
## Source: manual

---

## Task 001: Ship backend health check
- [x] 001: Ship backend health check
- AC:
  - backend health returns ok.
  - python tests pass.
- Files: backend/app.py, tests/test_backend.py, frontend/src/ui.js, frontend/tests/ui.test.js
- Verify: `python3 -m pytest -q`
- Risk: medium
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [backend/app.py]
  - touches: [tests/test_backend.py]
  - reads: [frontend/src/ui.js, frontend/tests/ui.test.js]
- Wiring-proof:
  - CLI: python3 -m pytest -q
  - Integration: backend health is imported by tests and exercised with a real assertion.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Recommendation: SEQUENTIAL_REQUIRED
EOF

    extract_plan_json
    commit_fixture "feat(task-1): ship backend health check"

    set +e
    output=$(bash "${VERIFY_SCRIPT}" --task 1 --full-sweep 2>&1)
    exit_code=$?
    set -e

    if [[ ${exit_code} -ne 0 ]] && echo "${output}" | grep -Eq 'javascript: Regression failed|Step 2 FAIL \(javascript\)'; then
        echo "  PASS  polyglot repo fails verification when frontend regression fails"
    else
        echo "  FAIL  polyglot repo did not fail on frontend regression"
        echo "        output: $(echo "${output}" | tail -8 | tr '\n' ' ')"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 4: JavaScript dead project import emits SIGN-001
# ══════════════════════════════════════════
echo "  Test: JavaScript dead project imports emit SIGN-001"

(
    case_dir="${tmp_root}/javascript-dead-import"
    mkdir -p "${case_dir}"
    cd "${case_dir}"
    setup_git_repo
    mkdir -p src tests

    cat > package.json <<'EOF'
{
  "name": "javascript-dead-import",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF

    cat > src/math.js <<'EOF'
export function add(a, b) {
    return a + b;
}

export function subtract(a, b) {
    return a - b;
}
EOF

    cat > tests/math.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { add, subtract } from '../src/math.js';

test('add sums two numbers', () => {
    assert.equal(add(2, 3), 5);
});
EOF

    init_spectra_project "javascript-dead-import"
    cat > .spectra/plan.md <<'EOF'
# SPECTRA Execution Plan

## Project: javascript-dead-import
## Level: 1
## Generated: 2026-03-13
## Source: manual

---

## Task 001: Detect dead JS imports
- [x] 001: Detect dead JS imports
- AC:
  - tests pass.
  - verifier warns on unused project imports.
- Files: src/math.js, tests/math.test.js
- Verify: `npm test`
- Risk: low
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [src/math.js]
  - touches: [tests/math.test.js]
  - reads: []
- Wiring-proof:
  - CLI: npm test
  - Integration: tests exercise the intended project export.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Recommendation: SEQUENTIAL_REQUIRED
EOF

    extract_plan_json
    commit_fixture "feat(task-1): detect dead js imports"

    set +e
    output=$(bash "${VERIFY_SCRIPT}" --task 1 --full-sweep 2>&1)
    exit_code=$?
    set -e

    if [[ ${exit_code} -eq 0 ]] && echo "${output}" | grep -q "SIGN-001: Dead import 'subtract'"; then
        echo "  PASS  JavaScript dead project imports emit SIGN-001"
    else
        echo "  FAIL  JavaScript dead import warning missing"
        echo "        output: $(echo "${output}" | tail -8 | tr '\n' ' ')"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# ══════════════════════════════════════════
# Test 5: JavaScript CLI entry points require subprocess tests
# ══════════════════════════════════════════
echo "  Test: JavaScript CLI entry points without subprocess tests emit SIGN-002"

(
    case_dir="${tmp_root}/javascript-cli-boundary"
    mkdir -p "${case_dir}"
    cd "${case_dir}"
    setup_git_repo
    mkdir -p bin tests

    cat > package.json <<'EOF'
{
  "name": "javascript-cli-boundary",
  "version": "0.1.0",
  "type": "module",
  "bin": {
    "hello-world": "./bin/hello.js"
  },
  "scripts": {
    "test": "node --test"
  }
}
EOF

    cat > bin/hello.js <<'EOF'
#!/usr/bin/env node
console.log('hello');
EOF

    cat > tests/hello.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';

test('placeholder unit test', () => {
    assert.equal(1 + 1, 2);
});
EOF

    init_spectra_project "javascript-cli-boundary"
    cat > .spectra/plan.md <<'EOF'
# SPECTRA Execution Plan

## Project: javascript-cli-boundary
## Level: 1
## Generated: 2026-03-13
## Source: manual

---

## Task 001: Detect JS CLI boundary gaps
- [x] 001: Detect JS CLI boundary gaps
- AC:
  - tests pass.
  - verifier warns when CLI is not covered through a subprocess boundary.
- Files: bin/hello.js, tests/hello.test.js, package.json
- Verify: `npm test`
- Risk: low
- Max-iterations: 3
- Scope: code
- File-ownership:
  - owns: [bin/hello.js]
  - touches: [tests/hello.test.js, package.json]
  - reads: []
- Wiring-proof:
  - CLI: npm test
  - Integration: CLI path is exercised through a real process boundary.

---

## Parallelism Assessment
- Independent tasks: [001]
- Sequential dependencies: []
- Recommendation: SEQUENTIAL_REQUIRED
EOF

    extract_plan_json
    commit_fixture "feat(task-1): detect js cli boundary gaps"

    set +e
    output=$(bash "${VERIFY_SCRIPT}" --task 1 --full-sweep 2>&1)
    exit_code=$?
    set -e

    if [[ ${exit_code} -eq 0 ]] && echo "${output}" | grep -q "SIGN-002: CLI entry point ./bin/hello.js"; then
        echo "  PASS  JavaScript CLI entry points without subprocess tests emit SIGN-002"
    else
        echo "  FAIL  JavaScript CLI subprocess warning missing"
        echo "        output: $(echo "${output}" | tail -8 | tr '\n' ' ')"
        exit 1
    fi
) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

echo ""
echo "  verify-project-trials: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "SPECTRA_TEST_RESULT suite=verify-project-trials pass=${PASS} fail=${FAIL} skip=${SKIP} total=$((PASS + FAIL + SKIP))"

export TEST_VERIFY_PROJECT_TRIALS_PASS=${PASS}
export TEST_VERIFY_PROJECT_TRIALS_FAIL=${FAIL}

[[ ${FAIL} -eq 0 ]]
