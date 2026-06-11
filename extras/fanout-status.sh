#!/usr/bin/env bash
# Aggregate status digest across all active M10 tribe clones.
#
# The parallel analogue of `make status` (which reads one .ralph/ dir).
# Reads each ../kotb-wt/m10-*/ clone and prints a one-line summary per tribe.
#
# Usage:
#   fanout-status.sh        (or: make fanout-status)
#
# Output columns:
#   TRIBE       tribe name (m10-<name> → <name>)
#   TURN        current turn number (.ralph/turn, or — if absent)
#   STATE       running | gated | stalled
#   LAST COMMIT short hash + subject (git log -1)
#
# See docs/specs/fanout-harness.md §7.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

wt_root="$(pwd)/../kotb-wt"

echo "=== M10 fan-out status ==="
echo

# Print header
printf "%-12s  %5s  %-9s  %s\n" "TRIBE" "TURN" "STATE" "LAST COMMIT"
printf "%-12s  %5s  %-9s  %s\n" "------------" "-----" "---------" "-----------"

found=0

for d in "$wt_root"/m10-*/; do
  # Guard: skip if glob didn't match (no clones)
  [ -d "$d" ] || continue
  found=1

  # Tribe name: strip trailing slash, strip path prefix, strip "m10-"
  dirname="${d%/}"
  basename="${dirname##*/}"
  tribe="${basename#m10-}"

  # Turn counter
  turn_file="$d/.ralph/turn"
  if [ -f "$turn_file" ]; then
    turn=$(cat "$turn_file" 2>/dev/null || echo "?")
  else
    turn="-"
  fi

  # State
  status_file="$d/STATUS.md"
  if grep -q '[^[:space:]]' "$status_file" 2>/dev/null; then
    if grep -qi 'complete' "$status_file" 2>/dev/null; then
      state="gated"
    else
      state="stalled"
    fi
  else
    state="running"
  fi

  # Last commit
  last_commit=$(git -C "$d" log -1 --format='%h %s' 2>/dev/null || echo "(no commits)")

  printf "%-12s  %5s  %-9s  %s\n" "$tribe" "$turn" "$state" "$last_commit"
done

if [ "$found" -eq 0 ]; then
  echo "  (no tribe clones found under $wt_root)"
fi

echo
