## 1. Test harness (write first)

- [x] 1.1 Extend the stub-`claude` test scaffold so a turn can append to `docs/questions.md` (a blocked decision), reusing the existing snippet mechanism
- [x] 1.2 Add `base/tests/test_notify.sh` with a stub `RALPH_NOTIFY_CMD` recorder (writes its `<event> <reason>` args to a file); wire into `base/tests/run.sh` and the CLAUDE.md single-slice list

## 2. Notifier seam (runner)

- [x] 2.1 Resolve `RALPH_NOTIFY_CMD` (default empty = off) honoring `environment > ralph.conf > default`; bash 3.2-safe
- [x] 2.2 At startup, if `RALPH_NOTIFY_CMD` is set, validate it is executable (mirror the `RALPH_REVIEWER` check) and refuse to start otherwise
- [x] 2.3 Add a non-fatal `notify_human <event> <reason>` helper: no-op when unset; else invoke `<cmd> <event> <reason>` under a short `timeout`, ignore its status, surface failures via `narrate` — never change the loop's exit code or flow

## 3. Notify at the needs-human exits (runner)

- [x] 3.1 Call `notify_human review-exhausted "<STATUS.md reason>"` at the review-gate exhausted-rounds halt
- [x] 3.2 Call `notify_human stall "<STATUS.md reason>"` at the `RALPH_MAX_STALLS` halt
- [x] 3.3 Call `notify_human stop "<STATUS.md reason>"` at the agent-wrote-a-stop-reason exit
- [x] 3.4 Pass the one-line reason from `STATUS.md` content (collapse to a single line)

## 4. Blocked-question immediate stop (runner)

- [x] 4.1 Add `RALPH_QUESTIONS` (default `docs/questions.md`); snapshot it at startup exactly like `STATUS.md` (`status_start` analogue)
- [x] 4.2 After a turn, if `RALPH_QUESTIONS` changed to a non-whitespace value AND the turn made no commit, stop immediately + `notify_human blocked "<new question summary>"` + exit — ordered AFTER the usage-limit pause and `STATUS.md` check but BEFORE the stall counter, so it is never also counted as a stall
- [x] 4.3 A pre-existing question list (unchanged during the run) must NOT trigger a blocked stop
- [x] 4.4 On a blocked stop, persist the decision into `RALPH_STATE_DIR` (e.g. a `blocked` field in the final `status.jsonl`/`current.json` record) so a later one-shot reader (`/ralph-status`, task 6.4) can report it without re-deriving from `docs/questions.md` — the file alone cannot tell a stale list from a current one

## 5. Tests pass (non-fatal + no-op are the critical cases)

- [x] 5.1 Test: each of the 3 halts invokes the notifier with the correct `<event>` and a non-empty reason
- [x] 5.2 Test: a changed `questions.md` triggers an immediate `blocked` stop + notification and is NOT counted toward `RALPH_MAX_STALLS`
- [x] 5.3 Test: a FAILING `RALPH_NOTIFY_CMD` (non-zero / slow) does not change the loop's exit code or flow
- [x] 5.4 Test: unset `RALPH_NOTIFY_CMD` = no notification and byte-identical behavior; pre-existing `questions.md` does not stop a fresh loop

## 6. Config, docs, and skill

- [x] 6.1 Document `RALPH_NOTIFY_CMD` (and `RALPH_QUESTIONS`) in `templates/ralph.conf.example`, default off/`docs/questions.md`; keep `example/` in sync
- [x] 6.2 Add `docs/recipes/slack-notify.md`: a `curl`-to-incoming-webhook script (secret in `SLACK_WEBHOOK_URL`, not on the command line), wired via `RALPH_NOTIFY_CMD`; note the zero-dep `gh pr comment` alternative; link from README. Document that the webhook is a **runner-plane secret reachable in the agent's container env (same plane as `GH_TOKEN`)** — agent-blind is behavioral, not env-isolation — so it should carry the same sensitivity as `GH_TOKEN`
- [x] 6.3 Update `CLAUDE.md`: document the notify seam + the NEW duplicated `questions.md` change-detection pair (ralph.sh ↔ ralph-status), alongside the existing `STATUS.md` invariant note
- [x] 6.4 Have `skills/ralph-status/SKILL.md` report whether notifications are configured and surface the blocked-question state — ONLY by reading the runner-persisted signal in `RALPH_STATE_DIR` (see 4.4), never by re-reading `docs/questions.md` directly (a one-shot reader cannot distinguish a stale pre-existing list from a current one)

## 7. Release and validation

- [x] 7.1 `make test` green, including `test_notify.sh`
- [x] 7.2 Two-channel release: bump `.claude-plugin/plugin.json` (from 0.5.0) AND flag the base-image rebuild in the change notes / CLAUDE.md release checklist
- [x] 7.3 `openspec validate outbound-notification --strict` passes
