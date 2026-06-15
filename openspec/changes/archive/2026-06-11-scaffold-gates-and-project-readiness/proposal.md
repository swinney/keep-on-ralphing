## Why

`/ralph-init` scaffolds a project's config (`ralph.conf`, `PROMPT.md`, `Containerfile`,
`Makefile`, `tasks.md`) but stops short of what a project actually needs to run the loop
*safely*. Two gaps stand out:

1. **The gate is prose, not a gate.** `PROMPT.md` instructs the agent to run the gate and
   "do not commit red," but the gate command is a hand-copied string with nothing
   enforcing it. This collides with the loop's core signal: `ralph.sh` treats *any* new
   commit as progress and resets the stall counter. So a red commit reads as success, and
   broken work compounds turn after turn. `/ralph-init`'s own guardrail says the gate
   "MUST match what CI runs" — yet no CI is scaffolded, so there is nothing to match.

2. **The scaffold assumes structure it never creates.** `PROMPT.md` step 1 reads the specs
   dir, escalates to `docs/questions.md`, and records decisions in the decisions dir — but
   none of those exist after `/ralph-init`. A fresh project's first turn has nothing to
   read and no spec to derive a test from. The runner also snapshots `STATUS.md` at
   startup, but `STATUS.md` is never seeded.

Fixing both makes a freshly-initialized project loop-ready and turns "don't commit red"
from a hope into a structural property.

## What Changes

- Add a **single-source gate definition** (`scripts/gate.sh`) to the scaffold: one
  executable that runs the project's full gate in CI order. `PROMPT.md`, the pre-commit
  hook, and CI all invoke it instead of duplicating the command string.
- Add an **enforced in-container pre-commit hook** that runs `scripts/gate.sh` and
  **blocks the commit on failure**. A red gate now yields *no commit* → the turn registers
  as a stall → the loop halts for human review after `RALPH_MAX_STALLS`, which is the
  behavior the stall-detection design already assumes.
- Add a **GitHub Actions CI workflow** that runs the same `scripts/gate.sh` on push/PR,
  matching the harness's "team-shared via GitHub" scope.
- Have `/ralph-init` **create the project-readiness structure**: the specs / tests /
  decisions directories, a seeded `STATUS.md` cold-start breadcrumb, a seeded
  `docs/questions.md`, and a minimal seed spec stub so the spec-driven loop has a starting
  point.
- Update `PROMPT.md.template` to **reference `scripts/gate.sh`** (and the hook) rather than
  inline a gate string, keeping a single source of truth.
- Update `skills/ralph-init/SKILL.md` to scaffold, install, and report all of the above,
  and refresh `example/` to show the fully-resolved result.

## Capabilities

### New Capabilities
- `gate-enforcement`: A scaffolded project gets a single-source gate command that is
  enforced by an in-container pre-commit hook (red gate ⇒ no commit ⇒ loop stall) and
  mirrored by a CI workflow, with no duplication of the gate string across PROMPT, hook,
  and CI.
- `project-bootstrap`: `/ralph-init` produces a loop-ready project skeleton — specs/tests/
  decisions directories, a seeded `STATUS.md` and `docs/questions.md`, and a minimal seed
  spec — so the first turn has the structure `PROMPT.md` assumes.

### Modified Capabilities
<!-- No existing specs in openspec/specs/; the /ralph-init behavior was never spec'd. All new. -->

## Impact

- **Plugin surface** (this repo): `skills/ralph-init/SKILL.md` (new scaffolding + install
  + report steps), `templates/` (new: `gate.sh.template`, pre-commit hook template, CI
  workflow template, `STATUS.md` seed, `questions.md` seed, seed-spec stub; modified:
  `PROMPT.md.template`).
- **Worked example**: `example/` gains the resolved gate script, hook, CI workflow, seeded
  files, and directory skeleton.
- **Consumer repos**: projects initialized after this change get an enforced gate and a
  loop-ready skeleton. No change to the `base/` image or the `ralph.sh` runner is required
  — enforcement rides on a standard git hook, so the runner's commit-graph signal is
  unchanged; it simply stops seeing red commits.
- **Decision touchpoint**: hook installation mechanism (committed `core.hooksPath` dir vs.
  `.git/hooks` install step vs. Makefile target) is a design decision — see `design.md`.
