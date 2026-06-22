## 1. Test harness (write first)

- [ ] 1.1 Add `base/tests/test_conformance.sh` — a STRUCTURAL slice that greps the tracked tree (`git ls-files`-scoped, runs no loop, needs only bash+git+python3); wire it into `base/tests/run.sh` and the CLAUDE.md single-slice list
- [ ] 1.2 Establish a small "scan tracked files for a pattern" helper in the slice so each check is deterministic and CI-safe (CI runs `make test` without building the image)

## 2. M1 structural checks (red first — each MUST fail on the current incumbent)

- [ ] 2.1 Check **complete live.log narration**: fail if a loop-body or signal-trap `echo "ralph:"`-style operator line is neither routed through `narrate` nor paired with `_live_append`/`tee "$log"`; explicitly exempt pre-loop refuse-to-start lines written to `>&2` before `live.log` exists. Confirm it FAILS today on the SIGINT trap (`ralph.sh:482`)
- [ ] 2.2 Check **single-source gate command**: fail if the resolved gate command string is restated in any tracked file other than its single source (`gate.sh`), across BOTH `templates/` and `example/`. Confirm it FAILS today on `example/Containerfile`
- [ ] 2.3 Check **`example/`⇔`templates/` parity**: fail if `example/` omits a config key its `templates/` counterpart carries, or restates a single-source value. Scope to checkable invariants (keys present / no restated value), not a byte diff

## 3. Bring incumbents into compliance (turn the red checks green)

- [ ] 3.1 SIGINT trap (`base/scripts/ralph.sh`): mirror the halt line to `live.log` via `_live_append` (keep `exit 130`; `_live_append` is already a safe no-op when live logging is off/unwritable). 2.1 now passes
- [ ] 3.2 `example/Containerfile`: replace the gate-command comment with a non-duplicative toolchain note matching `templates/Containerfile.template`. 2.2 now passes
- [ ] 3.3 `skills/ralph-init/SKILL.md` §4: add the `GH_TOKEN`-derivable check (`gh auth token` returns a value / Makefile forwards it) to the GitHub-readiness enumeration AND its remediation list — a `project-bootstrap` conformance fix (verified by reading the skill; not structurally greppable)

## 4. review-gate: surface auto-merge failure (MODIFIED requirement)

- [ ] 4.1 In `run_review_gate`, `narrate` on a failed `merge_pr` instead of swallowing it, and do NOT represent the PR as merged on failure (mirror the failed-push pattern)
- [ ] 4.2 Test (`base/tests/test_review_gate.sh`): with `RALPH_AUTO_MERGE=1` and a stubbed failing `gh pr merge`, the failure is surfaced (and reaches `live.log`), not silently swallowed

## 5. Incumbent-impact convention (M6) + future path (M2)

- [ ] 5.1 Add the incumbent-impact rule to `CLAUDE.md` (invariants/release guidance): a change that adds/modifies a *universal* requirement (every/all/always/never/SHALL-for-each) MUST enumerate the pre-existing governed sites and confirm or sweep them
- [ ] 5.2 Document M2 — the whole-tree conformance audit run as a gate when `openspec/specs/**` changes — as the future path and a candidate *product* capability (a conformance review distinct from the diff-scoped review gate); explicitly NOT built in this change

## 6. Release and validation

- [ ] 6.1 `make test` green, including `test_conformance.sh` and the new review-gate auto-merge scenario
- [ ] 6.2 Two-channel release: bump `.claude-plugin/plugin.json` (from 0.6.1) AND flag the base-image rebuild in the change notes / CLAUDE.md release checklist (runner changed)
- [ ] 6.3 `openspec validate spec-conformance-hardening --strict` passes
