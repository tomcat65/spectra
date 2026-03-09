#!/usr/bin/env bash
# SPECTRA Language Profile: Bash / Shell
# Sourced by spectra-verify.sh for language-aware wiring verification.

# Import patterns to detect in source files
IMPORT_PATTERNS=("^source " "^\. ")

# Entry point patterns
ENTRY_POINTS=("#!/usr/bin/env bash" "#!/bin/bash" "main()")

# CLI registry files
CLI_REGISTRIES=()

# Dependency manifest files
DEP_MANIFESTS=()

# Command to check if a dependency is installed
DEP_CHECK_CMD="command -v"

# File extension for this language
FILE_EXTENSION="sh"

# Test file patterns (for exclusion from production code analysis)
TEST_PATTERNS=("test-*.sh" "test_*.sh")

# Common stdlib/test imports to skip in dead import detection
SKIP_IMPORTS="set|echo|printf|local|readonly|declare|export"

# Regression command for Step 2
REGRESSION_CMD="bash tests/run-tests.sh"
