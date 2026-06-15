## ADDED Requirements

### Requirement: Decision prompts carry a repo-specific recommended option

When a Ralph skill presents the operator with a choice, it SHALL mark exactly one option as recommended and
SHALL accompany it with a one-line rationale tied to the current repository, rather than a static default, so a
non-expert always has a safe, explained path. The recommended option SHALL be presented first, consistent with
the AskUserQuestion convention of labelling the first option "(Recommended)".

For a choice that is high-stakes or hard to reverse — the gate command, the coverage threshold or mode,
enabling auto-merge, or otherwise changing the review gate — the recommendation SHALL state the risk in its
rationale and the skill SHALL still require explicit confirmation rather than silently accepting the
recommendation. Where there is genuinely no safe default, the skill SHALL say so plainly rather than present a
misleading recommendation. This convention governs presentation only and SHALL NOT change any default value or
behaviour.

#### Scenario: Every choice offers a recommended option with a reason

- **WHEN** a Ralph skill presents the operator with a set of options
- **THEN** exactly one option is marked recommended, presented first, with a one-line rationale specific to the current repo
- **AND** the rationale explains why it fits this repo, not merely that it is the default

#### Scenario: High-stakes recommendation states risk and still requires confirmation

- **WHEN** the choice is high-stakes or hard to reverse (e.g. the gate command, coverage threshold/mode, auto-merge)
- **THEN** the recommendation's rationale states the risk of the alternatives
- **AND** the skill requires the operator to confirm rather than silently applying the recommended option

#### Scenario: No safe default is stated honestly

- **WHEN** a choice has no safe default the skill can responsibly recommend
- **THEN** the skill says so explicitly instead of marking an arbitrary option as recommended
