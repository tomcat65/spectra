#!/usr/bin/env bash
# SPECTRA Language Profile: Python
# Sourced by spectra-verify.sh for language-aware wiring verification.

# Import patterns to detect in source files
IMPORT_PATTERNS=("^import " "^from .* import")

# Entry point patterns
ENTRY_POINTS=("if __name__ == '__main__'" "console_scripts" "entry_points")

# CLI registry files
CLI_REGISTRIES=("setup.py" "pyproject.toml" "setup.cfg")

# Dependency manifest files
DEP_MANIFESTS=("requirements.txt" "pyproject.toml" "setup.py" "Pipfile")

# Command to check if a dependency is installed
DEP_CHECK_CMD="pip show"

# File extension for this language
FILE_EXTENSION="py"

# Source file patterns for this language
SOURCE_PATTERNS=("*.py")

# Test file patterns (for exclusion from production code analysis)
TEST_PATTERNS=("test_*.py" "*_test.py")

# Common stdlib/test imports to skip in dead import detection
SKIP_IMPORTS="patch|MagicMock|Mock|pytest|unittest|mock|subprocess|os|sys|json|tempfile|shutil|pathlib|Path|Any|Dict|List|Optional|call|PropertyMock|fixture"

# Regression command for Step 2
REGRESSION_CMD="python3 -m pytest -q"

extract_dependency_modules() {
    find . -name "*.py" -not -path "./tests/*" -not -path "./.spectra/*" -not -name "test_*" 2>/dev/null | \
        grep -v __pycache__ | \
        xargs -r grep -hoP '^import\s+\K\w+|^from\s+\K\w+' 2>/dev/null | \
        sort -u || true
}

dependency_module_declared() {
    local module="$1"
    local manifest="$2"

    if python3 -c "import ${module}" >/dev/null 2>&1; then
        return 0
    fi

    grep -qi "${module}" "${manifest}" 2>/dev/null
}
