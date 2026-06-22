#!/usr/bin/env bash
# Behavioural test scaffold for ralph.sh — git-fixture based, no real `claude`.
#
# Each test builds a throwaway git repo as the workspace, puts a STUB `claude`
# on PATH whose per-invocation behaviour is scripted by counter-keyed snippets,
# runs ralph.sh against it, and asserts on exit code, STATUS.md, the turn
# counter, and the JSON state outputs. The runner only ever observes the commit
# graph and STATUS.md, so the stub is indistinguishable from the real CLI.
#
# Run:  bash ralph-harness/tests/test_ralph_runner.sh
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

# Build a fresh workspace: git repo + PROMPT.md + tasks.md + fake claude auth.
# Stub behaviour snippets go in $WS/.stub/count-<n>.sh (run in the workspace cwd
# with stdin drained); a missing snippet for a count is a no-op (a stall turn).
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
# Drain the piped PROMPT.md so the producer never sees SIGPIPE.
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

# Run ralph.sh in the workspace with a fast, deterministic environment. The
# review gate is ON by default but these tests exercise the INNER loop, so they
# opt out explicitly (RALPH_REVIEW_GATE=0) — otherwise loop mode would refuse to
# start without a git remote + gh. The review gate has its own suite.
run_ralph() {
  ( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 \
    RALPH_REVIEW_GATE=0 \
    "$@" bash "$RALPH" ${RALPH_ARGS:-} )
}

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. PROMPT.md missing → refuse, exit non-zero ---------------------------
new_ws
rm -f "$WS/PROMPT.md"
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
[ $? -ne 0 ] && ok "missing PROMPT.md refuses to start" || bad "missing PROMPT.md should exit non-zero"
cleanup

# --- 2. --once committing turn → exit 0, recorded as committed --------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm "turn work"
S
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
ec=$?
[ "$ec" -eq 0 ] && ok "--once commit exits 0" || bad "--once commit exit was $ec"
python3 - "$WS/.ralph/status.jsonl" <<'PY' && ok "committed turn recorded committed=true" || bad "status.jsonl not committed=true"
import json, sys
rec = json.loads(open(sys.argv[1]).read().splitlines()[-1])
sys.exit(0 if rec["committed"] and rec["sha"] else 1)
PY
python3 -c "import json;json.load(open('$WS/.ralph/current.json'))" 2>/dev/null \
  && ok "current.json is valid JSON" || bad "current.json invalid"
cleanup

# --- 3. --once non-committing turn → committed=false ------------------------
new_ws
# no snippet for count-1 → stub no-ops → no commit
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
python3 - "$WS/.ralph/status.jsonl" <<'PY' && ok "no-commit turn recorded committed=false" || bad "no-commit not recorded false"
import json, sys
rec = json.loads(open(sys.argv[1]).read().splitlines()[-1])
sys.exit(0 if not rec["committed"] else 1)
PY
cleanup

# --- 4. --once turn exceeding timeout → killed (exit 124), no commit --------
new_ws
cat >"$STUB/count-1.sh" <<'S'
sleep 5
S
RALPH_ARGS="--once" RALPH_TURN_TIMEOUT=1 run_ralph >/dev/null 2>&1
ec=$?
[ "$ec" -eq 124 ] && ok "timed-out turn exits 124" || bad "timeout exit was $ec (want 124)"
cleanup

# --- 5. turn counter survives restart ---------------------------------------
new_ws
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
RALPH_ARGS="--once" run_ralph >/dev/null 2>&1
[ "$(cat "$WS/.ralph/turn")" = "2" ] && ok "turn counter resumes (=2)" || bad "turn counter did not resume"
cleanup

# --- 6. pre-existing breadcrumb does NOT stop a fresh loop ------------------
new_ws
printf 'old breadcrumb from a previous run\n' >"$WS/STATUS.md"
# turn1 commits and leaves the breadcrumb; turn2 writes a NEW stop reason.
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: real stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_ralph >/dev/null 2>&1
ec=$?
turns=$(cat "$WS/.ralph/turn")
[ "$ec" -eq 0 ] && [ "$turns" -ge 2 ] \
  && ok "pre-existing breadcrumb ignored; stops on NEW status (turns=$turns)" \
  || bad "breadcrumb handling wrong (exit=$ec turns=$turns)"
cleanup

# --- 7. whitespace-only STATUS write is ignored -----------------------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
printf '   \n' >STATUS.md
git commit --allow-empty -qm t1
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop now\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_ralph >/dev/null 2>&1
turns=$(cat "$WS/.ralph/turn")
[ "$turns" -ge 2 ] && ok "whitespace-only STATUS did not stop the loop (turns=$turns)" \
  || bad "whitespace STATUS wrongly stopped loop (turns=$turns)"
cleanup

# --- 8. consecutive-stall halt → exit 1, runner writes STATUS.md ------------
new_ws
rm -f "$WS/STATUS.md"
# no snippets → every turn is a no-commit stall
RALPH_ARGS="" RALPH_MAX_STALLS=2 run_ralph >/dev/null 2>&1
ec=$?
[ "$ec" -eq 1 ] && ok "max-stalls halt exits 1" || bad "stall halt exit was $ec (want 1)"
grep -qi "Loop halted" "$WS/STATUS.md" \
  && ok "stall halt wrote a non-empty STATUS.md reason" || bad "stall halt STATUS.md missing reason"
cleanup

# --- 9. usage-limit turns are NOT stalls; same task is replayed -------------
new_ws
rm -f "$WS/STATUS.md"
# Three limit hits in a row (would trip MAX_STALLS=2 if miscounted), then a
# committing turn that stops the loop. Unparseable reset → fallback poll=1s.
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
[ "$ec" -eq 0 ] && ok "three usage-limit hits did not trip stall halt (exit 0)" \
  || bad "usage-limit miscounted as stall (exit=$ec)"
cleanup

# --- 10. ralph.conf is sourced; an env var of the same name overrides it ----
new_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
# conf sets a model; the heartbeat should record it (conf applied over default).
printf 'RALPH_MODEL="from-conf"\n' >"$WS/ralph.conf"
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph bash "$RALPH" --once >/dev/null 2>&1 )
python3 - "$WS/.ralph/status.jsonl" from-conf <<'PY' && ok "ralph.conf value is applied" || bad "ralph.conf value not applied"
import json, sys
rec = json.loads(open(sys.argv[1]).read().splitlines()[-1])
sys.exit(0 if rec["model"] == sys.argv[2] else 1)
PY
# now an env var of the same name must WIN over the conf file.
rm -rf "$WS/.ralph"
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_MODEL="from-env" \
  bash "$RALPH" --once >/dev/null 2>&1 )
python3 - "$WS/.ralph/status.jsonl" from-env <<'PY' && ok "env var overrides ralph.conf" || bad "env did not override conf"
import json, sys
rec = json.loads(open(sys.argv[1]).read().splitlines()[-1])
sys.exit(0 if rec["model"] == sys.argv[2] else 1)
PY
cleanup

# --- 11. startup narrates the baked base-version (provenance stamp) ----------
new_ws
printf 'deadbeefstamp\n' >"$WS/fake-base-version"
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  RALPH_BASE_VERSION_FILE="$WS/fake-base-version" bash "$RALPH" --once 2>&1 )
printf '%s' "$out" | grep -q "base-version deadbeefstamp" \
  && ok "startup narrates the baked base-version" \
  || bad "base-version not narrated (got: $(printf '%s' "$out" | grep -i base-version))"
cleanup

# --- 12. absent base-version file → narrates 'unknown' ----------------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
out=$( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
  RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
  RALPH_BASE_VERSION_FILE="$WS/does-not-exist" bash "$RALPH" --once 2>&1 )
printf '%s' "$out" | grep -q "base-version unknown" \
  && ok "absent base-version file narrates 'unknown'" \
  || bad "absent base-version did not narrate 'unknown'"
cleanup

echo
echo "ralph.sh runner tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
