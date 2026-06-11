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
5. **Recent commits** — `git log --oneline -6`.

## How to report

Print a compact digest, in this order: running state → current turn → recent
turns (newest last) → STATUS.md stop state → recent commits. Keep it scannable
(a few lines each). Don't editorialize; report the facts. If the state dir
doesn't exist yet, say the loop has not run in this repo.

## Guardrails
- Read-only. Never start, stop, or modify the loop or its state.
- A blank or whitespace-only `STATUS.md` is NOT a stop signal — never report it
  as one.
