#!/usr/bin/env bash
# Run the full kit test suite: the until_reset.py unit tests and the ralph.sh
# behavioural scaffold. Self-contained — needs only python3 (with pytest) and
# bash/git/timeout, not this or any other project's pytest configuration.
#
#   bash ralph-harness/tests/run.sh

set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

rc=0

echo "== python unit tests (until_reset.py, ralph_prefix.py) =="
# -c <kit ini> isolates from any surrounding project's pytest config.
if command -v pytest >/dev/null 2>&1; then
  pytest -q -c "$here/pytest.ini" "$here/test_until_reset.py" "$here/test_ralph_prefix.py" || rc=1
else
  python3 -m pytest -q -c "$here/pytest.ini" "$here/test_until_reset.py" "$here/test_ralph_prefix.py" || rc=1
fi

echo
echo "== ralph.sh runner tests =="
bash "$here/test_ralph_runner.sh" || rc=1

echo
echo "== live.log (aggregate logging) tests =="
bash "$here/test_live_log.sh" || rc=1

echo
echo "== gate hook tests =="
bash "$here/test_gate_hook.sh" || rc=1

echo
echo "== review gate tests =="
bash "$here/test_review_gate.sh" || rc=1

echo
echo "== outbound notification tests =="
bash "$here/test_notify.sh" || rc=1

echo
echo "== base-image freshness tests =="
bash "$here/test_base_freshness.sh" || rc=1

echo
echo "== structural conformance tests =="
bash "$here/test_conformance.sh" || rc=1

echo
[ "$rc" -eq 0 ] && echo "ALL KIT TESTS PASSED" || echo "KIT TESTS FAILED"
exit "$rc"
