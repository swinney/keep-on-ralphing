# spec-conformance Specification

## Purpose
TBD - created by archiving change spec-conformance-hardening. Update Purpose after archive.
## Requirements
### Requirement: Universal spec requirements are enforced by whole-tree structural tests

The kit's test suite SHALL include structural checks that scan the tracked source tree and fail when ANY
site — pre-existing ("incumbent") or newly added — violates a designated universal requirement (one whose
scope is a class of code sites, e.g. "every orchestration line", "the gate command anywhere"). These checks
SHALL run as part of `make test` with no container required, so an incumbent violation is caught even when
no diff touches the offending code.

#### Scenario: An incumbent violation fails the suite
- **WHEN** tracked code violates a universal requirement covered by a structural check, even though no recent change touched that code
- **THEN** `make test` fails and names the offending file and the rule it broke

#### Scenario: Complete live.log narration is enforced
- **WHEN** an operator-facing orchestration line in the loop body or a signal trap is emitted without reaching `live.log` (neither routed through `narrate` nor paired with `_live_append`/`tee "$log"`)
- **THEN** the structural check fails
- **AND** pre-loop refuse-to-start lines written to stderr before `live.log` exists are exempt

#### Scenario: Single-source gate command is enforced
- **WHEN** the resolved gate command string is restated in any tracked file other than its single source (the gate script), in either `templates/` or `example/`
- **THEN** the structural check fails

#### Scenario: The golden-reference example conforms to the templates
- **WHEN** the `example/ralph.conf` key set diverges from `templates/ralph.conf.example` in either direction (a documented key missing from the example, or a stray key absent from the template)
- **THEN** the structural check fails

### Requirement: A change that adds or modifies a universal requirement declares its incumbent impact

A change's proposal SHALL declare the incumbent impact of any universal-scope requirement it adds or
modifies. A requirement is universal when it governs a class of sites rather than one (every / all / always
/ never / applies to each). The proposal SHALL enumerate the pre-existing ("incumbent") governed sites and
SHALL confirm they comply or include tasks to sweep them. This addresses the *semantic* class of drift that
a structural test cannot encode, where "governed site" needs per-requirement reasoning.

#### Scenario: A universal requirement lists its incumbent sites
- **WHEN** a change's proposal adds or modifies a universal-scope requirement
- **THEN** the change enumerates the incumbent governed sites and either confirms compliance or adds tasks to sweep them
- **AND** a reviewer can check incumbent compliance without re-deriving the governed set from scratch

