## MODIFIED Requirements

### Requirement: Coverage gating defaults to a global floor with patch coverage documented

The scaffolded coverage check SHALL default to a global coverage floor for a greenfield project (the
project-wide percentage must meet the threshold), as the most portable mechanism across coverage tools and the
natural fit for a project grown test-first. Patch/diff coverage — gating only the lines or paths a turn changed
— SHALL be a first-class coverage mode the kit can scaffold **directly into `scripts/gate.sh`** (not merely
documented prose), and SHALL be the mode used when `/ralph-init` determines the target is brownfield, where a
global floor would couple unrelated turns and break the first commit. The templates SHALL provide a concrete
scoped/patch recipe for the detected ecosystem so the emitted gate is copy-correct.

#### Scenario: Default scaffold uses a global floor

- **WHEN** `/ralph-init` scaffolds the coverage check for a clearly-greenfield project with no override
- **THEN** the gate enforces a project-wide coverage floor (e.g. `--cov-fail-under=<N>`)
- **AND** the templates document how to switch to patch/diff coverage for a brownfield project

#### Scenario: Brownfield scaffold emits a patch/scoped coverage gate

- **WHEN** `/ralph-init` scaffolds the coverage check for a target it determined is brownfield
- **THEN** `scripts/gate.sh` contains a patch/scoped coverage invocation (coverage limited to the changed package/paths, or diff coverage against the base branch), not a project-wide global floor
- **AND** the invocation is a concrete, runnable recipe for the detected ecosystem
