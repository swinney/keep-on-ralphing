## Why

The gate enforces that tests *pass*, never that code is *tested*. An agent can ship a spec, one trivial
assertion, and a large implementation, and the gate goes green with near-zero real coverage — "tests pass" ≠
"code is tested." The harness's whole value proposition is spec → test → implement, but the only part the
*gate* enforces is "tests exit 0." Coverage is the missing bridge that moves "actually tested" from soft
(PROMPT.md prose) to hard (the enforced gate) — the same move the kit already made for formatting ("run a
FORMATTER, not just a format-CHECK").

Honest scope (from the `keep-on-the-borderlands` field log): a coverage threshold catches the *trivial-test*
class but **not** the *faked-precondition* class (§5.18 — tests that execute the code while faking the one
precondition that matters; those lines count as "covered"). The field log's catchers for that class were
independent review (the separate `outer-loop-review-gate` change) and a human exercising the real artifact.
So this is a **supporting** gate that raises the floor, not the headline — and the proposal says so plainly.

## What Changes

- **Mandate that a scaffolded gate includes a coverage check with a threshold.** The kit mandates the
  *presence* of coverage gating in `scripts/gate.sh`, not a fixed number — the threshold and the coverage tool
  stay project-owned config (like the rest of the gate command). The single-source model means adding it to
  `gate.sh` auto-propagates to the pre-commit hook, CI, and the PROMPT's gate step.
- **Default mechanism: a global coverage floor** (e.g. `--cov-fail-under=N`). It is the most portable signal —
  every coverage tool supports it — and fits the Ralph use case (greenfield projects grown test-first, where
  global coverage stays high naturally). Patch/diff coverage (gate only the lines a turn changed) is documented
  as the option for brownfield adoption, where a global floor would couple unrelated turns.
- **`/ralph-init` infers the coverage invocation** for the detected toolchain (e.g. `pytest --cov=<pkg>
  --cov-fail-under=80`, `vitest --coverage`, `go test -cover`), folds it into the inferred gate in CI order, and
  **confirms the threshold with the user** (a wrong/too-aggressive threshold blocks every commit). It also adds
  the matching coverage tooling to the Containerfile and CI toolchain blocks.
- **PROMPT.md gains a brief coverage clause**: write tests that exercise the real path to meet the threshold;
  if code is genuinely not reasonably testable, exclude it via the language's standard coverage pragma or
  escalate to `questions.md` — never delete tests or lower the threshold to pass (guards ④/⑤). Keep the closed
  placeholder set.
- Out of scope: end-to-end / "exercise the real artifact" acceptance verification (the §5.18 catcher) — a
  separate future change; and the independent-review gate (already its own change).

## Capabilities

### New Capabilities
<!-- none — this strengthens existing capabilities -->

### Modified Capabilities
- `gate-enforcement`: the single-source gate SHALL include a coverage check with a configured threshold (in CI
  order, alongside format/lint/type/test); a coverage shortfall SHALL fail the gate exactly like any other
  check, so it blocks the commit and a repeated shortfall surfaces as a loop stall.
- `project-bootstrap`: `/ralph-init` SHALL infer the coverage invocation + threshold for the toolchain, confirm
  the threshold with the user, fold it into the gate in CI order, and add the coverage tooling to the
  Containerfile/CI setup; the scaffolded `PROMPT.md` SHALL carry the coverage clause.

## Impact

- **Templates:** `templates/gate.sh.template` (header guidance on the coverage step), `PROMPT.md.template`
  (coverage clause); `example/` golden reference (`scripts/gate.sh`, `PROMPT.md`, Containerfile/CI) gains a
  concrete coverage step.
- **Plugin:** `skills/ralph-init/SKILL.md` — coverage inference, threshold confirmation, toolchain-block update.
- **This repo's specs:** deltas on `gate-enforcement` and `project-bootstrap`.
- **This repo's own gate:** `make test` has no coverage step today; adding one for the kit itself is optional
  and tracked as a task, not required by this change.
- **Compatibility:** consumers re-running `/ralph-init` get the coverage step; existing scaffolds are unaffected
  until regenerated or hand-edited. A new gate step can block commits, so threshold confirmation is mandatory.
