## MODIFIED Requirements

### Requirement: Upgrade writes and surfaces the scaffold manifest

`/ralph-upgrade` SHALL include writing or refreshing the scaffold provenance manifest
(`.ralph-scaffold.json`) as an explicit item in its proposed plan and its final report, and SHALL write it
after a confirmed upgrade. It SHALL record a content hash **only for files whose post-upgrade content matches
the re-rendered current template** (genuinely template-faithful — created, regenerated, or clean), and SHALL
**omit** any file it left customized or insert-merged with operator edits. A customized file's hash MUST NOT
be recorded, because the "pristine" check treats `current == recorded` as safe to regenerate wholesale —
recording a customized file would make the next upgrade misread it as pristine and propose destroying the
customization. Writing the manifest MUST happen even when the project had no manifest (the legacy /
feature-detection case), because it is what lets the next upgrade use the precise pristine/customized path.

A file that is present in the project but **absent from the manifest's `files`** SHALL be treated as
manifest-absent for that file on read — i.e. feature-detected (insert-only, preserve), never
wholesale-regenerated.

#### Scenario: A legacy project's first upgrade backfills the manifest with template-faithful files
- **WHEN** `/ralph-upgrade` runs in feature-detection mode (no `.ralph-scaffold.json`) and the operator confirms the upgrade
- **THEN** the plan and report list writing `.ralph-scaffold.json`, and after applying, a tracked manifest is written recording hashes ONLY for files whose content matches the re-rendered current template
- **AND** a subsequent `/ralph-upgrade` runs in manifest-based mode

#### Scenario: A customized file is omitted from the manifest, not recorded as pristine
- **WHEN** the upgrade leaves a file customized (e.g. a scoped-coverage `scripts/gate.sh`, or a project's toolchain `Containerfile`/`.github/workflows/ci.yml`)
- **THEN** that file is omitted from the manifest's `files`
- **AND** a subsequent `/ralph-upgrade` feature-detects it (insert-only, preserved) and never proposes regenerating it wholesale

#### Scenario: The manifest write is visible, not silent
- **WHEN** the upgrade proposes changes
- **THEN** creating/refreshing the tracked `.ralph-scaffold.json` appears as a listed action the operator can see and approve, not an unannounced side effect
