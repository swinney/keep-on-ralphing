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

import html
import json
import os
import re
import subprocess

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


def classify_phase(current, container_running):
    """The liveness decision (D4).

    Returns one of: none | starting | running | idle | paused | ended | killed.
      * no heartbeat            → "none"
      * terminal halt class     → "ended" (the loop wrote why it stopped)
      * container running       → the live state ("paused" when a pause is recorded)
      * non-terminal + no container → "killed" (vanished without a terminal write)
    """
    if not current:
        return "none"
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


def derive_state(state_dir, container_running, tasks_path=None, now_epoch=None):
    """Derive the full dashboard snapshot from the structured state files + task list.

    Facts come from current.json / status.jsonl / tasks.md — never from log scraping
    (the spec's "derives facts from structured state" requirement).
    """
    current = read_json(os.path.join(state_dir, "current.json"))
    phase = classify_phase(current, container_running)
    cur = current or {}
    if tasks_path is None:
        tasks_path = os.path.join(os.path.dirname(os.path.abspath(state_dir)), "tasks.md")
    return {
        "run_id": cur.get("run_id"),
        "run_started": cur.get("run_started"),
        "phase": phase,
        "live": phase in _LIVE_PHASES,
        "halt_class": cur.get("state") if phase == "ended" else None,
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
