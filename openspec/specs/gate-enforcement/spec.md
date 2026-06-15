# gate-enforcement Specification

## Purpose

Define a single, executable gate for a scaffolded project and enforce it identically across the agent prompt, the git pre-commit hook, and CI, so red work cannot land and repeated red turns surface as loop stalls.
## Requirements
### Requirement: Single-source gate definition

A scaffolded project SHALL have exactly one executable definition of its gate command,
`scripts/gate.sh`, that runs the project's full gate in CI order (format, lint,
type-check, test). The gate command string SHALL NOT be duplicated anywhere else; the
prompt, the pre-commit hook, and the CI workflow SHALL all invoke `scripts/gate.sh`.

#### Scenario: Gate command lives in one place

- **WHEN** `/ralph-init` scaffolds a project
- **THEN** `scripts/gate.sh` is created, is executable, and contains the full gate in CI order
- **AND** `PROMPT.md`, the pre-commit hook, and the CI workflow each call `scripts/gate.sh` rather than embedding the gate command string

#### Scenario: Gate runs the gate in CI order

- **WHEN** `scripts/gate.sh` is executed in a project whose code is correctly formatted, lint-clean, type-clean, and passing tests
- **THEN** it exits 0
- **AND** when any one of those checks fails it exits non-zero, having run the checks in the same order CI runs them

### Requirement: Pre-commit hook blocks a red gate

A scaffolded project SHALL install a git pre-commit hook that runs `scripts/gate.sh` and
aborts the commit with a non-zero exit when the gate fails, so a commit cannot be created
while the gate is red.

#### Scenario: Red gate aborts the commit

- **WHEN** a commit is attempted in the loop container while the gate is failing
- **THEN** the pre-commit hook runs `scripts/gate.sh`, the gate exits non-zero, and the commit is aborted
- **AND** `HEAD` is unchanged afterward

#### Scenario: Green gate allows the commit

- **WHEN** a commit is attempted while the gate passes
- **THEN** the pre-commit hook runs `scripts/gate.sh`, the gate exits 0, and the commit is created

### Requirement: A blocked commit registers as a loop stall

The enforced gate SHALL compose with the existing runner semantics so that a turn whose
commit is blocked by the hook makes no new commit and is therefore counted as a stall by
`ralph.sh`; after `RALPH_MAX_STALLS` consecutive such turns the loop SHALL halt for human
review. No change to `ralph.sh` is required for this behavior.

#### Scenario: Repeated red turns halt the loop

- **WHEN** the agent produces red work on consecutive turns and each commit is blocked by the pre-commit hook
- **THEN** `HEAD` does not advance on those turns, so each is counted as a no-commit stall
- **AND** after `RALPH_MAX_STALLS` consecutive stalls the loop writes `STATUS.md` and exits for human review

### Requirement: CI mirrors the gate

A scaffolded project SHALL include a GitHub Actions workflow that runs `scripts/gate.sh`
on push and pull request, so the gate enforced locally in the loop is the same gate
enforced on the shared branch.

#### Scenario: CI runs the single-source gate

- **WHEN** a commit is pushed or a pull request is opened
- **THEN** the workflow checks out the repo, sets up the toolchain, and runs `scripts/gate.sh`
- **AND** the workflow fails if and only if `scripts/gate.sh` exits non-zero

### Requirement: Prompt references the gate, not a copy

The scaffolded `PROMPT.md` SHALL instruct the agent to run the gate by invoking
`scripts/gate.sh` and SHALL NOT inline the gate command string, so the prompt cannot drift
from the hook and CI.

#### Scenario: PROMPT.md points at the script

- **WHEN** `/ralph-init` renders `PROMPT.md` from the template
- **THEN** the pre-commit step references `scripts/gate.sh`
- **AND** no literal gate command string (e.g. `ruff ... && pytest`) appears inlined in `PROMPT.md`

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

