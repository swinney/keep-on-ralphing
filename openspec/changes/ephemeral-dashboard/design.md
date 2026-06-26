## Context

The loop already produces a rich, bind-mounted state substrate under `.ralph/`: a `current.json`
heartbeat, an append-only `status.jsonl` (one record per turn), a turn-correlated `live.log`, and
per-turn logs. Two consumers read it today — the `/ralph-status` skill (on demand) and the
vector-console recipe (host-side tail). The kit's stated stance is "a log **source**, not a log
**service**": the container stays network-isolated and ships no dashboard or port.

This change adds a third consumer — an opt-in web dashboard — but an adversarial design pass found
the existing substrate **cannot be rendered honestly as a live view**:

- `current.json` is written `state="running"` at turn start and `"idle"` at turn end, with **no
  terminal write on any exit path**. So "finished," "paused 6h on a rate limit," and "resting between
  turns" are identical on disk.
- The usage-limit pause is a foreground sleep (up to ~6h) with **zero heartbeat** and the turn
  counter **decremented** for the replay — a naive UI reads "hung" or "turns going backwards."
- `.ralph/` is **never cleared between runs**, so a fresh loop on a reused workspace would show the
  *previous* run's final turn (possibly a stale `blocked:true`) as live on its first frame.
- Stall pressure, review rounds, and the pause's resume time exist **only as `live.log` narration** —
  free text the kit explicitly treats as a non-API log source.

Hence the two-phase shape: make the state honest first, then render it.

## Goals / Non-Goals

**Goals:**
- An opt-in (default-off) dashboard that auto-launches with `make loop`, advertises a recoverable
  localhost URL, updates live without reloading, and tears down when the loop ends.
- Honest lifecycle signals in the runner's state files, valuable on their own to `/ralph-status` and
  the notify seam.
- A single-sourced viewer with **zero per-project footprint** and a small, zero-dependency
  (stdlib-only) surface.
- A visual that renders the kit's own thesis ("commit graph = progress").

**Non-Goals:**
- A per-host, multi-loop discovery dashboard (designed-for as a clean follow-up, not built in v1).
- Remote access. The URL is loopback; reaching it from an SSH client is the operator's tunnel to set
  up. The remote "come look" path remains the existing `RALPH_NOTIFY_CMD` seam.
- Gate-stage progress (format/lint/type/test). The gate runs inside the agent's project-owned
  `gate.sh` and emits no structured per-stage signal; drawing stage pills would be a fabricated
  signal. Explicitly deferred as a future best-effort heuristic if ever revisited.
- Any change to the loop's control behavior, the review-gate verdict, the usage-limit pause/replay,
  or the `live.log` format.

## Decisions

### D1 — Phase 1 (honest lifecycle state) is a prerequisite, not a follow-up
The dashboard's correctness depends on signals the substrate lacks. Phase 1 adds: a per-invocation
**run-id + start time** (fences stale prior-run data); an **explicit terminal write in the EXIT trap**
naming the halt class; a structured **`paused:{reason,until}`** around the usage-limit sleep and the
review-gate CI wait; and **stall/review-round counters** promoted into `current.json`. All reuse the
existing `persist_blocked` merge pattern so a partial write never clobbers other heartbeat fields.
*Rationale:* without these, a viewer the kit implicitly warrants as faithful would confidently lie at
exactly the moments truth matters. *Independent value:* `/ralph-status` and notify get the same
honest signals regardless of the dashboard. *Alternative rejected:* build on existing fields and
scrape `live.log` for the rest — dishonest, and couples the UI to non-API free text.

### D2 — Single-sourced viewer, never scaffolded into the consumer repo
The viewer is **generic machinery** (an HTTP/SSE server + a `.ralph/` reader, byte-identical across
projects), not project-owned config. *Rationale:* the kit's one scaffolded-script exception
(`gate.sh`) is justified as project-*specific* config with a `{{placeholder}}`; a viewer has none.
Scaffolding it would add a manifest entry, a golden-reference file, a conformance pin, and a
`/ralph-upgrade` insert-vs-regenerate obligation on the file **most** likely to be customized (a
"visually interesting" UI invites restyling) — and `/ralph-upgrade`'s primitives (regenerate-pristine
or insert-missing-blocks) cannot patch an evolving app. A bug would then live in N repos at N
versions. *Alternatives:* scaffold-into-repo (rejected — vendoring an evolving app); copy-paste recipe
like vector-console (viable, stance-pure, but **not** the zero-config auto-launch the operator asked
for — kept as the documented fallback if the dashboard is judged not worth the maintenance).

### D3 — Viewer placement & launch mechanism *(key open decision — spike at Phase 2 start)*
Auto-launch-on-`make loop` constrains placement: the consumer's thin `Makefile` runs one
`podman run … ralph.sh` and **cannot resolve `$CLAUDE_PLUGIN_ROOT`** (only skills can), so the only
single source `make loop` reliably reaches is **the base image it already runs**. Two viable shapes:

- **D3a — Host-side execution, viewer sourced from the image (recommended).** The single-shell loop
  wrapper extracts the viewer from the image to a host temp path at launch, runs it with **host
  `python3`** against the bind-mounted `.ralph/`, and traps teardown to kill it + remove the temp
  file. *Pro:* the container stays strictly **port-free** (the kit's stance intact); teardown is a
  clean host trap. *Con:* requires host `python3` (graceful-skip if absent); viewer changes ride the
  base-image channel.
- **D3b — In-container execution, loopback-published.** `ralph.sh` backgrounds the viewer when
  `RALPH_DASHBOARD=1` and kills it via its **existing** EXIT/SIGINT trap; the `Makefile` publishes
  `-p 127.0.0.1::<port>`. *Pro:* trivial single-source (on the image PATH), no host-`python3`
  dependency, teardown reuses the runner's trap. *Con:* **softens "the container opens no port"** to
  "loopback-only, operator-initiated, read-only file view," and surfacing the OS-assigned host port
  while the container is foreground is fiddly (`podman port`).

*Note:* either way, because the viewer reaches `make loop` via the image, **viewer iteration is a
two-channel (base-rebuild) concern** — the hoped-for "plugin-channel-only viewer iteration" is not
achievable *together with* auto-launch. A `/ralph-dashboard` skill (which *can* resolve the plugin
root) is a possible complement for attaching to an already-running loop, but not the primary path.
Resolve D3a-vs-D3b with a short spike before building the viewer.

**Resolved (Phase 2 spike) → D3a (host-side, viewer extracted from the image).** Validated on a real
`ralph-base:v1`: `podman create` + `podman cp` + `podman rm` extracts a baked file to a host temp path
**without running the container**, and host `python3` (3.14.5) executes the extracted script. The
workspace is bind-mounted (`-v $(WORKSPACE):/workspace`), so `.ralph/` is host-native at
`$(WORKSPACE)/.ralph/` — the host viewer reads it directly, no mount. D3a keeps the container strictly
**port-free** (the kit's "log source, not a service" stance), lets the viewer bind `127.0.0.1:0` and
print its own URL directly (no `podman port` gymnastics against a foreground container), and gives a
clean host-trap teardown. D3b was rejected: surfacing an OS-assigned host port out of a foreground
`podman run` is raced/fiddly and softens the no-port stance. D3a's only cost — host `python3` — is
satisfied here and degrades gracefully (skip-with-warning) when absent, per the dashboard spec.

### D4 — Liveness = run-id match AND container-running
The viewer determines "is this loop live?" from the **run-id** (matches the launch) combined with
whether the loop container is actually running (`podman ps`, the same honest source `/ralph-status`
already uses). *Rationale:* `current.json` alone cannot distinguish idle-between-turns from a killed
process; the EXIT trap does not fire on SIGKILL/OOM, so a "killed" outcome is **reader-inferred**
(run-id was live, process is gone → ended). *Alternative rejected:* trust `current.json.state` —
provably ambiguous.

### D5 — Live updates via SSE with snapshot-on-(re)connect; no Last-Event-ID
Every connect/reconnect **re-derives full state** from `current.json` + `status.jsonl`, then streams
subsequent deltas. *Rationale:* the append-only files **are** the replay store, so a slept/woken
laptop or a second tab re-syncs correctly for free — no event-id replay machinery to build.
*Alternative rejected:* WebSocket (over-engineered for one-directional, read-only data) and
Last-Event-ID replay (redundant given the files).

### D6 — Threaded stdlib server, hardened
Use `ThreadingHTTPServer` (not bare `HTTPServer`, which is single-threaded and would let one
long-lived SSE GET block every other tab/asset) with `daemon_threads = True` (so teardown never
hangs on a held stream), per-write `BrokenPipe`/`ConnectionReset` handling (dead tabs), and a periodic
heartbeat comment line (the only way a one-directional stream detects a dead client). Stdlib only — no
new dependency.

### D7 — Ephemeral port + recoverable URL; print, don't auto-open
Bind `127.0.0.1:0` (OS-assigned) so concurrent loops never collide; print one unmissable
`Dashboard: http://127.0.0.1:<port>` line **and** write it to a stable file so it survives the
terminal scrolling. Auto-open is **off by default** and `$BROWSER`-respecting (loop hosts are often
headless/SSH). *Rationale:* matches the multi-loop reality the vector-console recipe already supports;
"give me the URL" ≠ "open a tab on a headless box."

### D8 — Teardown bound to the loop process; protect the SIGINT path
"Loop over" and "project done" are the same event (the loop process returns), so a single teardown
trigger suffices. The `Makefile` `loop` recipe is multi-line (each line its own shell), so it is
refactored into a **single-shell wrapper** that owns launch + `podman run` + a teardown trap. The
refactor MUST preserve the interactive container's `SIGINT → exit 130` stop path (the container stays
foreground; only the viewer is backgrounded). *Defense-in-depth:* the viewer also self-exits if the
loop's run-id/container disappears, covering the `kill -9` case where the trap never runs.

### D9 — One centerpiece: the churn-weighted Commit Ribbon
A left-to-right chain of turn-nodes that grows in real time: filled when `HEAD` advanced this turn,
hollow on a stall, **weighted by diff churn** computed host-side via `git show --numstat <sha>` (no
runner change, no stored field). Framed by a single X/N task arc (parsed from `tasks.md`) and a
**stakes strip** that lights only when live (rate-limit countdown from `paused.until`, a stall-pressure
meter from the promoted counters, review-round pips). `live.log` is a collapsible drawer, not a
primary pane. *Rationale:* a browser `tail -f` loses to the terminal; the ribbon renders the kit's
own "commit graph = progress" thesis as something worth leaving open.

### D10 — Per-loop in v1, designed for a per-host follow-up
Ship one dashboard per loop in v1, but the **run-id/epoch + the URL file** are designed so a future
per-host discovery dashboard (globbing `*/.ralph/`, project-keyed like vector-console) is a
non-breaking addition rather than a rewrite.

### D11 — Security is a first-class requirement, not a footnote
The viewer renders **agent-authored** text. It MUST escape every such field into the page, serve a
restrictive CSP, and validate the `Host` header against DNS-rebind to the loopback listener. The
listener shares the `GH_TOKEN` env-plane blast radius the kit already documents for the `gh`/notify
seams — **documented, not newly isolated**. The `127.0.0.1` bind is necessary but not sufficient.

### D12 — Testability within the kit's discipline
Phase 1 signals are tested in the existing stubbed-`claude` suite (assert `current.json` carries the
run-id, terminal halt class per exit path, the paused record around the limit/CI waits, and the
promoted counters). The viewer's **pure logic** (state derivation, liveness decision, ribbon data,
HTML escaping) is unit-tested against `.ralph/` fixtures; the socket/SSE/thread plumbing is covered
structurally (analogous to image contents covered by a smoke check, not the unit suite).

## Risks / Trade-offs

- **Kit now maintains a browser viewer** → single-source it (D2), keep it stdlib-only and small, and
  make it opt-in so the default loop carries none of it.
- **Makefile refactor could regress the SIGINT stop** (D8) → keep the container foreground, background
  only the viewer, and add an explicit test of the interrupt stop path.
- **Headless/SSH host: a loopback URL is unreachable remotely** (D7, Non-Goals) → document the tunnel;
  the remote summon path stays `RALPH_NOTIFY_CMD`.
- **Two-channel release coordination**: Phase 1 (runner) needs a base-image rebuild; the viewer ships
  in the image too (D3) → follow the existing release checklist; bump `plugin.json` and rebuild base.
- **XSS / secret-plane exposure via agent text** (D11) → escaping + CSP + Host-header validation as
  spec'd requirements, reviewed before merge.
- **Proportionality**: real cost for an aesthetic gain → opt-in default-off, Phase 1 stands alone, and
  the recipe fallback (D2) remains if the bundled viewer isn't judged worth it.

## Migration Plan

1. **Phase 1** ships first as an additive runner change (base-image rebuild). Inert if unread; it only
   adds fields and improves `/ralph-status` + notify.
2. **Phase 2** spikes D3 (placement), then builds the viewer + the `Makefile` wrapper + the
   `RALPH_DASHBOARD` opt-in key + docs; bump `plugin.json`.
3. **Rollback:** `RALPH_DASHBOARD` off disables Phase 2 entirely; Phase 1 fields are harmless if
   nothing reads them.

## Open Questions (resolved at Phase 2 kickoff)

- **D3a vs D3b** — **RESOLVED → D3a** (host-side image-extraction). See the D3 resolution above; the
  spike validated the extraction mechanic and host `python3`, and D3a preserves the no-port stance.
- **URL file location** — **RESOLVED → `.ralph/dashboard.url`** (travels with the workspace, already
  gitignored, consistent with the rest of `.ralph/`). A host cache path (`~/.cache/ralph/`) is the
  better substrate for a future per-host index (D10) but is not needed for the per-loop v1; the
  run-id/epoch in the URL file keeps that follow-up non-breaking.
- **Is the bundled viewer worth it vs the recipe fallback?** **Yes for v1**, gated by opt-in
  (default-off) + Phase 1 standing alone: the marginal cost is one stdlib-only baked file extracted at
  launch and a small Makefile wrapper, with the copy-paste recipe (D2) retained as the documented
  fallback if the viewer is later judged not worth the upkeep.
