## ADDED Requirements

### Requirement: Upgrade adds missing config without overwriting customizations

The `/ralph-upgrade` skill SHALL bring a consumer's scaffolded config up to the current bundled templates by
ADDING missing pieces (Makefile blocks, `ralph.conf` keys, `PROMPT.md` clause-blocks, new files) while
preserving the operator's existing customizations. It SHALL show the proposed change as a diff and require
explicit confirmation before writing any file; it SHALL NOT apply changes silently and SHALL NOT overwrite a
customized line in place of merely inserting what is absent. Before comparing a templated file, it SHALL
re-render the current template with the project's own values (from `ralph.conf`) so substituted placeholders
do not register as differences.

#### Scenario: Missing config is proposed, not silently written
- **WHEN** `/ralph-upgrade` finds config the current templates contain but the project lacks
- **THEN** it presents the additions as a diff and applies them only after the operator confirms

#### Scenario: Operator customizations are preserved
- **WHEN** the project's file contains custom edits (e.g. extra Makefile targets or tuned `RUN_FLAGS`)
- **THEN** the upgrade keeps those edits intact and only inserts the missing upgrade blocks

#### Scenario: Filled placeholders are not flagged as drift
- **WHEN** a templated file differs only because its `{{PLACEHOLDER}}`s were substituted at init
- **THEN** the upgrade re-renders the template with the project's values and reports no spurious change for those lines

### Requirement: Upgrade works without provenance and is more precise with a manifest

The skill SHALL function on a project that carries no scaffold provenance by detecting whether each known
upgrade block is present and offering to insert the missing ones (feature-detection). When a scaffold
provenance manifest is present, the skill SHALL use its recorded per-file hashes to classify each file as
**pristine** (current hash matches the recorded hash → untouched since scaffold) or **customized** (hashes
differ): a pristine file MAY be regenerated wholesale from the current template (re-rendered with the
project's values), while a customized file SHALL be upgraded by preserving edits and inserting only the
missing blocks. The skill SHALL report which mode it used so the operator knows the confidence level.

#### Scenario: Legacy project with no manifest
- **WHEN** `/ralph-upgrade` runs on a project scaffolded before manifests existed
- **THEN** it uses feature-detection to find and offer the missing known blocks, and states that it ran in feature-detection mode

#### Scenario: A pristine file is upgraded cleanly via the manifest
- **WHEN** the manifest is present and a file's current hash matches its recorded hash (untouched since scaffold)
- **THEN** the skill may regenerate that file wholesale from the current template, since there are no customizations to preserve

#### Scenario: A customized file is preserved
- **WHEN** the manifest is present but a file's current hash differs from its recorded hash
- **THEN** the skill preserves the operator's edits and inserts only the missing upgrade blocks rather than regenerating the file

### Requirement: The Makefile upgrade restores the host-container seam blocks

The skill SHALL specifically detect and offer the known `Makefile` upgrade blocks — the `GH_TOKEN` export and
its `-e GH_TOKEN` forwarding in `RUN_FLAGS`, and the `check-base` preflight target with its `loop`/`loop-once`
prerequisite — inserting any that are absent at the correct location, because a missing block here can make
the loop refuse to start (the default-on review gate needs a forwarded `GH_TOKEN`). It SHALL mark this as a
high-stakes change, state the risk (an un-forwarded token blocks the review-gated loop), and still require
confirmation.

#### Scenario: A pre-GH_TOKEN Makefile is upgraded
- **WHEN** the project's `Makefile` lacks the `GH_TOKEN` forwarding the current template carries
- **THEN** the skill offers to insert the `GH_TOKEN` export and `-e GH_TOKEN` forwarding, noting that without it a review-gated loop refuses to start

#### Scenario: A Makefile missing the base-staleness preflight is upgraded
- **WHEN** the project's `Makefile` has no `check-base` target
- **THEN** the skill offers to add the `check-base` target and wire it as a `loop`/`loop-once` prerequisite

### Requirement: Upgrade is bounded to config and defers runner upgrades

The skill SHALL NOT rebuild or modify the base image or the runner machinery, and SHALL NOT edit files
outside the Ralph-owned config set. When it detects the project is running on a superseded base image, it
SHALL direct the operator to `/ralph-build-base` rather than attempting the rebuild itself.

#### Scenario: A stale base image is detected during upgrade
- **WHEN** `/ralph-upgrade` observes that the project's base image is superseded
- **THEN** it tells the operator to run `/ralph-build-base` and does not attempt to rebuild the image itself

#### Scenario: Non-Ralph files are left untouched
- **WHEN** the repository contains files outside the Ralph-owned config set
- **THEN** the skill does not read them as upgrade targets or modify them
