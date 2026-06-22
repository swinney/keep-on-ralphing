## MODIFIED Requirements

### Requirement: Build the base image from the plugin-bundled sources

The harness SHALL provide a way to build the `ralph-base:v1` image from the plugin-bundled `base/` directory,
resolved via `$CLAUDE_PLUGIN_ROOT`, so an operator who installed the plugin does NOT need to separately clone
the source repository to obtain the image. The build SHALL use the host-matched UID/GID build arguments,
preserving bind-mount ownership under rootless podman. The build SHALL also stamp the image with a
content-derived provenance hash of the runner sources + base `Containerfile` (passed as a build argument and
exposed as both an image `LABEL` and an in-image file), so the runner baked into the content-mutable `:v1`
tag is afterward machine-identifiable.

#### Scenario: Build from the installed plugin without a clone

- **WHEN** an operator who installed the plugin provisions the base image during or after `/ralph-init`
- **THEN** `ralph-base:v1` is built from the bundled `base/` under `$CLAUDE_PLUGIN_ROOT` (e.g. `make -C "$CLAUDE_PLUGIN_ROOT" build-base`)
- **AND** no clone of the source repository is required

#### Scenario: Host UID/GID matching is preserved

- **WHEN** the base image is built from the bundled sources
- **THEN** the build passes the invoking host user's UID and GID as build args, exactly as the source-clone build does
- **AND** files the loop later writes under the bind-mounted `/workspace` are owned by the host user

#### Scenario: The build stamps the image with its content hash

- **WHEN** the base image is built (from the bundled plugin sources or a source checkout)
- **THEN** the build computes the content hash of the runner sources + base `Containerfile` and bakes it into the image as the provenance stamp

### Requirement: Provide a rebuild-after-update path

After the plugin is updated, the operator SHALL be able to rebuild `ralph-base:v1` from the newly installed
bundled `base/` with a single documented, plugin-side action, so the runner stays in lockstep with the
installed plugin version. That action SHALL be freshness-aware: it rebuilds when the baked provenance stamp
differs from the currently bundled `base/` (or the image is missing/unstamped, or a force option is given),
and otherwise reports the image is already current and skips the rebuild — so it is safe to run routinely
without a wasteful unconditional build.

#### Scenario: Rebuild after a plugin update picks up the new runner

- **WHEN** the operator updates the plugin and then triggers the rebuild affordance
- **THEN** `ralph-base:v1` is rebuilt from the updated plugin's bundled `base/`
- **AND** the resulting image carries the runner from the updated plugin, not a stale prior version

#### Scenario: Re-triggering when already current does not rebuild

- **WHEN** the operator triggers the rebuild affordance and the baked stamp already matches the bundled `base/`
- **THEN** it reports the image is already current and skips the rebuild
