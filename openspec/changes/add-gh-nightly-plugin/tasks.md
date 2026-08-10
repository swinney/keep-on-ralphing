## 1. Resolve blocking decisions

- [ ] 1.1 Decide D3 (symmetric relocation into `plugins/ralph-harness/` vs. the zero-churn
  asymmetric layout keeping `ralph-harness` at `"source": "./"`); record the verdict and reason
  in `design.md`, and skip group 4 entirely if asymmetric is chosen
- [ ] 1.2 Decide whether `weekly-report` and `track-work` ship at all (open question in
  `design.md`); if dropped, remove them from group 7 and from the proposal's skill list
- [ ] 1.3 Decide whether the drain handoff shape is a spec'd contract or an implementation
  detail; if spec'd, add a requirement to `specs/nightly-supervision/spec.md`

## 2. Publication scrub gate (must land before any extracted content)

- [ ] 2.1 Write the pattern-fixture test asserting every configured scrub pattern matches at
  least one fixture string, and watch it fail with no patterns defined
- [ ] 2.2 Add the pattern list as a single-source file (internal hostnames, private repo slugs,
  absolute operator home paths, secret-store paths, tracker project/task identifiers, internal
  service ports) until 2.1 passes
- [ ] 2.3 Write a test asserting the scrub check fails on a fixture file containing a private
  pattern and passes on a clean fixture; the clean fixture MUST include near-miss words that an
  unanchored pattern would wrongly match (e.g. ordinary prose containing a product name as a
  substring), so over-matching fails the test as loudly as under-matching; watch it fail
- [ ] 2.4 Implement `make scrub-check` over all tracked content with no directory allowlist,
  reporting file, line and matched pattern, until 2.3 passes
- [ ] 2.5 Wire `scrub-check` into `make test` and the pre-commit hook; verify a deliberate
  violation is refused at commit time, then revert the violation
- [ ] 2.6 Confirm the existing planning artifacts pass `make scrub-check`; genericize any wording
  that names a private repo, host or tracker

## 3. Version-bump conformance check

- [ ] 3.1 Write a conformance test asserting the gate fails when a plugin's tree changed since the
  last release without that plugin's own manifest version changing, including the case where only
  the sibling's version moved; watch it fail
- [ ] 3.2 Implement the per-plugin version-bump check until 3.1 passes

## 4. Marketplace relocation (only if 1.1 chose symmetric)

- [ ] 4.1 Record the pre-move baseline: `make test` green, and capture the passing suite list
- [ ] 4.2 Move `base/`, `Makefile`, `skills/`, `templates/`, `example/`, `extras/` and
  `.claude-plugin/plugin.json` into `plugins/ralph-harness/` with `git mv`, changing no file
  content
- [ ] 4.3 Update relative paths in `base/tests/*`, the CI workflow, and the `Makefile` so the
  suite runs from the new location
- [ ] 4.4 Point the marketplace entry's `source` at `./plugins/ralph-harness`
- [ ] 4.5 Verify `make test` green and identical to the 4.1 baseline; verify plugin-root-relative
  provisioning still resolves dynamically from the new location
- [ ] 4.6 Update the root-relative path documentation in `CLAUDE.md` to match the new layout
- [ ] 4.7 Commit the relocation alone, with no content change in the diff

## 5. `gh-nightly` skeleton

- [ ] 5.1 Create `plugins/gh-nightly/` with `.claude-plugin/plugin.json` (name, description,
  version, author, homepage, repository, license, keywords) and empty `skills/`, `supervisor/`,
  `templates/`, `extras/` trees
- [ ] 5.2 Add the second marketplace entry with its relative `source`, per
  `specs/marketplace-multi-plugin/spec.md`
- [ ] 5.3 Write a test asserting both plugins resolve from a cloned marketplace and each manifest
  is well-formed; watch it fail, then make it pass
- [ ] 5.4 Verify locally that both plugins install and update independently, and that a bump to
  one leaves the other a no-op
- [ ] 5.5 Document the declared prerequisites (executor plugin, spec tooling, `gh`, systemd user
  units, `jq`) and the Linux-only scope in the new plugin's README

## 6. Supervisor extraction

- [ ] 6.1 Copy the nine supervisor scripts, the settings template and the twelve unit files into
  `plugins/gh-nightly/supervisor/` **verbatim**, and copy the five existing shell suites
  unchanged
- [ ] 6.2 Run the five suites against the verbatim copies to establish a passing baseline; record
  the result — a suite that only goes green after edits proves nothing about the extraction
- [ ] 6.3 Write failing tests asserting the supervisor refuses to run when a required
  configuration value is absent, per `specs/nightly-config/spec.md`
- [ ] 6.4 Delete every project-specific default from the scripts so configuration becomes
  required, keeping the `DRAIN_*` variable names; make 6.3 pass and keep the 6.2 baseline green
- [ ] 6.5 Write a failing test asserting the deny hook enforces exactly the configured globs with
  no baked-in project patterns, then parameterize the deny list until it passes
- [ ] 6.6 Convert the twelve unit files to templates with placeholders, add an
  `EnvironmentFile=` pointing at the configuration file, and add a rendering test comparing
  output to a golden reference
- [ ] 6.7 Write a failing test for the fail-closed workspace rule (service-managed invocation with
  no explicit workspace refuses and names the default it declined), then verify it passes against
  the extracted script
- [ ] 6.8 Confirm the deliverable assertion, cleanup trap, branch pruning, failure alarm and
  time-bounded cost reporter all satisfy `specs/nightly-supervision/spec.md`; add tests for any
  requirement not already covered by the inherited suites
- [ ] 6.9 Move the operator-specific report upload and mail plumbing to
  `plugins/gh-nightly/extras/` with a note that it is unsupported
- [ ] 6.10 Verify `make scrub-check` passes over everything added in this group

## 7. Skills genericization

- [ ] 7.1 Copy the ten skills into `plugins/gh-nightly/skills/` verbatim and record a diff
  baseline so semantic drift is detectable
- [ ] 7.2 Replace hardcoded proper nouns with documented configuration reads in `nightly-triage`,
  preserving the label taxonomy, the five-condition bar, the effort tiers and the priority tiers
  **verbatim in meaning**
- [ ] 7.3 Same for `nightly-drain`, including the bounded-phase / handoff split and the
  never-merge rail
- [ ] 7.4 Same for `nightly-explore` and `nightly-review`
- [ ] 7.5 Same for `pr-review-response`, `followup-issue` and `resolve-parked`
- [ ] 7.6 Ship `background-explorer` as the vendored exploration engine and update
  `nightly-explore` to reference the vendored copy
- [ ] 7.7 Generalize `weekly-report` and `track-work` to a default local-file sink with an
  optional tracker sink, per 1.2
- [ ] 7.8 Add a conformance check asserting no skill in the new plugin contains a project-specific
  literal (it must be a configuration read instead)
- [ ] 7.9 Add a conformance check asserting every skill documents reading the configuration file
  as its first step
- [ ] 7.10 Verify the `(recommended)`-first choice-presentation convention holds in every skill
  that presents the operator a choice

## 8. Configuration contract and lifecycle skills

- [ ] 8.1 Write `templates/gh-nightly.conf.example` covering all configured values, with a
  comment per value naming its consumer
- [ ] 8.2 Write failing tests for `nightly-onboard`: nothing is written before confirmation, and a
  detected gate command is presented with its evidence rather than assumed
- [ ] 8.3 Implement `nightly-onboard` — detect trunk, gate command and candidate deny globs;
  confirm each; write the configuration file; render and install the units — until 8.2 passes
- [ ] 8.4 Write a failing test for the tracked provenance manifest (template version plus a
  content hash per generated file, git-tracked rather than in an ignored state directory), then
  implement it
- [ ] 8.5 Add a golden reference of fully-rendered onboarding output carrying its manifest, and a
  conformance check that the recorded hashes match the reference files
- [ ] 8.6 Write failing tests for `nightly-upgrade`: missing keys proposed as a diff and applied
  only on confirmation; customized files insert-only; filled placeholders not reported as drift;
  functions without a manifest by detection
- [ ] 8.7 Implement `nightly-upgrade` until 8.6 passes
- [ ] 8.8 Write a failing test for `nightly-doctor` asserting a present-but-disabled timer is
  reported as a fault and that every installed unit is enumerated
- [ ] 8.9 Implement `nightly-doctor` — timer enablement, credential validity, executor image
  availability, isolated-checkout cleanliness, each reporting its observed value — until 8.8 passes
- [ ] 8.10 Bump `plugins/gh-nightly/.claude-plugin/plugin.json`, and `ralph-harness`'s version if
  its tree changed; confirm the group 3 check passes

## 9. Cutover and live acceptance

- [ ] 9.1 Run `nightly-onboard` against the first consuming project; review the generated
  configuration and units before installing
- [ ] 9.2 Install the rendered units and disable the private repository's existing units in the
  same step, so both never run the same schedule on one host
- [ ] 9.3 Run `nightly-doctor` and confirm every timer reports enabled
- [ ] 9.4 `chezmoi forget` and delete all ten migrated skills from the user skills directory;
  verify by absence that no dotfile copy remains to shadow the plugin versions
- [ ] 9.5 Let one live night run; confirm a real issue drained to a real pull request with
  unchanged behavior, the cost comment posted, and no merge performed
- [ ] 9.6 Compare the live night's report against a pre-cutover night for behavioral equivalence;
  record the comparison as the acceptance evidence
- [ ] 9.7 Leave the private repository's scripts in place until 9.5 has passed, then note the
  rollback path is no longer needed

## 10. Release

- [ ] 10.1 `make test` green including `scrub-check` and both conformance checks
- [ ] 10.2 Update the marketplace README describing both plugins, their relationship, and the
  prerequisite chain
- [ ] 10.3 Add an ADR in `docs/decisions/` recording why the stack is prerequisite-based rather
  than adapter-based, and why the new plugin has its own upgrade skill instead of extending the
  executor plugin's
- [ ] 10.4 Update `CHANGELOG.md` for both plugins
- [ ] 10.5 Open the pull request to trunk; do not merge
- [ ] 10.6 After merge, update the marketplace and confirm a new cached version directory appears
  for each plugin
