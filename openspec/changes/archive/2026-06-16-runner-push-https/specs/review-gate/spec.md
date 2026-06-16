## ADDED Requirements

### Requirement: The runner pushes over an authenticated HTTPS transport derived from the token

The runner SHALL push the working branch over an authenticated HTTPS transport derived from the provisioned
`GH_TOKEN`, independent of the consumer remote's protocol, so the PR always reflects the current commits. When
the review gate is on, the runner SHALL configure git once so that an SSH GitHub remote (`git@github.com:…`) is
rewritten to HTTPS and authenticated with the token (e.g. `gh auth setup-git` plus an `insteadOf` rewrite). A
branch push that fails SHALL be reported with a clear message rather than being silently ignored, because a push
that does not land leaves the PR reviewing stale code. No SSH key or `ssh` binary is required.

#### Scenario: Branch push succeeds against an SSH remote

- **WHEN** the review gate is on and the consumer's remote is an SSH GitHub URL
- **THEN** the runner pushes the working branch over HTTPS using the provisioned token
- **AND** the remote branch is updated with the turn's new commits before the PR/verdict step

#### Scenario: A failed push is surfaced, not hidden

- **WHEN** the runner cannot push the working branch to the remote
- **THEN** it reports the failure with a clear `ralph:` message
- **AND** it does not silently proceed as if the remote reflected the current commits

#### Scenario: HTTPS-remote consumers are unaffected

- **WHEN** the consumer's remote is already an HTTPS GitHub URL
- **THEN** the push uses the token credential with no protocol rewrite needed
- **AND** behavior is unchanged from a working HTTPS push
