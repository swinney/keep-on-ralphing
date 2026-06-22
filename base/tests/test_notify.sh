#!/usr/bin/env bash
# Behavioural tests for the outbound-notification seam (RALPH_NOTIFY_CMD) and the
# blocked-question immediate stop in ralph.sh.
#
# Same git-fixture philosophy as test_ralph_runner.sh / test_review_gate.sh: a
# throwaway repo is the workspace, a STUB `claude` scripts each turn, a STUB
# notifier records its `<event> <reason>` args, and — for the review-exhausted
# halt — a STUB `gh` + a bare `origin` remote drive the review gate with NO
# network. Scenarios assert the four notify events (review-exhausted/stall/stop/
# blocked), the non-fatal contract (a failing/slow notifier never changes the
# loop's exit code or flow), the blocked-question NOT-a-stall ordering + persisted
# signal, and the unset = byte-identical no-op invariant.
#
# Run:  bash base/tests/test_notify.sh
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

# Build a workspace: git repo + bare origin + feature branch + stub claude + stub
# gh + a notifier recorder. Always wires the gate scaffold so a scenario can run
# either the inner loop (RALPH_REVIEW_GATE=0, the default in run()) or the review
# gate (RALPH_REVIEW_GATE=1) without rebuilding.
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
  git -C "$WS" symbolic-ref HEAD refs/heads/main
  printf 'prompt\n' >"$WS/PROMPT.md"
  printf -- '- [ ] 1.1 first task\n' >"$WS/tasks.md"
  git -C "$WS" add -A
  git -C "$WS" commit -qm init

  git init --bare -q "$WS/origin.git"
  git -C "$WS" remote add origin "$WS/origin.git"
  git -C "$WS" push -q origin main
  git -C "$WS" checkout -q -b feat

  : >"$STUB/pr_number"   # empty -> `pr view` reports "no PR" until `pr create`
  echo 0 >"$STUB/ci_exit" # gh pr checks exit: 0=pass, 8=pending, other=fail
  : >"$STUB/findings"
  : >"$STUB/gh.log"
  : >"$STUB/notify.log"  # notifier records one "event=<e> reason=<r>" line per call

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

  cat >"$STUB/bin/gh" <<STUBEOF
#!/usr/bin/env bash
echo "\$*" >>"$STUB/gh.log"
case "\$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"--json number"*)
    if [ -s "$STUB/pr_number" ]; then cat "$STUB/pr_number"; exit 0; else exit 1; fi ;;
  *"pr view"*"--json comments"*)
    cat "$STUB/findings"; exit 0 ;;
  *"pr create"*) echo 1 >"$STUB/pr_number"; exit 0 ;;
  *"pr edit"*) exit 0 ;;
  *"pr checks"*) exit "\$(cat "$STUB/ci_exit" 2>/dev/null || echo 0)" ;;
  *"pr merge"*) exit 0 ;;
  *) exit 0 ;;
esac
STUBEOF
  chmod +x "$STUB/bin/gh"

  # Notifier recorder: the runner invokes it as `<cmd> <event> <reason>`. Record
  # in an easily/portably greppable form (no literal tabs to match).
  cat >"$STUB/bin/notify" <<STUBEOF
#!/usr/bin/env bash
printf 'event=%s reason=%s\n' "\$1" "\$2" >>"$STUB/notify.log"
STUBEOF
  chmod +x "$STUB/bin/notify"

  # A notifier that BOTH records, then hangs and fails — to prove the seam is
  # non-fatal (a short timeout kills the hang; the non-zero exit is ignored).
  cat >"$STUB/bin/notify-bad" <<STUBEOF
#!/usr/bin/env bash
printf 'event=%s reason=%s\n' "\$1" "\$2" >>"$STUB/notify.log"
sleep 30
exit 1
STUBEOF
  chmod +x "$STUB/bin/notify-bad"

  # A notifier that IGNORES SIGTERM, so a plain \`timeout\` (TERM-only) could not
  # kill it — only \`timeout -k\` (TERM then KILL) bounds it. Proves the halt is
  # not stalled by a SIGTERM-resistant notifier. (\`sleep\` here honours TERM, so
  # the bad stub above never exercised this path.)
  cat >"$STUB/bin/notify-stubborn" <<STUBEOF
#!/usr/bin/env bash
printf 'event=%s reason=%s\n' "\$1" "\$2" >>"$STUB/notify.log"
trap '' TERM
sleep 30
exit 1
STUBEOF
  chmod +x "$STUB/bin/notify-stubborn"
}

# Run ralph.sh. Inner loop (RALPH_REVIEW_GATE=0) by default; per-scenario env is
# passed as VAR=val arguments and routed through `env` (a VAR=val from "$@"
# expansion is not treated as an assignment prefix by the shell, but env reads
# it). A later assignment wins, so "$@" overrides the defaults here.
run() {
  ( cd "$WS" && env PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 \
    RALPH_REVIEW_GATE=0 RALPH_BASE_BRANCH=main RALPH_LIMIT_POLL=0 RALPH_REVIEW_CI_MAX=2 \
    "$@" bash "$RALPH" ${RALPH_ARGS:-} )
}

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. agent-wrote-a-stop-reason halt notifies event=stop ------------------
new_ws
cat >"$STUB/count-1.sh" <<'S'
printf 'done: all tasks complete\n' >STATUS.md
S
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify" >/dev/null 2>&1
ec=$?
grep -q '^event=stop reason=.' "$STUB/notify.log" \
  && ok "stop halt notifies event=stop with a non-empty reason" \
  || bad "stop halt did not notify event=stop (log: $(cat "$STUB/notify.log"))"
[ "$ec" -eq 0 ] && ok "stop halt still exits 0 with a notifier set" || bad "stop exit was $ec (want 0)"
cleanup

# --- 2. consecutive-stall halt notifies event=stall ------------------------
new_ws
rm -f "$WS/STATUS.md"
# no snippets -> every turn is a no-commit stall
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify" RALPH_MAX_STALLS=2 >/dev/null 2>&1
ec=$?
grep -q '^event=stall reason=.' "$STUB/notify.log" \
  && ok "stall halt notifies event=stall with a non-empty reason" \
  || bad "stall halt did not notify event=stall (log: $(cat "$STUB/notify.log"))"
[ "$ec" -eq 1 ] && ok "stall halt still exits 1 with a notifier set" || bad "stall exit was $ec (want 1)"
cleanup

# --- 3. review-exhausted halt notifies event=review-exhausted (gate ON) -----
new_ws
printf 'still wrong\n' >"$STUB/findings"
for n in 1 2 3 4; do
  cat >"$STUB/count-${n}.sh" <<'S'
git commit --allow-empty -qm work
S
done
RALPH_ARGS="" run RALPH_REVIEW_GATE=1 RALPH_REVIEW_MAX_ROUNDS=2 RALPH_MAX_STALLS=9 \
  RALPH_NOTIFY_CMD="$STUB/bin/notify" >/dev/null 2>&1
ec=$?
[ "$ec" -eq 1 ] && grep -q '^event=review-exhausted reason=.' "$STUB/notify.log" \
  && ok "review-exhausted halt notifies event=review-exhausted" \
  || bad "review-exhausted notify missing (exit=$ec, log: $(cat "$STUB/notify.log"))"
cleanup

# --- 4. blocked question: immediate stop, NOT a stall, persisted, notified --
new_ws
rm -f "$WS/STATUS.md"
cat >"$STUB/count-1.sh" <<'S'
mkdir -p docs
printf -- '- Should the cache be write-through or write-back?\n' >>docs/questions.md
S
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify" RALPH_MAX_STALLS=2 >/dev/null 2>&1
ec=$?
turns=$(cat "$WS/.ralph/turn")
grep -q '^event=blocked reason=.' "$STUB/notify.log" \
  && ok "blocked question notifies event=blocked with a non-empty reason" \
  || bad "blocked question did not notify event=blocked (log: $(cat "$STUB/notify.log"))"
[ "$turns" = 1 ] \
  && ok "blocked stop fires after ONE turn (never counted toward MAX_STALLS)" \
  || bad "blocked stop took $turns turns (should stop on the first, not stall)"
grep -q '^event=stall' "$STUB/notify.log" \
  && bad "a blocked stop must NOT also fire a stall event" \
  || ok "blocked stop did not also fire a stall event"
[ "$ec" -eq 1 ] && ok "blocked stop exits 1 (needs human)" || bad "blocked exit was $ec (want 1)"
python3 -c "import json,sys;d=json.load(open('$WS/.ralph/current.json'));sys.exit(0 if d.get('blocked') and d.get('state')=='blocked' else 1)" 2>/dev/null \
  && ok "blocked decision persisted to current.json (readable by /ralph-status)" \
  || bad "blocked state not persisted in current.json"
# the blocked write must MERGE into the heartbeat, not clobber task/model/started.
python3 -c "import json,sys;d=json.load(open('$WS/.ralph/current.json'));sys.exit(0 if d.get('task') and d.get('started') else 1)" 2>/dev/null \
  && ok "blocked current.json keeps the heartbeat fields (task/started not clobbered)" \
  || bad "blocked current.json clobbered the heartbeat (task/started lost)"
cleanup

# --- 5. a pre-existing questions.md does NOT trigger a blocked stop ---------
new_ws
rm -f "$WS/STATUS.md"
mkdir -p "$WS/docs"
printf -- '- old pre-existing question from a prior run\n' >"$WS/docs/questions.md"
git -C "$WS" add -A
git -C "$WS" commit -qm "seed questions"
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
S
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify" >/dev/null 2>&1
turns=$(cat "$WS/.ralph/turn")
grep -q '^event=blocked' "$STUB/notify.log" \
  && bad "a pre-existing (unchanged) questions.md must NOT trigger blocked" \
  || ok "pre-existing questions.md is ignored (no blocked stop)"
[ "$turns" -ge 2 ] \
  && ok "loop continued past a pre-existing question list (turns=$turns)" \
  || bad "loop stopped early on a pre-existing question (turns=$turns)"
cleanup

# --- 5b. a question added on a COMMITTING turn must not false-block a later turn
new_ws
rm -f "$WS/STATUS.md"
# turn 1: append a question AND commit (real progress) — must NOT block.
cat >"$STUB/count-1.sh" <<'S'
mkdir -p docs
printf -- '- A question raised alongside real progress?\n' >>docs/questions.md
git add -A
git commit -qm "work + note a question"
S
# turn 2: a plain no-commit stall that adds NO new question — must NOT block. (With
# a stale startup snapshot, questions_now != questions_start would falsely fire it.)
# turn 3: a clean stop.
cat >"$STUB/count-3.sh" <<'S'
printf 'done: stop\n' >STATUS.md
S
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify" RALPH_MAX_STALLS=5 >/dev/null 2>&1
turns=$(cat "$WS/.ralph/turn")
grep -q '^event=blocked' "$STUB/notify.log" \
  && bad "a question added on a COMMITTING turn must not block a later unrelated turn" \
  || ok "a committed question-write does not false-block a subsequent no-commit turn"
[ "$turns" -ge 3 ] \
  && ok "loop ran past the committed question-write to a real stop (turns=$turns)" \
  || bad "loop halted early after a committed question-write (turns=$turns)"
cleanup

# --- 6. non-fatal: a failing + slow notifier never changes exit code/flow ---
new_ws
cat >"$STUB/count-1.sh" <<'S'
printf 'done: stop\n' >STATUS.md
S
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify-bad" RALPH_NOTIFY_TIMEOUT=1 >/dev/null 2>&1
ec=$?
[ "$ec" -eq 0 ] \
  && ok "a failing+slow notifier does not change the halt's exit code (stop still 0)" \
  || bad "non-fatal contract violated — exit was $ec (want 0)"
grep -q '^event=stop ' "$STUB/notify.log" \
  && ok "the failing notifier was still invoked (and its failure swallowed)" \
  || bad "notifier was not invoked at the stop halt"
cleanup

# --- 6b. non-fatal even for a SIGTERM-IGNORING notifier (hard-kill bound) ----
new_ws
cat >"$STUB/count-1.sh" <<'S'
printf 'done: stop\n' >STATUS.md
S
t0=$SECONDS
RALPH_ARGS="" run RALPH_NOTIFY_CMD="$STUB/bin/notify-stubborn" RALPH_NOTIFY_TIMEOUT=1 >/dev/null 2>&1
ec=$?
elapsed=$((SECONDS - t0))
[ "$ec" -eq 0 ] \
  && ok "a SIGTERM-ignoring notifier does not change the halt's exit code (stop still 0)" \
  || bad "non-fatal violated for a TERM-ignoring notifier — exit was $ec"
[ "$elapsed" -lt 15 ] \
  && ok "a SIGTERM-ignoring notifier is hard-killed — halt bounded (${elapsed}s, well under the 30s sleep)" \
  || bad "halt stalled ${elapsed}s — 'timeout -k' is not bounding a TERM-resistant notifier"
cleanup

# --- 7. unset RALPH_NOTIFY_CMD = no notification, behaviour unchanged --------
new_ws
cat >"$STUB/count-1.sh" <<'S'
printf 'done: stop\n' >STATUS.md
S
RALPH_ARGS="" run >/dev/null 2>&1   # NOTE: no RALPH_NOTIFY_CMD
ec=$?
[ "$ec" -eq 0 ] && [ ! -s "$STUB/notify.log" ] \
  && ok "unset notifier = no notification + unchanged exit code" \
  || bad "unset notifier misbehaved (exit=$ec, notify lines=$(wc -l <"$STUB/notify.log"))"
cleanup

# --- 8. a non-executable RALPH_NOTIFY_CMD refuses to start ------------------
new_ws
RALPH_ARGS="--once" run RALPH_NOTIFY_CMD="/no/such/notifier" >/dev/null 2>&1
[ $? -ne 0 ] \
  && ok "a non-executable RALPH_NOTIFY_CMD refuses to start" \
  || bad "a bad RALPH_NOTIFY_CMD should refuse to start"
cleanup

# --- 8b. a RALPH_NOTIFY_CMD that resolves to a shell builtin refuses ---------
# `:` passes a bare `command -v`, but the notifier is exec'd via `timeout` (not a
# shell), so a builtin would only fail at halt-time. Validation must reject it.
new_ws
RALPH_ARGS="--once" run RALPH_NOTIFY_CMD=":" >/dev/null 2>&1
[ $? -ne 0 ] \
  && ok "a builtin-only RALPH_NOTIFY_CMD (':') refuses to start (timeout needs a real file)" \
  || bad "':' passed validation but would fail at halt-time under timeout"
cleanup

echo
echo "notify tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
