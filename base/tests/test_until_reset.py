"""Unit tests for the kit's until_reset.py helper.

Self-contained: adds the kit's scripts/ dir to sys.path so it runs from any
repo that copied ralph-harness/ wholesale, with no project pytest config needed.
Run with `python3 -m pytest ralph-harness/tests/test_until_reset.py` or directly
via `python3 ralph-harness/tests/test_until_reset.py`.
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from until_reset import (
    BUFFER_SECONDS,
    MAX_WAIT_SECONDS,
    main,
    seconds_until_reset,
)

UTC = timezone.utc  # noqa: UP017  intentional: match the 3.7+ helper
ONE_HOUR = 3600
HALF_HOUR = 1800
FLOOR_SECONDS = 60


def test_session_reset_later_today_is_exact() -> None:
    now = datetime(2026, 6, 10, 4, 30, tzinfo=UTC)
    wait = seconds_until_reset("resets 5am UTC", now=now)
    assert wait == HALF_HOUR + BUFFER_SECONDS


def test_session_reset_already_passed_rolls_to_next_day() -> None:
    # 6am now, reset 5am → next day 5am = 23h out, clamped to the misparse guard.
    now = datetime(2026, 6, 10, 6, 0, tzinfo=UTC)
    wait = seconds_until_reset("resets 5am UTC", now=now)
    assert wait == MAX_WAIT_SECONDS


def test_pm_time_parsed() -> None:
    now = datetime(2026, 6, 10, 12, 0, tzinfo=UTC)
    wait = seconds_until_reset("resets 1pm UTC", now=now)
    assert wait == ONE_HOUR + BUFFER_SECONDS


def test_weekly_reset_is_within_bounds() -> None:
    now = datetime(2026, 6, 10, 12, 0, tzinfo=UTC)
    wait = seconds_until_reset("resets Mon 12:00am UTC", now=now)
    assert FLOOR_SECONDS <= wait <= MAX_WAIT_SECONDS


def test_ambiguous_fragment_raises() -> None:
    now = datetime(2026, 6, 10, 12, 0, tzinfo=UTC)
    raised = False
    try:
        seconds_until_reset("resets soon", now=now)
    except ValueError:
        raised = True
    assert raised


def test_main_exits_zero_on_good_fragment(capsys) -> None:
    code = main(["until_reset.py", "resets", "5am", "UTC"])
    out = capsys.readouterr().out.strip()
    assert code == 0
    assert out.isdigit()


def test_main_exits_nonzero_on_ambiguous() -> None:
    code = main(["until_reset.py", "resets", "soon"])
    assert code == 1


def test_main_exits_nonzero_on_empty() -> None:
    code = main(["until_reset.py"])
    assert code == 1


if __name__ == "__main__":
    raise SystemExit(__import__("pytest").main([__file__, "-q"]))
