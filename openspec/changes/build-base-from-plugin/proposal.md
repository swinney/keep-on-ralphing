## Why

The loop machinery ships as the `ralph-base:v1` image, built locally from `base/` (registry-free,
UID/GID-matched to the host user). Today `/ralph-init`'s final "Next steps" tell the operator to obtain that
image by **cloning `keep-on-ralphing` and running `make build-base`**. But the marketplace plugin **already
bundles `base/` *and* the root `Makefile`** — byte-identical to the repo — so every plugin install already
ships the complete build material at `$CLAUDE_PLUGIN_ROOT` (verified: `base/Containerfile`,
`base/scripts/ralph.sh`, `base/scripts/until_reset.py`, and a `build-base` target whose relative paths
resolve correctly from the plugin root).

So the clone is redundant friction — a plugin user is told to fetch material they already have — and it is
actively harmful: a separately-cloned repo can drift from the *installed* plugin version, reintroducing the
exact two-channel skew CLAUDE.md's release checklist warns about (plugin updated, runner stale, or vice
versa). Building from the bundled `base/` instead makes the runner source travel *with* the plugin, so
`/plugin update` + rebuild keeps runner and plugin in lockstep with no second checkout to maintain.

## What Changes

- `/ralph-init` SHALL build (or offer to build) `ralph-base:v1` from the **plugin-bundled** `base/` via
  `$CLAUDE_PLUGIN_ROOT` (`make -C "$CLAUDE_PLUGIN_ROOT" build-base`), eliminating the clone requirement for
  plugin users. The UID/GID build-args (host-matched) are unchanged — it stays a local build.
- The runner machinery is **NOT** copied into the consumer repo. The single source remains the plugin's
  `base/`; this change is explicitly *not* consumer-repo vendoring of `ralph.sh`/`until_reset.py`/the base
  `Containerfile`.
- Provide a **rebuild-after-update** path that resolves the bundled `base/` at build time and never freezes a
  version-pinned cache path (the per-version cache dir is orphan-pruned ~7 days after an update). Because the
  resolution must happen where `$CLAUDE_PLUGIN_ROOT` is defined (the plugin execution context), the rebuild
  is a **plugin-side action**, not a command the consumer `Makefile` can carry.
- The init "Next steps" output drops the "clone keep-on-ralphing" line; CLAUDE.md and README are updated to
  describe the bundled-build path and the rebuild-after-update step.
- **Backwards-compatible:** the clone + `make build-base` path still works for source/dev users and CI; this
  change is additive — it gives plugin users a shorter, drift-free path.

### Non-goals

- Publishing a pullable `ralph-base` registry image (the registry-free, UID/GID-matched design is a separate,
  ADR-backed scope choice).
- Changing the `v1` image tag scheme or addressing tag-vs-content looseness across plugin versions.
- Changing the consumer `Makefile` run flags or the `--userns=keep-id` runtime model.

## Capabilities

### New Capabilities

- `base-image-provisioning`: build `ralph-base:v1` from the plugin-bundled `base/` (resolved via
  `$CLAUDE_PLUGIN_ROOT` at build time), with no separate source clone, no consumer-repo vendoring of runner
  machinery, host-matched UID/GID preserved, and a plugin-side rebuild-after-update path.

## Impact

- **Plugin:** `skills/ralph-init/SKILL.md` (§0 locate, §4 report/offer-to-build). Likely a small dedicated
  rebuild affordance (a `ralph-build-base` skill or an init sub-mode — see design).
- **Docs:** `CLAUDE.md` (release checklist + how-the-image-is-built), `README.md` (install/build steps).
- **Tests:** the bash suite stubs `claude` and does not build images, and `/ralph-init` is markdown-driven, so
  coverage here is path-resolution/instruction correctness plus a manual throwaway-project smoke test (as used
  to validate the 0.2.0 scaffold), not an in-CI podman build.
- **Compatibility:** no runner behavior change; the source-clone build path remains valid. Operators who
  already built `ralph-base:v1` are unaffected until they choose to rebuild.
