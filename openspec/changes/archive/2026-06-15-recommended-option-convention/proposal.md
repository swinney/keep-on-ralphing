## Why

When a Ralph skill asks the operator to choose, a non-expert needs a safe path through the prompt. The
0.3.x `/ralph-init` coverage question does this well — it flags a "recommended" option with a repo-specific
reason ("recommended for this repo — a global floor would fail the first commit"). But that is **ad hoc**: it
is not guaranteed across the skill's *other* prompts (threshold, gate confirmation, task/spec wiring) or across
the other Ralph skills. An unflagged either/or leaves an operator who doesn't understand the trade-off with no
default — and the choices most likely to be misjudged (gate command, coverage threshold/mode) are exactly the
ones the kit calls "the most damaging thing the scaffold can emit."

Make "a recommended option + a one-line, repo-specific why" a **presentation contract** for every choice a
Ralph skill presents — without changing any actual default.

## What Changes

- Every choice a Ralph skill presents (via AskUserQuestion) SHALL mark exactly **one option "(recommended)"**
  with a **one-line rationale tied to the current repo**, not a static default. (Aligns with the
  AskUserQuestion convention of labelling the first option "(Recommended)".)
- **Recommend ≠ pre-decide.** For high-stakes or irreversible choices (the gate command, the coverage
  threshold/mode, enabling auto-merge or otherwise changing the review gate), the recommendation SHALL state the
  *risk* in its rationale and the skill SHALL still require explicit confirmation — never silent-accept. The
  recommendation's confidence scales with how reversible the choice is.
- **Honest no-default.** When there is genuinely no safe default (a real either/or the operator must own), the
  skill SHALL say so rather than fabricate a "(recommended)" — a misleading recommendation is worse than none.
- **Presentation only.** No actual default value or behaviour changes; this governs how choices are *presented*.

## Capabilities

### Modified Capabilities

- `project-bootstrap`: the scaffolding interaction gains a decision-presentation convention — every prompt
  carries a repo-specific recommended option (with the high-stakes carve-out and the honest-no-default clause),
  written as a general skill convention the other Ralph skills inherit.

## Impact

- **Plugin:** `skills/ralph-init/SKILL.md` — a guardrail clause plus threading it through the existing prompts
  (coverage mode already complies; add threshold, gate confirmation, task/spec wiring). A shared note so
  `skills/ralph-build-base` and `skills/ralph-status` follow it when they present choices.
- **Defaults/templates:** unchanged — this is a presentation contract, not a behaviour change.
- **Tests/Docs:** `/ralph-init` is markdown-driven, so verification is convention correctness + a smoke check
  that each prompt shows a recommended option with a repo-specific reason; a one-line mention in `CLAUDE.md`.
- **Compatibility:** additive; no scaffolded output changes.
