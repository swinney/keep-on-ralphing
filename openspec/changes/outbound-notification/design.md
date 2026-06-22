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

### D4 — `docs/questions.md` detection is a PER-TURN diff (not a startup snapshot)
Capture `docs/questions.md` at the *start of each turn*; after the turn, if it changed to a
non-whitespace value AND the turn made no commit, stop immediately with a `blocked` notification. *Why
NOT a startup snapshot like `status_start`:* a startup snapshot works for `STATUS.md` because that stop
fires on **any** change, committed or not — but the blocked check is gated on a **no-commit** turn. With
a startup snapshot, a question added on a *committing* turn would leave the snapshot stale, and the next
unrelated no-commit turn would then satisfy `now != startup` and falsely halt as `blocked`. Comparing
this-turn-before vs after detects only a question the agent wrote *during this turn*; a pre-existing list
(or a question committed earlier) is unchanged across a later turn and so is naturally ignored. Detection
therefore lives in exactly one place (`ralph.sh`) — it is NOT duplicated into `ralph-status` (which
consumes the persisted `blocked` signal instead; see Risks). Path is pinned to `docs/questions.md` (what
the PROMPT hardcodes); expose `RALPH_QUESTIONS` (default `docs/questions.md`) for the rare relocation, via
the standard precedence.

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
- **`questions.md` false-positive stops** (a pre-existing list, or a question added on an earlier
  committing turn) → per-turn before/after diff + changed-non-whitespace + no-commit gate (D4); covered by
  a "pre-existing list does not stop" test AND a "committed question-write does not false-block a later
  turn" test.
- **Detection drift between `ralph.sh` and `ralph-status`** → document the new duplicated pair alongside
  the existing `STATUS.md` note in CLAUDE.md; keep both rules byte-aligned. *Caveat for `/ralph-status`:*
  the runner's blocked detection relies on a shell-local startup snapshot, which a one-shot status reader
  does not have — so it cannot, from the file alone, distinguish a stale pre-existing `questions.md` from a
  question appended during the current run. Therefore `/ralph-status` MUST NOT re-derive blocked state by
  reading `questions.md` directly. If it surfaces blocked state at all (optional, task 6.4), it MUST read a
  signal the runner *persisted* into `RALPH_STATE_DIR` (e.g. the snapshot or the blocked decision recorded
  in `status.jsonl`/`current.json`); otherwise it MUST NOT classify questions at all. This avoids
  false-reporting exactly the pre-existing-list case the runner is built to ignore.
- **Notifier leaks secrets in args** (a webhook URL on a command line) → the recipe keeps the secret in
  `SLACK_WEBHOOK_URL` (env), not in `RALPH_NOTIFY_CMD`; document this.
- **Notifier secret reachable in the agent's env** → the runner runs *in* the container and invokes the
  notifier there, so `SLACK_WEBHOOK_URL`/`RALPH_NOTIFY_CMD` must be present in the container env, where the
  `claude` turn (started from the inherited env, no scrub) can read them. This is the **same exposure plane
  as the already-forwarded `GH_TOKEN`** (the consumer Makefile forwards it via `-e GH_TOKEN` today), so it
  introduces no new *class* of exposure: "agent-blind" is a behavioral contract (the runner owns all
  git/gh/network work, the agent does not), not env isolation. The recipe SHALL therefore treat the
  webhook as a runner-plane secret of the same sensitivity as `GH_TOKEN` and document it as such. Full
  env-isolation of the agent turn (scrubbing runner-only secrets before exec) is a broader hardening that
  would also cover `GH_TOKEN` and is **explicitly out of scope** for this change — calling it out here so
  it is a recorded decision, not an oversight.
- **Two-channel release friction** → runner change reaches a loop only after a base rebuild; tasks call
  out the `plugin.json` bump + rebuild.

## Migration Plan

Additive and non-breaking. With `RALPH_NOTIFY_CMD` unset, no notification occurs and the loop behaves as
today — the only intended behavior change is that a blocked `docs/questions.md` now stops promptly
instead of after `RALPH_MAX_STALLS` (a strict improvement; still halts, just sooner and with a signal).
Rollback is unsetting `RALPH_NOTIFY_CMD` (notifications) and, if needed, reverting the questions-stop.
Reaching a machine requires the two-channel step: bump `.claude-plugin/plugin.json` and rebuild the base
image.

## Resolved Decisions

- **Notify synchronously, under a short `timeout`** (confirms D3). The notifier runs inline at the halt,
  status ignored; a hung notifier is killed by the `timeout` and the halt proceeds. No background/async
  dispatch — a halt is not latency-sensitive, and synchronous is the simplest path that stays non-fatal.
- **Ship the `RALPH_QUESTIONS` knob** (not hardcoded). A configurable path defaulting to
  `docs/questions.md`, honouring `environment > ralph.conf > default` — cheap and consistent with every
  other path being configurable. (Task 4.1.)
- **`/ralph-status` surfaces blocked state** — yes, do it. The skill reports whether notifications are
  configured and the blocked-question state, reading the runner-persisted signal in `RALPH_STATE_DIR`
  (task 4.4), never re-deriving from `docs/questions.md`. The summon-a-human purpose of this change makes a
  blocked state `/ralph-status` cannot show a half-finished signal; the persistence cost (one field in an
  existing record) is small. (Tasks 4.4 + 6.4, now both committed rather than optional.)
