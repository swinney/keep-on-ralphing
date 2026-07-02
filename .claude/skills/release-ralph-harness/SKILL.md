---
name: release-ralph-harness
description: Ship a keep-on-ralphing change through BOTH release channels (plugin
  version bump + base-image rebuild) so it reaches installs, not just main. Use after
  merging or finishing a change that touched skills/, templates/, base/scripts/, or
  base/Containerfile — phrases like "release this", "ship the harness change", "cut a
  release", "bump and push". keep-on-ralphing repo only.
compatibility: keep-on-ralphing repo only. Needs make, podman, gh, an authenticated remote.
metadata:
  author: swinney
  version: "1.0"
---

# release the ralph harness (two channels)

## When to use
You changed harness behaviour in keep-on-ralphing and need it LIVE for users — not
just merged to main. Skip for changes touching only docs/tests/openspec.

## The two channels (why this skill exists)
A release ships through two channels with NO shared version. Moving only one is a
SILENT partial release (real incident: code was pushed but the marketplace stayed
stale until a later version bump).
- **Plugin channel** — `skills/` or `templates/` changed → bump
  `.claude-plugin/plugin.json`. That version string is the ONLY thing that makes
  `/plugin update` pull the change; no bump = the update is a no-op.
- **Base-image channel** — `base/scripts/` or `base/Containerfile` changed → the
  `ralph-base:v1` image must be rebuilt on every machine that runs a loop. A
  `/plugin update` does NOT rebuild it. Freshness keys on a content hash
  (`base/scripts/base_version.sh`), not the plugin version — the channels are unlinked.

A behaviour change often hits BOTH (e.g. runner logic + new config keys), so expect
to do both halves.

## Preferences & gotchas
- **Detect channels from the diff, don't guess:** `git diff --name-only <base>...HEAD`
  → any `skills/`/`templates/` path = plugin channel; any `base/scripts/` or
  `base/Containerfile` path = base channel.
- `make test` is the faithful CI predictor — green before anything ships.
- **Bump `plugin.json` only when pushing to main**, not per branch; confirm the new
  value actually differs from the old (a bump that didn't change the string ships nothing).
- This repo's OWN commits carry `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  + `Claude-Session:` trailers. (Opposite of kit-EMITTED PROMPT artifacts, which must
  carry NO AI attribution — don't confuse the two.)
- Commit/push is pre-authorized here — still show the diff and confirm tests pass first.
- On a feature PR post `@codex review`; do NOT on mechanical `chore: archive` PRs.
- The Skill tool loads the CACHED plugin, so a local change isn't live until the cache
  refreshes (`/plugin marketplace update keep-on-ralphing` → `/plugin update`).
- Bump the image TAG (`:v1`→`:v2`) only if the base change is breaking for existing
  consumers; otherwise `:v1` is content-mutable and the hash stamp tracks freshness.

## Steps
1. `make test` → green.
2. Identify changed channels from `git diff --name-only`.
3. Plugin channel changed? Bump `.claude-plugin/plugin.json` (semver); confirm it changed.
4. Commit (with this repo's trailers) + push to main.
5. Base channel changed? `make build-base` then `make smoke-base` (verifies image
   contents + the freshness stamp). Remind that every OTHER loop machine must rebuild
   too (`/ralph-build-base`).
6. Refresh the plugin cache so the new skills/templates actually load.
7. Print the two-channel checklist (below) with each half done or explicit N/A.

## Done
- `make test` green.
- Plugin half: `skills/`/`templates/` changed → `plugin.json` bumped (≠ old value),
  pushed to main, cache refreshed. Else N/A, stated.
- Base half: `base/scripts/`/`base/Containerfile` changed → `make build-base` +
  `make smoke-base` pass; other machines reminded to rebuild. Else N/A, stated.
- Final checklist printed showing BOTH halves resolved — never just one.
