## 1. Test harness (write first)

- [ ] 1.1 Extend the stub-`claude` test scaffold to capture the `--model` passed per turn, so work-class dispatch is assertable without a real agent
- [ ] 1.2 Add `base/tests/test_work_dispatch.sh` and `base/tests/test_orchestrator_lock.sh`; wire both into `base/tests/run.sh` and the CLAUDE.md single-slice list

## 2. Work-class model dispatch (runner)

- [ ] 2.1 Pin the tasks.md work-class tag syntax against `first_task()`'s parsing (must not collide with `- [ ]`, the `Ralph-Task:` trailer, or the `⛔ MILESTONE GATE` marker); document the chosen token
- [ ] 2.2 Add the class→model dispatch table to `ralph.sh` config (e.g. `RALPH_MODEL_STATEFUL`), bash 3.2-safe, honouring `environment > ralph.conf > default`
- [ ] 2.3 Select the per-turn model from the selected task's work-class tag, falling back to `RALPH_MODEL` when untagged
- [ ] 2.4 Test: a stateful-tagged task gets the mapped model from turn 1; an untagged task uses the default model unchanged

## 3. One-orchestrator workspace lock (runner)

- [ ] 3.1 At startup, acquire a PID lock at `$RALPH_STATE_DIR/lock`; refuse to start if a live PID owns it; reclaim if the recorded PID is dead
- [ ] 3.2 Release the lock on normal exit and via the existing SIGINT trap
- [ ] 3.3 Test: a second concurrent invocation on the same workspace refuses; a stale lock from a dead PID is reclaimed and the loop starts

## 4. Agent-facing discipline (PROMPT.md template)

- [ ] 4.1 Consolidate/add the agent-facing discipline clauses in `templates/PROMPT.md.template`: triage-before-brute-force, defer-to-ground-truth on external systems, constraints-in-prompt, no debug scaffolding in commits — keeping the placeholder set closed and one-task-per-turn intact
- [ ] 4.2 Add the tasks.md work-class tag convention to the rendered prompt's guidance

## 5. Operator-facing methodology (templates + docs)

- [ ] 5.1 Add a new operator-checklist template: the three pre-action checklists (background a job / reproduce a failure / assert a causal why), the four autonomy preconditions, and the output≠discipline caution
- [ ] 5.2 Add the documented dispatch-table keys to `templates/ralph.conf.example` (inert by default)
- [ ] 5.3 Update consumer-facing docs to frame unattended execution as a gated opt-in (catalytic + narrow-band) and velocity as serial-latency-targeting; reinforce `extras/` fan-out as unsupported/net-negative

## 6. /ralph-init and /ralph-status (skills)

- [ ] 6.1 Extend `skills/ralph-init/SKILL.md` to scaffold the dispatch table (inert), the operator checklist doc, and the autonomy-precondition note in its report — under the no-overwrite rule; never enable unattended assumptions for the user
- [ ] 6.2 Update `skills/ralph-status/SKILL.md` to surface the model used per turn (from `status.jsonl`) and the lock state

## 7. Golden reference and docs

- [ ] 7.1 Update `example/` (Acme Widgets) to match the new templates (ralph.conf keys, PROMPT clauses, operator checklist)
- [ ] 7.2 Update `CLAUDE.md` (this repo) and `README.md` to document work-class dispatch, the one-orchestrator lock, and the autonomy/velocity framing

## 8. Validation

- [ ] 8.1 Run the full kit suite (`make test`) green, including the new dispatch + lock tests
- [ ] 8.2 `openspec validate dispatch-and-operator-discipline --strict` passes
