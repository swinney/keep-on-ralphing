#!/usr/bin/env bash
# Behavioural tests for the aggregate live.log (RALPH_LIVE_LOG) — git-fixture
# based, no real `claude`, same stub-and-observe approach as test_ralph_runner.sh.
#
# Asserts: live.log is created, append-only, carries BOTH runner narration and
# agent output, is turn-prefixed + ISO-timestamped per line; the tee fan-out does
# NOT break exit-code capture (PIPESTATUS) or usage-limit detection; the terminal
# stream still gets agent output; and RALPH_LIVE_LOG=0 reproduces today's files.
#
# Run:  bash ralph-harness/tests/test_live_log.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, git, python3, timeout.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RALPH="$HERE/../scripts/ralph.sh"

pass=0
fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Fresh workspace: git repo + PROMPT.md + tasks.md + fake claude auth + stub.
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
c_file="$STUB/count"
n=\$(cat "\$c_file" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"\$c_file"
snippet="$STUB/count-\${n}.sh"
[ -f "\$snippet" ] && . "\$snippet"
exit \${STUB_EXIT:-0}
STUBEOF
  chmod +x "$STUB/bin/claude"
}

# Run ralph.sh (inner loop; review gate off). Extra env via positional args.
run_ralph() {
  ( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 \
    RALPH_REVIEW_GATE=0 \
    "$@" bash "$RALPH" ${RALPH_ARGS:-} )
}

# Poll a file for a pattern (live.log is fed by an async process-substitution
# prefixer, so the last lines can lag the turn's return — wait briefly).
wait_for() {
  local f="$1" pat="$2" n="${3:-30}"
  while [ "$n" -gt 0 ]; do
    grep -qE "$pat" "$f" 2>/dev/null && return 0
    sleep 0.1
    n=$((n - 1))
  done
  return 1
}

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. live.log: created, append-only, has narration + agent output ---------
new_ws
cat >"$STUB/count-1.sh" <<'S'
echo "AGENTMARK_ONE"
git commit --allow-empty -qm t1
S
cat >"$STUB/count-2.sh" <<'S'
echo "AGENTMARK_TWO"
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_ralph >/dev/null 2>&1
LIVE="$WS/.ralph/log/live.log"
[ -f "$LIVE" ] && ok "live.log is created" || bad "live.log missing"
wait_for "$LIVE" 'AGENTMARK_ONE' && wait_for "$LIVE" 'AGENTMARK_TWO' \
  && ok "live.log accumulates agent output across turns (append-only)" \
  || bad "live.log not append-only across turns"
grep -qE 'ralph: turn ' "$LIVE" \
  && ok "live.log contains runner narration (a narrate line)" \
  || bad "live.log missing runner narration"
cleanup

# --- 2. every live.log line is turn-prefixed + ISO-timestamped ---------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
echo "HELLO_FROM_AGENT"
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t1
S
RALPH_ARGS="" run_ralph >/dev/null 2>&1
LIVE="$WS/.ralph/log/live.log"
wait_for "$LIVE" 'HELLO_FROM_AGENT' || true
python3 - "$LIVE" <<'PY' && ok "every live.log line is turn-prefixed + ISO-timestamped" || bad "live.log lines not well-formed"
import re, sys
rx = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2} turn=\S+ \| ')
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
sys.exit(0 if lines and all(rx.match(l) for l in lines) else 1)
PY
cleanup

# --- 3a. tee fan-out preserves the agent exit code (PIPESTATUS) --------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
echo "noisy output"
STUB_EXIT=3
S
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
ec=$?
[ "$ec" -eq 3 ] && ok "fan-out preserves agent exit code (--once exits 3)" \
  || bad "agent exit code lost through fan-out (got $ec, want 3)"
cleanup

# --- 3b. usage-limit detection still works with the fan-out active ----------
new_ws
rm -f "$WS/STATUS.md"
for n in 1 2 3; do
  cat >"$STUB/count-${n}.sh" <<'S'
echo "You've hit your session limit · resets soon"
STUB_EXIT=1
S
done
cat >"$STUB/count-4.sh" <<'S'
printf 'done: after limits\n' >STATUS.md
git commit --allow-empty -qm t4
S
RALPH_ARGS="" RALPH_MAX_STALLS=2 RALPH_LIMIT_POLL=1 run_ralph >/dev/null 2>&1
ec=$?
[ "$ec" -eq 0 ] && ok "usage-limit still detected (not a stall) with live.log on" \
  || bad "usage-limit miscounted with live.log on (exit=$ec)"
cleanup

# --- 4. RALPH_LIVE_LOG=0 writes no live.log; turn-N.txt/status.jsonl intact --
new_ws
cat >"$STUB/count-1.sh" <<'S'
echo "RAW_AGENT_LINE"
git commit --allow-empty -qm t1
S
RALPH_LIVE_LOG=0 RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
[ ! -f "$WS/.ralph/log/live.log" ] && ok "RALPH_LIVE_LOG=0 writes no live.log" \
  || bad "live.log written despite RALPH_LIVE_LOG=0"
grep -q 'RAW_AGENT_LINE' "$WS/.ralph/log/turn-1.txt" \
  && ok "turn-N.txt still captures agent output with live.log off" \
  || bad "turn-N.txt missing agent output with live.log off"
[ -f "$WS/.ralph/status.jsonl" ] && ok "status.jsonl still written with live.log off" \
  || bad "status.jsonl missing with live.log off"
cleanup

# --- 5. terminal stream preserved + turn-N.txt is RAW (unprefixed) -----------
new_ws
cat >"$STUB/count-1.sh" <<'S'
echo "TERMMARK_42"
git commit --allow-empty -qm t1
S
out=$(RALPH_ARGS="--once" run_ralph 2>/dev/null)
echo "$out" | grep -q 'TERMMARK_42' \
  && ok "agent output still reaches stdout (terminal not blanked by fan-out)" \
  || bad "agent output missing from stdout — fan-out blanked the terminal"
# turn-N.txt must be the RAW agent stream (no live.log turn= prefix on its lines)
grep -q 'TERMMARK_42' "$WS/.ralph/log/turn-1.txt" \
  && ! grep -qE '^\S+ turn=[0-9]+ \| TERMMARK_42' "$WS/.ralph/log/turn-1.txt" \
  && ok "turn-N.txt remains raw/unprefixed (per-turn file unchanged)" \
  || bad "turn-N.txt was altered by the prefixer"
cleanup

# --- 6. prefixer unavailable → graceful degrade, no broken pipe -------------
# Run a copied runner from a script_dir that has ralph.sh + until_reset.py but
# NOT ralph_prefix.py, so the fan-out's prefixer cannot start. The turn must NOT
# break (no SIGPIPE/141, no truncated turn-N.txt); live.log is disabled + warned.
new_ws
SDIR="$WS/sdir"
mkdir -p "$SDIR"
cp "$HERE/../scripts/ralph.sh" "$HERE/../scripts/until_reset.py" "$SDIR/"
chmod +x "$SDIR/ralph.sh"
cat >"$STUB/count-1.sh" <<'S'
echo "DEGRADE_MARK"
git commit --allow-empty -qm t1
S
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  bash "$SDIR/ralph.sh" --once ) >"$WS/out.txt" 2>"$WS/err.txt"
ec=$?
[ "$ec" -eq 0 ] && ok "missing prefixer: turn still exits 0 (no broken pipe / 141)" \
  || bad "missing prefixer broke the turn (exit=$ec)"
grep -q 'DEGRADE_MARK' "$WS/.ralph/log/turn-1.txt" \
  && ok "missing prefixer: turn-N.txt not truncated" \
  || bad "missing prefixer truncated turn-N.txt"
[ ! -f "$WS/.ralph/log/live.log" ] \
  && ok "missing prefixer: live.log gracefully disabled" \
  || bad "live.log written despite missing prefixer"
grep -q 'disabling live.log' "$WS/err.txt" \
  && ok "missing prefixer: warned on stderr" \
  || bad "no warning emitted when prefixer unavailable"
cleanup

echo
echo "live.log tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
