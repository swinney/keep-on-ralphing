## ADDED Requirements

### Requirement: The gate includes a coverage threshold

A scaffolded project's single-source gate (`scripts/gate.sh`) SHALL include a test-coverage check with a
configured threshold, run in CI order alongside the format/lint/type/test checks. A coverage shortfall SHALL
fail the gate (non-zero exit) exactly like any other check, so it blocks the commit via the pre-commit hook and
a repeated shortfall surfaces as a loop stall. The kit mandates the *presence* of the coverage check; the
threshold value and the coverage tool remain project-owned configuration, not a kit-fixed number.

#### Scenario: Gate fails when coverage is below the threshold

- **WHEN** `scripts/gate.sh` runs in a project whose code is formatted, lint-clean, type-clean, and passing
  tests, but whose test coverage is below the configured threshold
- **THEN** the gate exits non-zero, the pre-commit hook aborts the commit, and `HEAD` is unchanged

#### Scenario: Gate passes when coverage meets the threshold

- **WHEN** all other checks pass and coverage is at or above the configured threshold
- **THEN** the gate exits 0 and the commit is allowed

### Requirement: Coverage gating defaults to a global floor with patch coverage documented

The scaffolded coverage check SHALL default to a global coverage floor (the project-wide percentage must meet
the threshold), as the most portable mechanism across coverage tools and the natural fit for a project grown
test-first. Patch/diff coverage (gating only the lines a turn changed) SHALL be documented as the alternative
appropriate for brownfield adoption, where a global floor would couple unrelated turns.

#### Scenario: Default scaffold uses a global floor

- **WHEN** `/ralph-init` scaffolds the coverage check with no project override
- **THEN** the gate enforces a project-wide coverage floor (e.g. `--cov-fail-under=<N>`)
- **AND** the templates document how to switch to patch/diff coverage for a brownfield project
