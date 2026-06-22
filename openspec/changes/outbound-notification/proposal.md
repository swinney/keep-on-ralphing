## Why

Developing async — kick off a loop and walk away — is only responsible if the loop can **summon you
back** when it needs a human. Today it cannot: every "needs-a-human" transition writes `STATUS.md` and
exits *silently*, and `STATUS.md` is a gitignored file you must be present to read. Worse, a blocked
decision is invisible: the PROMPT contract has the agent write `docs/questions.md` and exit without
committing, which the runner counts as a *stall* — so one ambiguity silently burns
`RALPH_MAX_STALLS` turns before halting, with no signal. This change adds an outbound notification seam
so the runner pings the operator (Slack the primary target) the moment a human is needed — the TAP half
of outbound observability, complementing the WATCH half (`log-streaming`).

## What Changes

- **`RALPH_NOTIFY_CMD` seam (runner).** A pluggable notifier command, mirroring `RALPH_REVIEWER`:
  invoked as `<cmd> <event> <one-line-reason>`. Default **empty = off** (opt-in; behavior byte-identical
  when unset). Startup-validated for executability when set. The **runner** invokes it — the agent stays
  GitHub/network-blind.
- **Notify at every needs-human exit.** A `notify_human <event> <reason>` helper fires at the three halt
  sites — review gate exhausted (`review-exhausted`), `RALPH_MAX_STALLS` reached (`stall`), and the agent
  wrote a stop reason (`stop`) — carrying the one-line `STATUS.md` reason. The notifier is **non-fatal**:
  a failing/slow notifier is reported but never changes the loop's exit code or flow.
- **Blocked questions stop immediately and notify (`blocked`).** A changed `docs/questions.md` is treated
  like `STATUS.md` — an immediate stop with a `blocked` notification — instead of silently burning
  `RALPH_MAX_STALLS` no-commit turns first.
- **Slack recipe (kit reference).** `docs/recipes/slack-notify.md` — a small `curl` to a Slack incoming
  webhook, wired via `RALPH_NOTIFY_CMD`; with a zero-dep `gh pr comment` alternative noted. The kit ships
  the **seam + recipe**, never a vendored Slack integration (notifier-agnostic).
- Non-breaking: with `RALPH_NOTIFY_CMD` unset the loop behaves exactly as today (except a blocked
  question now stops promptly instead of after `MAX_STALLS`).

## Capabilities

### New Capabilities
- `outbound-notification`: the runner-owned `RALPH_NOTIFY_CMD` seam that fires a one-line notification at
  every needs-human transition (`review-exhausted`/`stall`/`stop`/`blocked`), non-fatally and
  agent-blind, plus treating a changed `docs/questions.md` as an immediate stop; and the kit's Slack
  recipe documenting how to wire it (harness-as-source, no built-in integration).

### Modified Capabilities
<!-- None at the spec level. The 3 halt exits are runner behavior (covered by the runner test scaffold,
     not a capability spec); review-gate's halt is unchanged in meaning, only newly notified. /ralph-init
     gains a documented ralph.conf key but no new spec-level bootstrap requirement. -->

## Impact

- **Runner:** `base/scripts/ralph.sh` — `RALPH_NOTIFY_CMD` resolution + startup validation; a
  `notify_human` helper (non-fatal); calls at the 3 halt exits; `docs/questions.md` startup-snapshot +
  changed-content detection that stops immediately (ordered against the STATUS.md check, the usage-limit
  pause, and the stall counter). Optional `RALPH_QUESTIONS` to make the path configurable
  (default `docs/questions.md`). Bash 3.2-safe; precedence `environment > ralph.conf > default`.
- **Templates / example:** `templates/ralph.conf.example` documents `RALPH_NOTIFY_CMD` (and any
  `RALPH_QUESTIONS`), default off; `example/` kept in sync.
- **Docs:** new `docs/recipes/slack-notify.md` (kit reference, not scaffolded into consumers).
- **Skills:** `skills/ralph-status/SKILL.md` may note whether notifications are configured and surface a
  blocked-question state (same dup-in-sync care as STATUS.md detection).
- **Tests:** `base/tests/` — a stubbed `RALPH_NOTIFY_CMD` recorder asserts invocation + event/reason at
  each halt; a changed `questions.md` stops immediately as `blocked` (not a `MAX_STALLS` stall); a failing
  notifier does not change exit code/flow; unset = no-op. No network. Wired into `run.sh` + CLAUDE.md.
- **Release:** runner change → **two-channel**: bump `.claude-plugin/plugin.json` (from 0.5.0) AND rebuild
  the base image.
- **Compatibility:** non-breaking; unset notifier = today's behavior, with the one intended improvement
  that a blocked question halts promptly instead of after `MAX_STALLS`.
