## Why

The kit already mandates a coverage check in the gate and the `gate-enforcement` spec already names **patch/diff
coverage as the brownfield-appropriate mode** (a global floor "would couple unrelated turns"). But the
`project-bootstrap` step that actually confirms coverage with the operator does not surface that mode — so the
documented escape hatch never reaches the choice the user is asked to make.

This bit a real first run. On the "houses" project (a `rental-investment-dashboard` feature added via OpenSpec
to an existing app — i.e. **brownfield**), `/ralph-init` correctly flagged that the project's `CLAUDE.md` gate
omits coverage, then presented a coverage-mode question offering only **{80% global floor, 70% global floor, no
coverage}**. A global floor measures the *whole* existing codebase; if houses isn't already ~80% covered, that
gate **fails the very first loop commit** and stalls the loop immediately. The skill steered the operator
toward the trap the gate spec explicitly warns about, because patch/scoped coverage wasn't among the options.

## What Changes

- `/ralph-init` SHALL **assess whether the target is brownfield** and, when it is not clearly greenfield,
  present **patch/scoped coverage as a first-class, recommended option** in the coverage-mode confirmation —
  not merely "global floor vs none."
- `/ralph-init` SHALL **warn** that a global floor on an under-covered existing codebase fails the first commit,
  and SHALL NOT silently select a global floor the existing codebase does not already meet.
- Patch/scoped coverage becomes a **first-class scaffoldable mode** the kit emits directly into
  `scripts/gate.sh` (e.g. coverage scoped to the changed package/paths, or true diff coverage against the base
  branch) — not just documented prose. The templates carry a concrete scoped recipe per detected ecosystem.
- The **greenfield default is unchanged** (global floor), and the **mandate that coverage be present** is
  unchanged. This change is about *which coverage mode is offered and recommended*, not about weakening the gate.

### Non-goals

- Removing or weakening the coverage requirement (the gate must still include coverage).
- Changing the greenfield default away from a global floor.
- Auto-selecting a mode without the operator's confirmation (the choice stays user-confirmed; the kit only
  assesses and recommends).

## Capabilities

### Modified Capabilities

- `project-bootstrap`: the coverage-confirmation step gains brownfield assessment and MUST offer/recommend
  patch/scoped coverage (with a global-floor warning) when the target is not clearly greenfield.
- `gate-enforcement`: patch/diff (scoped) coverage is promoted from "documented alternative" to a first-class
  mode the kit can scaffold into `scripts/gate.sh`, and is the mode used for a brownfield target.

## Impact

- **Plugin:** `skills/ralph-init/SKILL.md` — the coverage-mode question (add the patch/scoped option + the
  brownfield warning) and a brownfield-assessment step.
- **Templates:** `templates/gate.sh.template` already documents the global-vs-patch trade-off; add a concrete
  per-ecosystem scoped recipe so the emitted gate is copy-correct.
- **Example:** `example/` (Acme Widgets) is greenfield → keeps the global floor; unchanged.
- **Tests/Docs:** `/ralph-init` is markdown-driven (no in-CI build), so verification is instruction correctness
  plus a brownfield-target smoke test; `CLAUDE.md`'s PROMPT/gate notes mention the brownfield mode.
- **Compatibility:** additive — greenfield scaffolds are unchanged; brownfield scaffolds gain a mode that
  doesn't stall the first commit.
