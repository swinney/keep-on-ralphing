## ADDED Requirements

### Requirement: The dashboard launches with the loop and advertises its address

When enabled, the loop launcher SHALL start the dashboard, bind a loopback address, print its URL,
and write that URL to a stable file so it is recoverable after the terminal scrolls. When disabled —
the default — the loop SHALL behave exactly as it does without the feature: no server, no listening
port, no change to loop output.

#### Scenario: Enabled run advertises a usable URL
- **WHEN** a loop is started with the dashboard enabled
- **THEN** a loopback URL is printed and also written to a stable file a later command can read

#### Scenario: Disabled by default leaves the loop unchanged
- **WHEN** a loop is started without enabling the dashboard
- **THEN** no server is started, no port is opened, and the loop's behavior and output are unchanged

#### Scenario: Missing host interpreter degrades gracefully
- **WHEN** the dashboard is enabled but the host lacks the interpreter needed to run the viewer
- **THEN** the loop runs normally and the dashboard is skipped with a warning, never failing the loop

### Requirement: The dashboard tears down when the loop ends

The dashboard SHALL stop and release its port when the loop process exits for any reason — project
complete, any halt, or interrupt — leaving no orphaned listener. Tearing it down MUST NOT alter the
loop's own exit behavior, in particular the interrupt stop path.

#### Scenario: Normal loop end stops the dashboard
- **WHEN** the loop process returns (the project completed or the loop halted)
- **THEN** the dashboard process stops and its port is released

#### Scenario: Interrupt still stops the loop as before
- **WHEN** the operator interrupts the loop while the dashboard is running
- **THEN** the dashboard stops and the loop's existing interrupt stop behavior is preserved

### Requirement: The dashboard updates live without reloading

The dashboard SHALL deliver updates to a connected browser without a page reload. On each connect or
reconnect it SHALL re-derive full state from the structured state files and then stream subsequent
changes, so a client that slept and reconnected shows correct current state rather than a gap.

#### Scenario: A new turn updates the open page
- **WHEN** the loop completes a turn while a browser is connected
- **THEN** the page reflects the new turn without a manual reload

#### Scenario: Reconnect after sleep re-syncs full state
- **WHEN** a browser reconnects after being suspended across several turns
- **THEN** it re-derives full current state from the state files rather than resuming from a stale position and missing the intervening turns

### Requirement: The dashboard derives facts from structured state, not log scraping

The dashboard SHALL obtain loop facts — turn, model, commit, task progress, lifecycle state — from
the structured state files and the task list, and SHALL use the aggregate log only to populate a
human-readable activity feed. It MUST NOT derive those facts by parsing aggregate-log narration.

#### Scenario: State comes from the structured files
- **WHEN** the dashboard shows the current turn, model, latest commit, and task progress
- **THEN** those values are read from the structured state files and the task list, not parsed from log narration

#### Scenario: The aggregate log feeds only the activity view
- **WHEN** the dashboard renders the aggregate log
- **THEN** that content appears only in the scrolling activity feed and is not used as a source of structured state

### Requirement: The dashboard represents loop liveness honestly

The dashboard SHALL determine whether a loop is live from the run identity together with whether the
loop's container is actually running, and SHALL fence stale prior-run data. A paused loop SHALL render
as paused with its resume time; an ended loop SHALL render as its terminal halt class; a process that
vanished without a terminal write SHALL render as ended (inferred), never as running.

#### Scenario: A paused loop is shown as paused, not hung
- **WHEN** the loop is in a usage-limit or CI pause
- **THEN** the dashboard shows it as paused with the expected resume time, not as hung or idle

#### Scenario: A finished loop is shown by its halt class
- **WHEN** the loop has ended with a recorded terminal halt class
- **THEN** the dashboard shows that outcome (complete, blocked, stall, …) rather than "running"

#### Scenario: Stale prior-run state is not shown as live
- **WHEN** the state directory still holds a previous run's records but no current run is live
- **THEN** the dashboard does not present that prior-run state as the current live loop

#### Scenario: A killed loop is shown as ended
- **WHEN** the loop's process disappeared without writing a terminal halt class and its container is no longer running
- **THEN** the dashboard shows the loop as ended (inferred), not as still running

### Requirement: The dashboard renders agent-authored content safely

The dashboard SHALL escape every agent-authored field (commit subjects, blocking-question text, log
and turn output) before placing it in the page, SHALL serve a restrictive content-security policy,
and SHALL reject any request whose Host header is not its loopback bind, defending against DNS-rebind
access to the loopback listener. This matters because all of that text is produced by the agent (and
anything it fetched); the loopback bind is necessary but not sufficient on its own.

#### Scenario: Hostile agent text cannot execute in the page
- **WHEN** a commit subject or question text contains markup or script
- **THEN** it is rendered as inert text and does not execute in the browser

#### Scenario: A rebind/cross-origin request is refused
- **WHEN** a request arrives whose Host header is not the dashboard's loopback bind
- **THEN** the dashboard refuses to serve it

### Requirement: The dashboard is single-sourced, not vendored into the project

The dashboard viewer SHALL be distributed from a single source and launched from there; it SHALL NOT
be copied into the consumer repository. Enabling or running the dashboard SHALL add no per-project
viewer source file to the project tree or to the scaffold provenance manifest — only the loop
launcher's small wiring delta may be scaffolded.

#### Scenario: A run leaves no viewer source in the project tree
- **WHEN** a loop runs with the dashboard enabled and then ends
- **THEN** the project tree contains no added viewer source file and the scaffold manifest gained no viewer entry

#### Scenario: A viewer fix reaches projects without per-project edits
- **WHEN** the kit ships a fix to the viewer
- **THEN** projects pick it up by updating the kit, with no edit to any per-project copy of the viewer
