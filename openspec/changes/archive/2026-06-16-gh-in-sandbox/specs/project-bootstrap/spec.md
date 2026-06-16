## MODIFIED Requirements

### Requirement: Ensure GitHub readiness during scaffolding

Because the review gate is ON by default and loop mode refuses to start without GitHub, `/ralph-init` SHALL
check the preconditions during init — a configured git remote, an authenticated `gh`, a non-base feature
branch, and a **derivable `GH_TOKEN`** (`gh auth token` returns a value, so the loop can forward a credential
into the container) — mark each as ready or blocked, and give the user the exact fix for any that are blocked,
so they do not discover the refusal at first run. `/ralph-init` SHALL ensure the generated `Makefile` forwards
`GH_TOKEN` into the loop container, since host login alone does not authenticate the in-container runner. It
SHALL note that the explicit offline opt-out is `RALPH_REVIEW_GATE=0`.

#### Scenario: GitHub readiness is ensured and reported

- **WHEN** `/ralph-init` scaffolds the review-gate surface
- **THEN** it reports the status of the git remote, `gh` authentication, the working branch, and whether a `GH_TOKEN` is derivable for the container
- **AND** for any blocked precondition it gives the user the exact remediation, noting that `RALPH_REVIEW_GATE=0` is the offline opt-out

#### Scenario: Generated Makefile forwards the token into the container

- **WHEN** `/ralph-init` generates the consumer `Makefile`
- **THEN** the loop run forwards a host-derived `GH_TOKEN` into the container so the in-container runner is authenticated
- **AND** the token is supplied at run time, not committed or baked into the image
