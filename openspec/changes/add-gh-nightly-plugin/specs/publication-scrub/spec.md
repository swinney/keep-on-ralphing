## ADDED Requirements

### Requirement: The scrub SHALL state its threat model rather than claim leakage is impossible

The scrub SHALL document what it does and does not defend against, because a pattern-based check
cannot make leakage impossible and a check believed to be absolute stops being reviewed. In scope:
known private identifiers, structurally recognizable private paths and endpoints, and
credential-shaped or high-entropy strings. Explicitly out of scope: a private value that is
unlisted, novel, paraphrased, split across lines, or encoded. Human review remains required for
anything the check cannot see.

#### Scenario: The documented limits are discoverable
- **WHEN** a contributor reads the scrub documentation
- **THEN** it states the in-scope categories and the named out-of-scope gaps, rather than asserting
  that leakage is prevented

### Requirement: No literal private value SHALL be stored in tracked content

The pattern set SHALL NOT contain any literal private value, because the pattern file is itself
tracked content and would otherwise both disclose what it protects and trip its own check. Tracked
content SHALL carry only structural patterns — absolute home-directory paths, secret-store paths,
private-slug shapes, internal port numbers — plus salted digests for literal private values, matched
by comparing token digests. Literal values SHALL be supplied out of band by the operator or matched
by digest only.

#### Scenario: The pattern set passes its own scrub
- **WHEN** the scrub runs over the repository including its own pattern set
- **THEN** it reports no violation, because no literal private value is present to match

#### Scenario: A literal private value is caught without ever being stored
- **WHEN** tracked content contains a literal private value whose salted digest is registered
- **THEN** the scrub fails on that token, having never stored the value itself

### Requirement: Fixtures SHALL be synthetic and SHALL prove patterns both match and do not overmatch

A test SHALL assert that each configured pattern matches at least one synthetic fixture, so a
malformed pattern cannot silently match nothing and report a clean tree. Fixtures SHALL be
synthetic look-alikes rather than real private values. The same test SHALL assert that patterns do
NOT match a clean fixture containing near-miss words an unanchored pattern would wrongly catch, so
over-matching fails as loudly as under-matching.

#### Scenario: A typo'd pattern fails its own test
- **WHEN** a pattern is edited such that it no longer matches its fixture
- **THEN** the pattern test fails, independently of whether the repository is clean

#### Scenario: An unanchored pattern that fires on ordinary prose fails
- **WHEN** a pattern matches a near-miss word in the clean fixture — for example a product name
  appearing as a substring of an ordinary English word
- **THEN** the pattern test fails, because a check that fires on normal prose gets disabled and then
  protects nothing

#### Scenario: Adding a pattern requires adding a fixture
- **WHEN** a new pattern is added without a corresponding synthetic fixture
- **THEN** the pattern test fails

### Requirement: A pattern-independent layer SHALL scan for credential shapes and high entropy

The scrub SHALL include a second detection layer that does not depend on the enumerated pattern
set: high-entropy string detection and known-credential-shape detection. Pattern matching alone
finds only what someone already listed, so this layer exists to catch tokens nobody anticipated.
Negative tests SHALL assert that ordinary content — hashes in fixtures, base64 in test data,
provenance digests — does not trip it.

#### Scenario: An unlisted credential-shaped token is caught
- **WHEN** tracked content contains a token matching a known credential shape that no configured
  pattern covers
- **THEN** the scrub fails on it

#### Scenario: Legitimate high-entropy content does not trip the layer
- **WHEN** tracked content contains a provenance content hash or a digest from the scrub's own
  registry
- **THEN** the scrub does not report a violation

### Requirement: The scrub SHALL cover all tracked content, with narrowly justified exclusions

The check SHALL scan all tracked content, including planning artifacts and documentation, rather
than only the published plugin trees. Planning artifacts SHALL refer to a consuming project
generically rather than naming its repositories, hosts or trackers. An exclusion SHALL be permitted
only per-path, only for test data, and only with an inline reason recorded alongside it; a
directory-wide or category-wide allowlist SHALL NOT be used.

#### Scenario: A private slug in a planning document is caught
- **WHEN** a specification or design document names a private repository slug
- **THEN** the scrub check fails on that file just as it would inside a plugin tree

#### Scenario: An exclusion without a recorded reason is rejected
- **WHEN** an exclusion entry carries no inline justification
- **THEN** the scrub configuration is invalid and the check fails

### Requirement: The scrub SHALL be armed before extraction and SHALL run at every commit

The scrub check SHALL be committed and wired into both continuous integration and the pre-commit
hook **before** any extracted content is added to the repository, so no unscrubbed content is ever
committed even transiently. The check SHALL NOT be bypassable as part of the normal workflow.

#### Scenario: The gate is armed ahead of the extraction
- **WHEN** the first extracted script is committed
- **THEN** the scrub check was already active in CI and the pre-commit hook

#### Scenario: A violation is refused at commit time
- **WHEN** a commit would introduce content matching a configured pattern
- **THEN** the pre-commit hook refuses the commit

### Requirement: Incident narratives SHALL be retained

Explanatory narratives describing past failures SHALL be retained — their dates, symptoms and the
architectural consequence — because they are the rationale for the design. Only identifying
infrastructure details within them SHALL be removed.

#### Scenario: A retained narrative keeps its causal explanation
- **WHEN** a comment explains that an agent-backgrounded executor was killed when its turn ended,
  and that this is why the scheduler owns the executor's lifetime
- **THEN** that explanation is retained, with any hostname or private repository reference removed
