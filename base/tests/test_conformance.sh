#!/usr/bin/env bash
# Structural conformance checks for the kit's OWN source tree.
#
# Unlike the other slices (which drive ralph.sh against throwaway git fixtures),
# this one runs NO loop: it scans the tracked source and fails when any site —
# incumbent or newly added — violates a UNIVERSAL spec requirement (one that
# governs a class of code sites, broader than any single diff). It is the
# executable half of the spec-conformance capability: the net that catches drift
# diff-scoped review and behavioral tests structurally cannot see.
#
# These are SYNTACTIC checks (greps): they catch the common, mechanical forms of
# each drift. A determined reword/split can still evade them — that residue is the
# *semantic* tier's job (the incumbent-impact authoring convention + the future
# whole-tree audit), not this file's.
#
# Run:  bash base/tests/test_conformance.sh
# Exit: 0 if all pass, 1 otherwise. Requires bash, git.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd) # base/tests -> repo root
cd "$ROOT"

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

# Deterministic, .gitignore-honoring file listing. The whole suite already
# requires git; if this somehow runs outside a work tree, fail loudly rather than
# pass vacuously (a silent empty scan would defeat the check's purpose).
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "test_conformance.sh: not a git work tree — cannot scan tracked files" >&2
  exit 1
}
tracked() { git ls-files "$@"; }

# --- 1. Complete live.log narration -----------------------------------------
# log-streaming requires every runner orchestration line (incl. a stall/halt
# message) to reach live.log, not only the terminal. An operator line — an
# `echo`/`printf` emitting a "ralph:" message, any quoting — must route to
# live.log: via narrate (not echo/printf, so never a candidate here), a `| tee`
# to the per-turn log, or a same-line `_live_append`. The exception is a pre-loop
# refuse-to-start line written to stderr (`>&2`) BEFORE the loop (live.log does
# not exist yet). Each candidate has its trailing comment stripped first, so a
# routing token merely MENTIONED in a comment cannot grant a false exemption; the
# `>&2` exemption is gated on being before the main loop (a loop-body `>&2`
# reaches the terminal, not live.log, so it is NOT exempt).
runner="base/scripts/ralph.sh"
if [ ! -f "$runner" ]; then
  bad "live.log narration: runner $runner not found (renamed? this check would otherwise pass vacuously)"
else
  loop_line=$(grep -nE '^while true; do' "$runner" | head -1 | cut -d: -f1)
  loop_line=${loop_line:-0}
  narration_violations=""
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    ln=${entry%%:*}
    code=$(printf '%s' "${entry#*:}" | sed 's/[[:space:]]#.*$//') # strip trailing comment
    # routed to live.log (command position): a tee pipeline or an _live_append call (any quoting)
    printf '%s' "$code" | grep -qE '\| *tee|_live_append ' && continue
    # pre-loop refuse-to-start to stderr is exempt; a loop-body >&2 is NOT
    if printf '%s' "$code" | grep -q '>&2' && [ "$ln" -lt "$loop_line" ]; then continue; fi
    narration_violations="${narration_violations}${ln}: ${entry#*:}
"
  done <<EOF
$(grep -nE '(echo|printf)[^|]*ralph:' "$runner")
EOF
  if [ -z "$narration_violations" ]; then
    ok "live.log narration: every echo/printf 'ralph:' line routes via narrate/_live_append/tee (or pre-loop >&2)"
  else
    bad "live.log narration: operator line(s) bypass live.log (route via narrate or _live_append):"
    printf '%s' "$narration_violations" | sed "s#^#      $runner:#"
  fi
fi

# --- 2. Single-source gate command ------------------------------------------
# gate-enforcement requires the gate command to live in exactly one place (the
# gate script) and NOT be restated anywhere else, where the copies can drift.
# Scans BOTH the concrete example gate (example/scripts/gate.sh) and the template
# gate (templates/gate.sh.template, whose command line is the {{GATE_COMMAND}}
# placeholder): for each, no sibling Containerfile/Makefile (incl. .template
# variants) or CI workflow may restate any of its command lines verbatim.
gate_dups=""
while IFS= read -r gate; do
  [ -n "$gate" ] || continue
  case "$gate" in
    */scripts/gate.sh) pdir=$(dirname "$(dirname "$gate")") ;; # <proj>/scripts/gate.sh -> <proj>
    *) pdir=$(dirname "$gate") ;;                              # templates/gate.sh.template -> templates
  esac
  sibs="$pdir/Containerfile $pdir/Makefile $pdir/Containerfile.template $pdir/Makefile.template"
  # CI workflows: the example keeps a real .github/workflows/, the templates ship a
  # flat ci.yml.template (the shipped CI source) — scan both shapes.
  for ci in "$pdir"/.github/workflows/*.yml "$pdir"/.github/workflows/*.yaml \
    "$pdir"/ci.yml.template "$pdir"/ci.yaml.template "$pdir"/ci.yml "$pdir"/ci.yaml; do
    [ -f "$ci" ] && sibs="$sibs $ci"
  done
  while IFS= read -r raw; do
    line=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$line" in '' | '#'* | 'set '* | 'set -'*) continue ;; esac
    for sib in $sibs; do
      [ -f "$sib" ] || continue
      if grep -qF -- "$line" "$sib"; then
        gate_dups="${gate_dups}${sib} restates gate command: ${line}
"
      fi
    done
  done <"$gate"
done <<EOF
$(tracked '*scripts/gate.sh' 'scripts/gate.sh' '*gate.sh.template')
EOF
if [ -z "$gate_dups" ]; then
  ok "single-source gate: no Containerfile/Makefile/CI (templates/ or example/) restates a gate command"
else
  bad "single-source gate: the gate command is duplicated (single source is the gate script):"
  printf '%s' "$gate_dups" | sed 's/^/      /'
fi

# --- 3. example/ <-> templates/ key parity ----------------------------------
# The example/ golden reference is hand-maintained and drifts; its key set must
# match the templates/ counterpart in BOTH directions (no missing template key,
# no stray example key) so it stays a faithful sample.
tpl_keys=$(grep -oE '^RALPH_[A-Z_]+=' templates/ralph.conf.example 2>/dev/null | sort -u)
ex_keys=$(grep -oE '^RALPH_[A-Z_]+=' example/ralph.conf 2>/dev/null | sort -u)
key_diff=$(comm -3 <(printf '%s\n' "$tpl_keys") <(printf '%s\n' "$ex_keys") | sed 's/[[:space:]]//g' | grep -v '^$' || true)
if [ ! -f templates/ralph.conf.example ] || [ ! -f example/ralph.conf ]; then
  bad "example parity: a conf file is missing (templates/ralph.conf.example or example/ralph.conf) — cannot compare"
elif [ -z "$tpl_keys" ] || [ -z "$ex_keys" ]; then
  bad "example parity: no RALPH_ keys found in one of the conf files — the check would be vacuous"
elif [ -z "$key_diff" ]; then
  ok "example parity: example/ralph.conf and templates/ralph.conf.example carry the same key set"
else
  bad "example parity: key set differs between templates/ and example/: $(printf '%s' "$key_diff" | tr '\n' ' ')"
fi

# --- 4. The base-image content hash is single-sourced -----------------------
# base_version.sh is the ONE definition of the provenance stamp; the build,
# /ralph-build-base, /ralph-status, smoke-base, and base_freshness.sh all call it.
# A second hand-rolled sha256 over the runner would be a drift-prone duplicate.
hash_dups=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    base/scripts/base_version.sh | base/tests/*) continue ;; # the single source + the tests that name the tool
  esac
  [ -f "$f" ] || continue
  if grep -qE 'sha256sum|shasum[[:space:]]+-a[[:space:]]+256' "$f"; then
    hash_dups="${hash_dups}${f}
"
  fi
done <<EOF
$(tracked '*.sh' '*.template' 'Makefile' 'base/Containerfile')
EOF
if [ -z "$hash_dups" ]; then
  ok "single-source hash: only base_version.sh computes the provenance stamp (no re-implementation)"
else
  bad "single-source hash: a sha256 over the runner is re-implemented outside base_version.sh:"
  printf '%s' "$hash_dups" | sed 's/^/      /'
fi

# --- 5. example scaffold manifest matches the example files ------------------
# /ralph-init writes a tracked .ralph-scaffold.json (template version + per-file
# content hash) so /ralph-upgrade can classify a file as pristine vs customized.
# The example golden reference carries one; its recorded hashes MUST match the
# actual example files, or the manifest silently drifts and would misclassify
# files on upgrade. (sha256 here is in base/tests/, exempt from check 4's
# single-source rule, and uses python3 hashlib — not the sha256sum/shasum tokens.)
ex_manifest="example/.ralph-scaffold.json"
if [ ! -f "$ex_manifest" ]; then
  bad "scaffold manifest: $ex_manifest is missing (the golden reference must carry it)"
else
  # Capture BOTH output and exit status: the script is not `set -e`, so a python
  # failure (missing python3, malformed JSON, empty manifest) would otherwise yield
  # an empty string and pass vacuously. Success requires rc==0 AND no mismatch lines;
  # any non-zero rc (1=mismatch, 3=bad/empty manifest, 127=no python3) is a failure.
  man_out=$(cd example && python3 - <<'PY' 2>&1
import json, hashlib, sys
try:
    m = json.load(open(".ralph-scaffold.json"))
except Exception as e:
    print("cannot parse .ralph-scaffold.json: %s" % e); sys.exit(3)
files = m.get("files", {})
if not files:
    print("manifest has no 'files' entries (would be vacuous)"); sys.exit(3)
out = []
for path, want in files.items():
    try:
        got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    except OSError:
        out.append(f"{path}: file missing"); continue
    if got != want:
        out.append(f"{path}: {got[:12]} != recorded {want[:12]}")
print("\n".join(out))
sys.exit(1 if out else 0)
PY
)
  man_rc=$?
  if [ "$man_rc" -eq 0 ] && [ -z "$man_out" ]; then
    ok "scaffold manifest: example/.ralph-scaffold.json hashes match the example files"
  else
    bad "scaffold manifest: example/.ralph-scaffold.json check failed (rc=$man_rc):"
    printf '%s\n' "$man_out" | sed 's/^/      /'
  fi
fi

echo
echo "conformance tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
