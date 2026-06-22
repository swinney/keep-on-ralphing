# operator-discipline Specification

## Purpose
TBD - created by archiving change dispatch-and-operator-discipline. Update Purpose after archive.
## Requirements
### Requirement: One orchestrator per workspace is enforced

The runner SHALL take a workspace lock under `RALPH_STATE_DIR` at startup and refuse to start a second
concurrent loop on the same workspace, so competing orchestrators cannot corrupt shared state. The lock SHALL
record the owning process so a stale lock from a dead process is detected and reclaimed rather than blocking
forever.

#### Scenario: A second loop is started on the same workspace
- **WHEN** a loop is already running on a workspace and another `ralph.sh` is started on it
- **THEN** the second invocation refuses to start and reports that a loop already holds the workspace lock

#### Scenario: A stale lock from a dead process is reclaimed
- **WHEN** a lock exists but its owning process is no longer alive
- **THEN** the runner detects the stale lock and starts normally rather than refusing forever

### Requirement: Output quality is not evidence of operator discipline

The kit's operator-facing documentation SHALL state that a clean commit graph MUST NOT be read as a well-run
session — discipline and output quality are decoupled ("resilience masks sloppiness") — and that operator
discipline needs its own signal, met by the existing `.ralph/` instrumentation plus the pre-action checklists.

#### Scenario: A session produces clean output through heavy thrash
- **WHEN** a session ships zero red commits but did so via runaway processes, brute-force loops, or wrong theories
- **THEN** the documentation directs the operator not to read the clean commit graph as a well-run session

### Requirement: Pre-action checklists are scaffolded for the operator

`/ralph-init` SHALL scaffold an operator checklist document carrying the three pre-action checklists — before
backgrounding a job, before reproducing a failure, and before asserting a causal "why" about an external
system — alongside the four autonomy preconditions. These are the substitute for the gate the harness cannot
provide for operator actions.

#### Scenario: A high-risk operator action is about to happen
- **WHEN** the operator is about to background a job, reproduce a failure, or assert why an external system behaved as it did
- **THEN** the scaffolded checklist document provides the matching pre-action checklist to apply first

### Requirement: Agent-facing discipline is encoded in the prompt

The scaffolded `PROMPT.md` SHALL encode the agent-facing discipline as explicit constraints, because the
in-container agent performs reproduction and theorizing inside turns (an automated operator): triage an
intermittent failure (possible-from-code? infra-artifact? worth-it?) before brute-force reproduction; state
uncertainty and defer to ground truth rather than asserting tidy causal narratives about external systems; and
keep scope constraints in the prompt (not the filesystem) with no debug scaffolding left in commits.

#### Scenario: The agent meets an intermittent failure
- **WHEN** a test fails intermittently during a turn
- **THEN** the prompt directs the agent to run the possible/infra/worth-it triage before any reproduction loop

#### Scenario: The agent would explain an external system's behavior
- **WHEN** the agent is tempted to infer why CI, the reviewer, or an API behaved a certain way from indirect signals
- **THEN** the prompt directs it to present what is verified, flag what is inferred, and not assert a tidy narrative

