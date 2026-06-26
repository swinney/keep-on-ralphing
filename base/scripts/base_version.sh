#!/usr/bin/env bash
# Print the base image's content-hash provenance stamp: a sha256 over a FIXED
# list of the baked runner sources + the Containerfile (contents only, fixed
# order, no mtime), so it is reproducible on any host. This is the ONE definition
# of the stamp — the build bakes its output into the image, and the readers
# (/ralph-build-base, /ralph-status, smoke-base) recompute it to detect drift.
#
# It hashes only what determines runtime behaviour (the three baked scripts + the
# Containerfile). It is NOT itself baked into the image, so it is excluded from
# the hash — a change to this helper does not, by itself, force a rebuild.
#
# Resolves base/ relative to its own location, so it works both from a source
# checkout (base/scripts/base_version.sh) and the installed plugin
# ($CLAUDE_PLUGIN_ROOT/base/scripts/base_version.sh). bash 3.2-safe.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
base=$(cd "$here/.." && pwd)

# Fixed list (NOT a glob) so the input set is deterministic and never silently
# grows to include tests/helpers.
files="scripts/ralph.sh scripts/until_reset.py scripts/ralph_prefix.py scripts/ralph_dashboard.py Containerfile"

if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum; }
elif command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256; }
else
  echo "base_version.sh: no sha256 tool (sha256sum/shasum) on PATH" >&2
  exit 1
fi

for f in $files; do
  if [ ! -f "$base/$f" ]; then
    echo "base_version.sh: missing source $base/$f" >&2
    exit 1
  fi
done

# Hash each file's content in fixed order, then reduce the per-file digests to one.
( cd "$base" && for f in $files; do sha <"$f"; done ) | sha | cut -d' ' -f1
