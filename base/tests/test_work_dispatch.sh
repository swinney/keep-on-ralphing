#!/usr/bin/env bash
# Work-class model dispatch tests for ralph.sh — git-fixture based, no real `claude`.
#
# The operator tags a tasks.md task with a trailing work-class token, e.g.
# "(stateful)"; the runner maps that class to a model via the RALPH_MODEL_<CLASS>
# dispatch table and passes it as `claude --model` for that turn. An untagged task
# uses the existing RALPH_MODEL default, byte-for-byte as before. Classification is
# an explicit operator act — the runner NEVER auto-classifies.
#
# The stub `claude` records the --model it received per invocation (in $STUB/models),
# so dispatch is assertable with no real agent and no network.
#
# Run:  bash base/tests/test_work_dispatch.sh
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

# Build a fresh workspace whose first unchecked task is $1 (so the test can tag it
# with a work class or leave it untagged). Stub records the --model per turn.
new_ws() {
  local first_task="$1"
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
  printf -- '%s\n' "$first_task" >"$WS/tasks.md"
  git -C "$WS" add -A
  git -C "$WS" commit -qm init

  cat >"$STUB/bin/claude" <<STUBEOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
c_file="$STUB/count"
n=\$(cat "\$c_file" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"\$c_file"
# Record the --model arg (or "default" when unset) for THIS invocation.
model="default"
while [ \$# -gt 0 ]; do
  case "\$1" in
    --model) model="\${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' "\$model" >>"$STUB/models"
# Commit so the turn is productive (keeps --once exit 0; irrelevant to model capture).
git commit --allow-empty -qm "turn \$n" >/dev/null 2>&1 || true
exit 0
STUBEOF
  chmod +x "$STUB/bin/claude"
}

# Run one --once turn with the dispatch env, capturing nothing (we assert on files).
run_once() {
  ( cd "$WS" && PATH="$STUB/bin:$PATH" HOME="$HOME_DIR" \
    RALPH_WORKSPACE="$WS" RALPH_STATE_DIR=.ralph RALPH_REVIEW_GATE=0 \
    "$@" bash "$RALPH" --once >/dev/null 2>&1 )
}

# First model recorded by the stub (turn 1).
model_seen() { head -1 "$STUB/models" 2>/dev/null; }

cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

# --- 1. A stateful-tagged task uses the mapped (stronger) model from turn 1 ---
new_ws '- [ ] 2.3 migrate the session store (stateful)'
RALPH_MODEL="base-model" RALPH_MODEL_STATEFUL="strong-model" run_once
[ "$(model_seen)" = "strong-model" ] \
  && ok "stateful-tagged task dispatches RALPH_MODEL_STATEFUL from turn 1" \
  || bad "stateful dispatch wrong (got '$(model_seen)', want strong-model)"
cleanup

# --- 2. An untagged task uses the default model unchanged --------------------
new_ws '- [ ] 1.1 a plain well-specified task'
RALPH_MODEL="base-model" RALPH_MODEL_STATEFUL="strong-model" run_once
[ "$(model_seen)" = "base-model" ] \
  && ok "untagged task uses the default RALPH_MODEL (dispatch table ignored)" \
  || bad "untagged task wrong (got '$(model_seen)', want base-model)"
cleanup

# --- 3. A tagged class with no table entry falls back to RALPH_MODEL ---------
new_ws '- [ ] 1.1 a well-specified pure task (pure)'
RALPH_MODEL="base-model" run_once   # no RALPH_MODEL_PURE set
[ "$(model_seen)" = "base-model" ] \
  && ok "tagged class with no mapping falls back to RALPH_MODEL" \
  || bad "unmapped class fallback wrong (got '$(model_seen)', want base-model)"
cleanup

# --- 4. Untagged + no RALPH_MODEL → no --model passed (account default) ------
new_ws '- [ ] 1.1 plain task, no model configured'
run_once   # neither RALPH_MODEL nor any RALPH_MODEL_* set
[ "$(model_seen)" = "default" ] \
  && ok "untagged + no RALPH_MODEL passes no --model (account default)" \
  || bad "no-model case wrong (got '$(model_seen)', want default)"
cleanup

# --- 5. The dispatched model is recorded in status.jsonl --------------------
new_ws '- [ ] 2.1 stateful integration work (stateful)'
RALPH_MODEL="base-model" RALPH_MODEL_STATEFUL="strong-model" run_once
python3 - "$WS/.ralph/status.jsonl" strong-model <<'PY' \
  && ok "status.jsonl records the dispatched per-turn model" \
  || bad "status.jsonl model not the dispatched model"
import json, sys
rec = json.loads(open(sys.argv[1]).read().splitlines()[-1])
sys.exit(0 if rec["model"] == sys.argv[2] else 1)
PY
cleanup

# --- 6. env RALPH_MODEL_<CLASS> overrides ralph.conf (precedence) ------------
new_ws '- [ ] 3.2 a stateful migration (stateful)'
printf 'RALPH_MODEL="base-model"\nRALPH_MODEL_STATEFUL="conf-model"\n' >"$WS/ralph.conf"
RALPH_MODEL_STATEFUL="env-model" run_once
[ "$(model_seen)" = "env-model" ] \
  && ok "env RALPH_MODEL_<CLASS> overrides ralph.conf (env > conf)" \
  || bad "dispatch-table precedence wrong (got '$(model_seen)', want env-model)"
cleanup

# --- 7. Class normalization: a hyphen/upper tag maps to the _ upper env key --
new_ws '- [ ] 4.1 cross-service integration (pure-logic)'
RALPH_MODEL="base-model" RALPH_MODEL_PURE_LOGIC="logic-model" run_once
[ "$(model_seen)" = "logic-model" ] \
  && ok "class tag '(pure-logic)' maps to RALPH_MODEL_PURE_LOGIC" \
  || bad "class normalization wrong (got '$(model_seen)', want logic-model)"
cleanup

echo
echo "work-dispatch tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
