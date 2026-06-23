## ADDED Requirements

### Requirement: Upgrade writes and surfaces the scaffold manifest

`/ralph-upgrade` SHALL include writing or refreshing the scaffold provenance manifest
(`.ralph-scaffold.json`) as an explicit item in its proposed plan and its final report, and SHALL write it
after a confirmed upgrade — recording a content hash of each Ralph-owned config file as it stands after the
upgrade applies. This MUST happen even when the project had no manifest (the legacy / feature-detection case),
because writing it is what lets the next upgrade use the precise pristine/customized path instead of
feature-detection again.

#### Scenario: A legacy project's first upgrade backfills the manifest
- **WHEN** `/ralph-upgrade` runs in feature-detection mode (no `.ralph-scaffold.json`) and the operator confirms the upgrade
- **THEN** the plan and report list writing `.ralph-scaffold.json`, and after applying, a tracked manifest is written recording post-upgrade hashes of the config files
- **AND** a subsequent `/ralph-upgrade` runs in manifest-based mode

#### Scenario: The manifest write is visible, not silent
- **WHEN** the upgrade proposes changes
- **THEN** creating/refreshing the tracked `.ralph-scaffold.json` appears as a listed action the operator can see and approve, not an unannounced side effect

### Requirement: ralph.conf upgrade offers missing documented sections, not only active keys

The `ralph.conf` upgrade SHALL detect and offer commented documentation sections the current template adds
(for example the work-class dispatch block, which carries no active key), not only missing active `RALPH_*`
keys — so a project's `ralph.conf` is brought fully current, including documented-but-inert knobs. Offered
sections remain commented / behavior-neutral, and existing values are never reordered or rewritten.

#### Scenario: A commented template section absent from the project is offered
- **WHEN** the current template's `ralph.conf` contains a commented documentation block (e.g. the work-class dispatch keys) that the project's `ralph.conf` lacks
- **THEN** the upgrade offers to append that commented block, even though it adds no active key

### Requirement: Skip the specs-writing guide when a spec system is present

`/ralph-upgrade` and `/ralph-init` SHALL skip scaffolding the generic specs-dir writing guide when the
project already uses a recognized spec system (e.g. an `openspec/` directory, or an established non-trivial
specs body), rather than relying on ad-hoc judgment — the generic guide is redundant and confusing there.
When no such signal is present, the existing create-if-absent behavior is unchanged.

#### Scenario: Project uses OpenSpec
- **WHEN** the project has an `openspec/` spec system and the specs-dir guide is absent
- **THEN** the skill does not scaffold the generic specs-writing guide, and notes why

#### Scenario: Project has no spec system
- **WHEN** the project has no recognized spec system and no specs guide
- **THEN** the existing create-if-absent behavior applies and the guide is offered
