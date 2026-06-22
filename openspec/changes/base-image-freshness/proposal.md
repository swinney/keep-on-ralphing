## Why

The runner ships *inside* `ralph-base:v1`, a **content-mutable tag** distributed **registry-free, per
machine** (a deliberate scope choice). So a runner change reaches a loop only after that machine rebuilds
the image — and nothing today detects when that hasn't happened. This gap bit repeatedly: a plugin bump to
0.6.x sat next to a base image built from an earlier runner, so "merged" silently did not equal "live"
until a manual rebuild. There is no machine-readable way to ask *"what runner is actually baked in this
image?"* — the `:v1` tag hides it.

Because distribution is registry-free and per-machine, there is no central place to "generate once": each
machine must rebuild. So the fix is not a new artifact but reliable **detection + an idempotent trigger**
on each machine, built on a provenance stamp the image currently lacks.

## What Changes

- **Provenance stamp baked into the image.** The build stamps `ralph-base:v1` with a content hash of the
  runner sources + base `Containerfile` (a `LABEL` and a `/etc/ralph-base.version` file), passed as a
  build-arg. This is the missing primitive: the content identity the mutable `:v1` tag hides.
- **`/ralph-build-base` becomes freshness-aware / idempotent.** It computes the stamp of the currently
  bundled `base/` and compares it to the baked image; it rebuilds only when they differ (or `--force`),
  and otherwise reports "already current" and skips — so it is cheap and safe to run routinely.
- **Staleness is surfaced, never run silently stale.** `/ralph-status` reports the baked stamp and flags
  drift (baked ≠ currently bundled `base/`); the runner narrates its baked stamp at startup, so the
  `live.log`/`podman logs` stream records exactly which runner is executing.
- **The consumer loop image's base is checkable at the point of use.** The consumer `Makefile`
  `loop`/`loop-once` preflight detects when the thin image was built on a now-superseded `ralph-base:v1`
  and instructs `make build` — it detects + instructs (it cannot rebuild the *base*: that needs the plugin
  root, which a consumer command does not have).
- Non-breaking: an unstamped legacy image is reported as "unknown/needs rebuild", not an error.

## Capabilities

### New Capabilities
- `base-image-freshness`: the image carries a content-derived provenance stamp; staleness (baked runner ≠
  currently bundled `base/`, or a loop image built on a superseded base) is detectable and surfaced where
  the operator looks; and the rebuild is idempotent so re-running it when current is a fast no-op.

### Modified Capabilities
- `base-image-provisioning`: the build bakes the provenance stamp, and the rebuild-after-update path becomes
  freshness-aware (idempotent) rather than an unconditional rebuild.

## Impact

- **Base image** (`base/Containerfile`): `ARG`/`LABEL` + `/etc/ralph-base.version` for the stamp. **Runner**
  (`base/scripts/ralph.sh`): narrate the baked stamp at startup → **two-channel release** (plugin bump +
  rebuild).
- **Build** (`Makefile build-base`): compute + pass the stamp build-arg.
- **Skills**: `/ralph-build-base` (freshness check + idempotent rebuild), `/ralph-status` (report stamp +
  drift).
- **Consumer surface** (`templates/Makefile.template` + `example/Makefile`): loop/once preflight that
  surfaces the baked base stamp and warns on a superseded base.
- **Tests** (`base/tests/`): cover the stamp presence (`smoke-base`), the idempotent-skip path, and the
  drift surfacing; a structural conformance check that the stamp stays single-sourced.
- Out of scope (non-goals): a `SessionStart` hook that auto-rebuilds on drift (the proactive trigger — a
  documented future path); auto-rebuilding the base from the consumer `Makefile`; and any central
  registry/published image (reverses the registry-free scope decision).
