## ADDED Requirements

### Requirement: The sandbox provides the runner's GitHub tooling and the loop provisions its auth

The base sandbox image SHALL provide the `gh` CLI on PATH, and the loop SHALL provision `gh` authentication into
the container at run time by forwarding a host-derived `GH_TOKEN`, so a stock default-on loop can push, open a
PR, and read the verdict without manual setup inside the container. This is required because the review gate is
ON by default and the runner performs all `git`/`gh` work from inside the loop container. The credential SHALL
be supplied at run time, never baked into the image, and only the runner SHALL use it — the coding-agent
invocation stays unchanged and GitHub-blind. When `RALPH_REVIEW_GATE=0`, neither `gh` nor a token is required.

#### Scenario: Default-on loop starts with gh available and authenticated

- **WHEN** the loop starts with the review gate at its default (on) in a stock-built container, with a GitHub token provisioned
- **THEN** the runner finds `gh` on PATH and `gh auth status` succeeds via the provisioned token
- **AND** the loop proceeds rather than refusing to start

#### Scenario: gh is present but unauthenticated

- **WHEN** the container has `gh` but no token is provisioned
- **THEN** the runner refuses to start with a message that names the missing credential (e.g. set `GH_TOKEN`)

#### Scenario: Credential is run-time only and agent-blind

- **WHEN** the gate is enabled and a token is provisioned
- **THEN** the token is provided at run time and is not baked into the image
- **AND** only the runner uses it; the per-turn agent command is unchanged and never receives the token
