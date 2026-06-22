## Context

The runner (`base/scripts/ralph.sh`) already collapses every needs-human transition into one shape —
populate `STATUS.md`, then exit — at three sites: the review gate exhausting its rounds
(`REVIEW_GATE_HALT`, ~L467), `RALPH_MAX_STALLS` consecutive no-commit turns (~L480), and the agent
writing a new stop reason to `STATUS.md` (detected ~L455). All three are silent today. A fourth case is
mishandled: the PROMPT contract has the agent write `docs/questions.md` and exit without committing on a
blocked decision, which the runner sees only as a no-commit *stall* — so one ambiguity burns
`RALPH_MAX_STALLS` turns with no signal.

The kit already has the right seam pattern: `RALPH_REVIEWER` is a pluggable command (startup-validated,
empty = built-in default) that the runner shells out to. `RALPH_NOTIFY_CMD` copies it. Constraints carry
over: agent-agnostic (the in-container agent never touches the network/GitHub; only the runner notifies),
bash 3.2-safe, config precedence `environment > ralph.conf > default`. The runner also has a `narrate()`
helper (from `log-streaming`) for operator-facing lines.

## Goals / Non-Goals

**Goals:**
- One `notify_human <event> <reason>` call at each of the 3 halt exits, plus a new `blocked` stop on a
  changed `docs/questions.md`.
- A pluggable, notifier-agnostic `RALPH_NOTIFY_CMD` seam (Slack the primary documented target).
- Notification is non-fatal and never alters the loop's exit code or flow.
- Default behavior (unset notifier) byte-identical, except a blocked question now halts promptly.

**Non-Goals:**
- A run digest / `RUN-SUMMARY.md` (payload is the one-line reason; richer digest is future).
- Good-news notifications (PR passed/merged) — future; v1 is needs-human events only.
- A built-in Slack integration — the kit ships the seam + recipe only.
- B2 (skip a blocked task and continue) — breaks the linear one-task-per-turn contract.
- Durability/detach (Thread C) — separate future `loop-durability` change.
- Reusing `log-streaming`'s file-tailing — `NOTIFY` is an event-push seam, a distinct key.

## Decisions

### D1 — `RALPH_NOTIFY_CMD` mirrors the `RALPH_REVIEWER` seam
A single operator-supplied command, invoked `<cmd> <event> <reason>`; empty = off (no notification,
behavior unchanged). Startup-validated for executability when set (the same `command -v`/`-x` check the
reviewer seam uses). *Why:* reuses a proven, agent-agnostic indirection point; keeps the kit
notifier-agnostic so Slack/PR-comment/webhook are all just commands. Alternative (a built-in Slack
sink keyed on `SLACK_WEBHOOK_URL`) rejected — it couples the runner to one vendor and breaks the
established seam pattern.

### D2 — Event taxonomy: `review-exhausted` / `stall` / `stop` / `blocked`
Four needs-human events, each with the one-line reason (the `STATUS.md` content, or the new question for
`blocked`). *Why four:* they map 1:1 to the runner's existing halt sites plus the new questions stop, so
each call site passes a fixed literal — no classification logic. Good-news events (`passed`/`merged`) are
left as a documented future extension of the same taxonomy.

### D3 — `notify_human` is non-fatal and bounded
The helper invokes `RALPH_NOTIFY_CMD` only if set; wraps it so a non-zero exit, error, or slowness cannot
change the loop. Run it under `timeout` with a short cap and ignore its status (`notify ... || true`),
surfacing any failure via `narrate`. *Why:* a halt notification must never itself become a failure mode
or hang the exit — same principle as the review-gate "failed push is reported, not swallowed, loop
continues." *Open:* whether to background it (`&`); leaning synchronous-with-timeout for simpler ordering
and because halts are terminal anyway (no throughput cost).

### D4 — `docs/questions.md` detection mirrors `STATUS.md` exactly
Snapshot `docs/questions.md` at startup (like `status_start`); after a turn, if it changed to a
non-whitespace value AND the turn made no commit, stop immediately with a `blocked` notification. *Why
mirror STATUS.md:* the kit already documents that STATUS.md change-detection is duplicated between
`ralph.sh` and the `ralph-status` skill and they must stay in sync — `questions.md` adds a second such
pair, so it must use the identical startup-snapshot rule to avoid a stale pre-existing list stopping a
fresh loop. Path is pinned to `docs/questions.md` (what the PROMPT hardcodes); expose `RALPH_QUESTIONS`
(default `docs/questions.md`) for the rare relocation, via the standard precedence.

### D5 — Ordering of the new blocked-stop against existing checks
Per iteration the order becomes: run turn → usage-limit pause (unchanged; replays, never a stall) →
`STATUS.md` stop check → **new `questions.md` blocked check** → review gate (committing turns only) →
stall counter. *Why this slot:* a blocked question is a no-commit turn, so it must be caught *before* the
stall counter increments (otherwise it still counts as a stall), and after the usage-limit/ STATUS checks
so those keep precedence. The blocked check only fires on a no-commit turn whose `questions.md` grew, so
it cannot pre-empt a normal committing turn.

### D6 — Slack ships as a recipe, not an integration
`docs/recipes/slack-notify.md`: a few-line script that `curl`s `<event>`/`<reason>` to a Slack incoming
webhook (`SLACK_WEBHOOK_URL`), wired via `RALPH_NOTIFY_CMD=/path/to/notify-slack.sh`. Note a zero-dep
`gh pr comment` alternative (the runner is already `gh`-authenticated). *Why docs not scaffold:* the
notifier is optional external tooling, like the Vector recipe — scaffolding it into every consumer adds
noise.

## Risks / Trade-offs

- **A slow/hanging notifier delays the halt** → run under a short `timeout`, status ignored (D3); a
  notifier that hangs is killed, the halt proceeds. Covered by a failing-notifier test.
- **`questions.md` false-positive stops** (a pre-existing list) → startup snapshot + changed-non-whitespace
  rule, identical to `STATUS.md` (D4); covered by a "pre-existing list does not stop" test.
- **Detection drift between `ralph.sh` and `ralph-status`** → document the new duplicated pair alongside
  the existing `STATUS.md` note in CLAUDE.md; keep both rules byte-aligned.
- **Notifier leaks secrets in args** (a webhook URL on a command line) → the recipe keeps the secret in
  `SLACK_WEBHOOK_URL` (env), not in `RALPH_NOTIFY_CMD`; document this.
- **Two-channel release friction** → runner change reaches a loop only after a base rebuild; tasks call
  out the `plugin.json` bump + rebuild.

## Migration Plan

Additive and non-breaking. With `RALPH_NOTIFY_CMD` unset, no notification occurs and the loop behaves as
today — the only intended behavior change is that a blocked `docs/questions.md` now stops promptly
instead of after `RALPH_MAX_STALLS` (a strict improvement; still halts, just sooner and with a signal).
Rollback is unsetting `RALPH_NOTIFY_CMD` (notifications) and, if needed, reverting the questions-stop.
Reaching a machine requires the two-channel step: bump `.claude-plugin/plugin.json` and rebuild the base
image.

## Open Questions

- **Background vs synchronous notify** — leaning synchronous-under-`timeout` (D3); revisit only if a halt
  notification's latency proves annoying.
- **`RALPH_QUESTIONS` config** — ship the knob now or hardcode `docs/questions.md`? Leaning ship the knob
  (cheap, consistent with every other path being configurable), default `docs/questions.md`.
- **`ralph-status` surfacing** — whether the skill should report "notifications: configured" and a
  blocked-question state; decide during tasks (doc tweak, not a spec requirement).
