#!/usr/bin/env bash
# One-orchestrator workspace-lock tests for ralph.sh — git-fixture based.
#
# The runner guards a workspace with flock(1) on $RALPH_STATE_DIR/lock so two
# concurrent loops cannot corrupt shared state. flock (not a PID file) is used
# because the runner is PID 1 in its container: a PID-based lock left by a killed
# container would hold "1", and the next container's own live PID 1 would read it
# as live and refuse FOREVER. flock keys on the shared inode and the kernel drops
# it when the holder dies — across PID namespaces — so a leftover lock file with no
# live holder is reacquired cleanly. These tests assert exactly that.
#
# Run:  bash base/tests/test_orchestrator_lock.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, git, python3, timeout, flock.

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

if ! command -v flock >/dev/null 2>&1; then
  echo "  SKIP: flock not on PATH — the lock tests need it (it ships in the base image)"
  echo "orchestrator-lock tests: 0 passed, 0 failed (skipped)"
  exit 0
fi

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

cleanup() {
  [ -n "${HOLDER:-}" ] && kill "$HOLDER" 2>/dev/null
  [ -n "${WS:-}" ] && rm -rf "$WS"
  HOLDER=""
}
trap cleanup EXIT

# --- 1. A second loop refuses while another process holds the flock ----------
new_ws
mkdir -p "$WS/.ralph"
# Hold a REAL flock on the lock file. `exec sleep` makes $! the sleep itself, which
# inherits fd 9, so killing it (cleanup) actually releases the flock — no fd leak.
( exec 9>"$WS/.ralph/lock"; flock -n 9 || exit 1; : >"$WS/.ralph/held"; exec sleep 30 ) &
HOLDER=$!
for _ in $(seq 1 50); do [ -f "$WS/.ralph/held" ] && break; sleep 0.1; done
out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  timeout 20 bash "$RALPH" 2>&1 )
ec=$?
[ "$ec" -ne 0 ] && printf '%s' "$out" | grep -qi "lock" \
  && ok "second loop refuses while another holds the flock (exit $ec)" \
  || bad "second-loop refusal wrong (exit=$ec, out: $(printf '%s' "$out" | tail -1))"
# The refusing process must NOT delete the file (that would orphan the incumbent's lock).
[ -f "$WS/.ralph/lock" ] && kill -0 "$HOLDER" 2>/dev/null \
  && ok "a refused start leaves the incumbent's lock and holder intact" \
  || bad "refused start disturbed the incumbent (lock present: $([ -f "$WS/.ralph/lock" ] && echo yes || echo no))"
cleanup

# --- 2. A leftover lock FILE with no live holder is reclaimed (the PID-1 case) -
# Simulates a container killed before its EXIT trap ran: a lock file left holding
# "1", with NO process holding the flock. flock must reacquire and start.
new_ws
mkdir -p "$WS/.ralph"
printf '1\n' >"$WS/.ralph/lock"   # stale "PID 1" content, but nobody holds the flock
out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$RALPH" --once 2>&1 )
ec=$?
[ "$ec" -eq 0 ] \
  && ok "a leftover lock file with no live holder is reclaimed and the loop starts (exit 0)" \
  || bad "stale-file reclaim failed (exit=$ec, out: $(printf '%s' "$out" | tail -1))"
cleanup

# --- 3. A clean run with no prior lock acquires then releases on exit ---------
new_ws
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$RALPH" --once >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 0 ] && [ ! -f "$WS/.ralph/lock" ] \
  && ok "a normal --once run acquires and then releases (removes) the lock on exit" \
  || bad "lock not released after a clean exit (exit=$ec, lock present: $([ -f "$WS/.ralph/lock" ] && echo yes || echo no))"
cleanup

# --- 4. Two SEQUENTIAL runs both start (the lock is released between them) -----
new_ws
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$RALPH" --once >/dev/null 2>&1 )
e1=$?
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$RALPH" --once >/dev/null 2>&1 )
e2=$?
[ "$e1" -eq 0 ] && [ "$e2" -eq 0 ] && [ "$(cat "$WS/.ralph/turn")" = "2" ] \
  && ok "sequential runs both acquire the lock (turn counter reaches 2)" \
  || bad "sequential lock handoff wrong (e1=$e1 e2=$e2 turn=$(cat "$WS/.ralph/turn" 2>/dev/null))"
cleanup

echo
echo "orchestrator-lock tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
