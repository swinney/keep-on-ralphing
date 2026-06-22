## Why

A spec requirement with **universal scope** ("every orchestration line SHALL reach `live.log`", "the gate
command SHALL NOT be duplicated anywhere") governs a *class* of code sites — broader than the diff of
whatever change introduced it. When such a requirement is added or expanded, the changing PR updates only
the new/touched sites; pre-existing ("incumbent") sites the requirement now governs are silently left
behind. **No single PR diff reveals this**, diff-scoped review (human + Copilot/Codex) can't see it, and
behavioral tests only assert the new site. The gap lives in the spec↔implementation seam.

This is not hypothetical: a Codex post-merge review caught one instance (review-gate disposition lines
bypassing `live.log`, fixed in #7), and a follow-up whole-tree audit found **3 more live incumbent
violations across 3 different artifact types** (runner, the `example/` golden reference, and a skill doc),
plus a silent-failure gap. The harness has no executable defense against this class, and — notably — the
diff-scoped review gate it *ships* has the same blind spot.

## What Changes

- **Executable invariant checks (M1).** Add structural tests to the kit suite that scan the whole tree and
  fail when *any* site (incumbent or new) violates a designated universal requirement — the suite today is
  entirely behavioral, with **zero** structural assertions. Three to start: complete `live.log` narration
  coverage, single-source gate command, and `example/`⇔`templates/` parity.
- **Incumbent-impact convention (M6).** A lightweight authoring rule: a change that adds or modifies a
  *universal* requirement must enumerate the pre-existing governed sites and confirm (or sweep) them.
- **Fix the 3 incumbent violations** the audit found (conformance to existing requirements):
  - the SIGINT halt line (`ralph.sh`) reaches `live.log` (currently bare `echo`, stdout-only);
  - `example/Containerfile` stops restating the gate command verbatim (single-source violation);
  - `/ralph-init`'s readiness report states whether a `GH_TOKEN` is derivable (omitted today).
- **Surface auto-merge failures (review-gate).** Extend the existing "a failed remote action is surfaced,
  never silently swallowed" guarantee from the branch push to the `RALPH_AUTO_MERGE` merge call.
- **Note the future path (M2).** Document — without building — that the whole-tree conformance audit
  (run as a gate when `openspec/specs/**` changes) is the only net that catches *semantic*-scope drift a
  grep can't, and that it is a candidate **product** capability (a conformance review distinct from the
  diff-scoped review gate).

## Capabilities

### New Capabilities
- `spec-conformance`: the kit's executable enforcement that incumbent code conforms to universal spec
  requirements (structural invariant tests over the whole tree, not just diffs), plus the authoring
  convention that a change adding/modifying a universal requirement enumerates its incumbent governed sites.

### Modified Capabilities
- `review-gate`: the "no silently-swallowed remote failure" guarantee is extended from the branch push to
  the auto-merge call — a failed `RALPH_AUTO_MERGE` merge is surfaced, not treated as success.

## Impact

- **Runner** (`base/scripts/ralph.sh`): SIGINT trap mirrors its halt line to `live.log`; auto-merge failure
  is narrated. Runner change → **two-channel release** (bump `.claude-plugin/plugin.json`; rebuild
  `ralph-base:v1`).
- **Golden reference** (`example/Containerfile`): gate-command comment de-duplicated.
- **Skill** (`skills/ralph-init/SKILL.md`): readiness report gains the `GH_TOKEN`-derivable check.
- **Tests** (`base/tests/`): new structural invariant slice(s), wired into `run.sh` and the CLAUDE.md
  single-slice list.
- **Conventions** (`CLAUDE.md`, `templates/PROMPT.md.template` or the proposal flow): the incumbent-impact
  rule for universal requirements.
- Conformance fixes touch behavior governed by existing `log-streaming`, `gate-enforcement`, and
  `project-bootstrap` requirements — no requirement text there changes; the new tests pin them.
