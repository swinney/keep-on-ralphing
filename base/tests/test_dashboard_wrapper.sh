#!/usr/bin/env bash
# Behavioural test for the `make loop` host-side wrapper (templates/Makefile.template
# `define RALPH_LOOP_RUN`). It extracts the SHIPPED wrapper body verbatim from the
# template (so there is no drift between test and template) and runs it under a stub
# `podman`, asserting the load-bearing guarantees:
#   * the loop container's exit code is preserved (SIGINT -> 130 stop path, D8/5.3)
#   * the dashboard viewer is torn down (process killed + temp file removed)
#   * RALPH_DASHBOARD precedence + graceful-skip when host python3 is absent (5.1)
#
# Run:  bash base/tests/test_dashboard_wrapper.sh   (needs bash, coreutils, python3)

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$HERE/../../templates/Makefile.template"

pass=0
fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Extract the wrapper body and undo Make's $$ -> $ doubling, yielding the exact
# shell program Make exports as $RALPH_LOOP_RUN.
WRAPPER=$(sed -n '/^define RALPH_LOOP_RUN$/,/^endef$/p' "$TEMPLATE" | sed '1d;$d' | sed 's/\$\$/$/g')
[ -n "$WRAPPER" ] && ok "extracted RALPH_LOOP_RUN wrapper from the template" \
  || bad "could not extract RALPH_LOOP_RUN from the template"

new_env() {
  WS=$(mktemp -d)
  STUB="$WS/stub"
  mkdir -p "$STUB"
  : >"$WS/last_dtmp"
  : >"$WS/vpid"
  # Stub podman: create/cp plant a real sleeping "viewer", run simulates the loop
  # container exiting 130 (the SIGINT stop path).
  cat >"$STUB/podman" <<STUBEOF
#!/usr/bin/env bash
case "\$1" in
  create) echo "cid123"; exit 0 ;;
  cp) # \$2=src  \$3=dest : record the temp path and plant a pid-recording sleeper
      printf '%s' "\$3" >"$WS/last_dtmp"
      printf 'import os,time\nopen(os.environ["VPIDFILE"],"w").write(str(os.getpid()))\ntime.sleep(30)\n' >"\$3"
      exit 0 ;;
  rm) exit 0 ;;
  ps) exit 0 ;;
  run) sleep 0.5; exit 130 ;;   # loop runs briefly (viewer records its pid), then 130
  *) exit 0 ;;
esac
STUBEOF
  chmod +x "$STUB/podman"
}
cleanup() { [ -n "${WS:-}" ] && rm -rf "$WS"; }
trap cleanup EXIT

run_wrapper() { # args: <dash_env> ; uses PATH with the stub + real tools
  ( cd "$WS" && PATH="$STUB:$PATH" VPIDFILE="$WS/vpid" \
    bash -c "$WRAPPER" ralph_loop podman testimg "$WS" "$1" -v "$WS:/workspace" )
}

# --- 1. dashboard ON: viewer launched, then exit 130 preserved + torn down ---
new_env
run_wrapper 1 >/dev/null 2>&1
ec=$?
[ "$ec" -eq 130 ] && ok "wrapper preserves the loop container exit code (130)" \
  || bad "wrapper exit was $ec (want 130 — SIGINT stop path)"
dtmp=$(cat "$WS/last_dtmp" 2>/dev/null)
[ -n "$dtmp" ] && [ ! -e "$dtmp" ] \
  && ok "viewer temp file removed on teardown" \
  || bad "viewer temp file not cleaned (dtmp='$dtmp')"
vpid=$(cat "$WS/vpid" 2>/dev/null)
if [ -n "$vpid" ]; then
  sleep 0.3
  kill -0 "$vpid" 2>/dev/null && { bad "viewer process still alive after teardown (pid $vpid)"; kill "$vpid" 2>/dev/null; } \
    || ok "viewer process killed on teardown"
else
  bad "viewer never launched when dashboard ON"
fi
cleanup

# --- 2. dashboard OFF (default): no viewer, container exit code still preserved -
new_env
run_wrapper 0 >/dev/null 2>&1
ec=$?
[ "$ec" -eq 130 ] && ok "dashboard off: exit code still preserved (130)" \
  || bad "dashboard off exit was $ec (want 130)"
[ ! -s "$WS/last_dtmp" ] && ok "dashboard off: no viewer extracted" \
  || bad "dashboard off should not extract a viewer"
cleanup

# --- 3. dashboard ON but host python3 absent: graceful skip, loop still runs ---
new_env
# PATH WITHOUT python3: only the stub dir + a minimal coreutils dir of symlinks.
COREUTILS="$WS/coreutils"
mkdir -p "$COREUTILS"
for t in bash sleep mktemp rm cat; do ln -s "$(command -v $t)" "$COREUTILS/$t" 2>/dev/null; done
out=$( cd "$WS" && PATH="$STUB:$COREUTILS" VPIDFILE="$WS/vpid" \
  bash -c "$WRAPPER" ralph_loop podman testimg "$WS" 1 -v "$WS:/workspace" 2>&1 )
ec=$?
[ "$ec" -eq 130 ] && ok "no python3: loop still runs and preserves exit code (130)" \
  || bad "no-python3 exit was $ec (want 130)"
printf '%s' "$out" | grep -qi "python3 not found" \
  && ok "no python3: dashboard skipped with a warning (graceful)" \
  || bad "no-python3 path did not warn/skip (got: $out)"
[ ! -s "$WS/last_dtmp" ] && ok "no python3: no viewer extracted" \
  || bad "no-python3 path should not extract a viewer"
cleanup

echo
echo "dashboard-wrapper tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
