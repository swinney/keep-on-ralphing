#!/usr/bin/env bash
# scripts/gate.sh — the project's quality gate, in CI order. SINGLE SOURCE.
#
# This is project-OWNED config, not harness machinery: it encodes THIS project's
# formatter / linter / type-checker / test runner. PROMPT.md, the pre-commit hook
# (hooks/pre-commit), and CI (.github/workflows/ci.yml) all invoke this one file —
# the gate command must never be duplicated, or the three will drift.
#
# Run a FORMATTER, not just a format-CHECK: a passing-tests commit still fails CI
# if it is unformatted. The pytest step enforces a GLOBAL coverage floor (80%) —
# "tests pass" is not "the code is tested."

set -euo pipefail

ruff format .
ruff check .
mypy .
pytest --cov=acme_widgets --cov-fail-under=80
