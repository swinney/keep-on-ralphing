## ADDED Requirements

### Requirement: The base image carries a content-derived provenance stamp

The base image SHALL be stamped at build time with a **content hash** of the runner sources and the base
`Containerfile`, exposed both as an image `LABEL` (readable host-side without starting a container) and as a
file readable by the in-container runner. The stamp identifies the runner actually baked into the
content-mutable `ralph-base:v1` tag, and SHALL change if and only if the hashed sources change (it is
independent of any human-set plugin version). An image that predates stamping (no stamp present) SHALL be
treated as "unknown — rebuild recommended", never as an error.

#### Scenario: A freshly built image is stamped with its content hash
- **WHEN** the base image is built from the bundled `base/`
- **THEN** the image carries a provenance stamp (a `LABEL` and an in-image file) equal to the content hash of the runner sources + base `Containerfile`
- **AND** rebuilding from unchanged sources yields the same stamp, while changing a runner source yields a different stamp

#### Scenario: A legacy unstamped image is not an error
- **WHEN** a reader inspects a base image built before stamping existed (no provenance stamp present)
- **THEN** it reports the provenance stamp as absent (unknown) and recommends a rebuild, rather than failing

### Requirement: The base-image rebuild is freshness-aware and idempotent

The rebuild affordance SHALL treat the image as current only when BOTH the baked provenance stamp matches the
currently bundled `base/` AND the baked host UID/GID match the invoking host's `id -u`/`id -g` (the build
bakes UID/GID for bind-mount ownership, so a stamp match alone does not guarantee the image is correct for
this machine). It SHALL rebuild when the stamp differs, the baked UID/GID differ from the host, the image is
missing/unstamped, or a force option is given; otherwise it SHALL report the image is already current and
skip the build. Running it when the image is already current MUST NOT perform a wasteful rebuild.

#### Scenario: Re-running when already current skips the build
- **WHEN** the operator triggers the rebuild, the baked stamp matches the currently bundled `base/`, AND the baked UID/GID match the host
- **THEN** the affordance reports the image is already current and does not rebuild

#### Scenario: A UID/GID mismatch forces a rebuild even when the stamp matches
- **WHEN** the baked provenance stamp matches the bundled `base/` but the baked UID/GID differ from the invoking host's `id -u`/`id -g`
- **THEN** the affordance rebuilds (a stamp-only "current" verdict would otherwise reintroduce the bind-mount ownership bug the UID/GID matching prevents)

#### Scenario: Running when stale rebuilds
- **WHEN** the baked stamp differs from the currently bundled `base/` (e.g. after a plugin update that changed the runner), or the image is missing/unstamped
- **THEN** the affordance rebuilds `ralph-base:v1` from the bundled `base/`, producing an image whose stamp matches the current sources

#### Scenario: Force overrides the freshness check
- **WHEN** the operator passes the force option
- **THEN** the affordance rebuilds regardless of whether the stamp already matches

### Requirement: Base-image staleness is surfaced, never run silently stale

A drifted base image (baked stamp ≠ currently bundled `base/`) SHALL be surfaced where the operator looks,
not silently executed. The status report SHALL show the baked stamp and flag drift; the runner SHALL narrate
its baked stamp at startup so the aggregate log records which runner is executing. Neither surfacing path
SHALL fail when the stamp is absent — it reports "unknown" instead.

#### Scenario: The status report flags a drifted base image
- **WHEN** `/ralph-status` runs and the image's baked stamp differs from the currently bundled `base/`
- **THEN** it reports the baked stamp and flags that the base image is stale (a rebuild is needed)

#### Scenario: The runner records its baked version at startup
- **WHEN** a loop turn starts
- **THEN** the runner narrates its baked base-image stamp into the aggregate log (`live.log`), or "unknown" if no stamp is present

### Requirement: The consumer loop image's base is checkable at the point of use

The consumer `Makefile`'s loop entry points SHALL detect, before running a turn, when the project's loop
image was built on a now-superseded `ralph-base:v1`, and SHALL instruct the operator to rebuild the loop
image rather than running on the stale base. Because a consumer-side command cannot resolve the plugin's
`base/`, this path SHALL detect-and-instruct only; it SHALL NOT attempt to rebuild the base image itself.

#### Scenario: A loop image built on a superseded base is flagged at the point of use
- **WHEN** `make loop` (or `loop-once`) is invoked and the loop image's inherited base stamp OR baked UID/GID differ from the `ralph-base:v1` currently on the machine
- **THEN** the preflight reports the loop image is built on a stale/mismatched base and instructs the operator to rebuild it (`make build`)

#### Scenario: A current base proceeds without friction
- **WHEN** the loop image's base stamp AND UID/GID match the `ralph-base:v1` on the machine
- **THEN** the preflight passes and the loop runs normally
