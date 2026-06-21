## Context

The runner (`base/scripts/ralph.sh`) already produces realtime, bind-mounted telemetry: per-turn
output is captured with `stdbuf -oL -eL … | tee "$log"` (line-buffered, so it tails live), and
`status.jsonl` is append-only newline-delimited JSON — already ideal for an aggregator's `json_lines`
parse. Two things keep the *human-readable* stream second-class for an aggregator: (1) the runner's
own narration (`ralph: turn N`, review-gate status, stall/halt lines) is printed to the terminal and
never lands in a file; (2) the captured output is split across `log/turn-N.txt` files with no per-line
turn correlation. This design adds a single append-only, turn-prefixed `live.log` and documents
tailing it (plus `status.jsonl`) into Vector — without giving the kit a dashboard or a network port.

Hard constraints carry over: the runner is agent-agnostic (the in-container agent stays
GitHub/network-blind; only the runner and an operator-run aggregator touch anything external),
bash 3.2-safe (no associative arrays; `printf %q` + `eval` config snapshot), and config precedence is
`environment > ralph.conf > default`. The base image runs Python 3.12 and already ships a Python
helper (`until_reset.py`) on PATH.

## Goals / Non-Goals

**Goals:**
- One stable, append-only tail target (`live.log`) carrying runner narration **and** agent output.
- Per-line turn correlation (turn number + ISO-8601 timestamp) so an aggregator can filter/timeline by turn.
- Zero regression to turn-outcome detection (agent exit code via `PIPESTATUS`; usage-limit grep).
- A copy-paste Vector recipe (console sink + `vector top`; multi-loop via glob + VRL) as kit reference docs.

**Non-Goals:**
- No in-kit network endpoint, dashboard, or team console (violates the deliberate network-isolation).
- No push-from-container sink in v1 (the `RALPH_LOG_SINK` http/tcp push seam is future work for when no
  host-side shipper is possible, e.g. an ephemeral CI runner).
- No multi-loop aggregation machinery in the kit — it is one Vector `file`-source glob plus a derived
  `project` field; a recipe, not code.
- No change to `status.jsonl` (already aggregator-ready) or to the per-turn `turn-N.txt` files.
- The sibling `RALPH_NOTIFY_CMD` event-notification thread is out of scope here.

## Decisions

### D1 — One append-only `live.log` alongside the per-turn files
Add `RALPH_STATE_DIR/log/live.log` as the single tail target; keep `turn-N.txt` and `status.jsonl`
untouched. *Why:* a tailer wants one stable file, not a new file per turn; but `turn-N.txt` is the
target the usage-limit grep already reads and the per-turn artifact `/ralph-status` references, so it
stays. Two complementary streams: `status.jsonl` = structured turn records; `live.log` = the
human-readable narrative.

### D2 — Line-prefixer is a small baked Python helper (e.g. `ralph_prefix.py`)
A one-process, line-buffered reader that reads stdin and writes `"<ISO-8601> turn=<n> | <line>"` to
stdout, flushing per line. Baked onto PATH in `base/Containerfile` next to `until_reset.py`. *Why
Python over alternatives:* (a) `date` per line is a fork-per-line storm — rejected; (b) `awk strftime`
is not portable to busybox awk — rejected; (c) turn-only prefix with the aggregator stamping ingest
time is viable but loses emit-time fidelity for a bare `tail -f`, and the operator explicitly chose a
per-line ISO timestamp — so emit-time wins. Python 3.12 is guaranteed in the base image and the
`until_reset.py` precedent makes a second tiny helper in-grain. (The runner script itself stays
bash 3.2-safe; the helper runs in-container where Python exists.)

### D3 — Pipe ordering preserves `PIPESTATUS` and the usage-limit grep
The hot path becomes:
```
stdbuf -oL -eL timeout -k 30 "$turn_timeout" claude … 2>&1 \
  | tee "$log" \
  | python3 /usr/local/bin/ralph_prefix.py "$turn" >> "$live"
turn_ec=${PIPESTATUS[0]}
```
In a three-stage pipe `${PIPESTATUS[0]}` is still the agent stage, so exit-code detection is
unchanged. `tee` writes the **raw** (unprefixed) output to `turn-N.txt` *before* the prefixer, so the
usage-limit grep — which reads `turn-N.txt` — sees byte-identical content to today. The prefixer is the
terminal stage; its own exit code is irrelevant. *Why this ordering:* prefixing before `tee` would
change what `turn-N.txt` and the grep observe — rejected.

### D4 — Runner narration via a `narrate()` helper
Introduce `narrate "msg"` that (a) echoes to the terminal exactly as the current `echo "ralph: …"`
does and (b) appends one turn-prefixed line to `live.log` (reusing the same prefix format as D2, via a
shell-side formatter so no pipe is needed for single lines). Convert the existing terminal-only
`echo "ralph: …"` / review-gate / stall lines to `narrate`. *Why:* narration is the missing half of
the story for a tailer; a helper unifies it without duplicating every call site. Ordering is safe
because narration happens **between** turns while the agent pipe is idle — writes to `live.log` are
sequential within the single runner process, so no locking is needed; the pipeline drains before the
next statement runs.

### D5 — Always-on, with a documented off-switch
`live.log` is written by default. Honor `RALPH_LIVE_LOG` (default `1`) through the standard precedence
so an operator can set `RALPH_LIVE_LOG=0` to suppress it. *Why default-on:* it is a cheap, gitignored,
strictly-additive file and the realtime-visibility use case is the point; *why an off-switch at all:*
everything else in the runner is a config key, and a disk-constrained or privacy-sensitive operator
deserves the escape hatch — consistent with `environment > ralph.conf > default`.

### D6 — Vector recipe ships as a kit reference doc, not scaffolded
A new `docs/` recipe: a Vector `file` source over `~/projects/*/.ralph/{status.jsonl,log/live.log}`, a
`remap` (VRL) transform (`. = parse_json!(.message)` for the JSONL; derive `.project` from the `.file`
path for multi-loop), and a `console` sink + `vector top` for the zero-backend realtime view, with a
one-line note that swapping to `elasticsearch`/`loki`/`datadog_logs` is a sink change. *Why docs not
scaffold:* the aggregator is optional external tooling; scaffolding it into every consumer (like
`STATUS.md`/`questions.md`) would add noise to projects that never attach one.

## Risks / Trade-offs

- **Prefixer becomes a fork-per-line hotspot** → one long-lived, line-buffered Python process (D2),
  not a per-line `date`/`awk` fork.
- **`PIPESTATUS` / usage-limit regression** → pipe ordering keeps `[0]` = agent and `turn-N.txt` raw
  (D3); covered by a test asserting a non-zero agent exit and a usage-limit message are still detected
  with the aggregate log active.
- **Narration/agent-output interleaving or partial flushes** → sequential single-process writes with
  the agent pipe drained before post-turn narration (D4); no concurrent writers, so no locking.
- **Timestamp portability** → Python (base-image guaranteed), not `awk strftime`/busybox (D2).
- **`live.log` grows unbounded over a long run** → accepted; it is gitignored and per-workspace, like
  `status.jsonl`. Rotation/truncation is the aggregator's or operator's job (truncate between runs),
  explicitly out of scope.
- **Two-channel release friction** → a runner + base-image change reaches a loop only after a base
  rebuild; without it the prefixer/narration silently never appear. Tasks call out the plugin bump +
  rebuild.

## Migration Plan

Additive and non-breaking. New loops emit `live.log` by default; existing tooling is unaffected
(`turn-N.txt`, `status.jsonl`, `/ralph-status` unchanged). Rollback is `RALPH_LIVE_LOG=0` or reverting
the runner; the new file is already gitignored under `.ralph/`. Reaching a running machine requires the
standard two-channel step: bump `.claude-plugin/plugin.json` and rebuild the base image
(`make build-base` / `/ralph-build-base`).

## Open Questions

- **Timestamp source** — pinned to emit-time via the Python prefixer (D2) per the operator's
  selection; revisit only if the prefixer proves a hotspot, in which case fall back to turn-only
  prefix + aggregator ingest timestamp.
- **`live.log` rotation** — left to the operator/aggregator for v1; revisit if long unattended runs
  make the file unwieldy.
- **`ralph-status` surfacing** — whether `/ralph-status` should print the `live.log` path and a
  `tail -f` hint is a skill doc tweak (not a spec requirement); decide during tasks.
