## Context

`gate-enforcement` mandates a coverage check and documents patch/diff coverage as the brownfield-appropriate
mode. `project-bootstrap` makes `/ralph-init` infer a coverage invocation + threshold and confirm the threshold
with the operator. The missing link: the confirmation surfaces threshold and global-vs-none, but never the
patch/scoped mode — so on a brownfield target the operator is offered only options that stall the first commit
(global floor on under-covered code) or remove the safeguard (no coverage).

## Goals / Non-goals

- **Goal:** the coverage-mode the operator chooses can't silently be a first-commit-breaking global floor on a
  brownfield repo; patch/scoped is offered and recommended there.
- **Goal:** keep coverage mandatory and keep the greenfield global-floor default.
- **Non-goal:** auto-deciding the mode (the operator confirms), or building a precise coverage measurement step
  into init.

## Decisions

### D1 — Assess brownfield by cheap signals; offer rather than measure

Measuring the existing global coverage at init means running the suite (slow, possibly failing, side-effects).
Instead `/ralph-init` SHALL classify the target with cheap signals and *offer accordingly*:

- **Brownfield signals:** a non-trivial pre-existing source tree beyond the feature being added; an existing
  test suite of unknown coverage; an existing lockfile + CI; the loop targeting a feature subdirectory of a
  larger app (e.g. tasks under `openspec/changes/<feature>/`).
- **Greenfield:** little/no pre-existing source, or the operator says it's a new project.

When signals are mixed or unclear, treat as **not clearly greenfield** → offer patch/scoped + warn. The warning
is the safety net for a misclassification; a false "brownfield" only adds an option, it never removes the global
floor.

### D2 — "Patch/scoped" concretely, per ecosystem

Two shapes, simplest-first:

- **Path-scoped coverage (default brownfield mode):** measure coverage only over the new code's paths. Tool-
  native, no extra dependency, no base-ref needed:
  - Python: `pytest --cov=<new_pkg_or_path> --cov-fail-under=<N>`
  - JS/vitest: `vitest run --coverage --coverage.include='<feature-dir>/**' --coverage.thresholds.lines=<N>`
  - Go: `go test -cover ./<feature-pkg>/...`
- **True diff coverage (stricter option):** gate only the lines changed vs the base branch (e.g. `diff-cover`
  on an lcov/coverage.xml report). More precise, but adds a tool and a base ref. Offer as the advanced choice.

Recommend path-scoped as the brownfield default; document diff coverage for teams that want line-level rigor.

### D3 — Greenfield default unchanged

Global floor stays the default for a clearly-greenfield target (matches `gate-enforcement`; least surprise;
right for a project grown test-first). This change only adds/recommends the brownfield path.

### D4 — Operator confirms; the kit recommends, never auto-switches

`/ralph-init` SHALL present the mode choice with the recommended option ordered first based on its brownfield
assessment, and SHALL NOT switch modes on the operator's behalf without confirmation — consistent with the
existing "confirm the threshold, don't assume it" rule.

### D5 — The review gate is the backstop for scoped coverage's blind spot

Path-scoped coverage can miss changes outside the scoped path. That residual risk is acceptable because (a) the
loop is one-subsystem-per-turn so a turn's changes are localized, and (b) the independent review gate is the
real catch for "tested the wrong thing." Coverage stays a *supporting* gate either way.

## Risks / Trade-offs

- **Brownfield detection is heuristic.** Mitigated by D1 (default to offering when unclear) and the explicit
  warning; the operator makes the final call.
- **Path-scoped coverage is coarser than true diff coverage.** Accepted per D5; diff coverage is offered for
  teams that want more.
- **More choices in one question.** Mitigated by ordering the recommended option first and keeping the global
  floor available.

## Migration

Additive. Greenfield scaffolds are byte-identical to today. A brownfield operator now sees a patch/scoped option
and a warning instead of only global-vs-none. No change to already-scaffolded projects; they can switch their
`scripts/gate.sh` to a scoped invocation using the documented recipe.
