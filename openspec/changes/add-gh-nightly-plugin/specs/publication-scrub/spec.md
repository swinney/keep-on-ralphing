## ADDED Requirements

### Requirement: A scrub check fails the gate on private-infrastructure content

The repository SHALL provide a scrub check that fails when tracked content matches any configured
private-infrastructure pattern. The pattern set SHALL cover at minimum: internal hostnames,
private repository slugs, absolute operator home paths, secret-store paths, task-tracker project
and task identifiers, and internal service ports.

#### Scenario: A private hostname blocks the gate
- **WHEN** tracked content contains an internal hostname pattern
- **THEN** the scrub check fails, naming the file, line and matched pattern

#### Scenario: A clean tree passes silently
- **WHEN** no tracked content matches any pattern
- **THEN** the scrub check succeeds without output requiring interpretation

### Requirement: The scrub covers the entire repository

The check SHALL scan all tracked content, including planning artifacts and documentation, rather
than only the published plugin trees. Consequently, planning artifacts SHALL refer to a
consuming project generically rather than naming its repositories, hosts or trackers. No
directory SHALL be exempted by allowlist.

#### Scenario: A private slug in a planning document is caught
- **WHEN** a specification or design document names a private repository slug
- **THEN** the scrub check fails on that file just as it would inside a plugin tree

### Requirement: Every pattern is proven to match a fixture

A test SHALL assert that each configured pattern matches at least one fixture string, so a
malformed pattern cannot silently match nothing and report a clean tree.

#### Scenario: A typo'd pattern fails its own test
- **WHEN** a pattern is edited such that it no longer matches its fixture
- **THEN** the pattern test fails, independently of whether the repository is clean

#### Scenario: Adding a pattern requires adding a fixture
- **WHEN** a new pattern is added without a corresponding fixture
- **THEN** the pattern test fails

### Requirement: The scrub runs before content arrives and at every commit

The scrub check SHALL be committed and wired into both continuous integration and the
pre-commit hook **before** any extracted content is added to the repository, so no unscrubbed
content is ever committed even transiently. The check SHALL NOT be bypassable as part of the
normal workflow.

#### Scenario: The gate is armed ahead of the extraction
- **WHEN** the first extracted script is committed
- **THEN** the scrub check was already active in CI and the pre-commit hook

### Requirement: Incident narratives are retained

Explanatory narratives describing past failures SHALL be retained — their dates, symptoms and the
architectural consequence — because they are the rationale for the design. Only identifying
infrastructure details within them SHALL be removed.

#### Scenario: A retained narrative keeps its causal explanation
- **WHEN** a comment explains that an agent-backgrounded executor was killed when its turn ended,
  and that this is why the scheduler owns the executor's lifetime
- **THEN** that explanation is retained, with any hostname or private repository reference removed
