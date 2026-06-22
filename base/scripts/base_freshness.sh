#!/usr/bin/env bash
# Decide whether the base image is CURRENT for THIS machine or needs a rebuild.
# Prints a verdict line and exits 0 (current) or 1 (stale). This is the ONE
# definition of the freshness rule — shared by /ralph-build-base (skip vs
# rebuild), /ralph-status (drift reporting), and the unit test (which stubs the
# runtime + `id`).
#
# The image is current iff BOTH: its baked provenance stamp equals the bundled
# base/ stamp (base_version.sh), AND its baked UID/GID equal the invoking host's
# id -u / id -g — because the build bakes UID/GID for bind-mount ownership, so a
# stamp match alone could still be wrong for this host.
#
# Env: RUNTIME (default podman), IMAGE (default ralph-base:v1). Runs host-side
# (the checkout or $CLAUDE_PLUGIN_ROOT), not inside the image. bash 3.2-safe.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
RUNTIME=${RUNTIME:-podman}
IMAGE=${IMAGE:-ralph-base:v1}

want=$(bash "$here/base_version.sh") || {
  echo "error: cannot compute the bundled base/ stamp" >&2
  exit 2
}

# Distinguish "can't inspect" from "image is unstamped": without the runtime we
# cannot judge freshness at all. Exit non-zero (safe-side — callers treat it as
# needs-attention), but say so plainly rather than mislabel it "unstamped".
if ! command -v "$RUNTIME" >/dev/null 2>&1; then
  echo "unknown: $RUNTIME not on PATH — cannot inspect $IMAGE (rebuild via /ralph-build-base)"
  exit 1
fi

label() { $RUNTIME image inspect "$IMAGE" --format "{{ index .Config.Labels \"$1\" }}" 2>/dev/null; }
baked_stamp=$(label org.ralph.base-version)
baked_uid=$(label org.ralph.user-uid)
baked_gid=$(label org.ralph.user-gid)
host_uid=$(id -u)
host_gid=$(id -g)

if [ -z "$baked_stamp" ]; then
  echo "stale: $IMAGE is missing or unstamped — rebuild (want $want)"
  exit 1
fi
if [ "$baked_stamp" != "$want" ]; then
  echo "stale: runner changed — rebuild (baked $baked_stamp, want $want)"
  exit 1
fi
if [ "$baked_uid" != "$host_uid" ] || [ "$baked_gid" != "$host_gid" ]; then
  echo "stale: UID/GID mismatch — rebuild (baked ${baked_uid:-?}:${baked_gid:-?}, host ${host_uid}:${host_gid})"
  exit 1
fi
echo "current: $IMAGE matches the bundled base/ and host UID/GID ($want)"
exit 0
