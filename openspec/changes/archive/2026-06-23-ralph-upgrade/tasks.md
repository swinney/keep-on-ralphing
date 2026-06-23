## 1. Scaffold provenance manifest

- [x] 1.1 Manifest format `{ "template_version": "<plugin version>", "files": { "<path>": "<sha256>" } }`, written TRACKED at repo root as `.ralph-scaffold.json` (resolved: not gitignored `.ralph/` — see design D7)
- [x] 1.2 Extend `skills/ralph-init/SKILL.md` to write `.ralph-scaffold.json` at scaffold time (template version + per-file content hash of generated files); advisory, never blocking; do NOT add it to `.gitignore` (it is meant to be committed)
- [x] 1.3 Add `.ralph-scaffold.json` to `example/` so the golden reference carries it (and so example↔templates parity checks see it)

## 2. /ralph-upgrade skill — core

- [x] 2.1 Create `skills/ralph-upgrade/SKILL.md`: resolve the bundled `templates/` (via `$CLAUDE_PLUGIN_ROOT`), confirm the target repo, read `ralph.conf` for placeholder values
- [x] 2.2 Implement the mode decision: manifest present → hash-classify each file pristine (regenerate) vs customized (insert-only); absent → feature-detection; report which mode was used
- [x] 2.3 Re-render each templated file with the project's values before diffing, so substituted placeholders are not flagged as drift
- [x] 2.4 Confirm-gated apply: show a per-file diff, mark the recommended action, require explicit confirmation; never write silently or overwrite a customized line

## 3. Per-file upgrade strategies

- [x] 3.1 `Makefile` (high-stakes): feature-detect + insert the known blocks — `GH_TOKEN` export, `-e GH_TOKEN` in `RUN_FLAGS`, the `check-base` target + `loop`/`loop-once` prerequisite — preserving custom targets/flags; flag the risk (an un-forwarded token blocks a review-gated loop)
- [x] 3.2 `ralph.conf`: append documented-but-missing keys, commented / at built-in defaults (behavior unchanged)
- [x] 3.3 `PROMPT.md`: offer to append missing contract clause-blocks, preserving operator edits
- [x] 3.4 New files (e.g. `docs/operator-checklist.md`): create if absent (reuse the no-overwrite path)
- [x] 3.5 Generic fallback: for any other template line absent from the project's file, offer it as an opt-in hunk

## 4. Scope boundary + integration

- [x] 4.1 Detect a superseded base image (reuse the freshness signal) and direct the operator to `/ralph-build-base`; never rebuild from this skill
- [x] 4.2 Restrict the skill to the Ralph-owned config set; never read/modify non-Ralph files
- [x] 4.3 Update `skills/ralph-init/SKILL.md` report to point to `/ralph-upgrade` for adopting template changes (init stays first-time-only)
- [x] 4.4 List `/ralph-upgrade` in `.claude-plugin/plugin.json` and bump the plugin version (host-side / one-channel release)

## 5. Docs + golden reference + validation

- [x] 5.1 README: document the upgrade path (`/plugin update` → `/ralph-build-base` → `/ralph-upgrade`) and the init/upgrade boundary
- [x] 5.2 CLAUDE.md: record the new skill + the init=scaffold / upgrade=merge split; note the manifest reuses the provenance-stamp pattern
- [x] 5.3 (Optional) add a "Consumer migration notes" convention to `CHANGELOG.md` for human-facing per-release deltas
- [x] 5.4 `make test` green (no runner change; confirm conformance/structural checks still pass with the new skill + example manifest)
- [x] 5.5 `openspec validate ralph-upgrade --strict` passes
