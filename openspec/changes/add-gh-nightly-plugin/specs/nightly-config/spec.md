## ADDED Requirements

### Requirement: Host-execution settings SHALL live outside the consumed repository

Configuration SHALL be split into a host config and a project config by trust boundary. The host
config is operator-owned, stored outside any repository the unattended executor can write, and
holds every value that selects what runs on the host: workspace and isolated-checkout paths,
executor command, agent binary and settings paths, model identifiers, timeouts, and the baseline
control-plane deny globs. The project config is tracked in the consuming repository and SHALL hold
only inert descriptors — repository slug, trunk branch, gate command, branch-name pattern, label
overrides, tracker visibility, report sink. No value in the project config SHALL select a host
binary, path, or command.

#### Scenario: A repository cannot redirect what the host executes
- **WHEN** the project config is modified to name a different executor command or agent binary
- **THEN** the host ignores it, because that key is not accepted in the project config, and the run
  uses the operator-owned value

#### Scenario: The host config is not writable from the executor's workspace
- **WHEN** onboarding places the host config
- **THEN** its path is outside the isolated checkout and outside the consumed repository

#### Scenario: Unsafe ownership or permissions refuse the run
- **WHEN** the host config is owned by another user or is group- or world-writable
- **THEN** the run refuses to start and reports the offending path and mode

### Requirement: Configuration SHALL use one restricted grammar and SHALL never be shell-sourced

Both configuration files SHALL use a single restricted grammar — one `KEY=VALUE` pair per line,
no command substitution, no variable expansion, no interpolation — chosen as the intersection of
what the service manager's environment-file parser accepts and what a strict reader can parse, so
that both readers derive identical values structurally rather than by coincidence. No component
SHALL evaluate a configuration file as a shell script. Unknown keys SHALL be rejected rather than
ignored.

#### Scenario: Injected shell syntax is data, never executed
- **WHEN** a configuration value contains command substitution, a semicolon-separated command, or
  backticks
- **THEN** the value is either rejected by the grammar or retained as a literal string, and no
  subprocess is spawned from it

#### Scenario: Both readers derive identical values
- **WHEN** the same configuration file is read by the service units and by a skill
- **THEN** every key resolves to a byte-identical value for both readers

#### Scenario: An unknown key is an error, not a silent no-op
- **WHEN** a configuration file contains a key the schema does not define
- **THEN** loading fails and names the unrecognized key

### Requirement: Control-plane deny globs SHALL be additive-only

The effective control-plane deny list SHALL be the union of the operator baseline and any
repository-supplied additions. A repository-supplied value SHALL be able to broaden the restriction
and SHALL NOT be able to narrow, remove, or override any baseline entry.

#### Scenario: A repository cannot relax the constraints on itself
- **WHEN** the project config supplies a deny list omitting a baseline entry
- **THEN** the effective list still contains every baseline entry

#### Scenario: A repository may add its own protected paths
- **WHEN** the project config adds a glob not present in the baseline
- **THEN** the effective list contains both the baseline entries and the addition

### Requirement: A typed key schema SHALL declare required, optional and per-consumer keys

The plugin SHALL define a typed schema declaring, for every configuration key: its file (host or
project), its type, whether it is required or optional, its default when optional, and which
skills and units consume it. A skill SHALL halt only on a missing key that the schema marks
required *for that skill*, and SHALL apply the schema default for an absent optional key rather
than halting. The schema SHALL be the single source for these facts, so implementations and tests
cannot disagree about them.

#### Scenario: An operator-present skill runs without scheduler keys
- **WHEN** a skill whose schema entry requires only repository slug and trunk branch is invoked on
  a machine with no host config
- **THEN** it runs, because no key it requires is missing

#### Scenario: An absent optional key resolves to its declared default
- **WHEN** the report sink is unset and the schema declares a local-file default
- **THEN** the report is written to the local file and the run does not halt

#### Scenario: An absent required key halts that skill only
- **WHEN** the trunk branch is unset
- **THEN** skills whose schema entry requires it halt and name it, and skills that do not require
  it are unaffected

#### Scenario: The dependency table is verified, not documentary
- **WHEN** a skill reads a key not listed as one of its consumers in the schema
- **THEN** a conformance check fails

### Requirement: Onboarding SHALL detect, present, and require confirmation

The onboarding skill SHALL infer what it can from the target repository — trunk branch, gate
command, candidate control-plane deny globs — and SHALL present each inference with its evidence
for confirmation before writing. Where it presents a choice it SHALL mark one option recommended
first with a one-line, repository-specific reason. High-stakes values (gate command, deny globs,
tracker visibility) SHALL require explicit confirmation rather than silent acceptance of a
detected default.

#### Scenario: A detected gate command is confirmed, not assumed
- **WHEN** onboarding detects a plausible gate command from existing hooks or CI
- **THEN** it presents the detection with its evidence and writes it only after confirmation

#### Scenario: Nothing is written before the operator confirms
- **WHEN** the operator declines during onboarding
- **THEN** no configuration file, unit file, or timer has been created or modified

### Requirement: Onboarding SHALL record tracked provenance for its generated files

Onboarding SHALL write a tracked provenance manifest recording a template version and a content
hash per generated file, so a later upgrade can distinguish a file untouched since generation from
one the operator customized. The manifest SHALL be tracked by git rather than stored in an ignored
state directory, so it travels with a clone. The manifest SHALL cover project-config-derived files
only; the host config is operator-owned and outside provenance.

#### Scenario: A pristine generated file is classified as safe to regenerate
- **WHEN** upgrade compares a generated file whose hash matches the manifest
- **THEN** it treats the file as pristine and may regenerate it wholesale

#### Scenario: A customized file is classified insert-only
- **WHEN** a generated file's hash differs from the manifest
- **THEN** upgrade treats it as customized and only inserts what is missing

### Requirement: Upgrade SHALL add what is missing without overwriting customizations

The upgrade skill SHALL bring an already-onboarded consumer up to current templates by ADDING
missing configuration keys, unit fragments and files while preserving operator edits. It SHALL
present the proposed change as a diff and write only after explicit confirmation. It SHALL
re-render templated files with the project's own values before comparing, so substituted
placeholders do not register as drift. It SHALL function without a manifest by detection, and more
precisely when one is present.

#### Scenario: Missing keys are proposed as a diff
- **WHEN** current templates contain a configuration key the consumer lacks
- **THEN** the addition is shown as a diff and applied only on confirmation

#### Scenario: Substituted placeholders are not reported as drift
- **WHEN** a generated file differs only because its placeholders were filled at onboarding
- **THEN** upgrade re-renders with the project's values and reports no change for those lines

### Requirement: Health verification SHALL check enablement, not mere presence

The health skill SHALL verify that each scheduled unit is **enabled**, not merely installed —
because a present-but-disabled timer produces silence indistinguishable from an empty queue. It
SHALL additionally verify credential validity, executor image availability, and isolated-checkout
cleanliness, and SHALL report each check's actual observed value rather than a pass/fail alone.

#### Scenario: A disabled timer is reported as a fault
- **WHEN** a unit file exists but its timer is disabled
- **THEN** the health check reports a fault naming that timer, not a clean bill of health

#### Scenario: Every scheduled unit is covered
- **WHEN** the health check runs
- **THEN** it enumerates every unit the onboarding step installs and reports enablement for each

#### Scenario: A missing executor image is caught before a run needs it
- **WHEN** the executor image is absent
- **THEN** the health check reports it with the command that would build it

### Requirement: Declared prerequisites SHALL be enforced, with versions

Every declared prerequisite SHALL carry a minimum version and a required capability, and
onboarding, health verification and upgrade SHALL each fail fast on a missing or incompatible
prerequisite rather than deferring discovery to an unattended run. Companion-plugin compatibility
SHALL be checked explicitly, because the two plugins version independently and can therefore be
installed as an incompatible pair.

#### Scenario: A missing prerequisite fails onboarding immediately
- **WHEN** a declared prerequisite is absent from the host
- **THEN** onboarding stops and names the prerequisite and its minimum version

#### Scenario: An incompatible companion plugin is reported before a run
- **WHEN** the installed companion plugin version is outside the compatible range
- **THEN** the health check reports the incompatibility with both versions, rather than the
  mismatch first surfacing as a failed scheduled run

#### Scenario: Version skew is detected, not just absence
- **WHEN** a prerequisite is present but older than its declared minimum
- **THEN** the check fails and reports the found and required versions
