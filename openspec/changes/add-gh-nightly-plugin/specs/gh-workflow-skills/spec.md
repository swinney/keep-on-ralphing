## ADDED Requirements

### Requirement: The operator-present skills work without any scheduler

The pull-request review, issue-filing, parked-backlog and reporting skills SHALL declare, in the
configuration schema, that they require only project-config keys — and SHALL therefore run with no
host config, no installed service units, no isolated checkout, and no executor image. Their
required-key sets are whatever the schema declares for each; this requirement asserts only that no
host-config key appears among them.

#### Scenario: Review response runs on a machine with no units installed
- **WHEN** an operator invokes the review-response skill having never onboarded the scheduler
- **THEN** it runs, because every key its schema entry marks required lives in the project config

#### Scenario: No operator-present skill requires a host-config key
- **WHEN** the schema is checked for these four skills
- **THEN** none of their required-key sets contains a host-config key

### Requirement: Review findings are verified against the code before any action

The review-response skill SHALL verify each automated-reviewer finding against the actual code
before acting on it, and SHALL support reasoned rejection of an incorrect finding rather than
requiring agreement. Each finding SHALL receive an in-thread reply stating the verdict and its
evidence.

#### Scenario: An incorrect finding is rejected with evidence
- **WHEN** a reviewer's finding does not hold against the code
- **THEN** the skill replies in-thread explaining why, and does not change the code to match it

#### Scenario: Every finding is answered in its own thread
- **WHEN** a review posts multiple findings
- **THEN** each has a reply in its own thread, so none is silently dropped

### Requirement: Review-clean is determined by evidence, not by silence

The skill SHALL treat an absent review as unknown rather than clean, and SHALL determine
review-clean status from positive evidence at every endpoint an automated reviewer may use.

#### Scenario: No review comment does not mean approved
- **WHEN** no review feedback is present
- **THEN** the skill reports the review state as unknown and does not conclude the pull request
  is review-clean

### Requirement: Filed issues are cold-start work orders

The issue-filing skill SHALL produce issues executable by an agent with no other context:
objective, file anchors, plan, verification commands, and acceptance criteria in the body, with
no reliance on conversation history or external discussion.

#### Scenario: A filed issue satisfies the unattended bar
- **WHEN** the issue-filing skill files an issue
- **THEN** the result meets every condition the triage bar requires of an armed issue

### Requirement: Parked-backlog resolution is operator-present only

The parked-backlog skill SHALL declare itself operator-present and SHALL NOT be wired to any
scheduled unit, because its purpose is resolving the decisions an unattended run correctly
refused to make.

#### Scenario: The skill is absent from the installed schedule
- **WHEN** onboarding installs the scheduled units
- **THEN** no unit invokes the parked-backlog skill

### Requirement: Reports are quantified and sink-agnostic

The reporting skills SHALL assemble a quantified summary written for a non-specialist reader and
SHALL write it to the configured sink. The sink key SHALL be declared optional in the schema with a
local-file default, so an unset sink resolves to that default rather than halting the skill. A
configured sink that is unreachable SHALL NOT fail the report — the local file is the fallback.

#### Scenario: An unreachable tracker degrades to a file
- **WHEN** the configured tracker sink cannot be reached
- **THEN** the report is written locally and the run reports success with the degradation noted

#### Scenario: The default installation needs no external service
- **WHEN** no sink is configured
- **THEN** the report is written to a local file and no external service is contacted
