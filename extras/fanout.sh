#!/usr/bin/env bash
# Fan-out orchestrator for M10 cave-tribe parallel build.
#
# Runs on the HOST (manages git clones + podman containers).
# Not designed to run inside a loop container.
#
# Usage:
#   fanout.sh              launch all tribe loops in a pool (default concurrency 2)
#   fanout.sh --dry-run    print the full plan — clones, branches, task files,
#                          launch commands — then exit; launches nothing.
#
# Environment (with defaults):
#   FANOUT_CONCURRENCY=2                  max parallel tribe containers
#   RALPH_MODEL=claude-sonnet-4-6         model passed to each tribe loop
#   IMAGE=kotb-ralph                      container image name
#   FANOUT_POLL=30                        seconds between status polls
#   GH_REMOTE=$(git remote get-url origin) GitHub remote URL (for PR targeting)
#
# Stop conditions (for each tribe slot):
#   * STATUS.md contains "complete"  → push branch, open PR, request Copilot review, free slot
#   * STATUS.md has non-whitespace but no "complete" → stall; surface, free slot, no PR
#
# See docs/specs/fanout-harness.md §5 for full design rationale.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

# ---------------------------------------------------------------------------
# Configuration (env with defaults)
# ---------------------------------------------------------------------------

concurrency="${FANOUT_CONCURRENCY:-2}"
model="${RALPH_MODEL:-claude-sonnet-4-6}"
image="${IMAGE:-kotb-ralph}"
poll="${FANOUT_POLL:-30}"
gh_remote="${GH_REMOTE:-$(git remote get-url origin 2>/dev/null || echo '')}"

repo="$(pwd)"
claude_dir="$repo/.ralph/claude-home"
wt_root="$repo/../kotb-wt"
manifest="scripts/m10-tribes.txt"

# Derive GitHub owner/repo from the remote URL for use in gh invocations.
# Supports both SSH (git@github.com:owner/repo.git) and HTTPS forms.
gh_slug=""
if [ -n "$gh_remote" ]; then
  # Strip trailing .git, then extract owner/repo
  _remote="${gh_remote%.git}"
  # SSH: git@github.com:owner/repo  →  owner/repo
  # HTTPS: https://github.com/owner/repo  →  owner/repo
  gh_slug="${_remote##*github.com[:/]}"
fi

# ---------------------------------------------------------------------------
# Read tribe list from manifest (skip comments and blank lines)
# ---------------------------------------------------------------------------

if [ ! -f "$manifest" ]; then
  echo "fanout: manifest not found: $manifest" >&2
  exit 1
fi

mapfile -t tribes < <(grep -vE '^\s*#|^\s*$' "$manifest")

if [ "${#tribes[@]}" -eq 0 ]; then
  echo "fanout: no tribes found in $manifest" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Function: scoped_tasks <tribe>
# Emit the per-tribe task file to stdout (heredoc parameterised by tribe name).
# ---------------------------------------------------------------------------

scoped_tasks() {
  local t="$1"
  cat <<TASKS
# M10 tribe: ${t} (scoped task list — canonical tasks.md untouched)
- [ ] world/zones/caves/${t}/ lair rooms + ${t} mobs (pure data + builder; mirror caves/kobold/)
- [ ] ${t} leaders wired to the M6 leadership-halt + rival scouting (repop.md §3-4)
- [ ] Faction standing shifts observable in ${t} behavior (M4 ↔ zone)
- [ ] tests/zones/test_${t}.py green (rooms/mobs/leaders/faction)
- [ ] ⛔ TRIBE GATE — write "${t} complete — paused for review." to STATUS.md and stop. Make no code changes and do not check this box.
TASKS
}

# ---------------------------------------------------------------------------
# Function: prepare <tribe>
# Clone repo, reset origin to GH remote, checkout tribe branch, write tasks.
# In dry-run: echo the plan; do nothing.
# ---------------------------------------------------------------------------

prepare() {
  local tribe="$1"
  local dest="$wt_root/m10-${tribe}"

  if [ "$dry_run" -eq 1 ]; then
    echo "DRY: rm -rf $dest"
    echo "DRY: git clone --quiet $repo $dest"
    echo "DRY: git -C $dest remote set-url origin $gh_remote"
    echo "DRY: git -C $dest fetch --quiet origin"
    echo "DRY: git -C $dest checkout -q -b tribe/m10-${tribe}"
    echo "DRY: mkdir -p $dest/.ralph"
    echo "DRY: scoped_tasks ${tribe} > $dest/.ralph/tribe-tasks.md  (contents follow)"
    scoped_tasks "$tribe" | sed 's/^/DRY:   /'
    return
  fi

  rm -rf "$dest"
  git clone --quiet "$repo" "$dest"
  git -C "$dest" remote set-url origin "$gh_remote"
  git -C "$dest" fetch --quiet origin
  git -C "$dest" checkout -q -b "tribe/m10-${tribe}"
  mkdir -p "$dest/.ralph"
  scoped_tasks "$tribe" > "$dest/.ralph/tribe-tasks.md"
}

# ---------------------------------------------------------------------------
# Function: launch <tribe>
# Start a detached podman container for the tribe loop.
# In dry-run: echo the command; do nothing.
# ---------------------------------------------------------------------------

launch() {
  local tribe="$1"
  local dest="$wt_root/m10-${tribe}"

  local -a cmd=(
    podman run -d --name "kotb-ralph-m10-${tribe}" --userns=keep-id
    -e "RALPH_MODEL=${model}" -e "RALPH_TASKS=.ralph/tribe-tasks.md"
    -v "${dest}:/workspace" -v "${claude_dir}:/home/claude/.claude"
    "${image}" ./scripts/ralph.sh
  )

  if [ "$dry_run" -eq 1 ]; then
    echo "DRY: ${cmd[*]}"
    return
  fi

  "${cmd[@]}"
  echo "fanout: launched kotb-ralph-m10-${tribe}"
}

# ---------------------------------------------------------------------------
# Function: land_on_gate <tribe>
# Push the tribe branch, open a PR, request Copilot review.
# Called only when STATUS.md contains "complete".
# ---------------------------------------------------------------------------

land_on_gate() {
  local tribe="$1"
  local dest="$wt_root/m10-${tribe}"
  local branch="tribe/m10-${tribe}"

  echo "fanout: tribe ${tribe}: gate reached — pushing $branch and opening PR"

  # Push and PR-create are load-bearing — a failure here must propagate so the
  # pool lists the tribe as stalled rather than silently dropping it.
  if ! git -C "$dest" push -u origin "$branch"; then
    echo "fanout: tribe ${tribe}: git push FAILED"
    return 1
  fi

  local pr_url_out
  if ! pr_url_out=$(gh pr create \
    --base main \
    --head "$branch" \
    --title "M10: ${tribe} tribe (caves)" \
    --body "$(cat <<BODY
Fan-out tribe PR: \`${tribe}\` cave content for M10.

Each tribe is an independent per-clone unit following the M9 kobold pattern.
This PR covers:
- \`world/zones/caves/${tribe}/\` lair rooms + mobs
- \`${tribe}\` leaders wired to leadership-halt + rival scouting
- Faction standing shifts in \`${tribe}\` behavior
- \`tests/zones/test_${tribe}.py\` green

---
*Auto-generated by \`scripts/fanout.sh\`.*
BODY
)"); then
    echo "fanout: tribe ${tribe}: gh pr create FAILED"
    return 1
  fi
  echo "fanout: tribe ${tribe}: PR: ${pr_url_out}"

  # Extract PR number from the URL gh pr create outputs (e.g. .../pull/42)
  local pr_num
  pr_num=$(echo "$pr_url_out" | grep -oE '[0-9]+$' || true)

  if [ -n "$pr_num" ]; then
    # Request a Copilot review via the REST API. `gh pr edit --add-reviewer
    # copilot` does NOT work: the Copilot reviewer is a bot, and gh's GraphQL
    # requestReviewsByLogin path cannot resolve the login `copilot` ("Could not
    # resolve user with login 'copilot'"). The requested_reviewers REST endpoint
    # accepts the bot under the login `Copilot`. Non-fatal: the PR exists either
    # way, so a reviewer-request hiccup must not stall.
    # NOTE: fanout-land.sh only auto-merges when there are zero Copilot inline
    # comments — which presumes a review was actually produced. Confirm Copilot
    # reviewed (it posts as `copilot-pull-request-reviewer[bot]`) before relying
    # on `make fanout-land` to merge.
    gh api -X POST "repos/{owner}/{repo}/pulls/${pr_num}/requested_reviewers" \
      -f "reviewers[]=Copilot" >/dev/null 2>&1 || \
      echo "fanout: tribe ${tribe}: note — could not add Copilot reviewer (non-fatal)"
    echo "fanout: tribe ${tribe}: PR #${pr_num} opened — slot freed"
  else
    echo "fanout: tribe ${tribe}: PR opened (could not parse PR number for Copilot request)"
  fi

  # Clean up the now-finished container
  podman rm -f "kotb-ralph-m10-${tribe}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main — prepare phase
# ---------------------------------------------------------------------------

echo "fanout: preparing ${#tribes[@]} tribe(s): ${tribes[*]}"
echo "fanout: wt_root=$wt_root  concurrency=$concurrency  model=$model"
[ "$dry_run" -eq 1 ] && echo "fanout: DRY-RUN MODE — nothing will be launched"
echo

mkdir -p "$wt_root"

for tribe in "${tribes[@]}"; do
  echo "fanout: prepare $tribe"
  prepare "$tribe"
  echo
done

if [ "$dry_run" -eq 1 ]; then
  echo "fanout: dry-run complete (nothing launched)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pool scheduler
# ---------------------------------------------------------------------------

# pending: tribes not yet launched (consume from front)
# running: space-separated string of currently active tribe names
pending=("${tribes[@]}")
running=()

summary_gated=()
summary_stalled=()

echo "fanout: starting pool scheduler (concurrency=${concurrency}, poll=${poll}s)"

while true; do
  # Fill empty slots from pending queue
  while [ "${#running[@]}" -lt "$concurrency" ] && [ "${#pending[@]}" -gt 0 ]; do
    local_tribe="${pending[0]}"
    pending=("${pending[@]:1}")
    launch "$local_tribe"
    running+=("$local_tribe")
  done

  # Nothing running and nothing pending → we're done
  if [ "${#running[@]}" -eq 0 ] && [ "${#pending[@]}" -eq 0 ]; then
    break
  fi

  sleep "$poll"

  # Poll each running tribe
  new_running=()
  for tribe in "${running[@]}"; do
    dest="$wt_root/m10-${tribe}"
    status_file="$dest/STATUS.md"

    if grep -q '[^[:space:]]' "$status_file" 2>/dev/null; then
      # STATUS.md has real content — check what kind
      if grep -qi 'complete' "$status_file" 2>/dev/null; then
        echo "fanout: tribe ${tribe}: GATED"
        if land_on_gate "$tribe"; then
          summary_gated+=("$tribe")
        else
          echo "fanout: tribe ${tribe}: land_on_gate FAILED — listed as stalled"
          podman rm -f "kotb-ralph-m10-${tribe}" 2>/dev/null || true
          summary_stalled+=("$tribe")
        fi
      else
        echo "fanout: tribe ${tribe}: STALLED — left for human triage (no PR)"
        sed "s/^/  [${tribe}] /" "$status_file"
        podman rm -f "kotb-ralph-m10-${tribe}" 2>/dev/null || true
        summary_stalled+=("$tribe")
      fi
      # Slot freed — do NOT add back to new_running
    else
      # STATUS.md is empty: the loop may still be working, OR the container
      # may have crashed/exited without writing a stop reason. If the latter,
      # the slot would never free and the pool would spin forever — so verify
      # the container is genuinely alive before re-adding it to running.
      container_state=$(podman inspect --format '{{.State.Status}}' \
        "kotb-ralph-m10-${tribe}" 2>/dev/null || echo "missing")
      if [ "$container_state" = "running" ]; then
        new_running+=("$tribe")
      else
        exit_code=$(podman inspect --format '{{.State.ExitCode}}' \
          "kotb-ralph-m10-${tribe}" 2>/dev/null || echo "?")
        echo "fanout: tribe ${tribe}: container ${container_state} (exit ${exit_code}) with no STATUS.md — STALLED"
        podman rm -f "kotb-ralph-m10-${tribe}" 2>/dev/null || true
        summary_stalled+=("$tribe")
        # Slot freed — do NOT add back to new_running
      fi
    fi
  done
  running=("${new_running[@]+"${new_running[@]}"}")
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "=== fanout summary ==="
echo "  in-review (PR open):"
if [ "${#summary_gated[@]}" -gt 0 ]; then
  for t in "${summary_gated[@]}"; do echo "    $t"; done
else
  echo "    (none)"
fi
echo "  stalled (needs human triage):"
if [ "${#summary_stalled[@]}" -gt 0 ]; then
  for t in "${summary_stalled[@]}"; do echo "    $t"; done
else
  echo "    (none)"
fi
