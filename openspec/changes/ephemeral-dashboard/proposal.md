## Why

You can already *tail* a running loop (`live.log`) and *query* it on demand (`/ralph-status`),
but there is no glanceable, always-fresh picture of progress for an operator who starts a loop and
walks away. Worse, a live view can't be built honestly on today's state files: the runner writes
`current.json` `state="running"` at turn start and `"idle"` at turn end, and emits **no terminal
write on any exit path** — so "the project finished," "paused 6h on a rate limit," and "resting 30s
between turns" are byte-for-byte identical on disk, and a fresh loop on a reused `.ralph/` shows the
*previous* run's final turn as if it were live. Any dashboard built on that substrate would
confidently mislead at exactly the moments truth matters. This change first makes the runner's state
honest, then adds an opt-in dashboard that renders it.

## What Changes

- **Phase 1 — honest lifecycle state (runner change).** The runner emits a small set of structured,
  single-sourced signals so *any* reader can faithfully represent the loop:
  - a **per-invocation run-id + start time** in `current.json`, so a reader can fence stale
    prior-run data (ignore any record whose run-id ≠ the live one);
  - an **explicit terminal write in the EXIT trap** recording the halt **class**
    (`complete | blocked | review-exhausted | stall | sigint`), so "done" is never confused with
    "idle between turns" (a SIGKILL/OOM leaves no write — the dashboard *infers* "killed", per design D4);
  - a structured **`paused: {reason, until}`** record around *both* the usage-limit sleep and the
    review-gate CI wait, so a long pause renders as "paused, resumes 14:32" not "hung";
  - the **stall count** and **review-round** counters promoted from `live.log` narration into
    `current.json` fields.
  - This is additive and reuses the existing `persist_blocked` merge pattern. It **independently
    improves `/ralph-status` and the notify seam** — they gain the same honest signals whether or not
    a dashboard is ever enabled.
- **Phase 2 — the dashboard (opt-in, default-off).** A host-side web viewer that:
  - starts with `make loop`, **prints one localhost URL** and writes it to a stable re-findable file,
    and **tears itself down** when the loop ends or the project completes (one event: the loop
    process returns);
  - **updates live without reloading** (server-sent events); every (re)connect re-derives full state
    from `current.json` + `status.jsonl` then tails — laptop-sleep resilience for free;
  - reads the **structured files for facts** and tails `live.log` only for the scrolling activity
    feed;
  - is enabled by `RALPH_DASHBOARD` (default off; `env > ralph.conf > default`), startup-validated,
    and **gracefully skipped** if host `python3` is absent — so the default loop is unchanged.
- **Single-sourced viewer, not vendored.** The viewer is generic harness machinery, so it lives in
  **one place** (bundled with the kit, launched fresh like `ralph_prefix.py`) and ships via
  `/plugin update`. It is **not** scaffolded into the consumer repo — only the small Makefile
  loop-wrapper delta is scaffolded and manifest-tracked. A bug fix reaches every project at once
  rather than being forked across N copies.
- **Visuals.** One centerpiece **Commit Ribbon** — a left-to-right chain of turn-nodes that grows in
  real time, filled when `HEAD` advanced / hollow on a stall, weighted by diff churn from
  `git show --numstat <sha>` (host-side, free) — plus a single X/N task arc and a **stakes strip**
  that lights only when live (rate-limit countdown, stall-pressure meter, review-round pips).
  `live.log` is a collapsible drawer. **Gate-stage pills (format/lint/type/test) are explicitly
  dropped from v1**: the gate runs inside the agent's project-owned `gate.sh` and emits no structured
  per-stage signal, so drawing them would be a fake signal.
- **Cardinality.** Ship **per-loop** in v1, but design the run-id/epoch and URL file so a future
  **per-host multi-loop** discovery dashboard (globbing `*/.ralph/`, project-keyed like the
  vector-console recipe) is a clean, non-breaking follow-up.

No breaking changes. The dashboard is off by default; Phase 1 fields are additive.

## Capabilities

### New Capabilities
- `loop-lifecycle-state`: the runner emits structured, single-sourced lifecycle signals in its state
  files — per-run identity/epoch, an explicit terminal halt-class on exit, a structured paused
  record, and promoted stall/review counters — so any reader (the dashboard, `/ralph-status`, the
  notify seam) can faithfully distinguish running / idle-between-turns / paused / done / killed and
  fence stale prior-run data.
- `progress-dashboard`: an opt-in (default-off), auto-launching, host-side, ephemeral localhost web
  dashboard for a running loop — starts with `make loop`, prints and persists a URL, updates live
  without reloading, renders the structured state safely, and tears down when the loop ends.

### Modified Capabilities
<!-- None. Phase 1 adds new structured fields the runner writes; it does not change the
     requirements of review-gate, work-dispatch, outbound-notification, or log-streaming. The
     review-gate verdict rule, the usage-limit pause behavior, and live.log's format are all
     unchanged — those code paths gain additive state-emission calls only. -->

## Impact

- **Runner (`base/scripts/ralph.sh`)** — Phase 1 lifecycle emissions on the startup, exit-trap,
  usage-limit, stall, and review-gate paths. Runner change ⇒ **base-image rebuild** (two-channel
  release); new tests in the stubbed-`claude` suite.
- **New plugin-bundled host viewer** — `python3` stdlib only (threaded HTTP server + SSE), single-
  sourced, shipped via `/plugin update`. Its pure-logic parts (state derivation, escaping, ribbon
  data) are unit-testable; the socket/SSE plumbing is covered structurally.
- **Templates / example** — `Makefile` `loop` recipe refactored to a single-shell wrapper that
  launches the viewer, prints/persists the URL, and traps teardown — **without regressing the
  existing `SIGINT → exit 130` stop path**; new `RALPH_DASHBOARD` opt-in key in `ralph.conf.example`.
  Only the Makefile-wrapper delta is added to `.ralph-scaffold.json` (+ `/ralph-upgrade` propagation);
  the viewer adds **nothing** to the manifest, the Ralph-owned config set, or conformance check 5.
- **Security (first-class).** The viewer renders **agent-authored text** (commit subject,
  `blocked_reason`, `live.log`/turn output). It MUST escape every field into the page, set a strict
  CSP, and validate the `Host` header against DNS-rebind. The loopback listener shares the
  `GH_TOKEN` env-plane blast radius the kit already documents for the `gh`/notify seams — documented,
  not newly isolated. The `127.0.0.1` bind is necessary but not sufficient.
- **Docs / release** — `CLAUDE.md` (new capabilities + two-channel note), `CHANGELOG.md`,
  `.claude-plugin/plugin.json` version bump.

### Proportionality

Over `tail -f live.log` + `/ralph-status`, the dashboard adds: a glanceable, always-fresh,
zero-keystroke view; the Commit Ribbon as a felt sense of progress; and live stakes (pause countdown,
stall pressure, review rounds) you cannot get from raw tailing. The cost is real — a two-channel
runner change, a host viewer the kit maintains, a Makefile refactor, and new test/security surface —
which is why the viewer is **opt-in and single-sourced** (no per-project footprint) and **Phase 1 is
justified on its own** (it improves `/ralph-status` and notify regardless of the dashboard).
