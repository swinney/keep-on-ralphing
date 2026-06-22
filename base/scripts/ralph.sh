#!/usr/bin/env bash
# Ralph Loop runner — project-agnostic.
#
# Drives an LLM coding agent through a task list one turn at a time, using the
# commit graph as the objective progress signal. Designed to run inside a
# sandbox container (see the Containerfile/Makefile templates) but works on any
# host with bash, git, and the `claude` CLI on PATH.
#
# Configuration (all optional; precedence: environment > ralph.conf > default):
#   RALPH_WORKSPACE     project dir to operate in            (default: $PWD)
#   RALPH_CONF          path to the config file to source    (default: ./ralph.conf)
#   RALPH_TASKS         task-list file, relative to workspace (default: tasks.md)
#   RALPH_STATE_DIR     runtime state dir, gitignored        (default: .ralph)
#   RALPH_MODEL         passed to `claude --model`           (default: account default)
#   RALPH_TURN_TIMEOUT  per-turn wall-clock cap, seconds     (default: 1200 = 20 min)
#   RALPH_MAX_STALLS    consecutive no-commit turns to halt  (default: 2)
#   RALPH_LIMIT_POLL    fallback wait on an unparseable limit (default: 900 = 15 min)
#   RALPH_POLL_INTERVAL inter-turn sleep in loop mode, seconds (default: 30)
#
# Outer-loop review gate. RALPH_REVIEW_GATE is ON by default — independent review
# is the highest-value gate — so loop mode needs a git remote + an authenticated
# gh + a non-base working branch, and REFUSES to start without them. Set
# RALPH_REVIEW_GATE=0 to run the offline inner loop only.
#   RALPH_REVIEW_GATE      1 to push -> PR -> independent review after a commit  (default: 1, ON)
#   RALPH_AUTO_MERGE       1 to merge a PASSED PR; else park it for a human      (default: 0)
#   RALPH_REVIEW_MAX_ROUNDS consecutive finding-producing rounds before halt     (default: 3)
#   RALPH_BASE_BRANCH      PR base branch; empty = origin's default branch       (default: auto)
#   RALPH_REVIEWER         reviewer command (run as: <cmd> <pr-number>, prints
#                          findings, empty = clean); empty = GitHub Copilot      (default: Copilot)
#
# Usage:
#   ralph.sh            loop until STATUS.md gets a stop reason, SIGINT, or stall
#   ralph.sh --once     run exactly ONE logged turn, then exit with its code
#
# Stop conditions (loop mode):
#   * <workspace>/STATUS.md becomes NON-EMPTY with NEW content (the agent wrote a
#     stop reason). A pre-existing breadcrumb does NOT stop a fresh loop.
#   * RALPH_MAX_STALLS consecutive turns make no new commit (hung/timed-out or
#     stuck-on-red) — the loop writes STATUS.md and exits 1 rather than spin.
#   * SIGINT (Ctrl-C) from the operator.
#
# Resilience: each turn is wrapped in `timeout`, so a hung turn is killed and
# retried next iteration; the loop only gives up after RALPH_MAX_STALLS in a row
# produce no commit. A usage-limit turn is NOT a stall — the loop waits for the
# window to refresh (until_reset.py parses the reset time; RALPH_LIMIT_POLL on a
# parse miss) and replays the SAME task.
#
# State outputs (under $RALPH_STATE_DIR/, gitignored — read via the status script):
#   log/turn-<n>.txt   per-turn output, line-buffered so `tail -f` is live
#   current.json       heartbeat: the turn running right now
#   status.jsonl       objective git-derived record appended per completed turn
#   turn               turn counter

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- config loading: environment > ralph.conf > built-in default ------------
# Snapshot any RALPH_* already set in the environment as re-runnable assignments;
# these win over the file. Uses printf %q + eval rather than an associative
# array so the kit also runs on bash 3.2 (e.g. stock macOS).
_env_override=$(
  while IFS= read -r _v; do
    printf '%s=%q\n' "$_v" "${!_v}"
  done < <(compgen -v | grep '^RALPH_' || true)
)

conf="${RALPH_CONF:-ralph.conf}"
# shellcheck disable=SC1090
[ -f "$conf" ] && . "$conf"

# Re-apply the environment overrides on top of whatever the file set.
[ -n "$_env_override" ] && eval "$_env_override"

cd "${RALPH_WORKSPACE:-$PWD}" || {
  echo "ralph: cannot cd into RALPH_WORKSPACE='${RALPH_WORKSPACE:-$PWD}' — refusing to start" >&2
  exit 1
}

# Preflight the external commands the loop assumes, so a missing tool fails fast
# with a clear message instead of an opaque error mid-turn.
for _cmd in git claude timeout; do
  command -v "$_cmd" >/dev/null 2>&1 || {
    echo "ralph: required command '$_cmd' not found on PATH — refusing to start" >&2
    exit 1
  }
done

once=0
[ "${1:-}" = "--once" ] && once=1

turn_timeout=${RALPH_TURN_TIMEOUT:-1200}
max_stalls=${RALPH_MAX_STALLS:-2}
limit_poll=${RALPH_LIMIT_POLL:-900}
tasks_file=${RALPH_TASKS:-tasks.md}
state_dir=${RALPH_STATE_DIR:-.ralph}
poll_interval=${RALPH_POLL_INTERVAL:-30}
# Outbound notification seam: a pluggable command the RUNNER invokes as
# `<cmd> <event> <reason>` at every needs-human halt. Empty = off (opt-in; no
# notification side effects when unset). Plain ${VAR:-default} reads suffice —
# the env-over-conf snapshot at the top already gives these precedence. bash 3.2-safe.
notify_cmd=${RALPH_NOTIFY_CMD:-}
notify_timeout=${RALPH_NOTIFY_TIMEOUT:-30}
# The file the PROMPT contract has the agent write when it hits a decision the
# specs don't cover; a NEW entry mid-run is a blocked-stop signal (like STATUS.md).
questions_file=${RALPH_QUESTIONS:-docs/questions.md}
# Aggregate log: a single append-only tail target (runner narration + agent
# output, turn-prefixed) for an external aggregator. On by default; =0 reproduces
# the pre-feature behaviour exactly. See the Vector recipe in docs/.
live_log_enabled=${RALPH_LIVE_LOG:-1}

if [ ! -f PROMPT.md ]; then
  echo "ralph: PROMPT.md missing in $(pwd) — refusing to start" >&2
  exit 1
fi

# Auth comes from the bind-mounted $HOME/.claude (populated by `make login`). If
# it isn't there, refuse to start rather than burn turns waiting for an
# interactive login that will never come.
if [ ! -d "$HOME/.claude" ] || [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
  echo "ralph: $HOME/.claude is empty — run 'make login' on the host first" >&2
  exit 1
fi

# Claude Code's config is ~/.claude.json — a SIBLING of ~/.claude (the only thing
# we persist), so it's missing on every fresh container. Restore it from the
# newest backup (kept inside the persisted .claude/backups) so each container
# starts clean and quiet.
if [ ! -f "$HOME/.claude.json" ]; then
  newest_backup=$(ls -t "$HOME"/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
  if [ -n "$newest_backup" ]; then
    cp "$newest_backup" "$HOME/.claude.json"
  else
    echo '{}' >"$HOME/.claude.json"
  fi
fi

mkdir -p "$state_dir/log"
turn_file="$state_dir/turn"
turn=$(cat "$turn_file" 2>/dev/null || echo 0)
live_log="$state_dir/log/live.log"

# The agent-output fan-out pipes through python3 + ralph_prefix.py. python3 is
# OPTIONAL in this runner (emit_status no-ops without it; the preflight does not
# require it), so don't let live logging turn a missing interpreter/helper into a
# broken output pipe: if the prefixer can't start, the fan-out's sink closes and
# tee takes SIGPIPE once the agent exceeds a pipe buffer — truncating turn-N.txt /
# stdout and masking the agent's exit code with 141. Degrade gracefully instead.
if [ "$live_log_enabled" = 1 ] &&
  { ! command -v python3 >/dev/null 2>&1 || [ ! -f "$script_dir/ralph_prefix.py" ]; }; then
  echo "ralph: RALPH_LIVE_LOG=1 but python3 or ralph_prefix.py is unavailable — disabling live.log for this run" >&2
  live_log_enabled=0
fi

# Same failure, different cause: if the sink path is not appendable (a read-only
# bind-mount, or a stale directory sitting at live.log), the fan-out's
# `>> "$live_log"` redirect fails before the prefixer reads, closing the pipe and
# triggering the same tee SIGPIPE / truncation. Preflight with a no-op append.
if [ "$live_log_enabled" = 1 ] && ! (: >>"$live_log") 2>/dev/null; then
  echo "ralph: RALPH_LIVE_LOG=1 but $live_log is not writable — disabling live.log for this run" >&2
  live_log_enabled=0
fi

model_args=()
[ -n "${RALPH_MODEL:-}" ] && model_args=(--model "$RALPH_MODEL")

# Validate the optional notifier up front (independent of the review gate — it
# fires at the stall/stop/blocked halts too, which run with the gate off): a
# configured-but-unrunnable notifier refuses to start rather than failing silently
# at a halt, when the operator most needs the ping. Unlike RALPH_REVIEWER (invoked
# directly in the shell, so a builtin/function is fine), the notifier is exec'd via
# `timeout` — a real executable FILE — so a bare `command -v` (which also accepts
# builtins/functions/aliases) is too lax: resolve the actual exec target and
# require it to be an -x file, or it would only fail at halt-time.
if [ -n "$notify_cmd" ]; then
  case "$notify_cmd" in
    */*) notify_exe="$notify_cmd" ;;                          # explicit path -> use as-is
    *)   notify_exe=$(command -v "$notify_cmd" 2>/dev/null) ;; # bare name -> PATH lookup
  esac
  if [ -z "$notify_exe" ] || [ ! -x "$notify_exe" ]; then
    echo "ralph: RALPH_NOTIFY_CMD='$notify_cmd' is not an executable file — refusing to start" >&2
    exit 1
  fi
fi

head_rev() { git rev-parse HEAD 2>/dev/null || echo none; }

# Append one line to the aggregate live.log, turn-prefixed and timestamped to
# match ralph_prefix.py's format. Single runner lines use this shell-side
# formatter (no pipe); the high-volume agent output goes through ralph_prefix.py
# in run_turn. No-op when RALPH_LIVE_LOG=0.
_live_append() {
  [ "${live_log_enabled:-1}" = 1 ] || return 0
  printf '%s turn=%s | %s\n' "$(date -Is)" "${turn:-0}" "$*" >>"$live_log" 2>/dev/null || true
}

# Narrate one runner line: to stdout (the live terminal / `podman logs` view) AND
# the aggregate live.log, so the loop's own orchestration story is part of the
# single stream a tailer follows — not terminal-only as it was before.
narrate() {
  echo "$@"
  _live_append "$@"
}

# Collapse multi-line text (read from stdin) to a single trimmed line, so a halt
# reason drawn from STATUS.md / questions.md is one clean line for a notification.
oneline() { tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }

# Fire the operator notifier at a needs-human halt: RALPH_NOTIFY_CMD invoked as
# `<cmd> <event> <reason>` under a short timeout. NON-FATAL by contract — a
# notifier that errors, hangs, or is slow is killed/ignored and never changes the
# loop's exit code or control flow (the caller exits with its own explicit code
# regardless). The `-k 2` mirrors the turn invocation: after $notify_timeout we
# send TERM, then KILL 2s later, so even a SIGTERM-ignoring notifier cannot stall
# the halt beyond a bounded window. No-op with no side effects when
# RALPH_NOTIFY_CMD is unset. The RUNNER calls this; the agent never does.
notify_human() {
  [ -n "$notify_cmd" ] || return 0
  local event="$1" reason="$2"
  if timeout -k 2 "$notify_timeout" "$notify_cmd" "$event" "$reason" >/dev/null 2>&1; then
    narrate "ralph: notified operator — event=$event"
  else
    narrate "ralph: notifier failed (event=$event) — non-fatal, loop unaffected"
  fi
  return 0
}

# The first unchecked tasks.md task (what the upcoming turn should pick up).
first_task() {
  grep -m1 '^- \[ \] ' "$tasks_file" 2>/dev/null \
    | sed -E 's/^- \[ \] *//; s/⛔ MILESTONE GATE.*/[milestone gate]/'
}

# Emit a status record from RJ_* env vars. mode=current overwrites the heartbeat
# ($state_dir/current.json); mode=append adds a line to the objective,
# git-derived feed ($state_dir/status.jsonl). No-op if python3 is unavailable.
emit_status() {
  command -v python3 >/dev/null 2>&1 || return 0
  RJ_MODE="$1" RJ_STATE_DIR="$state_dir" python3 - <<'PY' 2>/dev/null || true
import json, os
def opt(k):
    v = os.environ.get(k, "")
    return v if v else None
rec = {
    "turn": int(os.environ.get("RJ_TURN", "0")),
    "task": os.environ.get("RJ_TASK", ""),
    "model": opt("RJ_MODEL") or "default",
    "state": os.environ.get("RJ_STATE", ""),
    "started": opt("RJ_STARTED"),
    "ended": opt("RJ_ENDED"),
    "exit_code": int(os.environ["RJ_EXIT"]) if os.environ.get("RJ_EXIT") else None,
    "committed": os.environ.get("RJ_COMMITTED") == "1",
    "sha": opt("RJ_SHA"),
    "subject": opt("RJ_SUBJECT"),
    # Persisted blocked-question signal: a one-shot reader (/ralph-status) cannot
    # tell a stale questions.md from one written this run, so the runner records
    # its decision here instead of letting the reader re-derive it from the file.
    "blocked": os.environ.get("RJ_BLOCKED") == "1",
    "blocked_reason": opt("RJ_BLOCKED_REASON"),
}
if os.environ["RJ_MODE"] == "current":
    json.dump(rec, open(os.environ["RJ_STATE_DIR"] + "/current.json", "w"), indent=2)
else:
    with open(os.environ["RJ_STATE_DIR"] + "/status.jsonl", "a") as f:
        f.write(json.dumps(rec) + "\n")
PY
}

# Merge a blocked-question decision INTO the heartbeat current.json that run_turn
# just wrote, rather than overwriting it: a full emit_status mode=current write
# here would reset task/model/started/exit_code/sha to defaults (it builds the
# record fresh from RJ_* vars, which the main loop doesn't have), clobbering the
# very fields /ralph-status reads. So layer only state/blocked/blocked_reason onto
# the existing record. No-op without python3 (consistent with emit_status).
persist_blocked() {
  command -v python3 >/dev/null 2>&1 || return 0
  RJ_STATE_DIR="$state_dir" RJ_BLOCKED_REASON="$1" python3 - <<'PY' 2>/dev/null || true
import json, os
p = os.environ["RJ_STATE_DIR"] + "/current.json"
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["state"] = "blocked"
d["blocked"] = True
d["blocked_reason"] = os.environ.get("RJ_BLOCKED_REASON") or None
json.dump(d, open(p, "w"), indent=2)
PY
}

# --- outer-loop review gate (ON by default; set RALPH_REVIEW_GATE=0 to disable) 
# ALL GitHub interaction lives here, in the runner — the coding agent never
# touches git remotes, gh, or PRs, so the gate works no matter which agent runs
# in the container. Review findings re-enter the agent's world only as text in
# review-findings.md, which the scaffolded PROMPT.md tells it to resolve before
# any tasks.md task. The verdict (zero findings AND green CI) is the only PASS.
review_findings="review-findings.md"
REVIEW_GATE_HALT=0

working_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null; }

base_branch() {
  if [ -n "${RALPH_BASE_BRANCH:-}" ]; then
    printf '%s\n' "$RALPH_BASE_BRANCH"
    return
  fi
  # origin's default branch (refs/remotes/origin/HEAD -> origin/<name>); main if unknown.
  local d
  d=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/origin/##')
  printf '%s\n' "${d:-main}"
}

# Ensure a PR exists for the current branch; echo its number. Reuses an open one.
ensure_pr() {
  local num
  num=$(gh pr view --json number --jq .number 2>/dev/null)
  if [ -z "$num" ]; then
    gh pr create --base "$(base_branch)" --head "$(working_branch)" --fill \
      --title "ralph: $(working_branch)" \
      --body "Automated Ralph loop branch. Review input is the diff + repo state only." \
      >/dev/null 2>&1
    num=$(gh pr view --json number --jq .number 2>/dev/null)
  fi
  printf '%s\n' "$num"
}

# Request an independent review of PR <num>; print findings, one per line (empty
# == clean). Default reviewer is GitHub Copilot via gh; RALPH_REVIEWER=<cmd>
# overrides it (the substitution seam). The author's INTENT is withheld — only
# the PR diff/state is given to the reviewer.
request_review() {
  local num="$1"
  if [ -n "${RALPH_REVIEWER:-}" ]; then
    "$RALPH_REVIEWER" "$num"
    return
  fi
  # v1 default: request a Copilot review, then read its comments as findings.
  # (Exact Copilot request API is pinned at implementation — see design Open Qs.)
  gh pr edit "$num" --add-reviewer "@copilot" >/dev/null 2>&1 || true
  gh pr view "$num" --json comments --jq '.comments[].body' 2>/dev/null |
    grep -v '^[[:space:]]*$' || true
}

# CI verdict for PR <num>: echo success|pending|failure. Read DIRECTLY from CI
# (ground truth), never from a reviewer's claim. `gh pr checks` exits 0=all pass,
# 8=pending, other=failing.
ci_status() {
  gh pr checks "$1" >/dev/null 2>&1
  case $? in
    0) echo success ;;
    8) echo pending ;;
    *) echo failure ;;
  esac
}

merge_pr() { gh pr merge "$1" --merge >/dev/null 2>&1; }

# Run the gate for the just-committed turn. Returns 0 to continue the loop; sets
# REVIEW_GATE_HALT=1 (after writing STATUS.md) when the bounded rounds are spent.
# Not a stall: a committing turn already reset the stall counter, and the verdict
# wait below never reaches the stall check.
run_review_gate() {
  REVIEW_GATE_HALT=0
  local num status waited findings
  git push -u origin "$(working_branch)" >/dev/null 2>&1 ||
    narrate "ralph: review-gate could not push $(working_branch) to origin — check GH_TOKEN / remote (the PR may review stale commits)"
  num=$(ensure_pr)
  if [ -z "$num" ]; then
    narrate "ralph: review-gate could not resolve a PR for $(working_branch) — skipping this turn"
    return 0
  fi

  # Wait for CI to settle (pending is not a verdict), bounded so a wedged run
  # cannot hang the loop forever. Reuses the limit_poll cadence.
  waited=0
  status=$(ci_status "$num")
  while [ "$status" = pending ] && [ "$waited" -lt "${RALPH_REVIEW_CI_MAX:-60}" ]; do
    sleep "$limit_poll"
    waited=$((waited + 1))
    status=$(ci_status "$num")
  done

  findings=$(request_review "$num")

  if [ -z "${findings//[[:space:]]/}" ] && [ "$status" = success ]; then
    : >"$review_findings"
    review_rounds=0
    narrate "ralph: review-gate PASS on PR #$num (clean review, CI green)"
    if [ "${RALPH_AUTO_MERGE:-0}" = 1 ]; then
      if merge_pr "$num"; then
        narrate "ralph: auto-merged PR #$num into $(base_branch)"
      else
        narrate "ralph: auto-merge FAILED for PR #$num — left for a human (check gh auth / branch protection)"
      fi
    else
      narrate "ralph: PR #$num is ready for a human to merge (RALPH_AUTO_MERGE off)"
    fi
    return 0
  fi

  # NOT PASS: record findings so the next turn fixes them. A red/pending CI is
  # surfaced as a synthetic finding so the agent always has something to act on.
  {
    echo "# Review findings for PR #$num — resolve these before any tasks.md task."
    echo
    [ "$status" != success ] && echo "- CI is not green (status: $status). Make the gate match CI and fix the failure."
    if [ -n "${findings//[[:space:]]/}" ]; then
      printf '%s\n' "$findings" | grep -v '^[[:space:]]*$' | sed 's/^/- /'
    fi
  } >"$review_findings"
  review_rounds=$((review_rounds + 1))
  narrate "ralph: review-gate found issues on PR #$num (round ${review_rounds}/${RALPH_REVIEW_MAX_ROUNDS:-3}) — wrote $review_findings"

  if [ "$review_rounds" -ge "${RALPH_REVIEW_MAX_ROUNDS:-3}" ]; then
    printf 'Loop halted: review gate still failing after %d rounds on PR #%s. Human review needed.\n' \
      "$review_rounds" "$num" >STATUS.md
    REVIEW_GATE_HALT=1
  fi
  return 0
}

turn_ec=0
run_turn() {
  turn=$((turn + 1))
  echo "$turn" >"$turn_file"
  local log="$state_dir/log/turn-${turn}.txt"
  local task started ended before after committed sha subject summary
  task=$(first_task)
  started=$(date -Is)
  before=$(head_rev)

  # Heartbeat: what is running right now.
  RJ_TURN="$turn" RJ_TASK="$task" RJ_MODEL="${RALPH_MODEL:-}" RJ_STATE="running" \
    RJ_STARTED="$started" emit_status current

  narrate "ralph: turn $turn ($started)${RALPH_MODEL:+ model=$RALPH_MODEL} timeout=${turn_timeout}s -> $log"
  narrate "ralph:   task -> ${task:-<none>}"
  # stdbuf -oL line-buffers output so `tail -f` shows progress LIVE, not only
  # when the turn ends. timeout sends TERM at the cap, then KILL 30s later.
  # When live logging is on, fan a turn-prefixed copy into live.log via process
  # substitution — a fan-out, NOT a 3rd pipe stage — so a copy still reaches
  # stdout (terminal / podman logs) and ${PIPESTATUS[0]} stays the agent's code.
  if [ "${live_log_enabled:-1}" = 1 ]; then
    stdbuf -oL -eL timeout -k 30 "$turn_timeout" \
      claude -p --dangerously-skip-permissions "${model_args[@]}" <PROMPT.md 2>&1 \
      | tee "$log" >(python3 "$script_dir/ralph_prefix.py" "$turn" >>"$live_log")
  else
    stdbuf -oL -eL timeout -k 30 "$turn_timeout" \
      claude -p --dangerously-skip-permissions "${model_args[@]}" <PROMPT.md 2>&1 \
      | tee "$log"
  fi
  turn_ec=${PIPESTATUS[0]}
  if [ "$turn_ec" -eq 124 ]; then
    echo "ralph: turn $turn TIMED OUT after ${turn_timeout}s" | tee -a "$log"
    _live_append "ralph: turn $turn TIMED OUT after ${turn_timeout}s"
  fi

  after=$(head_rev)
  committed=0
  sha=""
  subject=""
  if [ "$before" != "$after" ]; then
    committed=1
    sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    subject=$(git log -1 --format=%s 2>/dev/null || echo "")
  fi
  ended=$(date -Is)

  # Objective, git-derived record of the completed turn.
  RJ_TURN="$turn" RJ_TASK="$task" RJ_MODEL="${RALPH_MODEL:-}" RJ_STATE="done" \
    RJ_STARTED="$started" RJ_ENDED="$ended" RJ_EXIT="$turn_ec" \
    RJ_COMMITTED="$committed" RJ_SHA="$sha" RJ_SUBJECT="$subject" emit_status append
  RJ_TURN="$turn" RJ_TASK="$task" RJ_MODEL="${RALPH_MODEL:-}" RJ_STATE="idle" \
    RJ_STARTED="$started" RJ_ENDED="$ended" RJ_EXIT="$turn_ec" \
    RJ_COMMITTED="$committed" RJ_SHA="$sha" RJ_SUBJECT="$subject" emit_status current

  if [ "$committed" = 1 ]; then
    summary="ralph: turn $turn exited $turn_ec ($ended) — committed $sha: $subject"
  else
    summary="ralph: turn $turn exited $turn_ec ($ended) — no commit"
  fi
  echo "$summary" | tee -a "$log"
  _live_append "$summary"
}

trap 'echo; _sig="ralph: caught SIGINT at turn $turn, exiting"; echo "$_sig"; _live_append "$_sig"; exit 130' INT

if [ "$once" -eq 1 ]; then
  narrate "ralph: single turn (--once) starting from turn $turn"
  run_turn
  narrate "ralph: --once complete — log at $state_dir/log/turn-${turn}.txt"
  exit "$turn_ec"
fi

narrate "ralph: starting at turn $turn ($(date -Is)) — timeout ${turn_timeout}s, max-stalls ${max_stalls}"

# Outer-loop review gate preflight (opt-in). All remote work is the runner's, so
# fail fast if its preconditions are unmet rather than silently skipping the gate.
review_rounds=0
if [ "${RALPH_REVIEW_GATE:-1}" = 1 ]; then
  command -v gh >/dev/null 2>&1 ||
    { echo "ralph: RALPH_REVIEW_GATE=1 but 'gh' is not on PATH — refusing to start (rebuild the base image; gh ships in ralph-base)" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 ||
    { echo "ralph: RALPH_REVIEW_GATE=1 but 'gh' is not authenticated — refusing to start (forward a GH_TOKEN into the container; the Makefile derives it from 'gh auth token')" >&2; exit 1; }
  # Push over HTTPS using the token: make gh the git credential helper and rewrite
  # SSH GitHub remotes to HTTPS, so `git push` works in the container (which has no
  # ssh binary or key). Idempotent; only when the gate is on.
  gh auth setup-git >/dev/null 2>&1 || true
  git config --global url."https://github.com/".insteadOf "git@github.com:" >/dev/null 2>&1 || true
  git remote | grep -q . ||
    { echo "ralph: RALPH_REVIEW_GATE=1 but no git remote is configured — refusing to start" >&2; exit 1; }
  if [ "$(working_branch)" = "$(base_branch)" ]; then
    echo "ralph: RALPH_REVIEW_GATE=1 but the working branch equals the base branch ($(base_branch)) — check out a feature branch first" >&2
    exit 1
  fi
  if [ -n "${RALPH_REVIEWER:-}" ] && ! command -v "$RALPH_REVIEWER" >/dev/null 2>&1 && [ ! -x "$RALPH_REVIEWER" ]; then
    echo "ralph: RALPH_REVIEWER='$RALPH_REVIEWER' is not executable — refusing to start" >&2
    exit 1
  fi
  narrate "ralph: review gate ON — branch $(working_branch) -> base $(base_branch); auto-merge ${RALPH_AUTO_MERGE:-0}; max-rounds ${RALPH_REVIEW_MAX_ROUNDS:-3}"
fi

# STATUS.md is BOTH the loop's stop-signal and the human cold-start breadcrumb,
# so it is normally non-empty when a loop starts. Snapshot it now and treat only
# a CHANGE to non-whitespace content as a stop reason — a pre-existing breadcrumb
# must not halt a fresh loop after a single turn.
status_start="$(cat STATUS.md 2>/dev/null || true)"
stalls=0
while true; do
  before=$(head_rev)
  # Snapshot the questions file PER TURN, not once at startup. Unlike STATUS.md
  # (which stops on any change, committed or not), the blocked check is gated on a
  # NO-COMMIT turn — so a startup snapshot would go stale the moment a question is
  # added on a COMMITTING turn, and the next unrelated no-commit turn would then
  # falsely halt as blocked. Comparing this-turn-before vs after detects only a
  # question the agent wrote DURING this turn; a pre-existing list is unchanged
  # across the turn and so is naturally ignored.
  questions_before="$(cat "$questions_file" 2>/dev/null || true)"
  run_turn
  after=$(head_rev)

  # Usage-limit pause (before the stall check): a rate-limited turn exits
  # non-zero and prints "hit your … limit · resets <time>" but makes no commit,
  # so it must NOT count toward max-stalls. Wait for the window to refresh, then
  # replay the SAME task. A genuine timeout (124) with no limit message falls
  # through to the stall logic.
  last_log="$state_dir/log/turn-${turn}.txt"
  if [ "$turn_ec" -ne 0 ] &&
    grep -qiE "hit your (session|weekly|opus|usage) limit" "$last_log" 2>/dev/null; then
    reset=$(grep -oiE "resets [^.]*" "$last_log" | head -1)
    wait_s=$(python3 "$script_dir/until_reset.py" "$reset" 2>/dev/null || echo "$limit_poll")
    narrate "ralph: usage limit hit at turn $turn (${reset:-reset time unknown}) — pausing ${wait_s}s, then retrying (not a stall)"
    sleep "$wait_s"
    turn=$((turn - 1)) # replay this turn number — the task was not completed
    echo "$turn" >"$turn_file"
    continue
  fi

  # Stop only on a stop-reason written DURING this run. STATUS.md doubles as the
  # human breadcrumb, so it is usually non-empty at startup; halting on any
  # non-empty file would stop a fresh loop after a single turn. Compare against
  # the startup snapshot and stop only when a turn CHANGED it to non-whitespace
  # content (a blank/whitespace-only write must still NOT trip a stop).
  status_now="$(cat STATUS.md 2>/dev/null || true)"
  if [ -n "${status_now//[[:space:]]/}" ] && [ "$status_now" != "$status_start" ]; then
    narrate "ralph: STATUS.md updated with a stop reason at turn $turn — stopping"
    echo "--- STATUS.md ---"
    cat STATUS.md
    _live_append "ralph: stop reason: $(printf '%s' "$status_now" | oneline)"
    notify_human stop "$(printf '%s' "$status_now" | oneline)"
    exit 0
  fi

  # Blocked-question immediate stop. THIS turn appended a NEW entry to the questions
  # file (a decision the specs don't cover) and made no commit: halt now with a
  # `blocked` signal instead of letting it burn turns toward RALPH_MAX_STALLS with
  # no signal. Compared against this turn's pre-run snapshot (changed + non-whitespace),
  # ordered AFTER the usage-limit pause and STATUS.md check but BEFORE the stall
  # counter, and gated on a no-commit turn, so it can never pre-empt a committing
  # turn or be double-counted as a stall.
  if [ "$before" = "$after" ]; then
    questions_now="$(cat "$questions_file" 2>/dev/null || true)"
    if [ -n "${questions_now//[[:space:]]/}" ] && [ "$questions_now" != "$questions_before" ]; then
      q_reason=$(grep -v '^[[:space:]]*$' "$questions_file" 2>/dev/null | tail -1 | oneline)
      printf 'Loop halted: blocked on a question in %s — human decision needed.\n' "$questions_file" >STATUS.md
      # Persist the decision (merged into this turn's heartbeat) so /ralph-status can
      # report blocked WITHOUT re-reading the file (it cannot tell a stale list from
      # a current one).
      persist_blocked "$q_reason"
      narrate "ralph: blocked on a question in $questions_file at turn $turn — stopping (not a stall)"
      echo "--- $questions_file ---"
      cat "$questions_file"
      _live_append "ralph: blocked question: $q_reason"
      notify_human blocked "$q_reason"
      exit 1
    fi
  fi

  # Outer-loop review gate: only when enabled AND this turn committed (there is
  # something new to review). A committing turn is not a stall, and the gate's
  # verdict wait never reaches the stall check below.
  if [ "${RALPH_REVIEW_GATE:-1}" = 1 ] && [ "$before" != "$after" ]; then
    run_review_gate
    if [ "$REVIEW_GATE_HALT" = 1 ]; then
      narrate "ralph: review gate exhausted its rounds at turn $turn — wrote STATUS.md, stopping"
      echo "--- STATUS.md ---"
      cat STATUS.md
      _live_append "ralph: review-exhausted reason: $(cat STATUS.md 2>/dev/null | oneline)"
      notify_human review-exhausted "$(cat STATUS.md 2>/dev/null | oneline)"
      exit 1
    fi
  fi

  if [ "$before" = "$after" ]; then
    stalls=$((stalls + 1))
    narrate "ralph: turn $turn produced NO commit (stall ${stalls}/${max_stalls}, exit ${turn_ec})"
    if [ "$stalls" -ge "$max_stalls" ]; then
      printf 'Loop halted: %d consecutive turns made no commit (last exit %d — hung/timed-out or stuck-on-red). Human review needed.\n' \
        "$stalls" "$turn_ec" >STATUS.md
      narrate "ralph: ${stalls} consecutive no-progress turns — wrote STATUS.md, stopping"
      notify_human stall "$(cat STATUS.md 2>/dev/null | oneline)"
      exit 1
    fi
  else
    stalls=0
  fi

  sleep "$poll_interval"
done
