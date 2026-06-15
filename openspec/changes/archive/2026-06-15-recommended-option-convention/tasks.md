## 1. Convention guardrail

- [x] 1.1 Add a Guardrails clause to `skills/ralph-init/SKILL.md`: every choice presented gets exactly one "(recommended)" option, presented first, with a one-line repo-specific rationale (not a static default)
- [x] 1.2 Encode the carve-outs: high-stakes/irreversible choices (gate command, coverage threshold/mode, auto-merge, review-gate changes) state the risk in the rationale and still require explicit confirmation (recommend ≠ pre-decide); where there is no safe default, say so rather than fabricate one

## 2. Thread through /ralph-init's existing prompts

- [x] 2.1 Coverage MODE — already complies (greenfield→global / brownfield→scoped, with reason); confirmed wording matches the convention
- [x] 2.2 Coverage THRESHOLD — §2 now says present a recommended value with a repo-specific reason (higher for a scoped pure-logic gate) and the "confirm, don't assume" risk note
- [x] 2.3 Gate command confirmation — §2 now folds the gate confirm into the recommended-option convention (recommend the inferred gate + risk that a wrong gate blocks every commit)
- [x] 2.4 Task/spec wiring & GitHub/offline prompts — covered by the catch-all Guardrails convention (any presented choice gets a reasoned recommendation)

## 3. Other skills

- [x] 3.1 Added the shared recommended-option note to `skills/ralph-build-base` and `skills/ralph-status` Guardrails

## 4. Docs

- [x] 4.1 One-line mention in `CLAUDE.md` ("Skill interaction convention") — presentation convention; defaults unchanged

## 5. Verification

- [ ] 5.1 Smoke-test: run `/ralph-init` on a throwaway target and confirm each prompt shows a recommended option first with a repo-specific reason, and high-stakes prompts still require confirmation — DEFERRED: needs the release installed so the Skill tool loads the new SKILL.md (cache predates this change)
- [x] 5.2 `make test` stays green (presentation-only; no runner/gate behaviour changed)
- [x] 5.3 `openspec validate recommended-option-convention --strict` passes
