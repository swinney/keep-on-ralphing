# project-bootstrap Specification

## Purpose

Make a freshly initialized project loop-ready by scaffolding the directories and breadcrumb files the prompt assumes, seeding an escalation file and a spec-writing guide (never a placeholder spec), preserving any pre-existing content, and reporting what was created or skipped.

## Requirements

### Requirement: Scaffold the directory structure the prompt assumes

`/ralph-init` SHALL create the specs, tests, and decisions directories that `PROMPT.md`
references (resolved from the inferred `SPECS_DIR`, `TESTS_DIR`, `DECISIONS_DIR`), each
tracked by git so an empty directory survives a clone.

#### Scenario: Directories exist after init

- **WHEN** `/ralph-init` finishes in a fresh repo
- **THEN** the specs, tests, and decisions directories exist and are git-tracked (e.g. via a `.gitkeep` or README placeholder)
- **AND** the paths match the `SPECS_DIR`/`TESTS_DIR`/`DECISIONS_DIR` values used in the rendered `PROMPT.md`

### Requirement: Seed the loop status breadcrumb

`/ralph-init` SHALL create a `STATUS.md` seeded with a non-empty cold-start breadcrumb
that is not a stop reason, so the runner's startup snapshot behaves as designed and
`/ralph-status` has content to read before the first turn.

#### Scenario: STATUS.md is seeded and does not stop a fresh loop

- **WHEN** `/ralph-init` finishes and the loop is then started
- **THEN** `STATUS.md` exists with a non-empty breadcrumb
- **AND** the runner snapshots it at startup and does NOT treat the pre-existing breadcrumb as a stop reason for the first turn

### Requirement: Seed the escalation file

`/ralph-init` SHALL create `docs/questions.md` so the first time the agent escalates an
undecided question (per the prompt's stop conditions) it appends to an existing file
rather than having to create one.

#### Scenario: questions.md exists for escalation

- **WHEN** `/ralph-init` finishes
- **THEN** `docs/questions.md` exists with a short header explaining its purpose

### Requirement: Seed a spec-writing guide, not a placeholder spec

`/ralph-init` SHALL place a spec-writing guide at `<SPECS_DIR>/README.md` (only if
absent) that orients the loop without being mistaken for requirements. It SHALL NOT
scaffold a placeholder spec, because the loop builds to whatever looks like a spec and a
fake one would make it build the wrong thing. Where the operator can describe the first
subsystem, `/ralph-init` SHALL offer to write that as the first real spec.

#### Scenario: A spec-writing guide is present, not a fake spec

- **WHEN** `/ralph-init` finishes in a project that had no specs
- **THEN** `<SPECS_DIR>/README.md` exists, explaining how to write a spec, and is marked as a guide rather than requirements
- **AND** no placeholder spec that the loop could derive tests from is written

#### Scenario: Operator-provided first subsystem becomes a real spec

- **WHEN** the operator describes the first subsystem during init
- **THEN** `/ralph-init` writes that description as a real spec at `<SPECS_DIR>/<system>.md`
- **AND** when the operator declines, the specs dir is left with only the guide

### Requirement: Do not overwrite existing project files

`/ralph-init` SHALL NOT overwrite a directory or file that already exists when scaffolding
readiness components; pre-existing specs, tests, decisions, `STATUS.md`, or
`docs/questions.md` SHALL be left intact and reported as skipped.

#### Scenario: Existing content is preserved

- **WHEN** `/ralph-init` runs in a repo that already has a specs directory with real specs
- **THEN** the existing specs are not modified or replaced, and no seed spec is written over them
- **AND** the init report marks those components as "skipped (already present)"

### Requirement: Report scaffolded components

`/ralph-init` SHALL report every readiness component it created or skipped, so the
operator can see at a glance that the project is loop-ready.

#### Scenario: Init reports the readiness components

- **WHEN** `/ralph-init` completes
- **THEN** its report lists the directory structure, `STATUS.md`, `docs/questions.md`, and the seed spec, each marked created or skipped
