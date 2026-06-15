# base-image-provisioning Specification

## Purpose
TBD - created by archiving change build-base-from-plugin. Update Purpose after archive.
## Requirements
### Requirement: Build the base image from the plugin-bundled sources

The harness SHALL provide a way to build the `ralph-base:v1` image from the plugin-bundled `base/` directory,
resolved via `$CLAUDE_PLUGIN_ROOT`, so an operator who installed the plugin does NOT need to separately clone
the source repository to obtain the image. The build SHALL use the host-matched UID/GID build arguments,
preserving bind-mount ownership under rootless podman.

#### Scenario: Build from the installed plugin without a clone

- **WHEN** an operator who installed the plugin provisions the base image during or after `/ralph-init`
- **THEN** `ralph-base:v1` is built from the bundled `base/` under `$CLAUDE_PLUGIN_ROOT` (e.g. `make -C "$CLAUDE_PLUGIN_ROOT" build-base`)
- **AND** no clone of the source repository is required

#### Scenario: Host UID/GID matching is preserved

- **WHEN** the base image is built from the bundled sources
- **THEN** the build passes the invoking host user's UID and GID as build args, exactly as the source-clone build does
- **AND** files the loop later writes under the bind-mounted `/workspace` are owned by the host user

### Requirement: Preserve the single-source rule (no consumer vendoring)

Provisioning from the bundled sources SHALL NOT copy runner machinery — `ralph.sh`, `until_reset.py`, or the
base `Containerfile` — into the consumer repository. The single source of the loop machinery remains the
plugin-bundled `base/`; the consumer repo continues to carry only its own config (e.g. `scripts/gate.sh`),
never the runner.

#### Scenario: Consumer repo carries no runner machinery after provisioning

- **WHEN** the base image has been provisioned from the bundled plugin sources
- **THEN** the consumer repository contains no `ralph.sh`, `until_reset.py`, or base `Containerfile`
- **AND** the consumer's own `Containerfile` still only `FROM`s `ralph-base:v1` and adds its toolchain

### Requirement: Resolve the bundled source at build time

The provisioning step SHALL resolve the plugin `base/` location at build time and SHALL NOT persist a frozen,
version-pinned cache path into any generated artifact, because the per-version plugin cache directory is
pruned after the plugin is updated. Provisioning therefore runs where `$CLAUDE_PLUGIN_ROOT` resolves freshly
(the plugin execution context), not from a consumer-side command that hardcodes a cache path.

#### Scenario: No frozen cache path is written into the consumer

- **WHEN** the provisioning affordance is set up for a project
- **THEN** no consumer artifact (e.g. the consumer `Makefile`) hardcodes a version-pinned plugin cache path such as `.../ralph-harness/0.2.0/base`
- **AND** the build resolves the current `$CLAUDE_PLUGIN_ROOT` each time it runs

### Requirement: Provide a rebuild-after-update path

After the plugin is updated, the operator SHALL be able to rebuild `ralph-base:v1` from the newly installed
bundled `base/` with a single documented, plugin-side action, so the runner stays in lockstep with the
installed plugin version.

#### Scenario: Rebuild after a plugin update picks up the new runner

- **WHEN** the operator updates the plugin and then triggers the rebuild affordance
- **THEN** `ralph-base:v1` is rebuilt from the updated plugin's bundled `base/`
- **AND** the resulting image carries the runner from the updated plugin, not a stale prior version

### Requirement: Fail loudly when provisioning preconditions are unmet

The provisioning step SHALL report the unmet precondition and fall back to printing the explicit build
command and the source-clone instructions when the base image cannot be built from the bundled sources —
that is, when `$CLAUDE_PLUGIN_ROOT` is unset or `make`/the container runtime is unavailable. It SHALL NOT
silently skip the build, which would surface only later as a missing-image failure at loop start.

#### Scenario: Missing prerequisite reports and falls back

- **WHEN** provisioning is attempted but `$CLAUDE_PLUGIN_ROOT` is unset or the container runtime is missing
- **THEN** the step names the unmet precondition
- **AND** it prints the explicit build command and the source-clone fallback rather than silently continuing

