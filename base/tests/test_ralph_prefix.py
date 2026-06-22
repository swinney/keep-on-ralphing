"""Unit tests for ralph_prefix.py — the live.log line-prefixer.

Self-contained: drives the script as a subprocess (no import-path assumptions),
matching the kit's stub-and-observe style. Run via the kit suite (run.sh) or:

    pytest -q -c base/tests/pytest.ini base/tests/test_ralph_prefix.py
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIX = os.path.join(HERE, "..", "scripts", "ralph_prefix.py")

# A line looks like:  2026-06-21T18:45:23-04:00 turn=7 | <original>
LINE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2} turn=(\S+) \| (.*)$")


def run(stdin, *args):
    p = subprocess.run(
        [sys.executable, PREFIX, *args],
        input=stdin, capture_output=True, text=True,
    )
    assert p.returncode == 0, p.stderr
    return p.stdout


def test_prefix_shape_and_turn():
    out = run("hello\n", "7")
    lines = out.splitlines()
    assert len(lines) == 1
    m = LINE_RE.match(lines[0])
    assert m, lines[0]
    assert m.group(1) == "7"
    assert m.group(2) == "hello"


def test_passthrough_content_unchanged_after_prefix():
    payload = "error: thing broke | with a pipe and = signs"
    out = run(payload + "\n", "3")
    assert out.splitlines()[0].endswith("| " + payload)


def test_one_prefixed_line_per_input_line():
    out = run("a\nb\nc\n", "12")
    lines = out.splitlines()
    assert len(lines) == 3
    assert [LINE_RE.match(l).group(2) for l in lines] == ["a", "b", "c"]


def test_last_line_without_trailing_newline_is_emitted():
    out = run("no newline at end", "1")
    lines = out.splitlines()
    assert len(lines) == 1
    assert lines[0].endswith("| no newline at end")


def test_missing_turn_arg_does_not_crash():
    out = run("x\n")  # no turn argv
    assert "turn=?" in out.splitlines()[0]
