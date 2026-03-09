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

# Test file patterns (for exclusion from production code analysis)
TEST_PATTERNS=("*.test.js" "*.spec.js" "*.test.ts" "*.spec.ts")

# Common stdlib/test imports to skip in dead import detection
SKIP_IMPORTS="describe|it|expect|jest|test|beforeEach|afterEach|beforeAll|afterAll|mock|vi|assert|require|fs|path|os|util|crypto"

# Regression command for Step 2
REGRESSION_CMD="npm test"
