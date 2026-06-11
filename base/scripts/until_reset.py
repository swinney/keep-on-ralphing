#!/usr/bin/env python3
"""Seconds to sleep until a Claude Code usage-limit window refreshes.

`claude -p` has no native wait-and-retry on a usage limit (only transient 5xx
errors are auto-retried). When the loop hits one it prints a human-readable line
like::

    You've hit your session limit · resets 5am UTC
    You've hit your weekly limit · resets Mon 12:00am

`scripts/ralph.sh` greps the "resets ..." fragment out of the turn log and hands
it here. We parse the clock time (and optional weekday, for the weekly limit),
compute the next moment it occurs, and print the seconds to wait until then plus
a small buffer so the window has truly refreshed.

Contract with the caller:
  * stdout = an integer number of seconds; exit 0 on a confident parse.
  * exit 1 on anything ambiguous, so the caller falls back to a fixed poll.
  * the result is clamped to ``[60, MAX_WAIT_SECONDS]`` — a misparse can never
    sleep the loop for an unreasonable span, and an under-sleep just retries.

The reset string carries no timezone offset we can fully trust, so "UTC" in the
text selects UTC and anything else is treated as the host's local time. `now` is
injectable purely so the parse is deterministically unit-testable.
"""

from __future__ import annotations

import re
import sys
from datetime import datetime, timedelta, timezone

# `datetime.UTC` is only 3.11+; this alias keeps the helper pure-stdlib but
# compatible back to Python 3.7 — the one intentional divergence from the
# verbatim original (see ralph-harness/README.md "drift note").
UTC = timezone.utc  # noqa: UP017  intentional: datetime.UTC is 3.11+; kit targets 3.7+

BUFFER_SECONDS = 120  # wait past the stated reset so the window has actually rolled over
MAX_WAIT_SECONDS = 6 * 3600  # misparse guard; also covers the 5h session window with margin.
# A weekly limit further out than this degrades to a poll: we wake, re-hit the
# limit, and sleep again — wasteful but always correct, never a false halt.

_HALF_DAY_HOURS = 12

_WEEKDAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}

_TIME_RE = re.compile(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", re.IGNORECASE)
_WEEKDAY_RE = re.compile(r"\b(mon|tue|wed|thu|fri|sat|sun)", re.IGNORECASE)


def seconds_until_reset(fragment: str, now: datetime | None = None) -> int:
    """Return seconds to sleep until the reset described by ``fragment``.

    Raises ``ValueError`` if no clock time is present so the caller can fall back.
    """
    text = fragment.lower()

    use_utc = "utc" in text
    if now is None:
        now = datetime.now(UTC) if use_utc else datetime.now().astimezone()
    elif use_utc:
        # Normalize an injected `now` so a UTC reset is computed in UTC regardless
        # of the caller's zone (a naive `now` is read as local, then converted).
        now = now.astimezone(UTC)

    match = _TIME_RE.search(text)
    if match is None:
        raise ValueError(f"no clock time in {fragment!r}")
    hour = int(match.group(1)) % _HALF_DAY_HOURS
    if match.group(3).lower() == "pm":
        hour += _HALF_DAY_HOURS
    minute = int(match.group(2) or 0)

    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)

    weekday = _WEEKDAY_RE.search(text)
    if weekday is not None:
        # Weekly limit: advance to the named weekday's occurrence of that time.
        delta_days = (_WEEKDAYS[weekday.group(1).lower()] - target.weekday()) % 7
        target += timedelta(days=delta_days)
        if target <= now:
            target += timedelta(days=7)
    elif target <= now:
        # Session/Opus limit: that clock time has already passed today.
        target += timedelta(days=1)

    wait = int((target - now).total_seconds()) + BUFFER_SECONDS
    return max(60, min(wait, MAX_WAIT_SECONDS))


def main(argv: list[str]) -> int:
    fragment = " ".join(argv[1:]).strip()
    if not fragment:
        return 1
    try:
        print(seconds_until_reset(fragment))
    except (ValueError, KeyError):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
