#!/usr/bin/env python3
"""Line-prefixer for the Ralph aggregate log (``live.log``).

Reads agent output on stdin and writes each line to stdout prefixed with an
ISO-8601 timestamp and the turn number::

    2026-06-21T14:03:11-05:00 turn=7 | <original line>

so a downstream aggregator (Vector, Logstash, …) can filter and timeline by turn
without reconstructing multi-line events. This is ONE long-lived, line-buffered
process — not a ``date``/``awk`` fork per line — and it runs in the ``tee``
fan-out in ``ralph.sh`` (``… | tee "$log" >(ralph_prefix.py "$turn" >> "$live")``),
so a copy of the agent output still reaches the terminal and ``${PIPESTATUS[0]}``
stays the agent's exit code.

Invoked as ``python3 "$script_dir/ralph_prefix.py" <turn>``, the same form the
runner uses for ``until_reset.py``. Baked next to it in the base image.

Drift note: targets Python 3.7+ for runtime portability (matching
``until_reset.py``), though the base image runs 3.12. ``datetime.astimezone()``
with no argument attaches the local offset on 3.6+, so no tz dependency is
needed.
"""
import sys
from datetime import datetime


def main() -> int:
    turn = sys.argv[1] if len(sys.argv) > 1 else "?"
    for line in sys.stdin:
        ts = datetime.now().astimezone().isoformat(timespec="seconds")
        sys.stdout.write("{} turn={} | {}\n".format(ts, turn, line.rstrip("\n")))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
