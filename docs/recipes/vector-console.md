# Recipe: watch Ralph loops in realtime with Vector (zero backend)

The Ralph harness is a **log source**, not a log service: it writes plain files under the
bind-mounted, gitignored `RALPH_STATE_DIR` (`.ralph/`), and you point your own aggregator at them.
Nothing here is built into the kit — this is a copy-paste starting point. The container stays
network-isolated; the aggregator runs **on the host**, tailing the bind-mounted files.

This recipe uses [Vector](https://vector.dev) with a `console` sink, so you get a live, structured
view with **no Elasticsearch/Loki/Datadog to stand up**. Swap the sink later (one block) when you want
storage and dashboards.

## What the harness emits

| File (under `.ralph/`) | Format | Use |
|---|---|---|
| `status.jsonl` | one JSON object per turn | structured turn timeline (turn, model, exit_code, committed, sha, subject) |
| `log/live.log` | text, `‹ISO-ts› turn=‹n› | ‹line›` per line | the human-readable narrative (runner narration + agent output), turn-correlated |
| `log/turn-‹n›.txt` | raw per-turn text | unchanged; not needed for this recipe |

`live.log` requires `RALPH_LIVE_LOG=1` (the default). `status.jsonl` is always written.

> **Two file types → two sources.** `status.jsonl` is JSON and `live.log` is plain text. Do **not**
> tail both through one source with a blanket `parse_json!` — it aborts on every `live.log` line and
> drops events. Use the two sources below (or one source with a path-keyed conditional).

## `vector.toml`

```toml
# Run on the HOST (not in the container). One Vector instance can watch every loop
# on the box via the globs below; `.project` is derived from each file's path.

data_dir = "/tmp/vector-ralph"   # checkpoint/offset store

# --- sources: one per file type -------------------------------------------------

[sources.ralph_status]
type    = "file"
include = ["/home/you/projects/*/.ralph/status.jsonl"]   # glob across all loops

[sources.ralph_live]
type    = "file"
include = ["/home/you/projects/*/.ralph/log/live.log"]
# A turn's last lines arrive slightly after the line is written (the runner's
# prefixer is async); that is expected.

# --- transforms -----------------------------------------------------------------

# status.jsonl: parse the JSON, keep the source path, tag the project.
[transforms.status_parse]
type   = "remap"
inputs = ["ralph_status"]
source = '''
  src = string!(.file)
  parsed, err = parse_json(string!(.message))
  if err != null {
    log("ralph status.jsonl: skipping non-JSON line: " + err, level: "warn")
  } else {
    . = object!(parsed)
    .file = src
  }
  proj, e = parse_regex(src, r'/(?P<name>[^/]+)/\.ralph/')
  .project = if e == null { proj.name } else { "unknown" }
  .stream  = "status"
'''

# live.log: lift the "‹ts› turn=‹n› | ‹line›" prefix into fields. Never parse_json here.
[transforms.live_parse]
type   = "remap"
inputs = ["ralph_live"]
source = '''
  src = string!(.file)
  m, err = parse_regex(string!(.message), r'^(?P<ts>\S+) turn=(?P<turn>\S+) \| (?P<line>.*)$')
  if err == null {
    .turn    = to_int(m.turn) ?? m.turn
    .message = m.line
    ts, terr = parse_timestamp(m.ts, "%+")
    if terr == null { .timestamp = ts }
  }
  proj, e = parse_regex(src, r'/(?P<name>[^/]+)/\.ralph/')
  .project = if e == null { proj.name } else { "unknown" }
  .stream  = "live"
'''

# --- sink: console (zero backend) ----------------------------------------------

[sinks.console]
type    = "console"
inputs  = ["status_parse", "live_parse"]
encoding.codec = "json"     # or "text" for a plain tail-like view
```

Run it and watch:

```sh
vector --config vector.toml     # streams every loop's events to your terminal
vector top --config vector.toml # live throughput TUI (per-source rates, errors)
```

## Going from console to a real store

Keep everything above; replace only the sink. For example, Elasticsearch:

```toml
[sinks.es]
type      = "elasticsearch"
inputs    = ["status_parse", "live_parse"]
endpoints = ["http://localhost:9200"]
bulk.index = "ralph-%Y.%m.%d"
```

`loki` (`type = "loki"`, label on `.project`/`.stream`) and `datadog_logs` (`type = "datadog_logs"`)
are the same one-block swap — Vector is by Datadog, so `datadog_logs` is first-class.

## Multi-loop "centralization"

There is none to install. The globs (`/home/you/projects/*/.ralph/...`) already match every loop on
the host, and `.project` (derived from each file's path) keeps them separable in one place. Aggregation
lives entirely in **your** Vector config — the kit ships no dashboard, no endpoint, and no aggregation
code.

## When you can't run a host-side shipper

If the loop runs somewhere you can't tail the bind-mount (e.g. an ephemeral CI runner), a
push-from-the-runner sink (`RALPH_LOG_SINK`, posting to Vector's `http`/`socket` source) is the
fallback. That seam is **not** built yet — file-tailing is the supported path because it keeps the
container network-isolated. See the `log-streaming` design notes for the future push seam.
