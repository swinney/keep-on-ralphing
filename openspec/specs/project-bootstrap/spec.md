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

### Requirement: Scaffold the review-gate config surface

`/ralph-init` SHALL scaffold the review-gate configuration surface into the target project. It SHALL write the
`ralph.conf` keys (`RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`, `RALPH_REVIEW_MAX_ROUNDS`, and the base-branch
setting) documented, with `RALPH_REVIEW_GATE` defaulting to ON (the loop is GitHub-dependent) and
`RALPH_AUTO_MERGE` defaulting to OFF, ensure a `review-findings.md` sink is gitignored, and include in the
rendered `PROMPT.md` the clause that requires the agent to resolve outstanding `review-findings.md` entries
before any `tasks.md` task. Existing files SHALL NOT be overwritten, consistent with the bootstrap no-overwrite
rule.

#### Scenario: Review-gate keys are scaffolded on by default
- **WHEN** `/ralph-init` scaffolds a project
- **THEN** `ralph.conf` contains the review-gate keys, documented, with `RALPH_REVIEW_GATE` on and `RALPH_AUTO_MERGE` off
- **AND** the user can restore an offline loop by setting `RALPH_REVIEW_GATE=0`

#### Scenario: PROMPT.md gains the finding-priority clause
- **WHEN** `/ralph-init` renders `PROMPT.md` from the template
- **THEN** the prompt instructs the agent to resolve outstanding `review-findings.md` entries before selecting the next `tasks.md` task

### Requirement: Ensure GitHub readiness during scaffolding

Because the review gate is ON by default and loop mode refuses to start without GitHub, `/ralph-init` SHALL
check the preconditions during init — a configured git remote, an authenticated `gh`, a non-base feature
branch, and a **derivable `GH_TOKEN`** (`gh auth token` returns a value, so the loop can forward a credential
into the container) — mark each as ready or blocked, and give the user the exact fix for any that are blocked,
so they do not discover the refusal at first run. `/ralph-init` SHALL ensure the generated `Makefile` forwards
`GH_TOKEN` into the loop container, since host login alone does not authenticate the in-container runner. It
SHALL note that the explicit offline opt-out is `RALPH_REVIEW_GATE=0`.

#### Scenario: GitHub readiness is ensured and reported

- **WHEN** `/ralph-init` scaffolds the review-gate surface
- **THEN** it reports the status of the git remote, `gh` authentication, the working branch, and whether a `GH_TOKEN` is derivable for the container
- **AND** for any blocked precondition it gives the user the exact remediation, noting that `RALPH_REVIEW_GATE=0` is the offline opt-out

#### Scenario: Generated Makefile forwards the token into the container

- **WHEN** `/ralph-init` generates the consumer `Makefile`
- **THEN** the loop run forwards a host-derived `GH_TOKEN` into the container so the in-container runner is authenticated
- **AND** the token is supplied at run time, not committed or baked into the image

### Requirement: Infer and confirm the coverage check during scaffolding

`/ralph-init` SHALL infer the coverage invocation and a starting threshold for the detected toolchain (e.g.
`pytest --cov=<pkg> --cov-fail-under=<N>`, a JS coverage runner, `go test -cover`), fold it into the inferred
gate command in CI order, and add the matching coverage tooling to the Containerfile and CI toolchain blocks.
Because a too-aggressive threshold *or the wrong coverage mode* blocks every commit, `/ralph-init` SHALL confirm
both the threshold and the coverage **mode** with the user rather than assume them.

`/ralph-init` SHALL assess whether the target is brownfield — a pre-existing, non-trivial codebase whose current
global coverage is unknown or likely below the threshold — using cheap signals (existing source beyond the
feature being added, an existing test suite, an existing lockfile/CI, or the loop targeting a feature
subdirectory of a larger app). When the target is not clearly greenfield, the coverage-mode choice it presents
SHALL include **patch/scoped coverage** (gating only the lines or paths a turn changes) as a first-class,
recommended option — not merely a global floor or no coverage — and SHALL warn that a global floor on an
under-covered existing codebase fails the very first commit. `/ralph-init` SHALL NOT silently select a global
floor that the existing codebase does not already meet, and SHALL leave the final mode choice to the operator.

#### Scenario: Coverage step is inferred and folded into the gate

- **WHEN** `/ralph-init` scaffolds a project whose toolchain has a coverage tool
- **THEN** `scripts/gate.sh` includes the coverage check in CI order
- **AND** the Containerfile and CI setup install the coverage tooling
- **AND** the threshold and coverage mode are confirmed with the user, not silently assumed

#### Scenario: Brownfield target is offered patch/scoped coverage with a warning

- **WHEN** `/ralph-init` assesses the target as brownfield (or not clearly greenfield)
- **THEN** the coverage-mode choice presented to the user includes patch/scoped coverage as a recommended option, alongside the global floor
- **AND** the user is warned that a global floor on an under-covered existing codebase will fail the first commit
- **AND** no global floor the existing codebase does not already meet is selected without the user's confirmation

#### Scenario: Greenfield target keeps the global-floor default

- **WHEN** `/ralph-init` assesses the target as clearly greenfield
- **THEN** the recommended coverage mode is a global floor
- **AND** patch/scoped coverage remains available if the user asks for it

### Requirement: PROMPT.md carries the coverage clause

The scaffolded `PROMPT.md` SHALL instruct the agent to write tests that exercise the real code path to meet the
coverage threshold, and — when code is genuinely not reasonably testable — to exclude it via the language's
standard coverage pragma or escalate to the questions channel, never to delete tests or lower the threshold to
make the gate pass (consistent with the do-not-game-the-verification guard).

#### Scenario: Prompt forbids gaming the coverage gate

- **WHEN** `/ralph-init` renders `PROMPT.md`
- **THEN** it tells the agent to satisfy coverage by testing the real path or escalating, and forbids deleting
  tests or lowering the threshold to turn the gate green

### Requirement: Decision prompts carry a repo-specific recommended option

When a Ralph skill presents the operator with a choice, it SHALL mark exactly one option as recommended and
SHALL accompany it with a one-line rationale tied to the current repository, rather than a static default, so a
non-expert always has a safe, explained path. The recommended option SHALL be presented first, consistent with
the AskUserQuestion convention of labelling the first option "(Recommended)".

For a choice that is high-stakes or hard to reverse — the gate command, the coverage threshold or mode,
enabling auto-merge, or otherwise changing the review gate — the recommendation SHALL state the risk in its
rationale and the skill SHALL still require explicit confirmation rather than silently accepting the
recommendation. Where there is genuinely no safe default, the skill SHALL say so plainly rather than present a
misleading recommendation. This convention governs presentation only and SHALL NOT change any default value or
behaviour.

#### Scenario: Every choice offers a recommended option with a reason

- **WHEN** a Ralph skill presents the operator with a set of options
- **THEN** exactly one option is marked recommended, presented first, with a one-line rationale specific to the current repo
- **AND** the rationale explains why it fits this repo, not merely that it is the default

#### Scenario: High-stakes recommendation states risk and still requires confirmation

- **WHEN** the choice is high-stakes or hard to reverse (e.g. the gate command, coverage threshold/mode, auto-merge)
- **THEN** the recommendation's rationale states the risk of the alternatives
- **AND** the skill requires the operator to confirm rather than silently applying the recommended option

#### Scenario: No safe default is stated honestly

- **WHEN** a choice has no safe default the skill can responsibly recommend
- **THEN** the skill says so explicitly instead of marking an arbitrary option as recommended

