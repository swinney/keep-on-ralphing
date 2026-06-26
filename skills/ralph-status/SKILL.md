---
name: ralph-status
description: Use to report the status of the Ralph loop in the CURRENT project — reads the runtime state files and git, works whether or not a loop is running. Triggers: "ralph status", "how's the loop", "is the loop running", "what did the loop do".
---

# ralph-status — report Ralph loop status

Produce a one-shot digest of the loop's state for the current project. This
replaces the old `ralph-status.sh` shell digest: read the state files and git
directly and report — no script is shipped to the project. Work whether or not a
loop is currently running.

## What to read

Resolve the state dir from `ralph.conf` (`RALPH_STATE_DIR`, default `.ralph`) in
the repo root, then read:

1. **Is a loop container up?** Resolve `RALPH_CONTAINER` (default `ralph-loop`) and
   `RALPH_RUNTIME` (default `podman`) from `ralph.conf`. If that runtime is on
   PATH, run `<runtime> ps --filter name=<container> --format '{{.Names}} {{.Status}}'`.
   If nothing matches (or the runtime is absent), report "not running".
1b. **Base-image freshness** — if the plugin's `base/scripts/base_freshness.sh` is
   resolvable (via `$CLAUDE_PLUGIN_ROOT`) and the runtime is on PATH, run it and
   report the verdict: `current` (the baked `ralph-base:v1` matches the bundled
   `base/` and the host UID/GID) or `stale: <reason>` (rebuild with
   `/ralph-build-base`). Read-only — it never rebuilds. If the helper/runtime is
   unavailable, report "base-image freshness: unknown" and move on; never fail.
1c. **Workspace lock** — read `<state_dir>/lock` (the one-orchestrator `flock`).
   If absent, report "lock: none (no loop holds this workspace)". If present, show
   the recorded PID (informational only) and cross-reference the container-running
   check above: a present lock file **with** a running loop container = the loop
   holds it; a present lock file **without** a running container = a likely **stale
   leftover** from a killed loop (the `flock` is already released by the kernel, so
   the next `ralph.sh` reacquires automatically — flag it, don't act). Do NOT
   `kill -0` the PID and do NOT treat the file's mere presence as "held": the PID is
   the loop's own container-namespace value and `flock`, not the file, is the
   authority — a host-side liveness check is meaningless. Read-only.
2. **Current turn** — `<state_dir>/current.json` (the heartbeat: turn, task,
   model, state, started). If absent, "no heartbeat yet". The heartbeat now carries
   honest lifecycle signals — read and report them:
   - **`run_id`** identifies THIS invocation. When the container-running check (step 1)
     says no loop is up, a `current.json` whose `run_id` belongs to a finished run is
     stale prior-run state — report the loop as ended, not live. (Pair it with the
     terminal `state` below; a live `run_id` with no running container ⇒ the loop was
     **killed** — inferred, since a SIGKILL/OOM leaves no terminal write.)
   - **`state`** is `running`/`idle` mid-loop, or a terminal **halt class** once the
     loop ended: `complete` (project done / clean stop), `blocked`, `review-exhausted`,
     `stall`, or `sigint`. Report the halt class verbatim — never read a terminal state
     as "idle/still working".
   - **`paused`** (object, or absent/null): when set, the loop is waiting, not hung —
     report `paused.reason` (e.g. `usage-limit`) and the resume time from
     `paused.until_epoch` (epoch seconds; render as a local time / countdown).
   - **`stalls`/`max_stalls`** and **`review_round`/`review_max`**: progress-toward-halt
     counters — surface them as `stalls N/max` and (gate on) `review round N/max` so the
     operator sees how close the loop is to giving up.
3. **Recent turns** — the last ~10 lines of `<state_dir>/status.jsonl`; each line
   is a JSON record with turn, model, exit_code, committed, sha, task. Summarize
   one per line, marking committed turns. **Show the `model` per turn** — it is the
   model the runner actually dispatched that turn, which work-class dispatch can
   vary between turns (a `(stateful)`-tagged task may run a stronger model than an
   untagged one), so surfacing it makes the dispatch visible. `"default"` means no
   `--model` was passed (the account default).
4. **Stop signal** — `STATUS.md`. Treat it as a stop reason **only if it has
   non-whitespace content** (mirror the runner's rule — a blank/whitespace-only
   file is NOT a stop). Show the reason if stopped.
5. **Review gate (only if `RALPH_REVIEW_GATE=1` in `ralph.conf`)** — report it is
   active, and surface any open review feedback: if `review-findings.md` exists and
   is non-empty, the last review found issues the next turn must resolve, so show a
   short summary (the PR number from its header + the finding count). If it is
   absent/empty, the last review was clean. If the gate is off, omit this section.
6. **Notifications & blocked state** — report whether outbound notifications are
   configured: `RALPH_NOTIFY_CMD` non-empty in `ralph.conf` → "notifications: on
   (`<cmd>`)", else "notifications: off". Then surface a blocked-question halt
   **only from the persisted signal** in `current.json`: if its `blocked` field is
   `true`, report that the loop is blocked on a question and show `blocked_reason`.
   **Do NOT read `docs/questions.md` (or `RALPH_QUESTIONS`) directly** — a one-shot
   reader cannot tell a stale pre-existing list from one written this run, so the
   runner's `current.json.blocked` is the only trustworthy source. If `blocked` is
   absent/false, say nothing about questions.
7. **Recent commits** — `git log --oneline -6`.
8. **Live log** — if `<state_dir>/log/live.log` exists (the aggregate stream;
   present when `RALPH_LIVE_LOG` is not `0`), note its path and that
   `tail -f <state_dir>/log/live.log` follows the loop in realtime. Optionally show
   its last 1–2 lines. If absent, omit this section.

## How to report

Print a compact digest, in this order: running state → base-image freshness →
workspace lock → current turn (incl. terminal halt class / paused-with-resume /
stall + review counters) → recent turns (newest last, with per-turn model) →
STATUS.md stop state → review-gate state (if on) → notifications + blocked state →
recent commits → live-log hint (if present). Keep it scannable
(a few lines each). Don't editorialize; report the facts. If the state dir
doesn't exist yet, say the loop has not run in this repo.

## Guardrails
- Read-only. Never start, stop, or modify the loop or its state.
- A terminal `state` (`complete`/`blocked`/`review-exhausted`/`stall`/`sigint`) means
  the loop ENDED — never report it as running/idle. `idle` is only between turns.
- A live `run_id` with no running container ⇒ killed (inferred); a finished-run
  `run_id` left in `current.json` is stale — don't present it as the live loop.
- A blank or whitespace-only `STATUS.md` is NOT a stop signal — never report it
  as one.
- Read blocked-question state ONLY from `current.json`'s `blocked` field, never by
  reading `docs/questions.md`/`RALPH_QUESTIONS` — the file alone cannot distinguish
  a stale pre-existing list from one written this run.
- If you ever present the user with a choice, follow the Ralph recommended-option
  convention: mark one option "(recommended)" first with a one-line, repo-specific
  reason; state the risk and require confirmation for any high-stakes choice.
