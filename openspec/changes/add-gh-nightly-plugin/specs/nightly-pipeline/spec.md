## ADDED Requirements

### Requirement: Only issues meeting the unattended bar are eligible

Triage SHALL apply the opt-in label that arms unattended implementation only when every one of
these holds: the issue body is a self-contained work order (objective, file anchors, acceptance
criteria, no "see discussion"); the work is code-only in the configured repo, deliverable as a
pull request to the configured trunk and verifiable by the configured gate command and/or the
pull request's own CI; it needs no live deployment or host access and contains no open design
decision; it touches no path matching the configured control-plane deny globs; and its claims
verify against the working tree (cited paths exist, revisions resolve, the target code is
tracked in this repo). When any condition is uncertain, triage SHALL NOT apply the label.

#### Scenario: An issue with unresolved design questions is not armed
- **WHEN** an issue's body requires a decision its own text cannot answer
- **THEN** triage routes it to the human-decision label and does NOT apply the opt-in label

#### Scenario: An issue requiring a control-plane path is never armed
- **WHEN** an issue can only be implemented by editing a path matching a configured deny glob
- **THEN** triage routes it to the human-decision label, because the unattended run's tool-layer
  deny hook would block the write regardless

#### Scenario: Unverifiable claims block arming
- **WHEN** an issue cites a file, symbol or revision that does not resolve in the working tree
- **THEN** triage records a skip reason and does NOT apply the opt-in label

### Requirement: Triage assigns exactly one workflow label and one priority tier

Triage SHALL assign each previously-unlabeled open issue exactly one workflow label and exactly
one priority tier, plus a type label. It SHALL add labels only — never removing one — and SHALL
leave untouched any issue already carrying an in-flight or awaiting-human-triage label. If an
issue already carries a priority tier, triage SHALL leave that tier as-is.

#### Scenario: In-flight issues are not relabeled
- **WHEN** an issue carries the in-flight label from a run already working it
- **THEN** triage skips the issue entirely and records that it was skipped

#### Scenario: A pre-existing priority tier is preserved
- **WHEN** an issue already carries a priority tier
- **THEN** triage assigns no second tier and does not replace the existing one

### Requirement: Effort tiers are mutually exclusive and never cheapen the highest priority

Triage SHALL add at most one effort tier alongside the opt-in label: the reduced-cost tier and the
elevated-verification tier SHALL NOT both be applied, and the reduced-cost tier SHALL NOT be
applied to a highest-priority issue. The supervisor SHALL independently re-check the issue's
real priority and downgrade a reduced-cost tier to the default rather than trusting the label.

#### Scenario: Conflicting effort tiers fall back to the default
- **WHEN** an issue somehow carries both effort tier labels
- **THEN** the run treats it as the default tier and reports the conflict

#### Scenario: The supervisor overrides a mislabeled cheap run
- **WHEN** an issue carries the reduced-cost tier and also the highest priority tier
- **THEN** the supervisor forces the default model and logs the override

### Requirement: Exactly one issue per drain invocation

A drain invocation SHALL open at most one pull request. On encountering a candidate that needs
deployment access or a human decision, it SHALL relabel that candidate, continue to the next
candidate, and NOT count the bounce against its one-issue budget. An empty queue, or a queue
whose every candidate is routed away, SHALL be reported as success.

#### Scenario: A bounced candidate does not end the run
- **WHEN** the top candidate is routed to the deployment-required label
- **THEN** the run advances to the next candidate rather than terminating

#### Scenario: An empty queue is success, not failure
- **WHEN** no issue carries the opt-in label
- **THEN** the run writes a one-line report and exits successfully

### Requirement: The pipeline never merges

No skill or script in the pipeline SHALL merge a pull request, pass an administrative merge
override, or enable an auto-merge setting. The pipeline's terminal state on success is an open
pull request awaiting human review.

#### Scenario: A green, review-clean pull request is still left open
- **WHEN** the loop opens a pull request, CI is green, and no review findings remain
- **THEN** the run leaves the pull request open and reports it as ready for a human to merge

### Requirement: A halted loop is removed from the queue, not re-burned

When the executor halts without a pull request, the run SHALL push any partial branch so work is
not lost, remove the opt-in label, add the human-decision label, and record the halt reason.
Removing the opt-in label is what takes the issue off the next run's queue.

#### Scenario: A stalled issue is not retried the following night
- **WHEN** the executor halts on an issue
- **THEN** the opt-in label is removed and the human-decision label added, so the next run's
  queue no longer contains it

### Requirement: Triage reasoning is withheld from a public tracker

When the configured tracker is public, triage SHALL NOT post its reasoning as an issue comment,
because verification notes can reference internal infrastructure. All such notes SHALL go to the
local run report instead. A dangerously stale issue body SHALL be flagged in the report for a
human-authored correction rather than corrected publicly by the run.

#### Scenario: A stale issue body is reported, not publicly corrected
- **WHEN** triage finds an issue body citing dead revisions or renamed files
- **THEN** it records "needs a human-authored correction" in the local report and posts nothing

### Requirement: Exploration produces a note, never a pull request

The exploration step SHALL drain one issue carrying the exploration-request label per
invocation into a grounded options-and-recommendation note posted as a comment on that issue,
then relabel it to the awaiting-human-triage state. It SHALL NOT open a pull request, modify
code, or merge anything.

#### Scenario: Exploration leaves the tree untouched
- **WHEN** the exploration step finishes an issue
- **THEN** a note comment exists, the label has advanced, and the working tree is unchanged
