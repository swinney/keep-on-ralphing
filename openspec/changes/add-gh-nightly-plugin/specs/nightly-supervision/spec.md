## ADDED Requirements

### Requirement: The scheduler owns the long-running executor's lifetime

The supervisor script SHALL run the multi-hour executor in its **own** foreground, so the service
manager's start timeout governs it, and SHALL confine agent invocations to bounded phases. This
exists because a headless agent invocation is a batch process: nothing asynchronous survives its
turn. No agent phase SHALL background a child that outlives its turn, arm a watcher, or end a turn
intending to keep waiting.

#### Scenario: The executor is not backgrounded inside an agent turn
- **WHEN** the supervised path runs
- **THEN** the bounded agent phase writes a handoff and stops without starting the executor
- **AND** the supervisor script itself runs the executor in its own foreground

#### Scenario: A missing handoff aborts rather than proceeding blindly
- **WHEN** the bounded planning phase exits without writing the handoff file
- **THEN** the supervisor logs the reason and aborts with a failure status

### Requirement: The executor never runs in a tree a human edits

The supervisor SHALL run the executor in an isolated checkout, provisioned and verified by
dedicated scripts. When invoked by the service manager, it SHALL **fail closed** if the
workspace is not explicitly configured — refusing to fall back to any default that could be an
operator's own checkout. A by-hand invocation MAY use the configured default.

#### Scenario: A service-managed run without an explicit workspace refuses to start
- **WHEN** the supervisor detects it was launched by the service manager and no workspace is
  explicitly configured
- **THEN** it exits with an error naming the default it declined to use, and runs nothing

#### Scenario: The isolated checkout is verified before use
- **WHEN** provisioning completes
- **THEN** a verification script confirms the checkout's identity, remotes and cleanliness
  before the executor is started

### Requirement: Control-plane writes are blocked at the tool layer

The unattended profile SHALL install a deny hook that blocks writes to paths matching the
configured control-plane deny globs, independently of any instruction given to the agent. The
prose rails exist to keep a run from wasting effort attempting such a write; the hook is what
makes the guarantee.

#### Scenario: A denied write fails even if the agent attempts it
- **WHEN** an unattended agent attempts to write a path matching a deny glob
- **THEN** the hook refuses the operation regardless of the agent's intent

#### Scenario: The deny list comes from configuration
- **WHEN** a consumer configures its own control-plane deny globs
- **THEN** the hook enforces exactly those globs with no project-specific patterns baked in

### Requirement: Every run asserts a deliverable

Before exiting, the supervisor SHALL assert that the run produced either an open pull request for
the branch it worked, or a clean halt — the issue relabeled off the queue **and** a clean working
tree. Anything else SHALL exit non-success so the failure is visible rather than reported as a
quiet success.

#### Scenario: No pull request and no clean halt is a failure
- **WHEN** the executor produced no pull request and the issue still carries the opt-in label
- **THEN** the supervisor logs the missing deliverable and exits non-success

#### Scenario: A clean halt is an acceptable deliverable
- **WHEN** no pull request exists but the issue is relabeled to the human-decision label and the
  tree is clean
- **THEN** the supervisor accepts the run as successfully halted

### Requirement: Any non-success raises an alarm

The service unit SHALL invoke a failure alarm on any non-success termination, including a
start-timeout kill, so a run that dies without reaching its own reporting step is still visible
to the operator.

#### Scenario: A timeout kill still alarms
- **WHEN** the run is killed by the service manager's start timeout
- **THEN** the failure alarm fires even though no agent phase reported

### Requirement: Cost reporting is best-effort and cannot change the outcome

The supervisor SHALL report per-run token usage and estimated cost as a marked, edited-in-place
comment on the pull request. The reporter SHALL be time-bounded, SHALL self-skip when no pull
request exists, and its failure or timeout SHALL NOT alter the run's outcome. When a phase's cost
is unparseable, the report SHALL mark the figure partial rather than presenting one phase as the
whole.

#### Scenario: A stalled reporter cannot fail the run
- **WHEN** the cost reporter hangs
- **THEN** it is terminated at its bound and the run proceeds to the deliverable assertion

#### Scenario: A clean halt produces no cost comment
- **WHEN** no pull request was opened
- **THEN** the reporter self-skips without error

### Requirement: Stale state cannot mislead a later run

The supervisor SHALL clear the handoff file, truncate the findings file, and remove the stale
status feed at the start of a run, and SHALL restore a clean base state on exit via a trap that
runs on any termination path. Local branches whose pull requests are merged or closed SHALL be
pruned so a reclaim cannot collide with a leftover branch name.

#### Scenario: Yesterday's findings do not leak into tonight's run
- **WHEN** a run begins with a findings file left over from a previous run
- **THEN** the file is truncated before the executor starts

#### Scenario: Cleanup runs even on abnormal exit
- **WHEN** the run exits by error or signal
- **THEN** the trap still removes the handoff and restores the base branch
