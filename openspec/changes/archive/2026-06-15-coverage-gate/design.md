## Context

The kit's gate (`scripts/gate.sh`, single-sourced and mirrored by the pre-commit hook + CI) enforces
format/lint/type/test. "test" means tests *exit 0*, not that they *cover* the code. The spec → test → implement
discipline lives in `PROMPT.md` prose (soft); the only hard proof is "tests pass." This change moves "the code
is actually tested" into the enforced gate via a coverage threshold.

The mechanism is small — coverage is one more command in `gate.sh`, and the single-source model propagates it to
the hook, CI, and the prompt automatically. The hard parts are policy, and they're settled here so the apply
phase is mechanical. The companion `outer-loop-review-gate` change adds the orthogonal pillar (independent
review) that catches what coverage cannot.

## Goals / Non-Goals

**Goals:**
- Mandate the *presence* of a coverage check with a threshold in every scaffolded gate, in CI order.
- Keep the threshold and tool project-owned; default to a portable global floor.
- Have `/ralph-init` infer the coverage invocation, confirm the threshold, and wire the toolchain.
- Be honest in the docs that coverage is a supporting gate, not the headline.

**Non-Goals:**
- A kit-fixed coverage percentage (projects/languages differ; the kit mandates the check, not the number).
- End-to-end / real-artifact acceptance verification (the §5.18 catcher) — separate future change.
- Independent review — the separate `outer-loop-review-gate` change.
- Adding a coverage step to *this repo's own* `make test` (optional; a task, not a requirement).

## Decisions

### D1 — Mandate the check, not the number
The kit's existing contract lets the consumer define the whole gate command; it only guarantees single-sourcing
+ CI order. This change adds exactly one new guarantee: the gate *contains* a coverage check with a threshold.
The threshold/tool stay in `scripts/gate.sh` (project-owned, like the rest of the gate). *Why:* a kit-imposed
percentage would be wrong for some languages/projects and would be the most damaging thing to hardcode; the
*presence* of coverage gating is the portable, defensible mandate.

### D2 — Default to a global floor; document patch coverage
Default mechanism is a project-wide floor (`--cov-fail-under=N` or equivalent). *Why over patch/diff coverage:*
a global floor is supported by every coverage tool (no `diff-cover`/base-ref machinery), and Ralph projects are
typically greenfield grown test-first, so global coverage stays high without coupling turns. Patch coverage's
advantage (isolating to changed lines) matters for brownfield, where a single legacy untested module would tank
a global floor and block unrelated turns — so it's documented as the brownfield option, not the default.
*Alternative considered — a ratchet (coverage must not decrease):* gets a similar benefit but needs stored prior
coverage (extra state); deferred in favor of the simpler floor.

### D3 — `/ralph-init` confirms the threshold
A coverage threshold is the one gate parameter most likely to block every commit if set wrong. So `/ralph-init`
proposes an inferred starting value (default 80% where it must pick one) but **confirms it with the user**, the
same caution it already applies to the gate command itself.

### D4 — The prompt gets a do-not-game clause, with an escape valve
Adding a hard coverage gate creates a new stall source (genuinely-hard-to-cover code → blocked commit). The
prompt's coverage clause routes that pressure correctly: satisfy coverage by testing the real path; for code
that truly cannot be reasonably tested, use the language's standard coverage *pragma* to exclude it, or escalate
to `questions.md` — never delete tests or lower the threshold (guards ④/⑤). This keeps the gate honest without
turning hard-to-cover code into a dead loop.

### D5 — Honesty in the docs
Per the field log (§5.18), coverage-% catches the trivial-test class but not the faked-precondition class (those
lines are "covered"). The proposal, the template comments, and the README/CLAUDE note say so, and point at the
review gate + acceptance verification as the catchers for that class. This prevents coverage from being sold as
more than it is.

## Risks / Trade-offs

- **New stall source: hard-to-cover code.** → D4 escape valve (pragma / escalate), and the existing stall
  detector bounds it. Default threshold confirmed with the user (D3), not set aggressively by fiat.
- **Coverage theater.** A threshold can be met by low-value tests. → Acknowledged; coverage is explicitly a
  *floor*, paired with the review gate which targets test *quality*/wiring. Documented (D5).
- **Per-language tooling variance.** Coverage invocation differs by stack. → `/ralph-init` inference is
  best-effort and confirmed with the user (like the gate command); the kit mandates the check's presence, not a
  specific tool.
- **Brownfield adoption pain.** A global floor on an existing untested codebase blocks everything. → Patch
  coverage documented as the brownfield path (D2).

## Migration Plan

Additive. Existing consumers are unaffected until they re-run `/ralph-init` or hand-add the coverage line to
`scripts/gate.sh`. Rollback is removing the coverage line from `gate.sh` (single source — one place). No runner
(`ralph.sh`) change is required: a failing coverage check is just a red gate, which the existing hook/CI/stall
machinery already handles.

## Open Questions

- **Default starting threshold** when `/ralph-init` must pick one: 80% is the proposed convention, confirmed with
  the user. Open to a different default.
- **This repo's own gate:** whether to add a coverage step to `make test` for the kit itself (its suite is bash
  + a little python). Tracked as an optional task, decided during apply.
