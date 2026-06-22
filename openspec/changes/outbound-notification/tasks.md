## 1. Test harness (write first)

- [ ] 1.1 Extend the stub-`claude` test scaffold so a turn can append to `docs/questions.md` (a blocked decision), reusing the existing snippet mechanism
- [ ] 1.2 Add `base/tests/test_notify.sh` with a stub `RALPH_NOTIFY_CMD` recorder (writes its `<event> <reason>` args to a file); wire into `base/tests/run.sh` and the CLAUDE.md single-slice list

## 2. Notifier seam (runner)

- [ ] 2.1 Resolve `RALPH_NOTIFY_CMD` (default empty = off) honoring `environment > ralph.conf > default`; bash 3.2-safe
- [ ] 2.2 At startup, if `RALPH_NOTIFY_CMD` is set, validate it is executable (mirror the `RALPH_REVIEWER` check) and refuse to start otherwise
- [ ] 2.3 Add a non-fatal `notify_human <event> <reason>` helper: no-op when unset; else invoke `<cmd> <event> <reason>` under a short `timeout`, ignore its status, surface failures via `narrate` — never change the loop's exit code or flow

## 3. Notify at the needs-human exits (runner)

- [ ] 3.1 Call `notify_human review-exhausted "<STATUS.md reason>"` at the review-gate exhausted-rounds halt
- [ ] 3.2 Call `notify_human stall "<STATUS.md reason>"` at the `RALPH_MAX_STALLS` halt
- [ ] 3.3 Call `notify_human stop "<STATUS.md reason>"` at the agent-wrote-a-stop-reason exit
- [ ] 3.4 Pass the one-line reason from `STATUS.md` content (collapse to a single line)

## 4. Blocked-question immediate stop (runner)

- [ ] 4.1 Add `RALPH_QUESTIONS` (default `docs/questions.md`); snapshot it at startup exactly like `STATUS.md` (`status_start` analogue)
- [ ] 4.2 After a turn, if `RALPH_QUESTIONS` changed to a non-whitespace value AND the turn made no commit, stop immediately + `notify_human blocked "<new question summary>"` + exit — ordered AFTER the usage-limit pause and `STATUS.md` check but BEFORE the stall counter, so it is never also counted as a stall
- [ ] 4.3 A pre-existing question list (unchanged during the run) must NOT trigger a blocked stop

## 5. Tests pass (non-fatal + no-op are the critical cases)

- [ ] 5.1 Test: each of the 3 halts invokes the notifier with the correct `<event>` and a non-empty reason
- [ ] 5.2 Test: a changed `questions.md` triggers an immediate `blocked` stop + notification and is NOT counted toward `RALPH_MAX_STALLS`
- [ ] 5.3 Test: a FAILING `RALPH_NOTIFY_CMD` (non-zero / slow) does not change the loop's exit code or flow
- [ ] 5.4 Test: unset `RALPH_NOTIFY_CMD` = no notification and byte-identical behavior; pre-existing `questions.md` does not stop a fresh loop

## 6. Config, docs, and skill

- [ ] 6.1 Document `RALPH_NOTIFY_CMD` (and `RALPH_QUESTIONS`) in `templates/ralph.conf.example`, default off/`docs/questions.md`; keep `example/` in sync
- [ ] 6.2 Add `docs/recipes/slack-notify.md`: a `curl`-to-incoming-webhook script (secret in `SLACK_WEBHOOK_URL`, not on the command line), wired via `RALPH_NOTIFY_CMD`; note the zero-dep `gh pr comment` alternative; link from README
- [ ] 6.3 Update `CLAUDE.md`: document the notify seam + the NEW duplicated `questions.md` change-detection pair (ralph.sh ↔ ralph-status), alongside the existing `STATUS.md` invariant note
- [ ] 6.4 (Decide per design Open Questions) Optionally have `skills/ralph-status/SKILL.md` report whether notifications are configured and surface a blocked-question state

## 7. Release and validation

- [ ] 7.1 `make test` green, including `test_notify.sh`
- [ ] 7.2 Two-channel release: bump `.claude-plugin/plugin.json` (from 0.5.0) AND flag the base-image rebuild in the change notes / CLAUDE.md release checklist
- [ ] 7.3 `openspec validate outbound-notification --strict` passes
