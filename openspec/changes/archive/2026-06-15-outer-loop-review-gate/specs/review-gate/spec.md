## ADDED Requirements

### Requirement: The review gate is ON by default and the loop is GitHub-dependent

The runner SHALL enable the outer-loop review gate by default (`RALPH_REVIEW_GATE` defaults to ON). Because the
gate is on by default, loop mode SHALL preflight its preconditions (a configured git remote, an authenticated
`gh`, a reachable reviewer, and a non-base working branch) and SHALL refuse to start with a clear message if any
is missing, rather than silently skipping the gate — i.e. the loop is GitHub-dependent by default. Setting
`RALPH_REVIEW_GATE=0` SHALL restore the offline inner loop: no push, no PR, no review, and no dependency on a
git remote, network, or the `gh` CLI.

#### Scenario: Gate on by default refuses to start without GitHub
- **WHEN** the loop runs with `RALPH_REVIEW_GATE` unset (its default) and no git remote, no authenticated `gh`, or a base-branch checkout
- **THEN** the runner refuses to start and prints which precondition is unmet
- **AND** it does not begin running turns

#### Scenario: Explicit opt-out restores the offline loop
- **WHEN** the loop runs with `RALPH_REVIEW_GATE=0`
- **THEN** the runner completes turns using only the local gate and commit signal
- **AND** it neither pushes nor requires `gh`, a remote, or network access

### Requirement: The container agent stays GitHub-blind; the runner owns all remote interaction

All remote operations (push, PR creation, review request, verdict polling, merge) SHALL be performed by the
runner using `git`/`gh`. The coding-agent invocation SHALL be unchanged by the review gate, so the gate works
regardless of which agent runs in the container. The agent SHALL receive review outcomes only through a file
of tasks, never by being asked to call GitHub itself.

#### Scenario: Agent invocation is unaffected by the gate
- **WHEN** the review gate is enabled
- **THEN** the per-turn agent command is identical to the gate-disabled case
- **AND** the agent is never required to run `gh`, use a GitHub MCP, or know that a PR exists

### Requirement: A committing turn publishes and requests an independent review

When the review gate is ON and a turn produces a new commit, the runner SHALL push the working branch, ensure
a pull request targeting the configured base branch exists (create it if absent, reuse it if present), and
request an independent review of that PR. The reviewer SHALL be given the artifact and ground-truth repository
state but SHALL be withheld the author's intent/rationale, so the review remains assumption-challenging.

#### Scenario: First commit on a branch opens a PR and requests review
- **WHEN** a gate-enabled turn commits and no PR yet exists for the branch
- **THEN** the runner pushes the branch, opens a PR against the base branch, and requests a review
- **AND** the PR does not carry the agent's reasoning/intent as review input

#### Scenario: Subsequent commit reuses the open PR
- **WHEN** a later gate-enabled turn commits on a branch that already has an open PR
- **THEN** the runner pushes to the existing PR and requests a fresh review rather than opening a duplicate

### Requirement: Review passes only on zero findings and green CI

The runner SHALL treat a review as PASSED if and only if the reviewer returns zero findings AND CI for the PR
head is green. CI status SHALL be read by the runner directly from the CI system (ground truth), not inferred
from any claim made by the reviewer. Any other verdict SHALL be treated as NOT PASSED.

#### Scenario: Clean review and green CI passes
- **WHEN** the reviewer returns zero findings and the runner observes CI green for the PR head
- **THEN** the review is PASSED

#### Scenario: Findings or red CI does not pass
- **WHEN** the reviewer returns one or more findings, or the runner observes CI not-green
- **THEN** the review is NOT PASSED
- **AND** the runner does not treat a reviewer's unverifiable assertion about CI as the CI verdict

### Requirement: The asynchronous review wait is not a stall

While a review or CI run for the current PR is pending, the runner SHALL wait/poll for the verdict, reusing the
usage-limit pause/replay mechanism, and SHALL NOT count the wait as a no-commit stall.

#### Scenario: Pending verdict pauses rather than stalls
- **WHEN** the review or CI verdict is not yet available after a committing turn
- **THEN** the runner waits and re-checks without incrementing the stall counter

### Requirement: Findings re-enter the loop as prioritized agent tasks

When a review is NOT PASSED because of findings, the runner SHALL write those findings to `review-findings.md`
in the workspace. The scaffolded `PROMPT.md` contract SHALL require the agent to resolve outstanding entries in
`review-findings.md` before picking the next `tasks.md` task. A turn that addresses findings and commits SHALL
trigger a re-push and re-review of the PR; when a re-review is PASSED the runner SHALL clear `review-findings.md`.

#### Scenario: Findings become the agent's next work
- **WHEN** a review returns findings
- **THEN** the runner records them in `review-findings.md`
- **AND** the next turn's agent resolves those findings before any `tasks.md` task, per the prompt contract

#### Scenario: A passed re-review clears the findings
- **WHEN** a later review of the same PR returns zero findings and CI is green
- **THEN** the runner clears `review-findings.md`

### Requirement: Review rounds are bounded and escalate to a human stall

The runner SHALL bound the number of consecutive review rounds that still produce findings on one PR by
`RALPH_REVIEW_MAX_ROUNDS`. On reaching that bound the runner SHALL write a stop reason to `STATUS.md` and halt
for human review, so a reviewer that keeps surfacing new findings cannot loop indefinitely.

#### Scenario: Exhausted review rounds halt the loop
- **WHEN** `RALPH_REVIEW_MAX_ROUNDS` consecutive review rounds on the same PR each still return findings
- **THEN** the runner writes a stop reason to `STATUS.md` and exits for human review

### Requirement: Auto-merge is a separate opt-in defaulting to off

Merging a PASSED PR SHALL be controlled by `RALPH_AUTO_MERGE`, independent of `RALPH_REVIEW_GATE` and defaulting
to OFF. With auto-merge OFF, a PASSED PR SHALL be left ready for a human to merge. With auto-merge ON, the runner
SHALL merge a PASSED PR into the base branch.

#### Scenario: Passed PR is parked for a human by default
- **WHEN** a review is PASSED and `RALPH_AUTO_MERGE` is unset or `0`
- **THEN** the runner leaves the PR open and ready for a human to merge, and does not merge it

#### Scenario: Passed PR auto-merges when enabled
- **WHEN** a review is PASSED and `RALPH_AUTO_MERGE=1`
- **THEN** the runner merges the PR into the base branch

### Requirement: The reviewer is a replaceable seam with Copilot as the default

The runner SHALL isolate "request a review of a PR and return its findings" behind a single replaceable step
whose contract is: input a PR reference; output a list of findings (empty meaning clean). GitHub Copilot review
SHALL be the default implementation. CI status determination SHALL remain the runner's responsibility, separate
from the reviewer step, so an alternative reviewer can be substituted without reimplementing the gate.

#### Scenario: Default reviewer is Copilot
- **WHEN** the review gate is enabled with no reviewer override
- **THEN** the runner requests a GitHub Copilot review and reads its findings

#### Scenario: Reviewer step is substitutable
- **WHEN** a project supplies an alternative reviewer satisfying the input/output contract
- **THEN** the rest of the gate (publish, CI check, pass bar, findings-as-tasks, bounded rounds, merge) operates unchanged
