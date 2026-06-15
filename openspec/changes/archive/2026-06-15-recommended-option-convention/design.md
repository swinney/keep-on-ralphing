## Context

Ralph skills already ask the operator to choose at several points (coverage mode/threshold, the gate command,
GitHub/offline, task/spec wiring). The `scaffold-coverage-mode` change established a repo-aware recommended
option for the coverage question. This change generalizes that from one prompt to a convention covering every
prompt and every skill, so a non-expert always has a safe, explained path.

## Goals / Non-goals

- **Goal:** every choice carries one recommended option with a one-line, repo-specific rationale.
- **Goal:** the convention cannot become a rubber-stamp on damaging choices.
- **Non-goal:** changing any default value or behaviour (presentation only).
- **Non-goal:** a code-enforced mechanism — skills are markdown-driven; this is a guardrail the skills follow.

## Decisions

### D1 — Spec home is project-bootstrap, written as a general convention

The prompts live mostly in `/ralph-init` (project-bootstrap), so the requirement lands there, but it is phrased
as a skill-presentation convention so `/ralph-build-base` and `/ralph-status` inherit it when they present
choices.

### D2 — The rationale must be repo-derived, not static

"(recommended)" alone just moves the cursor; the one-line *why*, tied to this repo, is what informs a
non-expert. The coverage question is the model: "recommended for this repo — a global floor would fail the
first commit." A static "recommended: 80%" with no reason does not satisfy the convention.

### D3 — Confidence scales with reversibility (recommend ≠ pre-decide)

- **Low-stakes / reversible** (e.g. an inferred path): a plain recommended default is fine.
- **High-stakes / hard-to-reverse** (gate command, coverage threshold/mode, auto-merge, review-gate changes):
  the recommendation states the *risk* and the skill still requires explicit confirmation — never silent
  accept. This preserves the existing guardrails ("never set the threshold by fiat", "never enable the review
  gate on the user's behalf"): a recommendation is guidance, not a decision made for them.

### D4 — Honest no-default clause

Where there is no safe default — a genuine either/or the operator must own — the skill says so plainly instead
of fabricating a "(recommended)". A misleading recommendation undermines trust more than its absence.

### D5 — Align with the AskUserQuestion convention

The tool already supports labelling the first option "(Recommended)". The convention reuses that: recommended
option first, label suffixed, rationale in the option description.

## Risks / Trade-offs

- **Rubber-stamping high-stakes choices** — mitigated by D3 (risk-in-the-rationale + mandatory confirm).
- **A forced recommendation where none is safe** — mitigated by D4.
- **No automated enforcement** — accepted; same as every other markdown-driven skill guardrail. Verification is
  a smoke check of the rendered prompts.

## Migration

Additive and presentation-only. No scaffolded output changes; existing projects are unaffected. The coverage
question already complies and serves as the worked example for the other prompts.
