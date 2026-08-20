## 1. Resolve remaining open decisions

- [ ] 1.1 Decide whether `weekly-report` and `track-work` ship at all (open question in
  `design.md`); if dropped, remove them from group 7 and from the proposal's skill list
- [ ] 1.2 Decide whether the drain handoff shape is a spec'd contract or an implementation detail;
  if spec'd, add a requirement to `specs/nightly-supervision/spec.md`

*(D3 is resolved — disjoint plugin roots, see `design.md` D3. Group 4 is unconditional.)*

## 2. Publication scrub gate (must land before any extracted content)

- [ ] 2.1 Write the threat-model document stating in-scope categories and the named out-of-scope
  gaps (unlisted, paraphrased, split, encoded values; human review still required)
- [ ] 2.2 Write the pattern-fixture test asserting every configured pattern matches at least one
  **synthetic** fixture, and watch it fail with no patterns defined
- [ ] 2.3 Extend that test to assert patterns do NOT match a clean fixture containing near-miss
  words an unanchored pattern would wrongly catch (e.g. a product name appearing as a substring of
  an ordinary English word), so over-matching fails as loudly as under-matching
- [ ] 2.4 Add the structural pattern list (absolute home-directory paths, secret-store paths,
  private-slug shapes, internal ports) as a single-source file until 2.2 and 2.3 pass
- [ ] 2.5 Write a failing test asserting a literal private value is caught by salted digest, then
  implement digest matching so that **no literal private value is stored in tracked content**
- [ ] 2.6 Write a failing test asserting the pattern set passes its own scrub, then confirm it does
- [ ] 2.7 Write failing tests for the pattern-independent layer: a credential-shaped token no
  pattern covers is caught, and legitimate high-entropy content (provenance hashes, the scrub's own
  digest registry) is not flagged; implement entropy and credential-shape detection until they pass
- [ ] 2.8 Implement `make scrub-check` over all tracked content, reporting file, line and matched
  rule; permit per-path exclusions only with an inline recorded reason, and fail the configuration
  when an exclusion lacks one
- [ ] 2.9 Wire `scrub-check` into `make test` and the pre-commit hook; verify a deliberate violation
  is refused at commit time, then revert the violation
- [ ] 2.10 Confirm the existing planning artifacts pass `make scrub-check`; genericize any wording
  that names a private repo, host or tracker

## 3. Packaging conformance checks

- [ ] 3.1 Write a conformance test asserting no plugin's source root contains another plugin's
  files; watch it fail against the current root-sourced layout
- [ ] 3.2 Write a conformance test asserting that changing a file in one plugin's tree leaves the
  other plugin's release package byte-identical; watch it fail
- [ ] 3.3 Write a conformance test asserting the gate fails when a plugin's tree changed since the
  last release without that plugin's own manifest version changing, including the case where only
  the sibling's version moved; watch it fail
- [ ] 3.4 Implement the disjoint-root and per-plugin version-bump checks until 3.1–3.3 pass (3.1 and
  3.2 go green only after group 4)

## 4. Marketplace relocation to disjoint roots

- [ ] 4.1 Record the pre-move baseline: `make test` green, and capture the passing suite list
- [ ] 4.2 Move `base/`, `Makefile`, `skills/`, `templates/`, `example/`, `extras/` and
  `.claude-plugin/plugin.json` into `plugins/ralph-harness/` with `git mv`, changing no file content
- [ ] 4.3 Update relative paths in `base/tests/*`, the CI workflow, and the `Makefile` so the suite
  runs from the new location
- [ ] 4.4 Point the marketplace entry's `source` at `./plugins/ralph-harness`
- [ ] 4.5 Verify `make test` green and identical to the 4.1 baseline; verify plugin-root-relative
  provisioning still resolves dynamically from the new location; verify 3.1 and 3.2 now pass
- [ ] 4.6 Update the root-relative path documentation in `CLAUDE.md` to match the new layout
- [ ] 4.7 Commit the relocation alone, with no content change in the diff

## 5. `gh-nightly` skeleton

- [ ] 5.1 Create `plugins/gh-nightly/` with `.claude-plugin/plugin.json` (name, description,
  version, author, homepage, repository, license, keywords) and empty `skills/`, `supervisor/`,
  `templates/`, `extras/` trees
- [ ] 5.2 Add the second marketplace entry with its relative `source`, per
  `specs/marketplace-multi-plugin/spec.md`
- [ ] 5.3 Write a test asserting both plugins resolve from a cloned marketplace and each manifest is
  well-formed; watch it fail, then make it pass
- [ ] 5.4 Verify locally that both plugins install and update independently, and that a bump to one
  leaves the other a no-op
- [ ] 5.5 Document the declared prerequisites with minimum versions (executor plugin, spec tooling,
  `gh`, systemd user units, `jq`) and the Linux-only scope in the new plugin's README

## 6. Supervisor extraction

- [ ] 6.1 Copy the nine supervisor scripts, the settings template and the twelve unit files into
  `plugins/gh-nightly/supervisor/` **verbatim**, and copy the five existing shell suites unchanged
- [ ] 6.2 Run the five suites against the verbatim copies to establish a passing baseline; record
  the result — a suite that only goes green after edits proves nothing about the extraction
- [ ] 6.3 Write failing tests asserting the supervisor refuses to run when a required configuration
  value is absent, per `specs/nightly-config/spec.md`
- [ ] 6.4 Delete every project-specific default from the scripts so configuration becomes required,
  keeping the `DRAIN_*` key names; make 6.3 pass and keep the 6.2 baseline green
- [ ] 6.5 Write a failing test asserting the deny hook enforces exactly the *effective* (union) glob
  list with no baked-in project patterns, then parameterize the deny list until it passes
- [ ] 6.6 Write failing tests for the per-repository run lock: a second invocation defers without
  claiming while the first is live; a lock owned by a dead process is reclaimed and the reclaim
  recorded; the isolated checkout is never mutated concurrently
- [ ] 6.7 Implement the run lock until 6.6 passes
- [ ] 6.8 Write failing tests for the atomic claim protocol: two invocations cannot both claim one
  issue; a claim with no branch and no pull request ever is reclaimable; a claim whose pull request
  was closed unmerged is routed to the human-decision label and NOT reclaimed; a restart after
  pull-request creation but before relabeling opens no second branch or pull request
- [ ] 6.9 Implement the claim protocol, reconciling against branch and pull-request state rather
  than the label alone, until 6.8 passes
- [ ] 6.10 Convert the twelve unit files to templates with placeholders, add the environment-file
  reference, and add a rendering test comparing output to a golden reference
- [ ] 6.11 Write a failing test for the fail-closed workspace rule (service-managed invocation with
  no explicit workspace refuses and names the default it declined), then verify it passes
- [ ] 6.12 Confirm the deliverable assertion, cleanup trap, branch pruning, failure alarm and
  time-bounded cost reporter all satisfy `specs/nightly-supervision/spec.md`; add tests for any
  requirement not already covered by the inherited suites
- [ ] 6.13 Move the operator-specific report upload and mail plumbing to
  `plugins/gh-nightly/extras/` with a note that it is unsupported
- [ ] 6.14 Verify `make scrub-check` passes over everything added in this group

## 7. Skills genericization

- [ ] 7.1 Copy the ten skills into `plugins/gh-nightly/skills/` verbatim and record a diff baseline
  so semantic drift is detectable
- [ ] 7.2 Replace hardcoded proper nouns with documented configuration reads in `nightly-triage`,
  preserving the label taxonomy, the five-condition bar, the effort tiers and the priority tiers
  **verbatim in meaning**
- [ ] 7.3 Same for `nightly-drain`, including the bounded-phase / handoff split and the never-merge
  rail
- [ ] 7.4 Same for `nightly-explore` and `nightly-review`
- [ ] 7.5 Same for `pr-review-response`, `followup-issue` and `resolve-parked`
- [ ] 7.6 Ship `background-explorer` as the vendored exploration engine and update `nightly-explore`
  to reference the vendored copy
- [ ] 7.7 Generalize `weekly-report` and `track-work` to a schema-declared optional sink with a
  local-file default, per 1.1
- [ ] 7.8 Add a conformance check asserting no skill in the new plugin contains a project-specific
  literal (it must be a configuration read instead)
- [ ] 7.9 Add a conformance check asserting every skill documents reading configuration as its first
  step, and that no operator-present skill's required-key set contains a host-config key
- [ ] 7.10 Verify the `(recommended)`-first choice-presentation convention holds in every skill that
  presents the operator a choice

## 8. Configuration contract and lifecycle skills

- [ ] 8.1 Write the typed key schema: per key, its file (host or project), type, required/optional,
  default when optional, and the skills and units that consume it
- [ ] 8.2 Write a failing conformance test asserting the schema is the single source for those facts
  — a skill reading a key not listed as one of its consumers fails the check
- [ ] 8.3 Write failing tests for the restricted grammar: command substitution, semicolon-separated
  commands and backticks are either rejected or retained as literal strings with no subprocess
  spawned; an unknown key fails loading and is named
- [ ] 8.4 Write a failing parser-parity test asserting the service-manager reader and the skill
  reader derive byte-identical values for every key from the same file
- [ ] 8.5 Implement the restricted `KEY=VALUE` parser (no substitution, no expansion, no
  interpolation, unknown keys rejected) until 8.3 and 8.4 pass; confirm nothing `source`s a config
- [ ] 8.6 Write failing tests for the trust split: a project config naming an executor command or
  agent binary is rejected because that key is not accepted there; the host config path resolves
  outside the isolated checkout and outside the consumed repo
- [ ] 8.7 Write a failing test asserting unsafe ownership or permissions on the host config refuse
  the run and report the path and mode; implement the validation
- [ ] 8.8 Write failing tests for additive-only deny globs: a project config omitting a baseline
  entry still yields an effective list containing it; an added glob appears alongside the baseline
- [ ] 8.9 Write `templates/` examples for both configs, with a comment per value naming its consumer
- [ ] 8.10 Write failing tests for required/optional resolution: an absent optional key resolves to
  its declared default without halting; an absent required key halts only the skills that require it
- [ ] 8.11 Write failing tests for `nightly-onboard`: nothing is written before confirmation, and a
  detected gate command is presented with its evidence rather than assumed
- [ ] 8.12 Implement `nightly-onboard` — detect trunk, gate command and candidate deny globs;
  confirm each; write both configs; render and install the units — until 8.11 passes
- [ ] 8.13 Write a failing test for the tracked provenance manifest (template version plus a content
  hash per generated file, git-tracked, covering project-derived files only), then implement it
- [ ] 8.14 Add a golden reference of fully-rendered onboarding output carrying its manifest, and a
  conformance check that the recorded hashes match the reference files
- [ ] 8.15 Write failing tests for `nightly-upgrade`: missing keys proposed as a diff and applied
  only on confirmation; customized files insert-only; filled placeholders not reported as drift;
  functions without a manifest by detection
- [ ] 8.16 Implement `nightly-upgrade` until 8.15 passes
- [ ] 8.17 Write a failing test for `nightly-doctor` asserting a present-but-disabled timer is
  reported as a fault and that every installed unit is enumerated
- [ ] 8.18 Write failing tests for prerequisite enforcement: a missing prerequisite fails onboarding
  naming it and its minimum version; a present-but-too-old prerequisite fails reporting found and
  required versions; an incompatible companion-plugin pair is reported by the health check with both
  versions
- [ ] 8.19 Implement `nightly-doctor` — timer enablement, credential validity, executor image
  availability, isolated-checkout cleanliness, prerequisite presence and versions, companion-plugin
  compatibility — each reporting its observed value, until 8.17 and 8.18 pass
- [ ] 8.20 Bump `plugins/gh-nightly/.claude-plugin/plugin.json`, and `ralph-harness`'s version if its
  tree changed; confirm the group 3 checks pass

## 9. Requirement-to-test traceability

- [ ] 9.1 Build the traceability matrix mapping every requirement in the six capability specs to at
  least one test, or to an explicit reasoned waiver
- [ ] 9.2 Add a gate check that fails on any requirement with neither a mapped test nor a recorded
  waiver, so an unmapped requirement blocks release rather than passing unnoticed
- [ ] 9.3 Close the gaps the matrix exposes; re-run until every requirement is mapped or waived

## 10. Fault injection and rollback rehearsal

- [ ] 10.1 Fault-inject and verify the queue paths: empty queue exits success; every-candidate-bounced
  exits success; a bounced candidate does not consume the one-issue budget
- [ ] 10.2 Fault-inject and verify the executor paths: halt relabels off the queue and pushes the
  partial branch; a start-timeout kill fires the failure alarm; a signal mid-run still runs cleanup
- [ ] 10.3 Fault-inject and verify the concurrency paths: overlapping invocation defers; stale lock
  reclaimed; stale claim reclaimed; human-rejected claim not reclaimed; restart between
  pull-request creation and relabeling duplicates nothing
- [ ] 10.4 Fault-inject and verify the reporting paths: unreachable sink degrades to a local file
  without failing the run; the cost reporter hanging is bounded and does not change the outcome;
  a public tracker receives no triage reasoning
- [ ] 10.5 Fault-inject and verify the configuration paths: injection strings are data; parser parity
  holds; unsafe host-config ownership refuses; a project config cannot narrow the deny list
- [ ] 10.6 Verify a disabled timer is reported as a fault by the health check
- [ ] 10.7 Rehearse the rollback end-to-end: re-enable the previous units, restore the dotfile
  skills, confirm the prior arrangement runs — so rollback is practised, not first attempted under
  pressure
- [ ] 10.8 Confirm `make test` green with all fault-injection suites included

## 11. Cutover and live acceptance

- [ ] 11.1 Run `nightly-onboard` against the first consuming project; review both generated configs
  and the units before installing
- [ ] 11.2 Install the rendered units and disable the private repository's existing units in the same
  step, so both never run the same schedule on one host
- [ ] 11.3 Run `nightly-doctor` and confirm every timer reports enabled and every prerequisite is
  satisfied
- [ ] 11.4 `chezmoi forget` and delete all ten migrated skills from the user skills directory; verify
  by absence that no dotfile copy remains to shadow the plugin versions
- [ ] 11.5 Let multiple live scheduled cycles run; confirm at least one real issue drained to a real
  pull request with unchanged behavior, the cost comment posted, and no merge performed
- [ ] 11.6 Confirm the live cycles also exercised at least one non-happy path (empty queue, bounce or
  halt) and that it behaved as the fault-injection suite predicted
- [ ] 11.7 Compare the live cycles' reports against pre-cutover nights for behavioral equivalence;
  record the comparison as the acceptance evidence
- [ ] 11.8 Leave the private repository's scripts in place until 11.5–11.7 have passed

## 12. Release

- [ ] 12.1 `make test` green including `scrub-check`, the packaging conformance checks, the
  traceability gate and the fault-injection suites
- [ ] 12.2 Update the marketplace README describing both plugins, their relationship, and the
  prerequisite chain with minimum versions
- [ ] 12.3 Add an ADR in `docs/decisions/` recording why the stack is prerequisite-based rather than
  adapter-based, why the new plugin has its own upgrade skill instead of extending the executor
  plugin's, why configuration is split by trust and never shell-sourced, and why the scrub is a
  layered threat model rather than an absolute guarantee
- [ ] 12.4 Update `CHANGELOG.md` for both plugins
- [ ] 12.5 Open the pull request to trunk; do not merge
- [ ] 12.6 After merge, update the marketplace and confirm a new cached version directory appears for
  each plugin
