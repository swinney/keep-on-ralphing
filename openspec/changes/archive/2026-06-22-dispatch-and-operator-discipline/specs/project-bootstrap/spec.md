## ADDED Requirements

### Requirement: Scaffold the work-class dispatch table

`/ralph-init` SHALL scaffold the work-class dispatch table into the target project's `ralph.conf` —
documented, with the default model preserved and the class→model mapping commented/empty so behavior is
unchanged until the operator fills it — and SHALL document the tasks.md work-class tag convention in the
rendered `PROMPT.md`. Existing files SHALL NOT be overwritten.

#### Scenario: Dispatch table is scaffolded inert
- **WHEN** `/ralph-init` scaffolds a project
- **THEN** `ralph.conf` contains the documented dispatch-table keys with no class→model mapping active by default
- **AND** the loop uses the single default model until the operator tags tasks and fills the table

### Requirement: Scaffold the operator checklist and autonomy-precondition note

`/ralph-init` SHALL scaffold an operator-facing checklist document (the three pre-action checklists, the four
autonomy preconditions, and the output≠discipline caution) and SHALL surface the autonomy-precondition note in
its post-scaffold report, so the operator knows unattended mode is a gated opt-in. It SHALL NOT enable
unattended assumptions on the user's behalf.

#### Scenario: Operator checklist is scaffolded
- **WHEN** `/ralph-init` scaffolds a project
- **THEN** an operator checklist document is created (if absent) carrying the pre-action checklists and autonomy preconditions
- **AND** the post-scaffold report points the operator to it and notes unattended mode is opt-in
