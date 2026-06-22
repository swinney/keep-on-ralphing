## ADDED Requirements

### Requirement: The runner notifies the operator at every needs-human transition

The runner SHALL invoke an operator-configured notifier command (`RALPH_NOTIFY_CMD`) at every transition
where the loop stops and a human is needed, passing an event identifier and a one-line reason. The
notifier SHALL be invoked by the runner, never by the in-container agent (the agent stays
GitHub/network-blind). When `RALPH_NOTIFY_CMD` is unset, the runner SHALL NOT notify and SHALL behave
exactly as before.

#### Scenario: Review gate exhausts its rounds
- **WHEN** the review gate halts after its bounded rounds and `RALPH_NOTIFY_CMD` is set
- **THEN** the runner invokes the notifier with a `review-exhausted` event and the one-line stop reason

#### Scenario: The loop stalls
- **WHEN** `RALPH_MAX_STALLS` consecutive no-commit turns halt the loop and `RALPH_NOTIFY_CMD` is set
- **THEN** the runner invokes the notifier with a `stall` event and the one-line stop reason

#### Scenario: The agent writes a stop reason
- **WHEN** a turn writes a new stop reason to `STATUS.md` and `RALPH_NOTIFY_CMD` is set
- **THEN** the runner invokes the notifier with a `stop` event and the one-line stop reason

#### Scenario: No notifier configured
- **WHEN** `RALPH_NOTIFY_CMD` is unset and the loop halts for any reason
- **THEN** the runner does not invoke any notifier and its exit code and behavior are unchanged from today

### Requirement: The notifier seam is pluggable and notifier-agnostic

`RALPH_NOTIFY_CMD` SHALL be a single command the operator supplies, invoked as
`<cmd> <event> <reason>`, so any channel (Slack, a PR comment, a webhook) can be wired without the kit
embedding a specific integration. When set, the runner SHALL validate at startup that the command is
executable and refuse to start otherwise, consistent with the existing reviewer seam. The kit SHALL
document at least one concrete recipe.

#### Scenario: A configured notifier receives event and reason
- **WHEN** the runner notifies and `RALPH_NOTIFY_CMD` is set to a command
- **THEN** that command is run with the event as the first argument and the one-line reason as the second

#### Scenario: A non-executable notifier is rejected at startup
- **WHEN** `RALPH_NOTIFY_CMD` is set to something that is not executable
- **THEN** the runner refuses to start with a clear message, rather than failing mid-run

#### Scenario: A Slack recipe is provided
- **WHEN** an operator wants Slack notifications
- **THEN** the kit documents a recipe wiring `RALPH_NOTIFY_CMD` to post `<event>`/`<reason>` to a Slack incoming webhook (no built-in Slack integration in the runner)

### Requirement: A failing notifier never breaks the loop

Notification SHALL be non-fatal: a notifier that errors, hangs, or is slow MUST NOT change the loop's
exit code, alter its control flow, or prevent the halt it is reporting. Failures SHALL be surfaced in
the runner's output, not propagated.

#### Scenario: The notifier command fails
- **WHEN** `RALPH_NOTIFY_CMD` exits non-zero (e.g. a bad webhook) while reporting a halt
- **THEN** the loop still halts with the same exit code it would have had without a notifier, and the failure is reported in the runner output

### Requirement: A blocked question stops the loop immediately and notifies

The runner SHALL treat a changed `docs/questions.md` like a `STATUS.md` stop signal: it SHALL stop
immediately and notify with a `blocked` event, rather than counting the no-commit turn toward
`RALPH_MAX_STALLS` and burning further turns. (`docs/questions.md` is the file the PROMPT contract tells
the agent to write when it hits a decision the specs do not cover.) Detection SHALL mirror the
`STATUS.md` rule — a startup snapshot, stopping only on a changed, non-whitespace value.

#### Scenario: The agent records a blocked question
- **WHEN** a turn appends a new question to `docs/questions.md` and makes no commit
- **THEN** the runner stops immediately and (if `RALPH_NOTIFY_CMD` is set) notifies with a `blocked` event, instead of treating it as a stall

#### Scenario: A pre-existing question list does not stop a fresh loop
- **WHEN** `docs/questions.md` already had content before the loop started and no new question is added
- **THEN** the runner does not treat it as a blocked stop (only a change to non-whitespace content during the run does)
