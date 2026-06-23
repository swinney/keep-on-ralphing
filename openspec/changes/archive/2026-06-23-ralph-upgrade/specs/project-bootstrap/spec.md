## ADDED Requirements

### Requirement: Init writes a tracked scaffold provenance manifest

`/ralph-init` SHALL write a scaffold provenance manifest recording the template version it scaffolded from and
a content hash for each file it generated, so a later `/ralph-upgrade` can classify each file as pristine or
customized. The manifest SHALL be written to a tracked (committed) location at the repo root
(`.ralph-scaffold.json`), NOT inside the gitignored `.ralph/` runtime directory, so it travels with the repo
to other clones and machines. The manifest SHALL be advisory: its absence MUST NOT block any skill, and
writing it SHALL NOT change the zero-config default behavior of the scaffolded project.

#### Scenario: Manifest is written to a tracked location at scaffold time
- **WHEN** `/ralph-init` scaffolds (or fills in missing files for) a project
- **THEN** it writes `.ralph-scaffold.json` at the repo root (a tracked file, not under gitignored `.ralph/`) recording the template version and a per-file content hash for the files it generated

#### Scenario: A missing manifest is non-fatal
- **WHEN** a project has no scaffold provenance manifest (e.g. it was scaffolded before manifests existed)
- **THEN** the skills still operate, with `/ralph-upgrade` falling back to feature-detection

### Requirement: Init scaffolds first-time only; changes are the upgrade skill's job

`/ralph-init` SHALL remain a first-time scaffolder that never overwrites an existing file, and its report
SHALL direct an operator who wants to propagate template *changes* into an already-initialized project to
`/ralph-upgrade` instead of re-running init. Re-running `/ralph-init` SHALL NOT be presented as the way to
adopt changed templates.

#### Scenario: An operator wants newer template content on an existing project
- **WHEN** `/ralph-init` is run on a project that already has the core scaffolded files
- **THEN** it skips the existing files (no overwrite) and points the operator to `/ralph-upgrade` for adopting template changes
