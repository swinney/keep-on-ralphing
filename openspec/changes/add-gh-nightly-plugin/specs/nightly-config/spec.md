## ADDED Requirements

### Requirement: One sourceable file is the single source of project values

The plugin SHALL read every project-specific value from one shell-sourceable configuration file
in the consuming repo. The file SHALL be consumable both by the service units (as an environment
file) and by the skills, and each skill SHALL name reading it as its documented first step. No
skill or script SHALL carry a project-specific default for any configured value.

The configured values SHALL cover at minimum: repository slug, trunk branch, gate command,
control-plane deny globs, isolated-checkout path, executor command, spec command, whether the
tracker is public, report sink, default and reduced-cost model identifiers, branch-name pattern,
and label-name overrides.

#### Scenario: A skill halts rather than guessing a missing required value
- **WHEN** a skill runs and a required configuration value is absent
- **THEN** it stops and reports which value is missing, taking no tracker or repository action

#### Scenario: The same file drives both readers
- **WHEN** the service units start and a skill runs
- **THEN** both obtain identical values from the one configuration file, with no second source

### Requirement: Onboarding detects, presents, and confirms

The onboarding skill SHALL infer what it can from the target repo — trunk branch, gate command,
candidate control-plane deny globs — and present each inference for confirmation before writing.
Where it presents a choice it SHALL mark one option recommended first with a one-line,
repo-specific reason. High-stakes values (gate command, deny globs, tracker visibility) SHALL
require explicit confirmation rather than silent acceptance of a detected default.

#### Scenario: A detected gate command is confirmed, not assumed
- **WHEN** onboarding detects a plausible gate command from existing hooks or CI
- **THEN** it presents the detection with its evidence and writes it only after confirmation

#### Scenario: Nothing is written before the operator confirms
- **WHEN** the operator declines during onboarding
- **THEN** no configuration file, unit file, or timer has been created or modified

### Requirement: Onboarding records tracked provenance for its generated files

Onboarding SHALL write a tracked provenance manifest recording a template version and a content
hash per generated file, so a later upgrade can distinguish a file untouched since generation
from one the operator customized. The manifest SHALL be tracked by git rather than stored in an
ignored state directory, so it travels with a clone.

#### Scenario: A pristine generated file is classified as safe to regenerate
- **WHEN** upgrade compares a generated file whose hash matches the manifest
- **THEN** it treats the file as pristine and may regenerate it wholesale

#### Scenario: A customized file is classified insert-only
- **WHEN** a generated file's hash differs from the manifest
- **THEN** upgrade treats it as customized and only inserts what is missing

### Requirement: Upgrade adds what is missing without overwriting customizations

The upgrade skill SHALL bring an already-onboarded consumer up to current templates by ADDING
missing configuration keys, unit fragments and files while preserving operator edits. It SHALL
present the proposed change as a diff and write only after explicit confirmation. It SHALL
re-render templated files with the project's own values before comparing, so substituted
placeholders do not register as drift. It SHALL function without a manifest by detection, and
more precisely when one is present.

#### Scenario: Missing keys are proposed as a diff
- **WHEN** current templates contain a configuration key the consumer lacks
- **THEN** the addition is shown as a diff and applied only on confirmation

#### Scenario: Substituted placeholders are not reported as drift
- **WHEN** a generated file differs only because its placeholders were filled at onboarding
- **THEN** upgrade re-renders with the project's values and reports no change for those lines

### Requirement: Health verification checks enablement, not mere presence

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
