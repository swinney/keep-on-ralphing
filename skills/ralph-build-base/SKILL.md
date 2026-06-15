---
name: ralph-build-base
description: Use to build (or rebuild) the ralph-base:v1 sandbox image from the plugin's bundled base/, with no source clone — run it on first setup and after any /plugin update that touched the runner. Triggers: "build the ralph base image", "rebuild ralph-base", "refresh the runner after updating the plugin", "ralph base image is stale".
---

# ralph-build-base — build ralph-base:v1 from the bundled plugin sources

The loop runner (`ralph.sh`, `until_reset.py`) ships **inside this plugin** under
`base/`, alongside the root `Makefile`. So `ralph-base:v1` can be built directly
from the installed plugin — the user does **not** need to clone `keep-on-ralphing`.
Use this skill on first setup, and again after a `/plugin update` that changed the
runner (the image is otherwise stale and the loop keeps running the old runner).

## Why a skill (not a documented command)

`$CLAUDE_PLUGIN_ROOT` only resolves inside the plugin execution context, and the
plugin cache is **version-pinned and orphan-pruned** — a path like
`~/.claude/plugins/cache/.../0.2.0/base` stops existing after the next update. So
the build must resolve the plugin root *fresh each time it runs*, which is exactly
what invoking this skill does. Never hand the user a frozen cache path to reuse.

## Steps

1. **Resolve the bundled sources.** Confirm `$CLAUDE_PLUGIN_ROOT` is set and that
   `$CLAUDE_PLUGIN_ROOT/base/Containerfile` and `$CLAUDE_PLUGIN_ROOT/Makefile`
   exist. If `$CLAUDE_PLUGIN_ROOT` is unset, find the plugin install path the same
   way other Ralph skills do.

2. **Preconditions.** Check that `make` and the container runtime (`podman`, or the
   `RUNTIME` the user set) are on PATH. If a prerequisite is missing, STOP and tell
   the user exactly what's unmet — do not silently skip; a missing image only
   surfaces later as a failure at `make loop`.

3. **Build.** Run, from the plugin root so the Makefile's relative paths resolve:

   ```sh
   make -C "$CLAUDE_PLUGIN_ROOT" build-base
   ```

   This tags `ralph-base:v1`, registry-free, passing the host UID/GID as build args
   (`--build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g)`) so files the loop
   writes under the bind-mounted `/workspace` come out host-owned under rootless
   podman. The `make`-free equivalent (e.g. a non-default runtime) is:

   ```sh
   podman build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) \
     -t ralph-base:v1 \
     -f "$CLAUDE_PLUGIN_ROOT/base/Containerfile" "$CLAUDE_PLUGIN_ROOT/base"
   ```

4. **Report.** Confirm the image built and is tagged `ralph-base:v1`
   (`podman images ralph-base:v1`). Remind the user that a consuming project still
   needs `make build` there (rebuilds its thin image `FROM ralph-base:v1` and
   installs the gate hook) to pick up the new base.

## Guardrails

- This reads the plugin's bundled `base/` as **build context only** — it copies
  nothing into any project. Do NOT vendor `base/`, the base `Containerfile`, or the
  runner scripts into a consumer repo; the single source stays the plugin's `base/`.
- Resolve `$CLAUDE_PLUGIN_ROOT` at build time; never persist a version-pinned plugin
  cache path anywhere — it is pruned after an update.
- Building from a `keep-on-ralphing` source checkout (`make build-base` there) stays
  valid for contributors and CI; this skill is the clone-free path for plugin users.
- Do not run a project's `make loop` from this skill — building the image is its
  only job.
