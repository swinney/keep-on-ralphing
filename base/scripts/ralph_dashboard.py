#!/usr/bin/env python3
"""Ephemeral progress dashboard for a running Ralph loop (single-sourced, stdlib-only).

Per design D3a, this viewer is baked into the base image, extracted to a HOST temp
path by the loop launcher, and run with HOST python3 against the bind-mounted,
host-native .ralph/ — the container itself opens no port. This file holds two layers:

  * PURE logic (state derivation, the liveness decision, ribbon data, HTML escaping)
    — unit-tested in base/tests/test_dashboard.py against .ralph/ fixtures.
  * The HTTP/SSE server plumbing — covered structurally/by smoke, not the unit suite
    (D12), added below the pure core.

Liveness (D4): a loop is live only when its run identity is current AND its container
is actually running. .ralph/ is never cleared between runs, so a record alone cannot
say "live"; and the EXIT trap does not fire on SIGKILL/OOM, so a non-terminal state
with a vanished container is "killed" — inferred, never shown as running.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# The terminal halt classes the runner writes in its EXIT trap (Phase 1). A state in
# this set means the loop ENDED and names why; anything else is a live/pre-turn state.
TERMINAL_CLASSES = frozenset(
    {"complete", "blocked", "review-exhausted", "stall", "sigint"}
)
# Non-terminal states the runner writes while a loop is alive.
LIVE_STATES = frozenset({"starting", "running", "idle"})
# Phases a reader should treat as "the loop is live right now".
_LIVE_PHASES = frozenset({"starting", "running", "idle", "paused"})

_TASK_RE = re.compile(r"^\s*[-*] \[([ xX])\]")


def read_json(path):
    """Load a JSON file; return its object, or None if absent/unreadable/corrupt."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def parse_task_progress(path):
    """Count Markdown checkbox tasks in `path` → {"done", "total"} (0/0 if missing)."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return {"done": 0, "total": 0}
    done = total = 0
    for line in text.splitlines():
        m = _TASK_RE.match(line)
        if not m:
            continue
        total += 1
        if m.group(1) in ("x", "X"):
            done += 1
    return {"done": done, "total": total}


def escape_field(value):
    """Render an agent-authored field inert for HTML (D11). None → empty string."""
    if value is None:
        return ""
    return html.escape(str(value), quote=True)


def classify_phase(current, container_running, expected_run_id=None):
    """The liveness decision (D4): run-id match AND container-running.

    Returns one of: none | starting | running | idle | paused | ended | killed.
      * no heartbeat            → "none"
      * run_id != the latched live run → "ended" (stale leftover or replaced)
      * terminal halt class     → "ended" (the loop wrote why it stopped)
      * container running       → the live state ("paused" when a pause is recorded)
      * non-terminal + no container → "killed" (vanished without a terminal write)
    """
    if not current:
        return "none"
    # Run-id fencing: once we've latched the live run's id, a current.json showing a
    # DIFFERENT run means the run we track is gone (stale prior-run leftover, or a new
    # loop replaced it) — never live. .ralph/ is never cleared, so this is the guard.
    if expected_run_id and current.get("run_id") and current.get("run_id") != expected_run_id:
        return "ended"
    state = current.get("state") or ""
    if state in TERMINAL_CLASSES:
        return "ended"
    if container_running:
        if current.get("paused"):
            return "paused"
        return state if state in LIVE_STATES else "running"
    return "killed"


def read_status(state_dir):
    """Parse status.jsonl into a list of per-turn records (oldest first); [] if absent."""
    records = []
    try:
        with open(os.path.join(state_dir, "status.jsonl"), encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except ValueError:
                    continue  # skip a torn final line (append feed read mid-write)
    except OSError:
        return []
    return records


def git_churn(sha, cwd=None):
    """Total changed lines (added + deleted) for a commit, host-side via git.

    Computed from `git show --numstat` so the ribbon weights need no stored field and
    no runner change (D9). Returns 0 on any error or a binary-only diff ("-" counts).
    """
    if not sha:
        return 0
    try:
        out = subprocess.run(
            ["git", "show", "--numstat", "--format=", sha],
            cwd=cwd, capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return 0
    if out.returncode != 0:
        return 0
    total = 0
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            for n in parts[:2]:
                if n.isdigit():
                    total += int(n)
    return total


def ribbon_data(status_records, churn_fn=None):
    """Per-turn Commit-Ribbon nodes (D9): filled on a commit, hollow on a stall,
    weighted by diff churn. churn_fn is injected (the real one is git_churn) so the
    shape is unit-testable without a repo; only committed turns get a non-zero churn.
    """
    nodes = []
    for r in status_records:
        committed = bool(r.get("committed"))
        sha = r.get("sha")
        churn = churn_fn(sha) if (committed and sha and churn_fn) else 0
        nodes.append({
            "turn": r.get("turn"),
            "committed": committed,
            "sha": sha,
            "subject": r.get("subject"),
            "churn": churn,
        })
    return nodes


def derive_state(state_dir, container_running, tasks_path=None, now_epoch=None,
                 expected_run_id=None, current=None):
    """Derive the full dashboard snapshot from the structured state files + task list.

    Facts come from current.json / status.jsonl / tasks.md — never from log scraping
    (the spec's "derives facts from structured state" requirement). expected_run_id
    fences a stale/replaced run (D4); current may be passed in to avoid a re-read.
    """
    if current is None:
        current = read_json(os.path.join(state_dir, "current.json"))
    phase = classify_phase(current, container_running, expected_run_id)
    cur = current or {}
    # Only label a halt class when the ended record is THIS run's (not a stale leftover).
    run_matches = (not expected_run_id) or (cur.get("run_id") == expected_run_id)
    if tasks_path is None:
        tasks_path = os.path.join(os.path.dirname(os.path.abspath(state_dir)), "tasks.md")
    return {
        "run_id": cur.get("run_id"),
        "run_started": cur.get("run_started"),
        "phase": phase,
        "live": phase in _LIVE_PHASES,
        "halt_class": cur.get("state") if (phase == "ended" and run_matches) else None,
        "paused": cur.get("paused") if phase == "paused" else None,
        "turn": cur.get("turn") or 0,
        "task": cur.get("task") or "",
        "model": cur.get("model") or "default",
        "sha": cur.get("sha"),
        "subject": cur.get("subject"),
        "committed": bool(cur.get("committed")),
        "blocked": bool(cur.get("blocked")),
        "blocked_reason": cur.get("blocked_reason"),
        "stalls": cur.get("stalls") or 0,
        "max_stalls": cur.get("max_stalls") or 0,
        "review_round": cur.get("review_round") or 0,
        "review_max": cur.get("review_max") or 0,
        "task_progress": parse_task_progress(tasks_path),
    }


def tail_live_log(state_dir, limit=200):
    """Last `limit` RAW lines of the aggregate log, for the activity drawer only.

    Returns raw text — callers escape on the way into HTML (render_page) or render via
    textContent (the JS). The log feeds ONLY the activity view, never structured facts
    (the spec's "aggregate log feeds only the activity view" requirement).
    """
    path = os.path.join(state_dir, "log", "live.log")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return []
    return [ln.rstrip("\n") for ln in lines[-limit:]]


# ============================================================================
# HTTP / SSE server (D5/D6/D7/D11). Per D12 this plumbing is covered by a smoke
# test + the security checks, not the pure-logic unit suite above.
# ============================================================================

# Restrictive CSP (D11): no external loads at all; scripts/styles only from us, the
# SSE channel only to 'self'. Combined with escaping + textContent rendering, agent
# text cannot execute or exfiltrate.
CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; "
    "connect-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'"
)
SSE_POLL_SECONDS = 1.0
SSE_HEARTBEAT_SECONDS = 15.0


def container_is_running(runtime, container):
    """True if the loop's container is up — the honest liveness source /ralph-status uses."""
    if not runtime or not container:
        return False
    try:
        out = subprocess.run(
            [runtime, "ps", "--filter", "name=^" + re.escape(container) + "$",
             "--format", "{{.Names}}"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return container in out.stdout.split()


def render_page(snapshot):
    """Server-render the initial page with EVERY agent-authored field escaped (D11), so
    first paint and no-JS use are safe; the JS then live-updates via textContent."""
    tp = snapshot.get("task_progress") or {"done": 0, "total": 0}
    head = (
        "<header><h1>Ralph</h1>"
        "<span class=phase data-phase=\"" + escape_field(snapshot.get("phase")) + "\">"
        + escape_field(snapshot.get("phase")) + "</span>"
        "<span class=run>run " + escape_field(snapshot.get("run_id")) + "</span></header>"
    )
    sub = escape_field(snapshot.get("subject"))
    meta = (
        "<section id=meta>turn <b id=turn>" + escape_field(snapshot.get("turn")) + "</b>"
        " · model <span id=model>" + escape_field(snapshot.get("model")) + "</span>"
        " · tasks <b id=tasks>" + escape_field(tp["done"]) + "/" + escape_field(tp["total"]) + "</b>"
        " · last <span id=subject>" + sub + "</span></section>"
    )
    activity = "\n".join(escape_field(ln) for ln in (snapshot.get("activity") or []))
    body = (
        head + meta
        + "<section id=taskbar aria-label='task progress'><div id=taskfill></div>"
        + "<span id=tasklabel></span></section>"
        + "<div class=ribbonwrap><div class=caption>commit ribbon"
        + " <em>· bar height = diff churn · hollow = stall</em></div>"
        + "<section id=ribbon aria-label='commit ribbon'></section></div>"
        + "<section id=stakes></section>"
        + "<details id=logbox><summary>activity log</summary>"
        + "<pre id=activity>" + activity + "</pre></details>"
        # Escape "<" in the embedded JSON so agent text containing "</script>" cannot
        # break out of the bootstrap block (< is still valid JSON).
        + "<script type=application/json id=bootstrap>"
        + json.dumps(snapshot).replace("<", "\\u003c") + "</script>"
        + "<script src=/app.js></script>"
    )
    return (
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        "<title>Ralph dashboard</title><link rel=stylesheet href=/app.css></head>"
        "<body>" + body + "</body></html>"
    )


class _DashboardServer(ThreadingHTTPServer):
    daemon_threads = True  # teardown never hangs on a held SSE stream (D6)
    allow_reuse_address = True


class _Handler(BaseHTTPRequestHandler):
    server_version = "ralph-dashboard"
    protocol_version = "HTTP/1.0"  # connection-close per response; SSE reconnect = D5 resync

    def log_message(self, *args):  # silence default stderr access logging
        pass

    def _host_ok(self):
        # DNS-rebind defense (D11): only the loopback bind is an acceptable Host.
        return self.headers.get("Host", "") in self.server.allowed_hosts

    def _send(self, code, body=b"", ctype="text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _snapshot(self):
        s = self.server
        running = container_is_running(s.runtime, s.container)
        current = read_json(os.path.join(s.state_dir, "current.json"))
        # Latch the live run's id (D4): the first running, non-terminal run we see IS
        # this run. The runner stamps a fresh run_id at startup, so the live loop's
        # current.json carries a non-terminal state quickly; a later mismatch then
        # reads as ended (stale leftover / replaced).
        rid = (current or {}).get("run_id")
        # Latch the live run's id ONCE. Re-latching every snapshot would adopt a
        # REPLACING run's id (a new loop reusing the container name) as live and
        # defeat the fencing — so only set it while still unlatched.
        if (s.expected_run_id is None and running and rid
                and (current or {}).get("state") not in TERMINAL_CLASSES):
            s.expected_run_id = rid
        snap = derive_state(s.state_dir, running, tasks_path=s.tasks_path,
                            expected_run_id=s.expected_run_id, current=current)
        snap["ribbon"] = ribbon_data(
            read_status(s.state_dir), churn_fn=lambda sha: git_churn(sha, cwd=s.workspace)
        )
        snap["activity"] = tail_live_log(s.state_dir, 200)
        return snap

    def do_GET(self):
        if not self._host_ok():
            self._send(403, b"forbidden host\n", "text/plain; charset=utf-8")
            return
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            self._send(200, render_page(self._snapshot()).encode())
        elif path == "/app.css":
            self._send(200, APP_CSS.encode(), "text/css; charset=utf-8")
        elif path == "/app.js":
            self._send(200, APP_JS.encode(), "application/javascript; charset=utf-8")
        elif path == "/state":
            body = json.dumps(self._snapshot()).replace("<", "\\u003c").encode()
            self._send(200, body, "application/json; charset=utf-8")
        elif path == "/events":
            self._stream_events()
        else:
            self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def _stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        last = None
        last_beat = time.monotonic()
        stop = self.server.stop_event
        try:
            while not stop.is_set():
                payload = json.dumps(self._snapshot()).replace("<", "\\u003c")
                if payload != last:
                    self.wfile.write(("data: " + payload + "\n\n").encode())
                    self.wfile.flush()
                    last = payload
                    last_beat = time.monotonic()
                elif time.monotonic() - last_beat > SSE_HEARTBEAT_SECONDS:
                    self.wfile.write(b": heartbeat\n\n")  # detect dead one-way client (D6)
                    self.wfile.flush()
                    last_beat = time.monotonic()
                stop.wait(SSE_POLL_SECONDS)
        except (BrokenPipeError, ConnectionResetError, OSError):
            return  # client tab closed — reap quietly (D6)


def make_server(state_dir, workspace, runtime, container, tasks_path=None, port=0):
    httpd = _DashboardServer(("127.0.0.1", port), _Handler)
    bound = httpd.server_address[1]
    httpd.state_dir = state_dir
    httpd.workspace = workspace
    httpd.runtime = runtime
    httpd.container = container
    httpd.tasks_path = tasks_path
    httpd.expected_run_id = None  # latched on the first running, non-terminal snapshot (D4)
    httpd.stop_event = threading.Event()
    httpd.allowed_hosts = frozenset(
        {"127.0.0.1:%d" % bound, "localhost:%d" % bound}
    )
    return httpd


def _watch_teardown(server, grace=3):
    """Defense-in-depth (D8/4.10): if the loop container vanishes (kill -9, where the
    Makefile trap never ran), shut the viewer down so no orphan listener lingers."""
    seen_live = False
    misses = 0
    while not server.stop_event.is_set():
        rid = (read_json(os.path.join(server.state_dir, "current.json")) or {}).get("run_id")
        replaced = bool(server.expected_run_id and rid and rid != server.expected_run_id)
        if container_is_running(server.runtime, server.container) and not replaced:
            seen_live, misses = True, 0
        elif seen_live:
            misses += 1
            if misses >= grace:
                server.stop_event.set()
                threading.Thread(target=server.shutdown, daemon=True).start()
                return
        server.stop_event.wait(2)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ephemeral Ralph loop dashboard (host-side).")
    ap.add_argument("--state-dir", default=".ralph")
    ap.add_argument("--workspace", default=".")
    ap.add_argument("--runtime", default="podman")
    ap.add_argument("--container", default="ralph-loop")
    ap.add_argument("--tasks", default=None)
    ap.add_argument("--url-file", default=None)
    ap.add_argument("--open", action="store_true", help="open a browser (default off; $BROWSER-respecting)")
    ap.add_argument("--port", type=int, default=0)
    args = ap.parse_args(argv)

    server = make_server(args.state_dir, args.workspace, args.runtime, args.container,
                         tasks_path=args.tasks, port=args.port)
    port = server.server_address[1]
    url = "http://127.0.0.1:%d" % port
    print("Dashboard: " + url, flush=True)
    url_file = args.url_file or os.path.join(args.state_dir, "dashboard.url")
    try:
        os.makedirs(os.path.dirname(url_file) or ".", exist_ok=True)
        with open(url_file, "w", encoding="utf-8") as f:
            f.write(url + "\n")
    except OSError:
        pass
    if args.open:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    threading.Thread(target=_watch_teardown, args=(server,), daemon=True).start()
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.stop_event.set()
    return 0


APP_CSS = """
:root{--bg:#070a10;--panel:#0e1320;--fg:#dbe4f0;--dim:#6b7c93;--line:#1a2333;
--ok:#42d977;--ok2:#2ea043;--hollow:#1c2636;--warn:#f0b429;--bad:#ff5d5d;--accent:#6ea8ff}
*{box-sizing:border-box}
html,body{height:100%}
body{margin:0;color:var(--fg);font:15px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;
background:radial-gradient(1200px 600px at 15% -10%,#11203a 0%,transparent 55%),
radial-gradient(900px 500px at 100% 0%,#1a1330 0%,transparent 50%),var(--bg);
background-attachment:fixed}
header{display:flex;align-items:center;gap:16px;padding:20px 26px;border-bottom:1px solid var(--line)}
header h1{margin:0;font-size:22px;font-weight:800;letter-spacing:.22em;
background:linear-gradient(90deg,#7cc0ff,#9b8cff);-webkit-background-clip:text;background-clip:text;color:transparent}
.phase{padding:5px 16px;border-radius:999px;background:var(--panel);text-transform:uppercase;
font-size:12px;font-weight:700;letter-spacing:.14em;border:1px solid var(--line)}
.phase[data-phase=running],.phase[data-phase=starting]{background:#0c2a18;color:var(--ok);
border-color:#1c5733;box-shadow:0 0 0 0 rgba(66,217,119,.5);animation:pulse 2s infinite}
.phase[data-phase=paused]{background:#33280a;color:var(--warn);border-color:#5c4710}
.phase[data-phase=ended]{background:var(--panel);color:var(--dim)}
.phase[data-phase=killed],.phase[data-phase=blocked]{background:#360f0f;color:var(--bad);border-color:#5e1c1c}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(66,217,119,.45)}70%{box-shadow:0 0 0 10px rgba(66,217,119,0)}100%{box-shadow:0 0 0 0 rgba(66,217,119,0)}}
.run{margin-left:auto;color:var(--dim);font-size:13px;letter-spacing:.05em}
#meta{padding:16px 26px 6px;color:var(--dim);font-size:14px}#meta b{color:var(--fg)}#meta #subject{color:var(--accent)}
#taskbar{position:relative;height:26px;margin:8px 26px 4px;background:var(--panel);
border:1px solid var(--line);border-radius:8px;overflow:hidden}
#taskfill{height:100%;width:0;background:linear-gradient(90deg,var(--ok2),var(--ok));
transition:width .6s cubic-bezier(.2,.8,.2,1)}
#tasklabel{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
font-size:12px;font-weight:700;letter-spacing:.08em;color:#eaf2ff;text-shadow:0 1px 2px #000}
.ribbonwrap{padding:18px 26px 4px}
.caption{color:var(--dim);font-size:12px;margin-bottom:10px;letter-spacing:.04em}.caption em{color:#46566e;font-style:normal}
#ribbon{display:flex;align-items:flex-end;gap:7px;flex-wrap:wrap;min-height:120px}
.node{width:18px;border-radius:5px 5px 2px 2px;background:var(--hollow);position:relative;
border:1px solid #232f43;transition:height .5s cubic-bezier(.2,.8,.2,1)}
.node.commit{background:linear-gradient(180deg,var(--ok),var(--ok2));border-color:#1c5733;
box-shadow:0 0 10px rgba(66,217,119,.35)}
.node.enter{animation:grow .55s cubic-bezier(.2,.9,.2,1)}
@keyframes grow{from{transform:scaleY(.05);opacity:.2}to{transform:scaleY(1);opacity:1}}
.node{transform-origin:bottom}
.node:hover::after{content:attr(data-tip);position:absolute;bottom:108%;left:50%;transform:translateX(-50%);
white-space:nowrap;background:#0a1422;color:var(--fg);padding:6px 10px;border-radius:6px;font-size:12px;
border:1px solid var(--line);z-index:3;box-shadow:0 6px 20px rgba(0,0,0,.5)}
#stakes{display:flex;gap:28px;align-items:center;padding:14px 26px 20px;flex-wrap:wrap;color:var(--dim);font-size:13px}
.countdown{padding:6px 14px;border-radius:999px;background:#33280a;color:var(--warn);
border:1px solid #5c4710;font-weight:700;animation:pulse-w 2s infinite}
@keyframes pulse-w{0%{box-shadow:0 0 0 0 rgba(240,180,41,.4)}70%{box-shadow:0 0 0 9px rgba(240,180,41,0)}100%{box-shadow:0 0 0 0 rgba(240,180,41,0)}}
.meter{height:9px;width:150px;background:var(--hollow);border-radius:6px;overflow:hidden;display:inline-block;vertical-align:middle;margin-left:8px;border:1px solid #232f43}
.meter>span{display:block;height:100%;background:linear-gradient(90deg,var(--warn),var(--bad));transition:width .5s}
.pip{display:inline-block;width:11px;height:11px;border-radius:50%;background:var(--hollow);margin-left:5px;border:1px solid #232f43;vertical-align:middle}
.pip.on{background:var(--accent);box-shadow:0 0 8px rgba(110,168,255,.6);border-color:var(--accent)}
#logbox{margin:4px 26px 30px;border:1px solid var(--line);border-radius:10px;background:rgba(14,19,32,.6)}
#logbox summary{cursor:pointer;padding:10px 14px;color:var(--dim);user-select:none}
#logbox[open] summary{border-bottom:1px solid var(--line)}
#activity{margin:0;padding:14px;max-height:340px;overflow:auto;white-space:pre-wrap;font-size:12.5px;line-height:1.6;color:#9fb0c3}
"""

APP_JS = r"""
'use strict';
function $(id){return document.getElementById(id);}
function txt(el,v){if(el)el.textContent=(v==null?'':String(v));}
var prevTurns=-1; // track ribbon length to animate only genuinely-new nodes
function render(s){
  if(!s)return;
  var ph=document.querySelector('.phase');
  if(ph){ph.dataset.phase=s.phase||'';txt(ph,s.phase||'');}
  txt($('turn'),s.turn);txt($('model'),s.model);txt($('subject'),s.subject||'—');
  var tp=s.task_progress||{done:0,total:0};txt($('tasks'),tp.done+'/'+tp.total);
  // Task progress bar.
  var pct=tp.total?Math.round(100*tp.done/tp.total):0;
  $('taskfill').style.width=pct+'%';
  txt($('tasklabel'),tp.done+' / '+tp.total+' tasks  ·  '+pct+'%');
  // Commit Ribbon: filled gradient node on a commit, hollow on a stall, height scaled
  // by diff churn (sqrt so a huge commit doesn't flatten the rest). New nodes grow in.
  var rb=$('ribbon');rb.textContent='';
  var nodes=s.ribbon||[],max=1;
  nodes.forEach(function(n){if(n.churn>max)max=n.churn;});
  var fresh=(prevTurns>=0&&nodes.length>prevTurns)?nodes.length-prevTurns:0;
  nodes.forEach(function(n,i){
    var d=document.createElement('div');
    var isNew=(i>=nodes.length-fresh);
    d.className='node'+(n.committed?' commit':'')+(isNew?' enter':'');
    var scale=n.committed?Math.sqrt(Math.min(1,n.churn/max)):0;
    d.style.height=(n.committed?(24+Math.round(86*scale)):16)+'px';
    d.setAttribute('data-tip','turn '+n.turn+(n.committed?(' · '+(n.sha||'')+' · +'+n.churn+' lines · '+(n.subject||'')):' · stall'));
    rb.appendChild(d);
  });
  prevTurns=nodes.length;
  // Stakes strip — lit only when the loop is live.
  var stk=$('stakes');stk.textContent='';
  if(s.live){
    if(s.paused&&s.paused.until_epoch){
      var secs=Math.max(0,s.paused.until_epoch-Math.floor(Date.now()/1000));
      var m=Math.floor(secs/60),ss=secs%60;
      var pill=chip('⏸ '+s.paused.reason+' · resumes '+m+'m'+(ss<10?'0':'')+ss+'s');
      pill.className='countdown';stk.appendChild(pill);
    }
    stk.appendChild(meter('stall pressure',s.stalls,s.max_stalls));
    if(s.review_max){stk.appendChild(pips('review round',s.review_round,s.review_max));}
  }
  // Activity feed via textContent — agent text is inert regardless of content (D11).
  if(Array.isArray(s.activity)){var a=$('activity');a.textContent=s.activity.join('\n');a.scrollTop=a.scrollHeight;}
}
function chip(t){var e=document.createElement('span');e.textContent=t;return e;}
function meter(label,v,max){
  var wrap=document.createElement('span');wrap.appendChild(document.createTextNode(label+' '+v+'/'+max));
  var m=document.createElement('span');m.className='meter';var f=document.createElement('span');
  f.style.width=(max?Math.min(100,100*v/max):0)+'%';m.appendChild(f);wrap.appendChild(m);return wrap;
}
function pips(label,v,max){
  var wrap=document.createElement('span');wrap.appendChild(document.createTextNode(label+' '));
  for(var i=0;i<max;i++){var p=document.createElement('span');p.className='pip'+(i<v?' on':'');wrap.appendChild(p);}
  return wrap;
}
try{render(JSON.parse($('bootstrap').textContent));}catch(e){}
function connect(){
  var es=new EventSource('/events');
  es.onmessage=function(ev){try{render(JSON.parse(ev.data));}catch(e){}};
  es.onerror=function(){es.close();setTimeout(connect,2000);}; // D5: reconnect re-syncs
}
connect();
setInterval(function(){ // keep the rate-limit countdown ticking between snapshots
  var el=document.querySelector('#stakes .countdown');
  if(el){fetch('/state').then(function(r){return r.json();}).then(render).catch(function(){});}
},1000);
"""


if __name__ == "__main__":
    raise SystemExit(main())
