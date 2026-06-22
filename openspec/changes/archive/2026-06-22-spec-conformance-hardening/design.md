## Context

The kit's test suite (`base/tests/`) is entirely **behavioral** — it runs `ralph.sh` against git fixtures
and asserts on outcomes (commits, `STATUS.md`, JSON state). It has **zero structural assertions** about the
source itself. Canonical specs (`openspec/specs/`, 6 capabilities, ~43 requirements) include several
*universal* requirements whose scope is a class of code sites. A whole-tree audit (the workflow run during
exploration) found 3 real + 3 borderline incumbent violations of such universals — drift that diff-scoped
review and behavioral tests structurally cannot catch.

The drift has a syntactic flavor and a semantic flavor, and the mitigation differs by flavor — that is the
core design tension here.

## Goals / Non-Goals

**Goals:**
- Make the syntactically-checkable universals *executably enforced* over the whole tree (not just diffs).
- Fix the 3 live incumbent violations + the auto-merge silent-failure.
- Establish a cheap authoring convention (incumbent-impact) that addresses the *semantic* universals no
  grep can see.
- Keep all of it inside the existing self-contained suite (bash + git + python3; no new dependency, no
  container needed — matches CI).

**Non-Goals:**
- Building the whole-tree conformance audit as an automated gate (M2). It is documented as the future path
  and a candidate product capability, not implemented here.
- A general requirement→code traceability/coverage system (M3). Too heavy for a kit this size; it rots.
- Changing `log-streaming`, `gate-enforcement`, or `project-bootstrap` *requirement text* — those universals
  already govern the incumbent sites; this change brings code into compliance and pins it with tests.

## Decisions

### D1 — Two enforcement tiers, chosen by whether the universal is greppable
- **Syntactic universals → structural tests (M1).** A test greps the tracked tree for a forbidden/required
  shape and fails. Cheap, permanent, catches incumbents and recurrence. *Alternative considered:* relying on
  reviewer vigilance — rejected; that is exactly what already failed.
- **Semantic universals → authoring convention (M6) + future audit (M2).** Where "governed site" needs
  per-requirement reasoning (e.g. *summon-a-human* notify scope, where the SAME SIGINT line is a violation
  for `log-streaming` but correctly excluded for `outbound-notification`), no grep can encode it. M6 forces
  the author to enumerate incumbent sites; M2 (future) is the only net that catches what M6 misses.

### D2 — The three M1 tests
A new `base/tests/test_conformance.sh` (structural; greps source, runs no loop):
1. **Complete `live.log` narration.** Every loop-body / trap operator line (`echo "ralph:"` style) is
   either routed through `narrate` or paired with `_live_append`/`tee "$log"`. Pre-loop `>&2`
   refuse-to-start lines are explicitly exempt (they fire before `live.log` exists). This catches the SIGINT
   incumbent and any future bare-echo.
2. **Single-source gate command.** The resolved gate command string appears in exactly one tracked file per
   surface (the `gate.sh`), never restated in a Containerfile/Makefile/CI — across `templates/` AND
   `example/`. Catches the `example/Containerfile` dup.
3. **`example/`⇔`templates/` parity.** The golden reference carries the same config keys / structural rules
   the templates do (it is hand-maintained and drifts). Scope kept to checkable invariants, not full text
   diff. *Alternative:* generate `example/` from templates — rejected as a much larger change; a parity test
   is the proportional net.

### D3 — Fix the incumbents minimally, at the source
- SIGINT trap: add `_live_append` to the trap body (`$turn` is in scope; `_live_append` is already a safe
  no-op when live logging is off/unwritable).
- `example/Containerfile`: replace the gate-command comment with a non-duplicative toolchain note, matching
  `Containerfile.template`.
- `ralph-init` §4 readiness report: add the `GH_TOKEN`-derivable check to the enumeration + remediation.
- Auto-merge: narrate on a failed `merge_pr` instead of swallowing it (mirror the push-failure pattern).

### D4 — M6 lives where authors actually look
The incumbent-impact rule is added as a one-liner to the change/proposal convention and the CLAUDE.md
release/invariants guidance — not a new tool. It reads: *"If a requirement is universal (every/all/always/
never/SHALL-for-each), enumerate the pre-existing governed sites and confirm or sweep them."*

## Risks / Trade-offs

- **Grep heuristics are brittle** (false positives on a legitimately-exempt line) → keep each structural
  test narrow, comment the exemptions inline, and assert on a tight pattern; a false positive is a loud,
  fast, local failure (acceptable) rather than silent drift (not).
- **A structural test can be gamed / hard to express** for a fuzzy universal → that is the signal it belongs
  in the M6/M2 (semantic) tier, not M1. The tier split is the mitigation, not a workaround.
- **`example/` parity test over-fits** and breaks on benign divergence → scope it to the invariants that
  actually matter (keys present, no gate-command restatement), not a byte diff.
- **M2 not built** leaves semantic drift caught only at authoring time (M6) until then → explicitly
  accepted; the exploration audit shows the workflow already works as a manual/periodic run, so the gap is
  "not yet automated," not "no path."

## Migration Plan

Additive. The structural tests join `run.sh`; the runner fixes are backward-compatible (SIGINT still exits
130, auto-merge still merges — it just also narrates on failure). Reaching a machine is the standard
two-channel step: bump `.claude-plugin/plugin.json` and rebuild `ralph-base:v1` (runner changed). Rollback
is reverting the commit; no state migration.

## Open Questions

- **Where M6 is enforced** — a pure convention (CLAUDE.md + proposal guidance) now; could later become a
  checklist item the proposal artifact requires. Leaning convention-only for v1.
- **Whether to seed M2** as a saved workflow in the repo (so the audit is one command) vs. leave it as a
  documented pattern. Leaning: document now, seed later if the manual run recurs.
