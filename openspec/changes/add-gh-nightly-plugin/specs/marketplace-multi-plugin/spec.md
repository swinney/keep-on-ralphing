## ADDED Requirements

### Requirement: The marketplace lists each plugin with its own source

The marketplace manifest SHALL list every hosted plugin as its own entry with its own name,
description and `source`. A plugin hosted in this repository SHALL use a repository-relative
`source` path, so cloning the marketplace resolves it; a URL-only marketplace cannot resolve
relative paths and SHALL NOT be the distribution mechanism.

#### Scenario: Both plugins are installable from one marketplace
- **WHEN** an operator adds this marketplace
- **THEN** both plugins are listed and each can be installed independently by name

#### Scenario: Relative sources resolve from a cloned marketplace
- **WHEN** the marketplace is added from its git repository
- **THEN** each relative `source` resolves to a directory containing that plugin's manifest

### Requirement: Each plugin versions independently

Each plugin SHALL carry its own manifest version, and the two versions SHALL NOT be required to
move together. A change confined to one plugin's tree SHALL require a version bump for that
plugin only.

#### Scenario: One plugin releases without the other
- **WHEN** only one plugin's tree changes
- **THEN** only that plugin's version is bumped, and updating the other is a no-op

### Requirement: A changed plugin tree without a version bump fails the gate

The gate SHALL fail when a plugin's tree changed since the last release without that plugin's own
manifest version changing. This matters because the plugin updater keys off the manifest version
string: publishing a changed tree without bumping that plugin's version makes an update a silent
no-op that never reaches installs.

#### Scenario: An unbumped change is caught before release
- **WHEN** a plugin's skills or templates changed but its manifest version did not
- **THEN** the gate fails, naming the plugin whose version needs bumping

#### Scenario: A bump in the sibling does not satisfy the check
- **WHEN** one plugin's tree changed and only the other plugin's version was bumped
- **THEN** the gate still fails for the changed plugin

### Requirement: Relocating a plugin preserves its dynamically-resolved root

Any relocation of an existing plugin within the repository SHALL preserve behavior that resolves
the plugin root dynamically at runtime, and SHALL land as a change containing no content
modification, with the full gate green immediately before and after.

#### Scenario: Root-relative provisioning still works after a move
- **WHEN** a plugin is relocated within the repository
- **THEN** operations that resolve the plugin root dynamically continue to succeed from the new
  location without being given a hardcoded path

#### Scenario: A relocation commit changes no content
- **WHEN** the relocation lands
- **THEN** the diff consists of path moves and manifest source updates only, and the gate is
  green on both the parent and the relocation commit
