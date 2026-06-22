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
2. **Current turn** — `<state_dir>/current.json` (the heartbeat: turn, task,
   model, state, started). If absent, "no heartbeat yet".
3. **Recent turns** — the last ~10 lines of `<state_dir>/status.jsonl`; each line
   is a JSON record with turn, model, exit_code, committed, sha, task. Summarize
   one per line, marking committed turns.
4. **Stop signal** — `STATUS.md`. Treat it as a stop reason **only if it has
   non-whitespace content** (mirror the runner's rule — a blank/whitespace-only
   file is NOT a stop). Show the reason if stopped.
5. **Review gate (only if `RALPH_REVIEW_GATE=1` in `ralph.conf`)** — report it is
   active, and surface any open review feedback: if `review-findings.md` exists and
   is non-empty, the last review found issues the next turn must resolve, so show a
   short summary (the PR number from its header + the finding count). If it is
   absent/empty, the last review was clean. If the gate is off, omit this section.
6. **Recent commits** — `git log --oneline -6`.
7. **Live log** — if `<state_dir>/log/live.log` exists (the aggregate stream;
   present when `RALPH_LIVE_LOG` is not `0`), note its path and that
   `tail -f <state_dir>/log/live.log` follows the loop in realtime. Optionally show
   its last 1–2 lines. If absent, omit this section.

## How to report

Print a compact digest, in this order: running state → current turn → recent
turns (newest last) → STATUS.md stop state → review-gate state (if on) → recent
commits → live-log hint (if present). Keep it scannable
(a few lines each). Don't editorialize; report the facts. If the state dir
doesn't exist yet, say the loop has not run in this repo.

## Guardrails
- Read-only. Never start, stop, or modify the loop or its state.
- A blank or whitespace-only `STATUS.md` is NOT a stop signal — never report it
  as one.
- If you ever present the user with a choice, follow the Ralph recommended-option
  convention: mark one option "(recommended)" first with a one-line, repo-specific
  reason; state the risk and require confirmation for any high-stakes choice.
