"""Unit tests for the ephemeral dashboard viewer's PURE logic.

Per design D12, the viewer's state-derivation, liveness decision, ribbon data, and
HTML escaping are unit-tested against .ralph/ fixtures; the socket/SSE/thread
plumbing is covered structurally/by smoke, not here. Self-contained: adds the kit's
scripts/ dir to sys.path so it runs with no project pytest config.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from ralph_dashboard import (  # noqa: E402
    classify_phase,
    derive_state,
    escape_field,
    git_churn,
    make_server,
    parse_task_progress,
    ribbon_data,
)

TERMINAL = ["complete", "blocked", "review-exhausted", "stall", "sigint"]


def _ralph(tmp_path, current=None, status=None, tasks=None):
    """Build a .ralph/ fixture; return its path."""
    d = tmp_path / ".ralph"
    (d / "log").mkdir(parents=True)
    if current is not None:
        (d / "current.json").write_text(json.dumps(current))
    if status is not None:
        (d / "status.jsonl").write_text("".join(json.dumps(r) + "\n" for r in status))
    if tasks is not None:
        (tmp_path / "tasks.md").write_text(tasks)
    return d


# --- classify_phase: the liveness decision (D4) -----------------------------

def test_running_with_live_container_is_running():
    assert classify_phase({"state": "running", "run_id": "R1"}, container_running=True) == "running"


def test_paused_when_paused_record_and_container_live():
    cur = {"state": "running", "paused": {"reason": "usage-limit", "until_epoch": 9}}
    assert classify_phase(cur, container_running=True) == "paused"


def test_terminal_state_is_ended_regardless_of_container():
    for cls in TERMINAL:
        assert classify_phase({"state": cls}, container_running=False) == "ended"


def test_killed_inferred_when_nonterminal_but_container_gone():
    # No terminal write (SIGKILL/OOM) + container gone => ended-by-inference, NOT running.
    assert classify_phase({"state": "running"}, container_running=False) == "killed"
    assert classify_phase({"state": "idle"}, container_running=False) == "killed"


def test_no_current_is_none():
    assert classify_phase(None, container_running=False) == "none"
    assert classify_phase(None, container_running=True) == "none"


def test_stale_prior_run_is_never_live():
    # A reused .ralph/ with a prior run's record + no running container is not "live".
    assert classify_phase({"state": "complete", "run_id": "OLD"}, container_running=False) == "ended"
    assert classify_phase({"state": "idle", "run_id": "OLD"}, container_running=False) == "killed"


def test_run_id_mismatch_with_running_container_is_not_live():
    # D4: once a live run is latched, a current.json showing a DIFFERENT run_id —
    # even with a container running and a non-terminal state — is NOT the live run
    # (a stale leftover, or a new loop that replaced ours). Without the latch
    # (expected_run_id=None) the same record reads as the live run.
    cur = {"state": "running", "run_id": "NEW"}
    assert classify_phase(cur, container_running=True, expected_run_id="OURS") == "ended"
    assert classify_phase(cur, container_running=True, expected_run_id="NEW") == "running"
    assert classify_phase(cur, container_running=True) == "running"  # no latch yet


def test_derive_state_run_id_mismatch_drops_halt_class(tmp_path):
    # A stale/replaced run must not borrow another run's state as our halt class.
    state_dir = tmp_path / ".ralph"
    state_dir.mkdir()
    (state_dir / "current.json").write_text(
        '{"state": "complete", "run_id": "OTHER", "turn": 9}', encoding="utf-8"
    )
    snap = derive_state(str(state_dir), container_running=False, expected_run_id="OURS")
    assert snap["phase"] == "ended"
    assert snap["halt_class"] is None  # not "complete" — that was a different run
    assert snap["live"] is False


# --- derive_state: the SSE/template snapshot --------------------------------

def test_derive_state_reads_structured_fields(tmp_path):
    cur = {
        "run_id": "R1", "run_started": "2026-06-26T10:00:00Z", "turn": 4, "task": "do thing",
        "model": "claude-opus-4-8", "state": "idle", "committed": True, "sha": "abc1234",
        "subject": "feat: thing", "stalls": 1, "max_stalls": 5, "review_round": 2, "review_max": 3,
        "blocked": False, "blocked_reason": None,
    }
    state_dir = _ralph(tmp_path, current=cur, tasks="- [x] 1 a\n- [ ] 2 b\n- [x] 3 c\n")
    snap = derive_state(str(state_dir), container_running=True)
    assert snap["phase"] == "idle" and snap["live"] is True
    assert snap["turn"] == 4 and snap["task"] == "do thing" and snap["model"] == "claude-opus-4-8"
    assert snap["sha"] == "abc1234" and snap["subject"] == "feat: thing"
    assert snap["stalls"] == 1 and snap["max_stalls"] == 5
    assert snap["review_round"] == 2 and snap["review_max"] == 3
    assert snap["task_progress"] == {"done": 2, "total": 3}


def test_derive_state_ended_surfaces_halt_class(tmp_path):
    state_dir = _ralph(tmp_path, current={"state": "stall", "run_id": "R1", "turn": 9})
    snap = derive_state(str(state_dir), container_running=False)
    assert snap["phase"] == "ended" and snap["live"] is False
    assert snap["halt_class"] == "stall"


def test_derive_state_no_run(tmp_path):
    state_dir = _ralph(tmp_path)  # no current.json
    snap = derive_state(str(state_dir), container_running=False)
    assert snap["phase"] == "none" and snap["live"] is False


# --- parse_task_progress ----------------------------------------------------

def test_parse_task_progress_counts_checked(tmp_path):
    p = tmp_path / "tasks.md"
    p.write_text("# Tasks\n- [x] done one\n- [ ] open\n- [X] done two (caps)\n  - [ ] nested open\n")
    assert parse_task_progress(str(p)) == {"done": 2, "total": 4}


def test_parse_task_progress_missing_file():
    assert parse_task_progress("/no/such/tasks.md") == {"done": 0, "total": 0}


# --- escape_field: agent-authored text is inert (D11, security) -------------

def test_escape_field_neutralizes_markup():
    out = escape_field('<script>alert(1)</script> & "x" \'y\'')
    assert "<script>" not in out and "</script>" not in out
    assert "&lt;script&gt;" in out and "&amp;" in out


def test_escape_field_handles_none():
    assert escape_field(None) == ""


# --- ribbon_data: the Commit Ribbon (D9), churn injected for purity ----------

def test_ribbon_data_marks_commits_and_stalls():
    records = [
        {"turn": 1, "committed": True, "sha": "aaa", "subject": "feat: a"},
        {"turn": 2, "committed": False, "sha": None, "subject": None},
        {"turn": 3, "committed": True, "sha": "ccc", "subject": "fix: c"},
    ]
    churn = {"aaa": 10, "ccc": 3}
    nodes = ribbon_data(records, churn_fn=lambda sha: churn.get(sha, 0))
    assert [n["turn"] for n in nodes] == [1, 2, 3]
    assert [n["committed"] for n in nodes] == [True, False, True]
    assert nodes[0]["churn"] == 10 and nodes[2]["churn"] == 3
    assert nodes[1]["churn"] == 0  # a stall node carries no churn
    assert nodes[0]["sha"] == "aaa" and nodes[0]["subject"] == "feat: a"


def test_ribbon_data_without_churn_fn_defaults_zero():
    nodes = ribbon_data([{"turn": 1, "committed": True, "sha": "aaa", "subject": "x"}])
    assert nodes[0]["churn"] == 0


def test_ribbon_data_empty():
    assert ribbon_data([]) == []


# --- git_churn: host-side diff size for a sha (integration vs a git fixture) -

def test_git_churn_counts_changed_lines(tmp_path):
    import subprocess

    def g(*a):
        subprocess.run(["git", *a], cwd=tmp_path, check=True, capture_output=True)

    g("init", "-q")
    g("config", "user.email", "t@t.t")
    g("config", "user.name", "t")
    (tmp_path / "f.txt").write_text("a\nb\nc\n")
    g("add", "-A")
    g("commit", "-qm", "init")
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=tmp_path, capture_output=True, text=True
    ).stdout.strip()
    assert git_churn(sha, cwd=str(tmp_path)) == 3  # three lines added


def test_git_churn_bad_sha_is_zero(tmp_path):
    assert git_churn("nosuchsha", cwd=str(tmp_path)) == 0


# --- server smoke + security (D11/D12): plumbing isn't unit-tested, but the
# Host-header defense, CSP, and server-side escaping ARE (the security spec).
# Uses a non-existent container, so liveness is "not running" with or without podman.

import http.client  # noqa: E402
import socket  # noqa: E402
import threading  # noqa: E402


def _serve(state_dir, workspace):
    server = make_server(str(state_dir), str(workspace), "podman", "ralph-none-xyz", port=0)
    threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.2}, daemon=True).start()
    return server, server.server_address[1]


def _get(port, path, host=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request("GET", path, headers={"Host": host or ("127.0.0.1:%d" % port)})
    r = c.getresponse()
    body = r.read()
    headers = dict(r.getheaders())
    c.close()
    return r.status, headers, body


def test_server_serves_page_with_csp_and_escapes_agent_text(tmp_path):
    cur = {"state": "running", "run_id": "R1", "turn": 2, "subject": "<script>alert(1)</script>"}
    state_dir = _ralph(tmp_path, current=cur, tasks="- [x] a\n- [ ] b\n")
    server, port = _serve(state_dir, tmp_path)
    try:
        status, headers, body = _get(port, "/")
        text = body.decode()
        assert status == 200
        assert "default-src 'none'" in headers.get("Content-Security-Policy", "")
        assert "<script>alert(1)</script>" not in text  # hostile subject not live markup
        assert "&lt;script&gt;alert(1)&lt;/script&gt;" in text  # rendered inert
    finally:
        server.stop_event.set()
        server.shutdown()


def test_server_rejects_foreign_host(tmp_path):
    state_dir = _ralph(tmp_path, current={"state": "running", "run_id": "R1"})
    server, port = _serve(state_dir, tmp_path)
    try:
        status, _, _ = _get(port, "/", host="evil.example.com")
        assert status == 403  # DNS-rebind defense
    finally:
        server.stop_event.set()
        server.shutdown()


def test_server_state_endpoint_is_json_from_structured_files(tmp_path):
    state_dir = _ralph(tmp_path, current={"state": "idle", "run_id": "R1", "turn": 3})
    server, port = _serve(state_dir, tmp_path)
    try:
        status, headers, body = _get(port, "/state")
        data = json.loads(body)
        assert status == 200 and "application/json" in headers.get("Content-Type", "")
        assert data["turn"] == 3 and data["phase"] == "killed"  # container not running -> inferred
    finally:
        server.stop_event.set()
        server.shutdown()


def test_server_events_emits_initial_snapshot(tmp_path):
    state_dir = _ralph(tmp_path, current={"state": "running", "run_id": "R1", "turn": 5})
    server, port = _serve(state_dir, tmp_path)
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        s.settimeout(5)
        s.sendall(("GET /events HTTP/1.0\r\nHost: 127.0.0.1:%d\r\n\r\n" % port).encode())
        buf = b""
        while b'"turn": 5' not in buf:  # wait for the actual snapshot payload, not headers
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        s.close()
        assert b"data: " in buf and b'"turn": 5' in buf  # snapshot-on-connect (D5)
    finally:
        server.stop_event.set()
        server.shutdown()
