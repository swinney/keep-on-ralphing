#!/usr/bin/env bash
# Merge clean tribe PRs from the M10 fan-out (deferred auto-merge, explicit operation).
#
# Runs on the HOST after the pool scheduler has opened per-tribe PRs.
# Only merges a PR when ALL of:
#   1. CI checks all pass (no failures, no pending).
#   2. No CHANGES_REQUESTED reviews remain unresolved.
#   3. No inline comments from the Copilot reviewer bot (Copilot never uses
#      CHANGES_REQUESTED — it posts findings as inline comments on a COMMENTED
#      review, so this is the gate that actually catches Copilot findings).
#
# Usage:
#   fanout-land.sh             merge every clean tribe PR
#   fanout-land.sh --dry-run   list what WOULD be merged; merge nothing
#
# Does NOT delete branches (project convention: keep all branches post-merge).
#
# See docs/specs/fanout-harness.md §5.4 for the gate → land → free-slot design.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

[ "$dry_run" -eq 1 ] && echo "fanout-land: DRY-RUN MODE — nothing will be merged"

# ---------------------------------------------------------------------------
# Discover open tribe PRs
# ---------------------------------------------------------------------------

echo "fanout-land: listing open tribe/m10-* PRs..."

# gh pr list --json gives us structured data; filter by head branch pattern
pr_json=$(gh pr list \
  --state open \
  --json number,headRefName,title,url \
  --limit 50 2>/dev/null || echo '[]')

# Filter to tribe/m10-* heads using a simple shell loop over the JSON array.
# We use python3 for the JSON parsing (available in the dev environment).
mapfile -t tribe_prs < <(python3 - "$pr_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
for pr in data:
    head = pr.get("headRefName", "")
    if head.startswith("tribe/m10-"):
        print(f"{pr['number']} {head} {pr['url']}")
PY
)

if [ "${#tribe_prs[@]}" -eq 0 ]; then
  echo "fanout-land: no open tribe/m10-* PRs found — nothing to do"
  exit 0
fi

echo "fanout-land: found ${#tribe_prs[@]} tribe PR(s)"
echo

# ---------------------------------------------------------------------------
# Evaluate and (conditionally) merge each PR
# ---------------------------------------------------------------------------

merged_count=0
skipped_count=0

for entry in "${tribe_prs[@]}"; do
  pr_n="${entry%% *}"
  rest="${entry#* }"
  head_ref="${rest%% *}"
  pr_url="${rest##* }"

  echo "--- PR #${pr_n}  ${head_ref}  ${pr_url} ---"

  # 1. Check CI status: all checks must pass (no failures, no pending)
  checks_json=$(gh pr checks "$pr_n" --json name,state 2>/dev/null || echo '[]')
  ci_ok=$(python3 - "$checks_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
if not data:
    # No checks registered yet — treat as not ready
    print("no-checks")
    sys.exit(0)
failing = [c for c in data if c.get("state", "") not in ("SUCCESS", "NEUTRAL", "SKIPPED")]
if failing:
    print("failing:" + ",".join(c["name"] for c in failing))
else:
    print("ok")
PY
)

  if [ "$ci_ok" != "ok" ]; then
    echo "  SKIP: CI not clean ($ci_ok)"
    skipped_count=$((skipped_count + 1))
    echo
    continue
  fi

  # 2. Check for CHANGES_REQUESTED reviews
  reviews_json=$(gh api "repos/{owner}/{repo}/pulls/${pr_n}/reviews" 2>/dev/null || echo '[]')
  changes_requested=$(python3 - "$reviews_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
# Keep only the latest review per reviewer; if any is CHANGES_REQUESTED → not clean
latest = {}
for r in data:
    user = r.get("user", {}).get("login", "?")
    latest[user] = r.get("state", "")
blocking = [u for u, s in latest.items() if s == "CHANGES_REQUESTED"]
print(",".join(blocking) if blocking else "")
PY
)

  if [ -n "$changes_requested" ]; then
    echo "  SKIP: CHANGES_REQUESTED from ${changes_requested}"
    skipped_count=$((skipped_count + 1))
    echo
    continue
  fi

  # 3. Check for inline review comments from the Copilot reviewer bot.
  # CRITICAL: Copilot ALWAYS posts findings as a COMMENTED review with inline
  # comments — it never uses CHANGES_REQUESTED. So the review-state gate above
  # does NOT catch Copilot findings; we must count its inline comments directly.
  # Conservative on API error: a fetch failure skips (does not merge).
  copilot_comment_count=$(gh api "repos/{owner}/{repo}/pulls/${pr_n}/comments" \
    --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length' \
    2>/dev/null || echo "error")
  if [ "$copilot_comment_count" = "error" ]; then
    echo "  SKIP: could not fetch Copilot comments (API error — conservative skip)"
    skipped_count=$((skipped_count + 1))
    echo
    continue
  fi
  if [ "$copilot_comment_count" -gt 0 ]; then
    echo "  SKIP: Copilot left ${copilot_comment_count} inline comment(s) — needs human triage"
    skipped_count=$((skipped_count + 1))
    echo
    continue
  fi

  echo "  CI: ok  |  CHANGES_REQUESTED: none  |  Copilot inline comments: 0"

  if [ "$dry_run" -eq 1 ]; then
    echo "  DRY: would merge PR #${pr_n} (${head_ref}) with --merge (no branch delete)"
    merged_count=$((merged_count + 1))
    echo
    continue
  fi

  echo "  MERGING PR #${pr_n}..."
  if gh pr merge "$pr_n" --merge; then
    echo "  OK: PR #${pr_n} merged (branch ${head_ref} kept)"
    merged_count=$((merged_count + 1))
  else
    echo "  ERROR: merge failed for PR #${pr_n} — leaving for human triage"
    skipped_count=$((skipped_count + 1))
  fi
  echo
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "=== fanout-land summary ==="
if [ "$dry_run" -eq 1 ]; then
  echo "  would merge: ${merged_count}"
else
  echo "  merged:      ${merged_count}"
fi
echo "  skipped:     ${skipped_count} (needs triage)"
