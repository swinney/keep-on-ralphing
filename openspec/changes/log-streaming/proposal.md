## Why

Developing async — kick off a loop and walk away — needs realtime visibility into what the loop
is doing, but the harness is deaf in the outbound direction: `/ralph-status` is pull-only, and the
only continuous telemetry is split across per-turn `log/turn-N.txt` files that *omit the runner's own
narration* (the `ralph: turn N`, review-gate, and stall/halt lines go to the terminal only). The
structured feed (`status.jsonl`) is already aggregator-ready, but the human-readable stream is not.
The fix is to make the harness a first-class **log source** so an operator can point a standard
aggregator (Vector, Logstash, …) at the already-bind-mounted `.ralph/` and watch in realtime —
without the kit owning a dashboard or opening a network port, which would violate the deliberate
network-isolation and the anti-fan-out / single-orchestrator stances.

## What Changes

- **Aggregate `live.log` (runner).** The runner writes an append-only `RALPH_STATE_DIR/log/live.log`
  that interleaves the runner's orchestration narration **and** each turn's agent output into one
  stable tail target — the single file an aggregator (or a bare `tail -f`) follows across the whole
  run. Per-turn `turn-N.txt` files and `status.jsonl` are unchanged (purely additive).
- **Per-line turn correlation (runner).** Each line written to `live.log` is prefixed with its turn
  number (and an ISO-8601 timestamp) so an aggregator can filter, timeline, and correlate by turn
  without multiline-codec guesswork.
- **Vector recipe doc (kit reference).** A documented, copy-paste recipe: a Vector `file` source over
  `~/projects/*/.ralph/{status.jsonl,log/live.log}`, a VRL `remap` transform (`parse_json!` for the
  JSONL; derive a `project` field from the file path for multi-loop), and a `console` sink + `vector top`
  for a **zero-backend realtime view** — with a one-line note on swapping to an
  `elasticsearch`/`loki`/`datadog_logs` sink. Multi-loop "centralization" falls out of one glob + one
  VRL field; the kit ships **no** aggregation code.
- Non-breaking: untouched if no aggregator is attached; the new file is gitignored (under `.ralph/`)
  and additive; the offline test suite gains coverage but no new runtime dependency beyond what the
  base image already provides.

## Capabilities

### New Capabilities
- `log-streaming`: the runner emits an append-only, turn-correlated aggregate log (`live.log`) that
  merges runner narration with agent output as a single tail target, and the kit documents wiring an
  external aggregator (Vector, `console` sink) against the bind-mounted `.ralph/` — harness-as-source,
  no in-kit dashboard and no in-container network egress.

### Modified Capabilities
<!-- None. The new file lives under the already-gitignored .ralph/; /ralph-init scaffolding and the
     review/gate/bootstrap behaviors are unchanged. ralph-status MAY surface the live.log path, but
     that is a skill doc tweak, not a spec-level requirement change. -->

## Impact

- **Runner:** `base/scripts/ralph.sh` — a `narrate()` helper (echo to terminal **and** append a
  turn-prefixed line to `live.log`); the per-turn output pipe gains a prefixing stage writing to
  `live.log` while preserving `turn_ec=${PIPESTATUS[0]}` (the agent's exit code) and the usage-limit
  grep on `turn-N.txt`. Bash 3.2-safe; config precedence `environment > ralph.conf > default`.
- **Base image:** if the line-prefixer is a baked helper (see design), `base/Containerfile` ships it
  next to `until_reset.py` on PATH. No new network surface, no new port.
- **Templates / example:** `templates/ralph.conf.example` documents the live.log (and any toggle);
  `example/` (Acme Widgets) kept in sync as the golden reference.
- **Docs:** a new Vector recipe doc under `docs/` (kit reference, not scaffolded into consumers).
- **Tests:** `base/tests/` — `live.log` is created, append-only across turns, contains both narration
  and agent output, is turn-prefixed per line, and the prefixer does NOT break exit-code capture or
  usage-limit detection. Wired into `base/tests/run.sh` and the CLAUDE.md single-slice list.
- **Release:** runner change → **two-channel**: bump `.claude-plugin/plugin.json` AND rebuild the base
  image. A template/docs-only change would silently never reach a running loop.
- **Compatibility:** non-breaking and additive; loops with no aggregator attached behave as today.
