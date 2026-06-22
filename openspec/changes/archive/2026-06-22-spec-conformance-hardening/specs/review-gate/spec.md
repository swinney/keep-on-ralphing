## MODIFIED Requirements

### Requirement: Auto-merge is a separate opt-in defaulting to off

Merging a PASSED PR SHALL be controlled by `RALPH_AUTO_MERGE`, independent of `RALPH_REVIEW_GATE` and defaulting
to OFF. With auto-merge OFF, a PASSED PR SHALL be left ready for a human to merge. With auto-merge ON, the runner
SHALL merge a PASSED PR into the base branch. A failed merge SHALL be surfaced in the runner's output (and
`live.log`), never silently swallowed or represented as a successful merge — consistent with the failed-push
guarantee.

#### Scenario: Passed PR is parked for a human by default
- **WHEN** a review is PASSED and `RALPH_AUTO_MERGE` is unset or `0`
- **THEN** the runner leaves the PR open and ready for a human to merge, and does not merge it

#### Scenario: Passed PR auto-merges when enabled
- **WHEN** a review is PASSED and `RALPH_AUTO_MERGE=1`
- **THEN** the runner merges the PR into the base branch

#### Scenario: A failed auto-merge is surfaced, not swallowed
- **WHEN** `RALPH_AUTO_MERGE=1` and the merge of a PASSED PR fails
- **THEN** the runner reports the failure in its output (and `live.log`), and does not represent the PR as merged
