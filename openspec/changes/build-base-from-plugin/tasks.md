## 1. Confirm the bundled-build mechanism

- [x] 1.1 Verify the installed plugin bundles `base/` (Containerfile + `scripts/ralph.sh` + `scripts/until_reset.py`) and the root `Makefile`, and that `make -C "$CLAUDE_PLUGIN_ROOT" build-base` tags `ralph-base:v1` from the bundled sources with host UID/GID args (registry-free) — confirmed against the 0.2.0 cache
- [x] 1.2 Confirm the `marketplace.json` `source: "./"` keeps `base/` + `Makefile` in the published plugin (no `files`/ignore filter excludes them); add a regression note if a packaging filter is later introduced

## 2. /ralph-init: build from the bundled base (first-run)

- [x] 2.1 Update `skills/ralph-init/SKILL.md` §0/§4: replace the "in a clone of keep-on-ralphing: `make build-base`" instruction with building from `$CLAUDE_PLUGIN_ROOT` (`make -C "$CLAUDE_PLUGIN_ROOT" build-base`), and offer to run it during init
- [x] 2.2 Add the precondition/fallback behaviour: if `$CLAUDE_PLUGIN_ROOT` is unset or `make`/runtime is missing, name the unmet precondition and print the explicit `podman build …` command + source-clone fallback — never silently skip
- [x] 2.3 Ensure the build is read-only against the plugin cache (build context only) and writes no runner machinery into the consumer repo (single-source preserved) — added as a §Guardrails clause

## 3. Rebuild-after-update affordance

- [x] 3.1 Add a dedicated `ralph-build-base` skill (design D4) that runs `make -C "$CLAUDE_PLUGIN_ROOT" build-base`, resolving the path freshly each invocation (no frozen cache path)
- [x] 3.2 Skills are auto-discovered from `skills/` (plugin.json declares no skills field), so no manifest edit is needed — recorded here so a future manifest format doesn't silently drop the skill
- [x] 3.3 Cross-link from `/ralph-init`'s report: "after a `/plugin update`, run `/ralph-build-base` to refresh the runner"

## 4. Next-steps output + docs

- [x] 4.1 Update `/ralph-init`'s final "Next steps" so step 1 no longer says clone the repo (plugin users) while keeping the clone+`make build-base` path documented for contributors/CI
- [x] 4.2 Update `CLAUDE.md`: the release checklist step 4 (rebuild the base image) points at the bundled-build/`ralph-build-base` action; note the runner now travels with the plugin; add `/ralph-build-base` to the three-channel host-side row
- [x] 4.3 Update `README.md` install/build steps to present both paths (bundled-build for plugin users, clone+build for contributors)

## 5. Verification

- [ ] 5.1 Smoke-test on a throwaway project: install/refresh the plugin, run `/ralph-init`, confirm it builds `ralph-base:v1` from `$CLAUDE_PLUGIN_ROOT` with no clone, and the consumer repo gains no runner machinery — DEFERRED: needs the 0.3.0 plugin released so the cache carries the new skill + SKILL.md edits
- [ ] 5.2 Smoke-test the rebuild path: bump+update the plugin, run `/ralph-build-base`, confirm the image rebuilds from the new bundled `base/` — DEFERRED with 5.1 (same release dependency; also runs a real podman build)
- [x] 5.3 `make test` stays green (no runner/gate behaviour changed) — 15/15 review-gate + gate-hook + unit suites pass
- [x] 5.4 `openspec validate build-base-from-plugin --strict` passes
