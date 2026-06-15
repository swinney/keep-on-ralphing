## ADDED Requirements

### Requirement: Infer and confirm the coverage check during scaffolding

`/ralph-init` SHALL infer the coverage invocation and a starting threshold for the detected toolchain (e.g.
`pytest --cov=<pkg> --cov-fail-under=<N>`, a JS coverage runner, `go test -cover`), fold it into the inferred
gate command in CI order, and add the matching coverage tooling to the Containerfile and CI toolchain blocks.
Because a too-aggressive threshold blocks every commit, `/ralph-init` SHALL confirm the threshold with the user
rather than assume it.

#### Scenario: Coverage step is inferred and folded into the gate

- **WHEN** `/ralph-init` scaffolds a project whose toolchain has a coverage tool
- **THEN** `scripts/gate.sh` includes the coverage check in CI order
- **AND** the Containerfile and CI setup install the coverage tooling
- **AND** the threshold is confirmed with the user, not silently assumed

### Requirement: PROMPT.md carries the coverage clause

The scaffolded `PROMPT.md` SHALL instruct the agent to write tests that exercise the real code path to meet the
coverage threshold, and — when code is genuinely not reasonably testable — to exclude it via the language's
standard coverage pragma or escalate to the questions channel, never to delete tests or lower the threshold to
make the gate pass (consistent with the do-not-game-the-verification guard).

#### Scenario: Prompt forbids gaming the coverage gate

- **WHEN** `/ralph-init` renders `PROMPT.md`
- **THEN** it tells the agent to satisfy coverage by testing the real path or escalating, and forbids deleting
  tests or lowering the threshold to turn the gate green
