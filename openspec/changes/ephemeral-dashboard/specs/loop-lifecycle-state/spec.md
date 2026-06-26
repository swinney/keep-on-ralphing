## ADDED Requirements

### Requirement: Runner stamps each invocation with a unique run identity

The runner SHALL write a per-invocation run identifier and a start timestamp to `current.json` at
startup, so any reader can fence stale prior-run data by comparing a record's run identity to the
live one. The state directory (`.ralph/`) is never cleared between runs, so this identity is the only
reliable way to tell this run's state from a previous run's.

#### Scenario: A fresh loop on a reused state directory gets a new identity
- **WHEN** a loop starts in a workspace whose `.ralph/` already holds a prior run's `current.json` and `status.jsonl`
- **THEN** `current.json` carries a run identity distinct from the prior run's, written before turn 1 produces any output

#### Scenario: A reader can distinguish live state from stale state
- **WHEN** a reader holds the live run identity and encounters a state record carrying a different run identity
- **THEN** the differing record is identifiable as stale (not the current run)

### Requirement: Runner records an explicit terminal halt class on exit

The runner SHALL write a terminal state to `current.json` on every loop-ending path, naming the halt
class (one of `complete`, `blocked`, `review-exhausted`, `stall`, `sigint`), so that "the loop ended"
is never indistinguishable from "idle between turns". This write occurs via the runner's exit path so
it fires for both clean stops and the SIGINT handler.

#### Scenario: Project completion is recorded as a terminal halt
- **WHEN** the loop stops because the project is complete (its stop reason is written and the loop exits 0)
- **THEN** `current.json` carries a terminal state naming the halt class `complete`

#### Scenario: A stall halt is recorded distinctly from completion
- **WHEN** the loop stops after exceeding the consecutive no-commit stall limit
- **THEN** `current.json` carries a terminal state naming the halt class `stall`

#### Scenario: A blocked halt is recorded distinctly
- **WHEN** the loop stops because a new blocking question was raised on a no-commit turn
- **THEN** `current.json` carries a terminal state naming the halt class `blocked`

#### Scenario: Idle between turns is not a terminal state
- **WHEN** the loop has finished a turn and is waiting before the next turn (still looping)
- **THEN** `current.json` does not carry any terminal halt class

### Requirement: Runner records pause state with an expected resume time

The runner SHALL write a structured paused record to `current.json` whenever it pauses the loop — for
a usage-limit wait or a review-gate CI wait — naming the pause reason and the expected resume time,
and SHALL clear that record once the pause ends. This lets a reader show "paused, resumes HH:MM"
instead of misreading a multi-hour wait as a hang.

#### Scenario: A usage-limit pause is recorded with its reset time
- **WHEN** the runner detects a usage-limit message and begins waiting until the limit resets
- **THEN** `current.json` carries a paused record whose reason is the usage limit and whose expected resume time is the computed reset time

#### Scenario: A review-gate CI wait is recorded as paused
- **WHEN** the runner is waiting on continuous-integration results during the review gate
- **THEN** `current.json` carries a paused record naming that wait

#### Scenario: The paused record is cleared when work resumes
- **WHEN** a pause ends and the runner proceeds to run a turn
- **THEN** the paused record is cleared from `current.json` so the loop no longer reads as paused

### Requirement: Runner exposes progress-toward-halt counters as structured fields

The runner SHALL write the current stall count and its configured maximum, and the current
review-gate round and its configured maximum, as fields in `current.json` — not only as `live.log`
narration — so a reader obtains them as parsed values rather than by scraping free text.

#### Scenario: Stall pressure is available as structured fields
- **WHEN** a no-commit turn increments the stall count
- **THEN** `current.json` carries the current stall count and the configured maximum as fields

#### Scenario: Review-gate progress is available as structured fields
- **WHEN** the review gate runs a round
- **THEN** `current.json` carries the current review round and the configured maximum as fields

### Requirement: Lifecycle signals are additive and single-sourced

Adding these signals SHALL NOT change the runner's turn-outcome detection, its usage-limit
pause-and-replay behavior, the review-gate verdict, or the `live.log` format. Each signal MUST be
written by merging into `current.json` (the existing blocked-state merge pattern) so a partial update
never drops the turn's other heartbeat fields, and the decision MUST be persisted once by the runner
rather than re-derived by each reader.

#### Scenario: Existing control behavior is unchanged
- **WHEN** a turn fails, hits a usage limit, or stalls while lifecycle signals are being written
- **THEN** the runner detects and handles it exactly as it did before these signals existed

#### Scenario: A lifecycle write preserves the other heartbeat fields
- **WHEN** the runner writes a lifecycle field (e.g. the paused record) mid-run
- **THEN** the existing `current.json` heartbeat fields for that turn (turn, task, model, started, …) are preserved, not overwritten with blanks
