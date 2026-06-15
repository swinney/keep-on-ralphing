## ADDED Requirements

### Requirement: Scaffold the review-gate config surface

`/ralph-init` SHALL scaffold the review-gate configuration surface into the target project. It SHALL write the
`ralph.conf` keys (`RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`, `RALPH_REVIEW_MAX_ROUNDS`, and the base-branch
setting) documented, with `RALPH_REVIEW_GATE` defaulting to ON (the loop is GitHub-dependent) and
`RALPH_AUTO_MERGE` defaulting to OFF, ensure a `review-findings.md` sink is gitignored, and include in the
rendered `PROMPT.md` the clause that requires the agent to resolve outstanding `review-findings.md` entries
before any `tasks.md` task. Existing files SHALL NOT be overwritten, consistent with the bootstrap no-overwrite
rule.

#### Scenario: Review-gate keys are scaffolded on by default
- **WHEN** `/ralph-init` scaffolds a project
- **THEN** `ralph.conf` contains the review-gate keys, documented, with `RALPH_REVIEW_GATE` on and `RALPH_AUTO_MERGE` off
- **AND** the user can restore an offline loop by setting `RALPH_REVIEW_GATE=0`

#### Scenario: PROMPT.md gains the finding-priority clause
- **WHEN** `/ralph-init` renders `PROMPT.md` from the template
- **THEN** the prompt instructs the agent to resolve outstanding `review-findings.md` entries before selecting the next `tasks.md` task

### Requirement: Ensure GitHub readiness during scaffolding

Because the review gate is ON by default and loop mode refuses to start without GitHub, `/ralph-init` SHALL
check the preconditions during init — a configured git remote, an authenticated `gh`, and a non-base feature
branch — mark each as ready or blocked, and give the user the exact fix for any that are blocked, so they do
not discover the refusal at first run. It SHALL note that the explicit offline opt-out is `RALPH_REVIEW_GATE=0`.

#### Scenario: GitHub readiness is ensured and reported
- **WHEN** `/ralph-init` scaffolds the review-gate surface
- **THEN** it reports the status of the git remote, `gh` authentication, and the working branch
- **AND** for any blocked precondition it gives the user the exact remediation, noting that `RALPH_REVIEW_GATE=0` is the offline opt-out
