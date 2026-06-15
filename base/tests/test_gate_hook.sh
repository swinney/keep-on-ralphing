#!/usr/bin/env bash
# Behavioural test for the scaffolded gate hook — git-fixture based.
#
# Renders the ACTUAL plugin templates (templates/pre-commit.template and
# templates/gate.sh.template) into a throwaway repo, wires them up exactly as the
# Makefile `hooks` target does (git config core.hooksPath hooks), and asserts the
# central claim of the gate-enforcement spec: a RED gate aborts the commit (HEAD
# unchanged) and a GREEN gate lets it through. This proves a red turn produces no
# commit — which ralph.sh counts as a stall — without involving the loop runner.
#
# Run:  bash base/tests/test_gate_hook.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, git.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATES="$HERE/../../templates"

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

# Build a fresh repo with the gate wired up the way /ralph-init + `make hooks` do:
# render gate.sh from its template (substituting the gate command), copy the hook
# template verbatim, and point core.hooksPath at the tracked hooks/ dir.
# $1 is the gate command substituted for {{GATE_COMMAND}} (`true` green, `false` red).
# The baseline commit is made BEFORE the hook is wired, so the repo always has a
# clean HEAD to compare against regardless of the test's gate command.
new_repo() {
  REPO=$(mktemp -d)
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t

  printf 'seed\n' >"$REPO/file.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm init   # no hook active yet → clean baseline HEAD

  mkdir -p "$REPO/scripts" "$REPO/hooks"
  sed "s|{{GATE_COMMAND}}|$1|" "$TEMPLATES/gate.sh.template" >"$REPO/scripts/gate.sh"
  cp "$TEMPLATES/pre-commit.template" "$REPO/hooks/pre-commit"
  chmod +x "$REPO/scripts/gate.sh" "$REPO/hooks/pre-commit"
  git -C "$REPO" config core.hooksPath hooks
}

cleanup() { [ -n "${REPO:-}" ] && rm -rf "$REPO"; }
trap cleanup EXIT

# --- 1. RED gate aborts the commit; HEAD unchanged --------------------------
new_repo false
before=$(git -C "$REPO" rev-parse HEAD)
printf 'change\n' >>"$REPO/file.txt"
git -C "$REPO" add -A
( cd "$REPO" && git commit -qm "should be blocked" ) >/dev/null 2>&1
ec=$?
after=$(git -C "$REPO" rev-parse HEAD)
[ "$ec" -ne 0 ] && ok "red gate makes commit exit non-zero" || bad "red gate commit exit was $ec (want non-zero)"
[ "$before" = "$after" ] && ok "red gate leaves HEAD unchanged (no commit)" || bad "red gate still advanced HEAD"
cleanup

# --- 2. GREEN gate allows the commit; HEAD advances -------------------------
new_repo true
before=$(git -C "$REPO" rev-parse HEAD)
printf 'change\n' >>"$REPO/file.txt"
git -C "$REPO" add -A
( cd "$REPO" && git commit -qm "should pass" ) >/dev/null 2>&1
ec=$?
after=$(git -C "$REPO" rev-parse HEAD)
[ "$ec" -eq 0 ] && ok "green gate lets the commit exit 0" || bad "green gate commit exit was $ec (want 0)"
[ "$before" != "$after" ] && ok "green gate advances HEAD (commit created)" || bad "green gate did not create a commit"
cleanup

# --- 3. the hook actually runs gate.sh (not a no-op) ------------------------
# A red gate that also writes a marker proves the hook executed the script. git
# runs hooks with cwd at the repo top level, so a relative marker lands there.
new_repo 'echo RAN > .gate-ran; false'
printf 'change\n' >>"$REPO/file.txt"
git -C "$REPO" add -A
( cd "$REPO" && git commit -qm "blocked but ran" ) >/dev/null 2>&1
[ -f "$REPO/.gate-ran" ] && ok "pre-commit hook actually invokes scripts/gate.sh" \
  || bad "hook did not run scripts/gate.sh"
cleanup

echo
echo "gate hook tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
