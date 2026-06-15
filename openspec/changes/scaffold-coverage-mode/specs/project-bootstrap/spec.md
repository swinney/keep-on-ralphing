## MODIFIED Requirements

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
