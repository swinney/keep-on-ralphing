#!/usr/bin/env bash
# One-orchestrator workspace-lock tests for ralph.sh — git-fixture based.
#
# The runner takes a PID lock at $RALPH_STATE_DIR/lock at startup and refuses to
# start a second concurrent loop on the same workspace, so competing orchestrators
# cannot corrupt shared state. A lock owned by a DEAD process is stale: detected
# and reclaimed rather than blocking forever. The lock releases on exit.
#
# Run:  bash base/tests/test_orchestrator_lock.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, git, python3, timeout.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RALPH="$HERE/../scripts/ralph.sh"

pass=0
fail=0
ok() {
  echo "  ok: $1"
  pass=$((pass + 1))
}
bad() {
  echo "  FAIL: $1"
  fail=$((fail + 1))
}

# Fresh workspace whose stub `claude` commits each turn (so a started loop is
# productive and a started --once exits 0).
new_ws() {
  WS=$(mktemp -d)
  HOME_DIR="$WS/home"
  STUB="$WS/.stub"
  mkdir -p "$HOME_DIR/.claude" "$STUB/bin"
  touch "$HOME_DIR/.claude/.keep"
  echo '{}' >"$HOME_DIR/.claude.json"

  git -C "$WS" init -q
  git -C "$WS" config user.email t@t.t
  git -C "$WS" config user.name t
  printf 'prompt\n' >"$WS/PROMPT.md"
  printf -- '- [ ] 1.1 first task\n' >"$WS/tasks.md"
  git -C "$WS" add -A
  git -C "$WS" commit -qm init

  cat >"$STUB/bin/claude" <<STUBEOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
git commit --allow-empty -qm "turn work" >/dev/null 2>&1 || true
exit 0
STUBEOF
  chmod +x "$STUB/bin/claude"
}

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. A second loop on a workspace already locked by a LIVE pid refuses ----
new_ws
mkdir -p "$WS/.ralph"
echo "$$" >"$WS/.ralph/lock"   # this test process is alive → a live owner
out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  timeout 20 bash "$RALPH" 2>&1 )
ec=$?
[ "$ec" -ne 0 ] && printf '%s' "$out" | grep -qi "lock" \
  && ok "second loop refuses while a live PID holds the workspace lock (exit $ec)" \
  || bad "second-loop refusal wrong (exit=$ec, out: $(printf '%s' "$out" | tail -1))"
# The live owner's lock must be left intact — the refusing process must not steal it.
[ "$(cat "$WS/.ralph/lock" 2>/dev/null)" = "$$" ] \
  && ok "a refused start leaves the live owner's lock untouched" \
  || bad "refused start clobbered the live owner's lock (now: $(cat "$WS/.ralph/lock" 2>/dev/null))"
cleanup

# --- 2. A stale lock from a DEAD pid is reclaimed; the loop starts -----------
new_ws
mkdir -p "$WS/.ralph"
deadpid=$(sh -c 'echo $$')   # this sh prints its own PID then exits → now dead
# Guard against the (unlikely) reuse of that PID within the test window.
if kill -0 "$deadpid" 2>/dev/null; then
  bad "test setup: PID $deadpid unexpectedly still alive — cannot test stale reclaim"
else
  echo "$deadpid" >"$WS/.ralph/lock"
  out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
    bash "$RALPH" --once 2>&1 )
  ec=$?
  [ "$ec" -eq 0 ] \
    && ok "a stale lock from a dead PID is reclaimed and the loop starts (exit 0)" \
    || bad "stale-lock reclaim failed (exit=$ec, out: $(printf '%s' "$out" | tail -1))"
  printf '%s' "$out" | grep -qi "stale" \
    && ok "reclaiming a stale lock is narrated" \
    || bad "stale-lock reclaim was not narrated"
fi
cleanup

# --- 3. A clean run with no prior lock acquires then releases on exit --------
new_ws
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$RALPH" --once >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 0 ] && [ ! -f "$WS/.ralph/lock" ] \
  && ok "a normal --once run acquires and then releases the lock on exit" \
  || bad "lock not released after a clean exit (exit=$ec, lock present: $([ -f "$WS/.ralph/lock" ] && echo yes || echo no))"
cleanup

echo
echo "orchestrator-lock tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
