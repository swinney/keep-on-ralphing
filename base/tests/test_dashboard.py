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
