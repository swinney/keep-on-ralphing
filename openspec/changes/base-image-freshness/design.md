## Context

`ralph-base:v1` is a content-mutable tag, built by `make build-base` / `/ralph-build-base`, distributed
**registry-free, per machine** (scope: Linux + podman, team-shared via GitHub, no registry). The runner
(`base/scripts/`) lives inside it. Today the image carries **no version provenance** — `podman` can say the
tag and creation time, but nothing says *which runner* is baked. The two release channels are unlinked
(`plugin.json` version vs the image tag), so a plugin update routinely leaves a stale image with no signal.

The problem decomposes into three separable sub-problems, and the right home differs for each:
**① detect** (needs a stamp in the image), **② trigger the rebuild** (needs `$CLAUDE_PLUGIN_ROOT`, which
resolves only in the plugin/skill context), **③ gate at use** (must run host-side, before `podman run`).

## Goals / Non-Goals

**Goals:**
- Make "what runner is baked?" machine-readable, and "is it stale?" answerable on each machine.
- Make rebuilding idempotent so it is safe to run routinely (and one day from a hook).
- Surface drift where the operator already looks (`/ralph-status`, the loop's startup, `make loop`).
- Keep it inside the existing toolchain (bash + podman + the test suite); no new dependency.

**Non-Goals:**
- A `SessionStart` hook that auto-rebuilds on drift — the *proactive* trigger. Documented as the future
  path; not built here (a `podman build` on session start is heavy and surprising; v1 is "detect + one
  command").
- Auto-rebuilding the *base* from the consumer `Makefile` — impossible cleanly: a consumer command cannot
  resolve `$CLAUDE_PLUGIN_ROOT` to reach `base/`. The consumer side detects + instructs only.
- A central registry / published image — reverses the registry-free scope decision (see ADR direction);
  out of scope.

## Decisions

### D1 — The stamp is a CONTENT HASH, not the plugin version
Hash the runner sources + base `Containerfile` (`sha256` over a fixed file list, reduced to one digest).
*Why not `plugin.json` version:* the two channels are deliberately unlinked, so the version can lag the
actual `base/` content (the "forgot to bump" hazard this kit already documents). A content hash changes
**iff the baked artifact changes** — it answers "is the baked runner the one I have now?" precisely,
independent of any human version bump. The human-readable plugin version MAY be baked alongside as a
convenience label, but the *freshness decision* keys on the hash.

### D2 — Where the stamp lives, and avoiding circularity
Bake it two ways for the two readers: a `LABEL org.ralph.base-version=<hash>` (read host-side via
`podman image inspect` with no container start) and `/etc/ralph-base.version` (read by the in-container
runner for its startup narration). Both come from one `ARG RALPH_BASE_VERSION` the build passes. *No
circularity:* the `Containerfile` carries static `ARG`/`LABEL` lines (not the hash value), so hashing the
`Containerfile` is stable across rebuilds; the value is injected at build time only.

### D3 — `/ralph-build-base` is the idempotent trigger
It computes the stamp of the currently bundled `base/` and reads the baked `LABEL` of any existing
`ralph-base:v1`. If they match it reports "already current" and **skips the build**; if they differ (or the
image is missing / unstamped, or `--force`) it rebuilds. This makes the skill safe to run on every setup /
after every plugin update / eventually from a hook, without a wasteful unconditional `podman build`.
*Why here:* it is the only affordance that resolves `$CLAUDE_PLUGIN_ROOT` clone-free, so it must own both
the stamp computation and the build.

*Freshness key = (content stamp, host UID/GID), not the stamp alone.* The build bakes the host
`USER_UID`/`USER_GID` for bind-mount ownership (an existing `base-image-provisioning` guarantee), and those
are build-arg VALUES — not hashed file content — so a stamp-only "current" verdict would skip a rebuild for
an image whose baked UID/GID no longer match this host, silently reintroducing the ownership bug. So the
build also bakes the UID/GID as labels (`org.ralph.user-uid`/`-gid`), and the freshness check declares the
image current only when the stamp matches AND the baked UID/GID equal `id -u`/`id -g`; any mismatch forces a
rebuild. The content hash stays pure (source content only, portable/meaningful); UID/GID is a *separate*
equality in the decision, not folded into the hash.

### D4 — Three surfacing touchpoints, because no single one covers everyone
- **`/ralph-status`** (host-side reader): inspects the image `LABEL` and compares it to the current bundled
  `base/` stamp; reports the baked stamp and flags drift. Catches the Claude-Code operator.
- **Runner startup narration**: the runner echoes its `/etc/ralph-base.version` into the first turn's
  `narrate`, so the `live.log`/`podman logs` stream records which runner ran — catches the
  log-tailer/forensics path.
- **Consumer `Makefile` `loop`/`loop-once` preflight**: compares the thin loop image's recorded base stamp
  to the `ralph-base:v1` currently on the machine; if the loop image was built on a superseded base, it
  refuses-with-instruction (`make build`). Catches the bare-terminal operator. *Limit (D5):* it can only
  compare two LOCAL images; it cannot tell whether `ralph-base:v1` itself is current vs the plugin — that
  needs the plugin root, hence `/ralph-status` + `/ralph-build-base` own that question.

### D5 — Detect + instruct on the consumer side (no auto-rebuild)
The universal touchpoint (`make loop`) cannot reach `base/`, so its ceiling is *detect the stale base and
tell the operator the one command to fix it*, not auto-rebuild. Full hands-off auto-rebuild on the
bare-terminal path is structurally impossible without a registry (scope reversal) — stated plainly so it is
a recorded decision, not a gap.

## Risks / Trade-offs

- **Build-time and check-time hash must match exactly** → ship ONE helper (e.g. `base/scripts/base_version.sh`
  or a `Makefile`/skill-shared command) that both the build and the readers call, over a fixed sorted file
  list; never two hand-rolled hash expressions that can diverge.
- **Legacy unstamped images** (built before this change) → readers treat a missing `LABEL` as
  "unknown — rebuild recommended", never an error; `/ralph-build-base` rebuilds them.
- **Hash stability across platforms** → use a portable digest (`sha256sum` / `shasum -a 256`) over file
  *contents* (not metadata/mtime), bytes only, fixed order — reproducible on any host that builds the image.
- **`smoke-base`, not `make test`, covers image contents** (CI does not build the image) → the stamp's
  presence is asserted in `smoke-base`; the idempotent-skip + drift logic is unit-testable without a real
  build by stubbing `podman image inspect` (mirroring how the review-gate tests stub `gh`).
- **The runner reading `/etc/ralph-base.version`** must degrade if the file is absent (older image / odd
  build) → narrate "base-version: unknown" rather than failing the turn.

## Migration Plan

Additive. First rebuild after this ships stamps the image; until then, readers report "unknown — rebuild
recommended" (no breakage). Two-channel release: bump `.claude-plugin/plugin.json` and rebuild
`ralph-base:v1` (the runner gained startup narration; the build gained the stamp). Rollback is reverting the
commit; the stamp is inert metadata, so an unstamped image keeps working exactly as today.

## Open Questions

- **Helper home** — `base/scripts/base_version.sh` (baked, reusable by the in-container runner AND the
  build) vs a `Makefile`/skill-only command. Leaning a small baked helper so build and runner share one
  definition; revisit if it complicates the bash-3.2 surface.
- **Stamp granularity** — hash only `scripts/*` + `Containerfile`, or include everything under `base/`?
  Leaning the runner scripts + `Containerfile` (what actually determines runtime behavior); a docs-only
  `base/` change should not force a rebuild.
- **Whether to also bake the plugin version** as a second human-readable label (convenience only; the hash
  remains the decision key).
