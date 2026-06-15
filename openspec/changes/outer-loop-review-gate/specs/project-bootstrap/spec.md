## ADDED Requirements

### Requirement: Scaffold the review-gate config surface

`/ralph-init` SHALL scaffold the review-gate configuration surface into the target project without changing the
zero-config offline default. It SHALL write the new `ralph.conf` keys (`RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`,
`RALPH_REVIEW_MAX_ROUNDS`, and the base-branch setting) documented and defaulting to OFF/safe values, ensure a
`review-findings.md` sink exists (gitignored or empty), and include in the rendered `PROMPT.md` the clause that
requires the agent to resolve outstanding `review-findings.md` entries before any `tasks.md` task. Existing files
SHALL NOT be overwritten, consistent with the bootstrap no-overwrite rule.

#### Scenario: Review-gate keys are scaffolded off by default
- **WHEN** `/ralph-init` scaffolds a project
- **THEN** `ralph.conf` contains the review-gate keys, documented, with `RALPH_REVIEW_GATE` and `RALPH_AUTO_MERGE` defaulting to off
- **AND** the project's loop runs the offline inner loop unchanged until a user opts in

#### Scenario: PROMPT.md gains the finding-priority clause
- **WHEN** `/ralph-init` renders `PROMPT.md` from the template
- **THEN** the prompt instructs the agent to resolve outstanding `review-findings.md` entries before selecting the next `tasks.md` task

### Requirement: Report review-gate readiness during scaffolding

When the review gate is requested or detected as desired, `/ralph-init` SHALL report whether the review-gate
preconditions are satisfiable — a configured git remote, an authenticated `gh`, and an available default reviewer
— marking each as present or missing, so the user knows the gate cannot run until they are met. It SHALL NOT
enable the gate on the user's behalf without their confirmation.

#### Scenario: Precondition report is surfaced
- **WHEN** `/ralph-init` scaffolds the review-gate surface
- **THEN** it reports the status of the git remote, `gh` authentication, and the default reviewer
- **AND** it tells the user the gate stays off until they set `RALPH_REVIEW_GATE=1` with preconditions met
