#!/usr/bin/env bash
# Behavioural test scaffold for the opt-in outer-loop REVIEW GATE in ralph.sh.
#
# Same philosophy as test_ralph_runner.sh: a throwaway git repo is the workspace,
# a STUB `claude` scripts the agent turns, and — new here — a STUB `gh` plus a
# bare `origin` remote let the runner do its real push -> PR -> review -> verdict
# -> merge orchestration with NO network and NO real GitHub. The gh stub logs
# every call to $STUB/gh.log and returns scripted results ($STUB/pr_number,
# $STUB/ci_exit, $STUB/findings), so each scenario asserts exact runner behaviour.
#
# Run:  bash base/tests/test_review_gate.sh
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

# Build a workspace: git repo + bare origin remote + a feature branch + stub
# claude + stub gh. Scripted gh results live in files the test sets per scenario.
new_gate_ws() {
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

  # A bare remote so `git push` is real; then a feature branch to PR from.
  git init --bare -q "$WS/origin.git"
  git -C "$WS" remote add origin "$WS/origin.git"
  git -C "$WS" push -q origin main
  git -C "$WS" checkout -q -b feat

  # Scripted gh state (per-scenario overridable).
  : >"$STUB/pr_number"   # empty -> `pr view` reports "no PR" until `pr create`
  echo 0 >"$STUB/ci_exit" # gh pr checks exit: 0=pass, 8=pending, other=fail
  : >"$STUB/findings"     # reviewer findings, one per line (empty = clean)
  : >"$STUB/gh.log"

  # Stub claude (count-keyed snippets, same contract as test_ralph_runner.sh).
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

  # Stub gh: log every call, dispatch on the argument shape.
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
}

# Extra per-scenario env is passed as VAR=val arguments; route through `env` so
# they are applied even though they arrive via "$@" expansion (a VAR=val from an
# expansion is NOT treated as an assignment prefix by the shell, but env reads it).
run_gate() {
  ( cd "$WS" && env PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 \
    RALPH_REVIEW_GATE=1 RALPH_BASE_BRANCH=main RALPH_LIMIT_POLL=0 RALPH_REVIEW_CI_MAX=2 \
    "$@" bash "$RALPH" ${RALPH_ARGS:-} )
}

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. gate explicitly OFF → no gh use at all, inner loop unchanged --------
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm t1
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" RALPH_WORKSPACE="$WS" \
  RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 RALPH_REVIEW_GATE=0 bash "$RALPH" >/dev/null 2>&1 )
ec=$?
[ "$ec" -eq 0 ] && [ ! -s "$STUB/gh.log" ] \
  && ok "gate off: inner loop runs and never calls gh" \
  || bad "gate off should not touch gh (exit=$ec, gh.log $(wc -l <"$STUB/gh.log") lines)"
cleanup

# --- 2a. gate ON but working branch == base → refuse ------------------------
new_gate_ws
git -C "$WS" checkout -q main
RALPH_ARGS="" run_gate >/dev/null 2>&1
[ $? -ne 0 ] && ok "gate on base branch refuses to start" || bad "should refuse on base branch"
cleanup

# --- 2b. gate ON but no remote → refuse -------------------------------------
new_gate_ws
git -C "$WS" remote remove origin
RALPH_ARGS="" run_gate >/dev/null 2>&1
[ $? -ne 0 ] && ok "gate without a remote refuses to start" || bad "should refuse without remote"
cleanup

# --- 3. clean review + green CI, auto-merge OFF → PASS, PR parked -----------
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_gate >/dev/null 2>&1
grep -q "pr create" "$STUB/gh.log" && ok "PASS path opens a PR" || bad "no PR opened"
grep -q "pr merge" "$STUB/gh.log" && bad "auto-merge OFF should NOT merge" || ok "auto-merge off parks the PR (no merge)"
[ ! -s "$WS/review-findings.md" ] && ok "clean review leaves review-findings.md empty" || bad "review-findings.md should be empty on PASS"
cleanup

# --- 4. clean + green + auto-merge ON → merges ------------------------------
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_gate RALPH_AUTO_MERGE=1 >/dev/null 2>&1
grep -q "pr merge" "$STUB/gh.log" && ok "auto-merge ON merges a PASSED PR" || bad "auto-merge on should merge"
cleanup

# --- 5. findings → written to review-findings.md, then resolved & cleared ---
new_gate_ws
printf 'enum should be a string\n' >"$STUB/findings"
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
# turn 2 = agent resolves the finding (clears the stub) and commits.
cat >"$STUB/count-2.sh" <<S
: >"$STUB/findings"
git commit --allow-empty -qm fix
S
cat >"$STUB/count-3.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t3
S
RALPH_ARGS="" run_gate >/dev/null 2>&1
[ ! -s "$WS/review-findings.md" ] \
  && ok "findings recorded then cleared after a passing re-review" \
  || bad "review-findings.md should be cleared once review passes"
cleanup

# --- 6. persistent findings → bounded rounds halt to STATUS.md (exit 1) -----
new_gate_ws
printf 'still wrong\n' >"$STUB/findings"
for n in 1 2 3 4; do
  cat >"$STUB/count-${n}.sh" <<'S'
git commit --allow-empty -qm work
S
done
RALPH_ARGS="" run_gate RALPH_REVIEW_MAX_ROUNDS=2 RALPH_MAX_STALLS=9 >/dev/null 2>&1
ec=$?
[ "$ec" -eq 1 ] && ok "exhausted review rounds halt (exit 1)" || bad "review-round halt exit was $ec"
grep -qi "review gate still failing" "$WS/STATUS.md" \
  && ok "review-round halt wrote a STATUS.md reason" || bad "no review-round STATUS.md reason"
cleanup

# --- 7. pending CI is bounded and routed as a finding, not a stall halt -----
new_gate_ws
echo 8 >"$STUB/ci_exit" # gh pr checks: pending forever
for n in 1 2 3 4; do
  cat >"$STUB/count-${n}.sh" <<'S'
git commit --allow-empty -qm work
S
done
RALPH_ARGS="" run_gate RALPH_REVIEW_MAX_ROUNDS=2 RALPH_MAX_STALLS=2 >/dev/null 2>&1
ec=$?
# Halts via review rounds (1), not a stall (committing turns), and didn't hang.
[ "$ec" -eq 1 ] && grep -qi "review gate still failing" "$WS/STATUS.md" \
  && ok "pending CI is bounded, recorded as a finding, halts via rounds not stalls" \
  || bad "pending CI handling wrong (exit=$ec)"
cleanup

# --- 8. default reviewer (no override) requests a Copilot review ------------
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_gate >/dev/null 2>&1
grep -q "add-reviewer" "$STUB/gh.log" \
  && ok "default reviewer requests a Copilot review via gh" || bad "default path didn't request Copilot"
cleanup

# --- 9. reviewer seam: RALPH_REVIEWER overrides Copilot ---------------------
new_gate_ws
cat >"$STUB/bin/myreviewer" <<'S'
#!/usr/bin/env bash
echo "custom-reviewer finding"
S
chmod +x "$STUB/bin/myreviewer"
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_gate RALPH_REVIEWER="$STUB/bin/myreviewer" >/dev/null 2>&1
grep -q "custom-reviewer finding" "$WS/review-findings.md" \
  && ok "alternative reviewer's findings are used" || bad "RALPH_REVIEWER findings not used"
grep -q "add-reviewer" "$STUB/gh.log" \
  && bad "override should NOT request Copilot" || ok "override bypasses the Copilot request"
cleanup

# --- 10. gate is ON BY DEFAULT: unset RALPH_REVIEW_GATE refuses without GitHub -
new_gate_ws
git -C "$WS" remote remove origin
# Note: RALPH_REVIEW_GATE is NOT set here — it must default ON and refuse.
( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" RALPH_WORKSPACE="$WS" \
  RALPH_STATE_DIR=.ralph RALPH_POLL_INTERVAL=0 RALPH_BASE_BRANCH=main bash "$RALPH" >/dev/null 2>&1 )
[ $? -ne 0 ] && ok "review gate is ON by default (unset gate + no remote refuses)" \
  || bad "default did not behave as ON (should have refused without a remote)"
cleanup

# --- 11. gate ON configures token-backed HTTPS push (gh setup-git + SSH->HTTPS) -
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
RALPH_ARGS="" run_gate >/dev/null 2>&1
grep -q "auth setup-git" "$STUB/gh.log" \
  && ok "gate on runs 'gh auth setup-git' (token-backed git credential)" \
  || bad "runner did not configure gh as the git credential helper"
git config --file "$HOME_DIR/.gitconfig" --get url."https://github.com/".insteadOf 2>/dev/null | grep -q "git@github.com:" \
  && ok "gate on rewrites SSH GitHub remotes to HTTPS for push" \
  || bad "runner did not set the SSH->HTTPS insteadOf rewrite"
cleanup

# --- 12. a failed branch push is surfaced, not silently swallowed -----------
new_gate_ws
cat >"$STUB/count-1.sh" <<'S'
git commit --allow-empty -qm work
S
cat >"$STUB/count-2.sh" <<'S'
printf 'done: stop\n' >STATUS.md
git commit --allow-empty -qm t2
S
# Point origin at a non-existent path so `git push` fails (not a github URL, so
# the insteadOf rewrite leaves it alone — the push genuinely cannot land).
git -C "$WS" remote set-url origin "$WS/does-not-exist.git"
out=$(RALPH_ARGS="" run_gate 2>&1)
printf '%s' "$out" | grep -q "could not push" \
  && ok "failed push is reported (not swallowed by || true)" \
  || bad "a failing push was hidden — expected a 'could not push' message"
cleanup

echo
echo "review-gate tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
