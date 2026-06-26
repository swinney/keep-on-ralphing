# Tasks — ephemeral-dashboard

Phase 1 (groups 1–2) lands and ships first; it is valuable on its own. Phase 2 (groups 3–7) builds
the viewer on top of it. Each implementation task is test-first per the project's TDD discipline.

## 1. Phase 1 — Honest lifecycle state (runner: `base/scripts/ralph.sh`)

- [x] 1.1 Write failing tests in the stubbed-`claude` suite for the new `current.json` signals (run-id, terminal halt class, paused record, promoted counters) — see them fail before implementing
- [x] 1.2 Stamp a per-invocation run-id + start time into `current.json` at startup (before turn 1), via the existing merge pattern
- [x] 1.3 Write an explicit terminal state to `current.json` on every loop-ending path (EXIT trap), naming the halt class: `complete | blocked | review-exhausted | stall | sigint`
- [x] 1.4 Write a structured `paused:{reason,until}` record around the usage-limit sleep (reason = usage-limit, until = computed reset) and clear it when the pause ends
- [x] 1.5 Write the same `paused` record around the review-gate CI wait, and clear it on resume (test in `test_review_gate.sh`)
- [x] 1.6 Promote the stall count + configured max, and the review round + configured max, into `current.json` fields (in addition to existing narration)
- [x] 1.7 Confirm additivity: no change to turn-outcome detection, usage-limit replay, review-gate verdict, or `live.log`; partial writes never drop other heartbeat fields (explicit field-preservation assertion + full suite green)
- [x] 1.8 Update the `/ralph-status` skill to read the new structured fields (terminal halt class, paused record, counters) instead of inferring — it gains the same honest signals

## 2. Phase 1 — Land & release

- [ ] 2.1 `make test` green; runner tests cover every exit path's terminal halt class and both pause sites
- [ ] 2.2 Rebuild the base image and verify the baked runner in-container (PID 1), per the flock-lesson: confirm the terminal write fires on a real `podman stop` vs clean exit
- [ ] 2.3 Bump `.claude-plugin/plugin.json` (skills/`ralph-status` changed); update `CLAUDE.md` (new `loop-lifecycle-state` capability) and `CHANGELOG.md`

## 3. Phase 2 — Spike: resolve viewer placement (design D3)

- [ ] 3.1 Spike D3a (host-side, viewer extracted from the image, host `python3`) vs D3b (in-container, loopback-published) end-to-end on a real loop; decide and record the choice + rationale in `design.md`
- [ ] 3.2 Decide the URL-file location (`.ralph/dashboard.url` vs host cache) and confirm the bundled viewer adds nothing to `.ralph-scaffold.json`

## 4. Phase 2 — The viewer (single-sourced, stdlib-only)

- [ ] 4.1 State-derivation module + failing fixture tests: read `current.json`/`status.jsonl`/`tasks.md`; compute liveness from run-id match AND container-running; fence stale prior-run records; classify paused / terminal-halt / running / killed-inferred
- [ ] 4.2 Commit-Ribbon data: per-turn node (committed vs stall) weighted by diff churn from `git show --numstat <sha>` computed host-side (tested against a git fixture)
- [ ] 4.3 HTML-escape every agent-authored field (commit subject, `blocked_reason`, log/turn text) on the path into the page — tested with hostile-markup fixtures
- [ ] 4.4 `ThreadingHTTPServer` subclass: `daemon_threads = True`, per-write `BrokenPipe`/`ConnectionReset` handling, periodic heartbeat comment line
- [ ] 4.5 SSE endpoint: on every (re)connect re-derive full state from the files, then stream deltas (no Last-Event-ID); verify a simulated reconnect re-syncs without a gap
- [ ] 4.6 Bind `127.0.0.1:0`, read the OS-assigned port, print one unmissable URL line AND write it to the chosen URL file
- [ ] 4.7 `Host`-header validation (reject non-loopback-bind hosts) + a restrictive CSP header — tested
- [ ] 4.8 Auto-open off by default, `$BROWSER`-respecting when explicitly enabled
- [ ] 4.9 Front-end (stdlib-served static page): Commit-Ribbon centerpiece, X/N task arc, a stakes strip that lights only when live (rate-limit countdown, stall-pressure meter, review-round pips), `live.log` as a collapsible drawer — and NO gate-stage pills
- [ ] 4.10 Self-teardown if the live run-id/container disappears (covers the `kill -9` / orphan case)

## 5. Phase 2 — Launch & teardown wiring

- [ ] 5.1 Add the `RALPH_DASHBOARD` opt-in key (default off; `env > ralph.conf > default`) with startup validation and graceful-skip when host `python3` is absent
- [ ] 5.2 Refactor the `Makefile` `loop` recipe into a single-shell wrapper that launches the viewer (per D3), prints/persists the URL, and traps teardown on loop exit
- [ ] 5.3 Verify the wrapper preserves the loop's `SIGINT → exit 130` stop path (container stays foreground; only the viewer is backgrounded) — explicit regression test
- [ ] 5.4 Scaffold ONLY the Makefile-wrapper delta + `ralph.conf` key (templates + example parity); add just that delta to `.ralph-scaffold.json` and `/ralph-upgrade`; confirm the viewer source is not scaffolded

## 6. Phase 2 — Verification

- [ ] 6.1 Viewer pure-logic unit tests pass (state derivation, liveness, ribbon, escaping); server plumbing covered structurally/smoke
- [ ] 6.2 Security checks pass: escaping renders hostile text inert; non-loopback `Host` rejected; CSP present
- [ ] 6.3 Liveness honesty: a paused loop shows "paused, resumes …"; a finished loop shows its halt class; a reused `.ralph/` is not shown as live
- [ ] 6.4 Full `make test` green; spec-conformance checks pass (no new manifest drift)

## 7. Phase 2 — Docs & two-channel release

- [ ] 7.1 `CLAUDE.md`: document the `progress-dashboard` capability, the single-source/no-scaffold rule, the dropped gate-pills rationale, and the two-channel note
- [ ] 7.2 Docs: a dashboard section/recipe (enable, URL, teardown, headless tunnel note) and the copy-paste recipe fallback
- [ ] 7.3 `CHANGELOG.md` entry; bump `.claude-plugin/plugin.json`
- [ ] 7.4 Rebuild the base image (viewer + Phase 1 runner) and verify in-container; regenerate `example/.ralph-scaffold.json` if the Makefile template changed
