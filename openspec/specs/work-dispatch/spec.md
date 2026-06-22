# work-dispatch Specification

## Purpose
TBD - created by archiving change dispatch-and-operator-discipline. Update Purpose after archive.
## Requirements
### Requirement: Operator-tagged work class selects the model

The runner SHALL let the operator tag a task's work class (e.g. stateful/integration vs. well-specified-pure)
and map that class to a model via a configured dispatch table, selecting the model for that task's turn. The
runner SHALL NOT auto-classify work; classification is an explicit operator act. When a task carries no
work-class tag, the runner SHALL use the existing default model (`RALPH_MODEL`), preserving current behavior.

#### Scenario: A stateful-tagged task uses the stronger model
- **WHEN** a task is tagged with the stateful/integration work class and the dispatch table maps that class to a model
- **THEN** the runner selects that model for the task's turn from turn 1

#### Scenario: An untagged task uses the default model
- **WHEN** a task carries no work-class tag
- **THEN** the runner uses the default model and behaves exactly as it does today

### Requirement: The dial buys cheaper correctness, not more

The work-class dial SHALL be an efficiency lever, never a correctness lever. A misclassification MUST NOT be
able to produce an incorrect committed artifact — at worst it stalls and commits nothing — because the gate
and commit-as-truth remain the correctness guarantee.

#### Scenario: Stateful work is misclassified as pure and run cheap
- **WHEN** stateful work is wrongly tagged pure and dispatched to a cheaper model
- **THEN** the worst outcome is a stalled turn caught by the stall detector, never a bad commit reaching the branch

### Requirement: Unattended autonomy is a gated opt-in, not the default framing

The kit's consumer-facing documentation SHALL present unattended execution as an opt-in mode gated on four
preconditions — (1) well-specified work, (2) model matched from turn 1, (3) operator genuinely absent, (4) for
fan-out, single-unit build time dominates per-unit coordination cost — and SHALL record that, in evidence,
unattended operation was catalytic and narrow-band, not a general accelerator. The documentation SHALL mark
fan-out (`extras/`) as serial-by-default/unsupported, not a turnkey speedup.

#### Scenario: Preconditions are not all met
- **WHEN** any of the four autonomy preconditions is false
- **THEN** the documentation directs the operator to build supervised-direct rather than invoke unattended mode

#### Scenario: Fan-out is considered
- **WHEN** parallel content fan-out is considered
- **THEN** the documentation states it is serial-by-default with opt-in only and was net-negative at small unit size

### Requirement: Velocity targets serial latency, not turn throughput

The kit's documentation SHALL identify the human-gate cycle (PR → CI → review → fixes → merge) as the real
bottleneck and direct velocity effort at serial latency — batching milestones per PR, auto-merging on a clean
review, matching model to work class — rather than at parallelizing the convergence loop.

#### Scenario: An operator tries to go faster by parallelizing the loop
- **WHEN** the impulse is "more containers / more agents on the same milestone"
- **THEN** the documentation redirects effort to the latency moves, because systems-layer work shares files and collides and turn throughput was never the constraint

