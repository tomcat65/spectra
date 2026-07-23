#!/usr/bin/env bash
# SPECTRA Language Profile: JavaScript / TypeScript
# Sourced by spectra-verify.sh for language-aware wiring verification.

# Import patterns to detect in source files
IMPORT_PATTERNS=("^import " "require(")

# Entry point patterns
ENTRY_POINTS=("\"main\":" "\"bin\":" "\"scripts\":")

# CLI registry files
CLI_REGISTRIES=("package.json")

# Dependency manifest files
DEP_MANIFESTS=("package.json" "package-lock.json" "yarn.lock" "pnpm-lock.yaml")

# Command to check if a dependency is installed
DEP_CHECK_CMD="npm list"

# File extension for this language
FILE_EXTENSION="js"

# Source file patterns for this language
SOURCE_PATTERNS=("*.js" "*.mjs" "*.cjs" "*.ts" "*.tsx")

# Test file patterns (for exclusion from production code analysis)
TEST_PATTERNS=("*.test.js" "*.spec.js" "*.test.ts" "*.spec.ts")

# Common stdlib/test imports to skip in dead import detection
SKIP_IMPORTS="describe|it|expect|jest|test|beforeEach|afterEach|beforeAll|afterAll|mock|vi|assert|require|fs|path|os|util|crypto"

# Regression command for Step 2
REGRESSION_CMD="npm test"

extract_dependency_modules() {
    python3 <<'PY'
from pathlib import Path
import re

modules = set()
suffixes = {".js", ".mjs", ".cjs", ".ts", ".tsx"}
patterns = (
    r'import\s+(?:[^"\']+?\s+from\s+)?["\']([^"\']+)["\']',
    r'export\s+[^"\']*from\s+["\']([^"\']+)["\']',
    r'require\(\s*["\']([^"\']+)["\']\s*\)',
)

for path in Path(".").rglob("*"):
    if not path.is_file() or path.suffix not in suffixes:
        continue
    if any(part in {".spectra", "tests", "node_modules", "__pycache__"} for part in path.parts):
        continue

    text = path.read_text(encoding="utf-8", errors="ignore")
    for pattern in patterns:
        for spec in re.findall(pattern, text, re.MULTILINE):
            if spec.startswith((".", "/")):
                continue
            spec = spec[5:] if spec.startswith("node:") else spec
            if spec.startswith("@"):
                parts = spec.split("/")
                if len(parts) >= 2:
                    spec = "/".join(parts[:2])
            else:
                spec = spec.split("/")[0]
            modules.add(spec)

for module in sorted(modules):
    print(module)
PY
}

dependency_module_declared() {
    local module="$1"
    local manifest="$2"

    if node -e 'const mod = process.argv[1]; const builtins = new Set(require("module").builtinModules.map((name) => name.replace(/^node:/, ""))); process.exit(builtins.has(mod.replace(/^node:/, "")) ? 0 : 1)' "${module}" >/dev/null 2>&1; then
        return 0
    fi

    python3 - "${module}" "${manifest}" <<'PY'
import json
import sys

module, manifest = sys.argv[1:3]
with open(manifest, "r", encoding="utf-8") as handle:
    data = json.load(handle)

for section in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
    if module in data.get(section, {}):
        raise SystemExit(0)

raise SystemExit(1)
PY
}
