## Context

`ralph-base:v1` carries the loop runner (`ralph.sh`, `until_reset.py`) on PATH and is built locally,
registry-free, with `--build-arg USER_UID/GID` matched to the host user so bind-mounted `/workspace` writes
come out host-owned under rootless podman. The marketplace plugin's source is the repo root (`marketplace.json`
→ `source: "./"`), so an install copies the **whole repo** into the version-pinned cache
(`~/.claude/plugins/cache/keep-on-ralphing/ralph-harness/<version>/`), including `base/` and the root
`Makefile`. The `build-base` target uses paths relative to its own directory (`-f base/Containerfile base`),
so `make -C <plugin-root> build-base` builds the image from the bundled sources with no modification.

The friction this change removes: `/ralph-init` currently tells the operator to clone the repo to get
material the plugin already delivered, and a separate clone can fall out of sync with the installed plugin.

## Goals / Non-goals

- **Goal:** a plugin user builds `ralph-base:v1` with no separate clone, from the same versioned sources the
  plugin shipped.
- **Goal:** preserve the single-source invariant — no runner machinery copied into the consumer repo.
- **Goal:** a rebuild-after-update path that always targets the *currently installed* bundled `base/`.
- **Non-goal:** a registry image, tag-scheme changes, or consumer `Makefile` changes (see proposal Non-goals).

## Decisions

### D1 — Build from `$CLAUDE_PLUGIN_ROOT`, never copy into the consumer

The build context is the plugin's bundled `base/`. The consumer repo gains **nothing** runner-related. This is
the line between this change and the forbidden pattern: vendoring `ralph.sh`/`until_reset.py`/the base
`Containerfile` into a consumer would violate "the loop machinery has exactly one source — the base image"
and reintroduce per-consumer drift. Reading the plugin's `base/` as a build *context* keeps the single source
intact (the cache is read-only input; the build writes only to podman image storage).

### D2 — Mechanism: reuse the bundled `Makefile` target

The plugin already ships the root `Makefile`; its `build-base` target already passes the host UID/GID args.
So the canonical build is:

```sh
make -C "$CLAUDE_PLUGIN_ROOT" build-base       # → tags ralph-base:v1 from $CLAUDE_PLUGIN_ROOT/base
```

No new build script is strictly required. (If a `make`-free path is wanted, the equivalent is
`podman build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t ralph-base:v1
-f "$CLAUDE_PLUGIN_ROOT/base/Containerfile" "$CLAUDE_PLUGIN_ROOT/base"`.)

### D3 — Resolve the path at build time; the rebuild is a plugin-side action

`$CLAUDE_PLUGIN_ROOT` is defined only inside the plugin execution context, and the resolved path is
**version-pinned and orphan-pruned** (~7 days after an update the old `…/<old-version>/` dir disappears).
Therefore the build/rebuild must run where the variable resolves freshly — it must NOT be frozen into a
generated consumer artifact (a consumer `Makefile` line hardcoding `…/0.2.0/base` rots at the next update).
Consequence: base-image provisioning lives on the **plugin side**, invoked in-context.

### D4 — Rebuild affordance: a dedicated `ralph-build-base` skill (recommended)

Two ways to expose the in-context rebuild:

- **(A, recommended) A small `ralph-build-base` skill** that runs `make -C "$CLAUDE_PLUGIN_ROOT" build-base`.
  Cheap to invoke for "I just updated the plugin, refresh my runner," and semantically clean (one verb, one
  job). Adds one skill to the plugin surface (`ralph-init`, `ralph-status`, `ralph-build-base`).
- **(B) Re-run `/ralph-init`**, which builds as part of its existing offer-to-build step. Re-running init on an
  already-scaffolded project is heavier (it re-walks inference and the no-overwrite scaffold) for what is just
  an image rebuild.

Recommend **(A)**; `/ralph-init` still offers the build on first run so day-one needs no second command.

### D5 — Keep the source-clone path working

`make build-base` from a repo checkout stays valid and is what this repo's own dev loop and CI use (CI does
not build the image, but contributors do). The bundled-build path is the *plugin-user* path, not a
replacement. Docs present both: clone+build for contributors, bundled-build for plugin users.

### D6 — `$CLAUDE_PLUGIN_ROOT` unset / `make`/`podman` absent

If `$CLAUDE_PLUGIN_ROOT` is unset (skill run outside a plugin context) or `make`/`podman` is missing, the
provisioning step SHALL fail loudly with the unmet precondition and fall back to printing the explicit build
command and the source-clone instructions — never silently skip, leaving the operator to hit a missing-image
error at `make loop`.

## Risks / Trade-offs

- **One more skill** (D4-A) widens the plugin surface slightly; justified by avoiding frozen-path rot and
  heavy init re-runs.
- **Image tag `v1` is content-mutable across plugin versions** — building from a newer bundled `base/` still
  tags `ralph-base:v1`, so the tag does not encode runner version. Out of scope here, but noted: a future
  change could tag by plugin version.
- **No in-CI build coverage** — image builds aren't exercised by the stubbed bash suite, so correctness rests
  on path-resolution checks + a throwaway-project smoke test. Acceptable; matches how the kit already verifies
  scaffolding.

## Migration

Additive. Existing users keep their built image; next time they need a rebuild (e.g. after a plugin update
that touched `base/scripts/`), they use the new bundled-build path instead of pulling a fresh clone. The
release checklist in CLAUDE.md is updated so step 4 ("rebuild the base image") points at the bundled-build
action.
