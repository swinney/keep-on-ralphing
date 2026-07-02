# Recipe: the ephemeral progress dashboard

A glanceable, always-fresh web view of a running loop — the churn-weighted **Commit
Ribbon**, an **X/N task arc**, and a **stakes strip** (rate-limit countdown, stall-pressure
meter, review-round pips) that lights only while the loop is live. It auto-launches with
`make loop` and tears itself down when the loop ends.

It is **opt-in and off by default**. The loop itself is unchanged unless you enable it.

## Enable it

Set the key in `ralph.conf` (or per-run in the environment — `env > ralph.conf > default`):

```sh
# ralph.conf
RALPH_DASHBOARD="1"
```

```sh
# or just this run:
RALPH_DASHBOARD=1 make loop
```

On start you'll see one line:

```
Dashboard: http://127.0.0.1:53187
```

The port is OS-assigned (`127.0.0.1:0`), so concurrent loops never collide. The URL is also
written to **`.ralph/dashboard.url`** so it survives the terminal scrolling — recover it with:

```sh
cat .ralph/dashboard.url
```

The page updates live (Server-Sent Events); a tab that slept and reconnected re-derives full
state, so you never miss intervening turns.

## How it runs (and why the container stays port-free)

The dashboard runs **host-side**. `make loop` extracts the stdlib-only viewer from the loop
image to a host temp path and runs it with your **host `python3`** against the bind-mounted,
host-native `.ralph/`. The loop **container opens no port** — the kit's "log source, not a
service" stance is intact. Liveness is read honestly from the run-id plus whether the loop
container is actually running (`podman ps`), so a finished loop shows its halt class, a paused
loop shows "paused, resumes …", and a process that vanished without a clean exit reads as
"killed (inferred)" — never as still running.

Requirements: a host `python3` (3.7+). If it is absent, the dashboard is **skipped with a
warning and the loop runs normally** — it never fails the loop.

## Teardown

The dashboard stops and frees its port when the loop process exits for **any** reason —
project complete, any halt, or `Ctrl-C`. The interrupt stop path is unchanged: the container
stays foreground, only the viewer is backgrounded, so `Ctrl-C` still stops the loop with exit
130. A `kill -9` of the loop (where the teardown trap never runs) is also covered — the viewer
self-exits once it sees the loop container is gone.

## Headless / SSH hosts

The URL is **loopback only** — it is not reachable from another machine. On a remote loop
host, forward the port over SSH from your laptop, reading the assigned port from the URL file:

```sh
# on the loop host
PORT=$(sed 's#.*:##' .ralph/dashboard.url)
# on your laptop
ssh -N -L "$PORT:127.0.0.1:$PORT" you@loop-host
# then open http://127.0.0.1:$PORT locally
```

For "come look, the loop needs you" pings while you're away, use the
[`RALPH_NOTIFY_CMD`](slack-notify.md) seam — that, not the dashboard, is the remote summon path.

## Fallback: no bundled viewer

If you'd rather not run the bundled dashboard, the loop's state is plain files under `.ralph/`
and you can build your own view the same way the [vector-console recipe](vector-console.md)
tails `live.log` — the structured `current.json` / `status.jsonl` (run-id, halt class, paused
record, counters) are a stable, honest substrate to read from your own pipeline.
