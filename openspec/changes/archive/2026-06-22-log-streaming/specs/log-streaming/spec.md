## ADDED Requirements

### Requirement: Runner emits a single append-only aggregate log

The runner SHALL write an append-only aggregate log at `RALPH_STATE_DIR/log/live.log` that
interleaves the runner's own orchestration narration and each turn's agent output as one continuous,
tailable stream for the whole run. This is additive: the per-turn `log/turn-N.txt` files and the
`status.jsonl` feed SHALL remain unchanged.

#### Scenario: The aggregate log accumulates across turns
- **WHEN** a loop runs more than one turn
- **THEN** `live.log` retains earlier turns' content (append-only) rather than being truncated per turn

#### Scenario: Runner narration is captured, not only the agent output
- **WHEN** the runner emits an orchestration line that today goes only to the terminal (e.g. `ralph: turn N`, a review-gate status, a stall/halt message)
- **THEN** that line also appears in `live.log`

#### Scenario: Agent output is captured
- **WHEN** a turn produces agent output
- **THEN** that output appears in `live.log` alongside the surrounding narration

### Requirement: Each aggregate-log line is turn-correlated

Every line written to `live.log` SHALL carry the turn number and an ISO-8601 timestamp so a
downstream aggregator can filter, order, and timeline by turn without reconstructing multi-line
events.

#### Scenario: A line carries its turn number
- **WHEN** a line is written to `live.log` during turn N
- **THEN** the line includes a `turn=N` marker

#### Scenario: A line carries a timestamp
- **WHEN** a line is written to `live.log`
- **THEN** the line includes an ISO-8601 timestamp a tailer can parse for ordering

### Requirement: Aggregate logging preserves the runner's control signals

Adding the aggregate log SHALL NOT alter the runner's turn-outcome detection. The agent's exit code
(captured via `PIPESTATUS`) and the usage-limit detection that reads the per-turn log MUST behave
exactly as they do without the aggregate log.

#### Scenario: A failing turn is still detected as failing
- **WHEN** the agent process exits non-zero and its output is also being written to `live.log`
- **THEN** the runner still observes the agent's non-zero exit code (the prefixing stage does not mask it)

#### Scenario: A usage-limit turn still pauses rather than stalls
- **WHEN** a turn emits a usage-limit message while the aggregate log is active
- **THEN** the runner still detects it, waits, and replays the task (not counted as a stall)

### Requirement: The harness is a log source, not a log service

The aggregate log SHALL be a plain file under the already-bind-mounted, gitignored
`RALPH_STATE_DIR`. The runner SHALL NOT open a network listener or push logs off-box. Centralization
across turns or across loops SHALL be performed by an operator-run aggregator reading the bind-mounted
file(s), never by the kit.

#### Scenario: No aggregator attached
- **WHEN** a loop runs with no external aggregator configured
- **THEN** it behaves exactly as today, emitting only local files under `RALPH_STATE_DIR`

#### Scenario: No network surface is added for logs
- **WHEN** an operator wants to read the loop's logs
- **THEN** the access path is the bind-mounted files (or the container's stdout), and the container exposes no log port

### Requirement: The kit documents wiring an external aggregator

The kit SHALL provide a reference recipe for tailing the bind-mounted `.ralph/` files into a standard
aggregator, covering a zero-backend realtime view and multi-loop aggregation, as documentation rather
than scaffolded code.

#### Scenario: Zero-backend realtime view
- **WHEN** an operator wants realtime visibility without standing up a storage backend
- **THEN** the recipe provides an aggregator config with a `console` sink (and `vector top`) that tails `status.jsonl` and `live.log`

#### Scenario: Centralizing several loops
- **WHEN** an operator runs loops in several repositories on one host
- **THEN** the recipe shows a single glob over `*/.ralph/` plus a derived `project` field, so all loops land in one place — with no aggregation code added to the kit
