## 1. Provenance stamp primitive (one shared definition)

- [ ] 1.1 Add `base/scripts/base_version.sh` — print a portable content hash (`sha256sum`/`shasum -a 256` over a FIXED, sorted list of the runner sources + `base/Containerfile`, contents only, no mtime). This is the ONE definition both the build and the readers call; bash 3.2-safe
- [ ] 1.2 `base/Containerfile`: add `ARG RALPH_BASE_VERSION`, a `LABEL org.ralph.base-version="$RALPH_BASE_VERSION"`, and write it to `/etc/ralph-base.version`. Keep the `ARG`/`LABEL` lines static (value injected at build time) so hashing the `Containerfile` stays stable (no circularity)
- [ ] 1.3 `Makefile` `build-base`: compute the stamp via `base_version.sh` and pass `--build-arg RALPH_BASE_VERSION=<hash>` alongside the existing UID/GID args

## 2. Freshness-aware, idempotent rebuild (the trigger)

- [ ] 2.1 `skills/ralph-build-base/SKILL.md`: before building, compute the bundled `base/` stamp (`base_version.sh`) and read the baked `LABEL` (`podman image inspect`); rebuild only when they differ, the image is missing/unstamped, or `--force` is given; otherwise report "already current" and skip. Resolve `$CLAUDE_PLUGIN_ROOT` fresh (no frozen cache path)

## 3. Surfacing (gate at use, three touchpoints)

- [ ] 3.1 Runner (`base/scripts/ralph.sh`): narrate the baked stamp at startup (read from a path defaulting to `/etc/ralph-base.version`, overridable for tests; narrate "base-version: unknown" if absent) so it lands in `live.log`
- [ ] 3.2 `skills/ralph-status/SKILL.md`: inspect the image `LABEL`, compute the currently bundled `base/` stamp, report the baked stamp and FLAG drift (baked ≠ bundled, or unstamped → "unknown, rebuild recommended")
- [ ] 3.3 `templates/Makefile.template` + `example/Makefile`: a `loop`/`loop-once` preflight comparing the thin loop image's recorded base stamp to the `ralph-base:v1` on the machine; on mismatch, refuse with the fix (`make build`). Detect-and-instruct ONLY — never rebuild the base (no plugin root); document the limit in a comment

## 4. Tests

- [ ] 4.1 `make smoke-base`: assert the baked `LABEL` and `/etc/ralph-base.version` are present and equal to `base_version.sh` over the source (image-contents coverage; CI does not build the image)
- [ ] 4.2 Add `base/tests/test_base_freshness.sh`: unit-test the idempotent-skip + drift decision by stubbing `podman image inspect` (matching vs differing vs missing/unstamped stamp); assert skip-when-current, rebuild-when-stale, and force-always. Wire into `base/tests/run.sh` + the CLAUDE.md single-slice list
- [ ] 4.3 Extend `base/tests/test_conformance.sh`: a structural check that the stamp/hash computation is single-sourced in `base_version.sh` and not re-implemented in the `Makefile`/skills/runner (the same single-source discipline the gate command follows)
- [ ] 4.4 Runner test (`base/tests/test_ralph_runner.sh`): a turn's startup narration includes a `base-version:` line (pointing the override at a fixture file asserts the real value; absent → "unknown")

## 5. Conventions and docs

- [ ] 5.1 `CLAUDE.md`: document the provenance stamp + freshness model (the two-channel "merged ≠ live" gap it closes), the content-hash-not-version rationale, and that a `SessionStart` auto-rebuild hook is the future path (proactive trigger), explicitly NOT built here
- [ ] 5.2 `README.md`: note how to check freshness (`/ralph-status` flags drift; `make loop` preflights the loop image's base; `/ralph-build-base` rebuilds only when stale)

## 6. Release and validation

- [ ] 6.1 `make test` green (incl. `test_base_freshness.sh` + the conformance check); `make smoke-base` green locally (flag it — CI does not build the image)
- [ ] 6.2 Two-channel release: bump `.claude-plugin/plugin.json` (from 0.6.2) AND flag the base-image rebuild (runner + Containerfile changed) in the change notes / CLAUDE.md release checklist
- [ ] 6.3 `openspec validate base-image-freshness --strict` passes
