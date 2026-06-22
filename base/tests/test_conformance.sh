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
# live.log: via narrate (which is not echo/printf, so never a candidate here), a
# `| tee` to the per-turn log, or a same-line `_live_append`. Pre-loop
# refuse-to-start lines write to stderr (`>&2`) before live.log exists and are
# exempt. Routing tokens are matched in command position (`| tee`, `_live_append "`)
# so a mere mention in a trailing comment does NOT grant a false exemption.
runner="base/scripts/ralph.sh"
if [ ! -f "$runner" ]; then
  bad "live.log narration: runner $runner not found (renamed? this check would otherwise pass vacuously)"
else
  narration_violations=$(
    grep -nE '(echo|printf)[^|]*ralph:' "$runner" | grep -vE '>&2|\| *tee|_live_append "' || true
  )
  if [ -z "$narration_violations" ]; then
    ok "live.log narration: every echo/printf 'ralph:' line routes via narrate/_live_append/tee (or >&2 pre-loop)"
  else
    bad "live.log narration: operator line(s) bypass live.log (route via narrate or _live_append):"
    printf '%s\n' "$narration_violations" | sed "s#^#      $runner:#"
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
  for ci in "$pdir"/.github/workflows/*.yml "$pdir"/.github/workflows/*.yaml; do
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
if [ -z "$key_diff" ]; then
  ok "example parity: example/ralph.conf and templates/ralph.conf.example carry the same key set"
else
  bad "example parity: key set differs between templates/ and example/: $(printf '%s' "$key_diff" | tr '\n' ' ')"
fi

echo
echo "conformance tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
