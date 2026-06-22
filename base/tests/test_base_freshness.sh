#!/usr/bin/env bash
# Unit tests for base_freshness.sh — the base-image freshness DECISION (current
# vs stale). Stubs the container runtime (scripted image labels) and `id`
# (scripted host uid/gid) so the decision is exercised without a real image or
# build. The `want` stamp is the REAL bundled base/ hash (base_version.sh).
#
# Run:  bash base/tests/test_base_freshness.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, a sha256 tool.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FRESH="$HERE/../scripts/base_freshness.sh"
VERSION="$HERE/../scripts/base_version.sh"

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

setup() {
  STUB=$(mktemp -d)
  mkdir -p "$STUB/bin"
  cat >"$STUB/bin/podman" <<STUBEOF
#!/usr/bin/env bash
case "\$*" in
  *base-version*) cat "$STUB/lbl_stamp" 2>/dev/null ;;
  *user-uid*)     cat "$STUB/lbl_uid" 2>/dev/null ;;
  *user-gid*)     cat "$STUB/lbl_gid" 2>/dev/null ;;
esac
STUBEOF
  cat >"$STUB/bin/id" <<STUBEOF
#!/usr/bin/env bash
case "\$1" in
  -u) cat "$STUB/host_uid" ;;
  -g) cat "$STUB/host_gid" ;;
  *)  exec /usr/bin/id "\$@" ;;
esac
STUBEOF
  chmod +x "$STUB/bin/podman" "$STUB/bin/id"
  echo 1000 >"$STUB/host_uid"
  echo 1000 >"$STUB/host_gid"
}
teardown() { rm -rf "$STUB"; }
run_fresh() { ( PATH="$STUB/bin:$PATH" RUNTIME=podman IMAGE=ralph-base:v1 bash "$FRESH" ); }

want=$(bash "$VERSION")

# --- matching stamp + matching UID/GID -> current ---------------------------
setup
echo "$want" >"$STUB/lbl_stamp"; echo 1000 >"$STUB/lbl_uid"; echo 1000 >"$STUB/lbl_gid"
out=$(run_fresh); ec=$?
{ [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q '^current'; } \
  && ok "matching stamp + UID/GID => current (exit 0)" \
  || bad "current case wrong (ec=$ec out=$out)"
teardown

# --- changed runner stamp -> stale ------------------------------------------
setup
echo "differenthash" >"$STUB/lbl_stamp"; echo 1000 >"$STUB/lbl_uid"; echo 1000 >"$STUB/lbl_gid"
out=$(run_fresh); ec=$?
{ [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q 'runner changed'; } \
  && ok "changed stamp => stale (exit 1)" \
  || bad "stale-stamp case wrong (ec=$ec out=$out)"
teardown

# --- missing/unstamped image (empty stamp) -> stale -------------------------
setup
: >"$STUB/lbl_stamp"; echo 1000 >"$STUB/lbl_uid"; echo 1000 >"$STUB/lbl_gid"
out=$(run_fresh); ec=$?
{ [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q 'missing or unstamped'; } \
  && ok "missing/unstamped => stale (exit 1)" \
  || bad "unstamped case wrong (ec=$ec out=$out)"
teardown

# --- matching stamp but UID/GID mismatch -> stale (the Codex #11 P2 case) ----
setup
echo "$want" >"$STUB/lbl_stamp"; echo 1000 >"$STUB/lbl_uid"; echo 1000 >"$STUB/lbl_gid"
echo 1001 >"$STUB/host_uid" # host UID now differs from the baked 1000
out=$(run_fresh); ec=$?
{ [ "$ec" -eq 1 ] && printf '%s' "$out" | grep -q 'UID/GID mismatch'; } \
  && ok "matching stamp + UID/GID mismatch => stale (does not falsely skip)" \
  || bad "uid-mismatch case wrong (ec=$ec out=$out)"
teardown

echo
echo "base-freshness tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
