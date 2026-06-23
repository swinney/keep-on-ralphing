# Changelog

All notable changes to **keep-on-ralphing** (the Ralph loop harness) are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This kit ships through **two independent channels with no shared version**, so a feature
reaching a machine can take two steps:

- **Plugin** (`skills/` + `templates/`) — versioned by `.claude-plugin/plugin.json`; the
  version below is this one. Updated via `/plugin update`.
- **Base image** (`base/`) — versioned by its tag (`ralph-base:v1`), distributed by local
  `make build-base` / `/ralph-build-base`, **not** the marketplace. Entries that change the
  runner (`base/scripts/`) note "**rebuild the base image**" — until you do, the merged
  change is not live on that machine.

Dates are UTC.

## [0.8.2] — 2026-06-23

### Fixed
- **`/ralph-upgrade` manifest now records only template-faithful files.** The 0.8.1 backfill recorded a hash
  for *every* Ralph-owned file post-upgrade — including the **customized** ones it skipped (`scripts/gate.sh`,
  a project's toolchain `Containerfile`/`.github/workflows/ci.yml`). Because "pristine" means
  `current == recorded → safe to regenerate wholesale`, a later upgrade would misread those as pristine and
  propose regenerating them into the generic template — a data-loss-class defect (confirm-gated, so not
  silent). Now the manifest records only files whose post-upgrade content matches the re-rendered current
  template and **omits** customized/insert-merged ones; an un-recorded file is feature-detected (preserved),
  never regenerated. *Existing 0.8.1 manifests: re-run `/ralph-upgrade` once under 0.8.2 to rewrite correctly.*

Host-side only — no base-image rebuild.

## [0.8.1] — 2026-06-23

Refinements from `/ralph-upgrade`'s first live use. Host-side only — no base-image rebuild.

### Changed
- **`/ralph-upgrade` surfaces and writes the scaffold manifest.** Writing/refreshing `.ralph-scaffold.json`
  is now an explicit, approvable plan + report item (was buried), and it is written after a confirmed
  upgrade — including on a legacy no-manifest project, so the *next* run uses the precise manifest path.
- **`ralph.conf` upgrade offers missing commented documentation sections** (e.g. the work-class dispatch
  block), not only missing active keys.
- **The specs-writing guide is skipped when a spec system is present** — `/ralph-upgrade` and `/ralph-init`
  skip it when an `openspec/` directory exists or the specs dir already holds a real spec file (deterministic
  signal, not ad-hoc judgment).

## [0.8.0] — 2026-06-22

Adds an upgrade path for already-installed projects. Host-side only — no runner change, **no
base-image rebuild needed**.

### Added
- **`/ralph-upgrade` skill.** Brings a project's already-scaffolded config up to the current
  templates — a **confirm-gated** merge that ADDS missing pieces (`Makefile` blocks,
  `ralph.conf` keys, `PROMPT.md` clauses, new files) while **preserving your
  customizations**. It fills the gap `/ralph-init` cannot: init is no-overwrite (first-time
  only), so it never carries template *changes* into an existing project — `/ralph-upgrade`
  does. It is config-only and defers base-image upgrades to `/ralph-build-base`. Leads with
  the `Makefile`/`GH_TOKEN` block whose absence makes a review-gated loop refuse to start.
- **Scaffold provenance manifest.** `/ralph-init` now writes a tracked `.ralph-scaffold.json`
  at the repo root (`{ template_version, files: { <path>: <sha256> } }`) so `/ralph-upgrade`
  can classify each file as pristine-since-scaffold (safe to regenerate) vs. customized
  (insert-only). On projects without a manifest (anything scaffolded before 0.8.0),
  `/ralph-upgrade` falls back to feature-detection.

### Changed
- README gains an **"Upgrading an already-installed harness"** section
  (`/plugin update` → `/ralph-build-base` → `/ralph-upgrade`).
- `/ralph-init`'s report now points to `/ralph-upgrade` for adopting template changes (don't
  re-run init). A 5th structural conformance check keeps the example manifest honest.

## [0.7.0] — 2026-06-22

Ports the last two `ralph-framework` layers into the kit: **work-class model dispatch**
(Layer 2) and **operator discipline** (Layer 3). Two enforceable runner wins plus the
methodology, scaffolded for both audiences. Non-breaking — everything is inert until you
opt in. *Runner changed → rebuild the base image.*

### Added
- **Work-class model dispatch (cost dial).** Tag a task in `tasks.md` with a trailing
  work-class token — e.g. `- [ ] 2.3 migrate the session store (stateful)` — and map that
  class to a model in `ralph.conf` via `RALPH_MODEL_<CLASS>` (e.g.
  `RALPH_MODEL_STATEFUL="claude-opus-4-8"`). The runner picks that model for the task's turn
  from turn 1, instead of running one model for everything. Classification is always an
  explicit operator act — **the runner never auto-classifies**. It is a *cost dial, not a
  correctness lever*: the gate and commit-as-truth are untouched, so a misclassified task at
  worst stalls, never ships a bad commit. Untagged tasks use `RALPH_MODEL` exactly as before.
  The dispatched model is recorded per turn in `status.jsonl`.
- **One-orchestrator workspace lock.** The runner takes a `flock` on
  `$RALPH_STATE_DIR/lock` at startup and refuses to start a second concurrent loop on the
  same workspace (competing loops corrupt `.ralph/` and the branch). Because the loop runs
  as PID 1 in its container, the lock uses `flock` rather than a PID file: the kernel
  releases it when the holder dies — including a `podman stop`/SIGKILL/OOM that skips the
  exit handler — so a leftover lock self-heals and the next start reacquires it, instead of a
  stale "PID 1" blocking the loop forever. (Where `flock` is unavailable, outside the
  supported Linux+podman scope, the runner warns and runs without the lock.)
- **Scaffolded operator checklist** (`docs/operator-checklist.md`, written by `/ralph-init`):
  the three pre-action checklists (before backgrounding a job, reproducing a failure, or
  asserting a causal "why" about an external system), the four unattended-autonomy
  preconditions, the velocity-targets-serial-latency guidance, and the "output quality is not
  operator discipline" caution.
- **Agent-facing discipline in the scaffolded `PROMPT.md`**: triage before brute-force
  reproduction, defer to ground truth on external systems, keep scope constraints in the
  prompt, leave no debug scaffolding in commits — plus the work-class tag convention.

### Changed
- `/ralph-status` now surfaces the **model used per turn** and the **workspace-lock state**.
- `/ralph-init` scaffolds the dispatch-table keys **inert** (commented) and adds an autonomy
  note to its report — it never enables unattended assumptions on your behalf.
- Consumer docs reframe **unattended execution as a precondition-gated opt-in** (catalytic
  and narrow-band, not a general accelerator), reaffirm `extras/` fan-out as
  unsupported/net-negative, and direct velocity effort at the human-gate serial latency
  (batch milestones per PR, auto-merge on a clean review) rather than parallelizing the loop.

New config keys: `RALPH_MODEL_<CLASS>` (e.g. `RALPH_MODEL_STATEFUL`, `RALPH_MODEL_PURE`).

## [0.6.3] — 2026-06-22

### Added
- **Base-image freshness ("merged ≠ live" guard).** The base image is stamped with a
  content-derived **provenance hash**, so you can answer "which runner is actually baked into
  this `ralph-base:v1`?" — the mutable tag no longer hides it.
- `/ralph-build-base` is now **freshness-aware and idempotent**: it rebuilds only when the
  baked runner (or the host UID/GID) drifts from the bundled `base/`, otherwise reports
  "already current" and skips. `--force` rebuilds unconditionally.
- `/ralph-status` reports the baked stamp and flags drift; the runner narrates its stamp at
  startup; the consumer `Makefile` `loop`/`loop-once` preflight refuses a loop image built on
  a now-superseded base and tells you to `make build`.

Non-breaking: a legacy unstamped image is reported as "unknown — rebuild recommended", never
an error. *Runner changed → rebuild the base image.*

## [0.6.2] — 2026-06-22

### Fixed
- **Auto-merge failures are no longer swallowed**: with `RALPH_AUTO_MERGE` on, a failed merge
  of a PASSED PR is reported (output + `live.log`) instead of being treated as merged.
- The **SIGINT halt line now reaches `live.log`** (previously stdout only), so an operator
  tailing one stream sees the manual stop alongside every other narration line.
- `/ralph-init`'s readiness report now states whether a `GH_TOKEN` is derivable for the
  in-container runner, catching the review-gate auth prerequisite at setup, not mid-loop.

### Added
- **Self-defense against silent spec-drift**: `make test` now fails (naming the file and
  rule) if any tracked file — even untouched code — violates a universal requirement
  (complete `live.log` narration, single-source gate command, `example/`↔`templates/` config-key
  parity), plus an authoring convention requiring universal-requirement changes to enumerate
  their pre-existing affected sites.

*Runner changed → rebuild the base image.*

## [0.6.1] — 2026-06-22

### Fixed
- The review gate's **disposition and merge-failure lines now route to `live.log`** (not just
  the terminal), so the aggregate stream records the full outer-loop story. *Runner changed →
  rebuild the base image.*

## [0.6.0] — 2026-06-22

### Added
- **Outbound notification — the loop can summon you back.** Set `RALPH_NOTIFY_CMD` to any
  command and the runner calls it as `<cmd> <event> <one-line-reason>` at every needs-human
  halt: `review-exhausted`, `stall`, `stop`, `blocked`. The notifier is yours to choose
  (Slack, a PR comment, any webhook) — the kit ships the seam plus a documented Slack recipe
  (`docs/recipes/slack-notify.md`), never a built-in integration. Validated as executable at
  startup; **non-fatal** by contract (a notifier that errors, hangs, or is slow never changes
  the loop's exit code or flow).
- **A blocked question now stops the loop immediately** (event `blocked`) instead of silently
  burning `RALPH_MAX_STALLS` turns — this fires whether or not a notifier is configured.

New config keys: `RALPH_NOTIFY_CMD`, `RALPH_NOTIFY_TIMEOUT`, `RALPH_QUESTIONS` (relocate the
questions file; default `docs/questions.md`). Off by default; unset = identical prior behavior
aside from the faster blocked-question stop. *Runner changed → rebuild the base image.*

## [0.5.0] — 2026-06-21

### Added
- **Live aggregate log — the loop is now a tail-able log source.** With `RALPH_LIVE_LOG=1`
  (default) the runner writes a single append-only `.ralph/log/live.log` interleaving its
  orchestration narration with each turn's agent output, every line `turn=N`-prefixed and
  ISO-8601 timestamped — one stable `tail -f` target for the whole run. `RALPH_LIVE_LOG=0`
  reproduces the prior behavior exactly; `turn-N.txt`, `status.jsonl`, and `/ralph-status`
  are unchanged.
- A zero-backend **Vector recipe** (`docs/recipes/vector-console.md`) for a realtime console
  view and multi-loop centralization. Stays network-isolated — the kit ships the log source,
  not an aggregator or dashboard, and opens no port.

New config key: `RALPH_LIVE_LOG`. Non-breaking, purely additive. *Runner changed → rebuild
the base image.*

## [0.4.1] — 2026-06-16

### Fixed
- **Review gate now pushes reliably over HTTPS, including from SSH remotes.** Previously an
  SSH remote (`git@github.com:…`) left the in-container runner unable to push (no ssh
  binary/key), so commits never reached the remote and the PR kept reviewing stale code. The
  runner now pushes over HTTPS authenticated with your `GH_TOKEN`, transparently rewriting SSH
  GitHub remotes to HTTPS; a failed push is surfaced (non-fatal — the next turn retries) rather
  than silently swallowed. *Rebuild the base image to get the fix.*

## [0.4.0] — 2026-06-15

### Fixed
- **The default-on review gate now works out of the box.** The sandbox base image ships the
  GitHub CLI (`gh`) as standard runner machinery, and the loop authenticates by forwarding a
  host-derived `GH_TOKEN` into the container at run time (no `gh auth login` inside the
  container, no credential baked into the image; the token stays out of `argv`). Previously a
  stock loop refused to start with "gh is not on PATH", leaving the marquee feature
  non-functional. The container stays agent-blind: only the runner uses `gh`/`GH_TOKEN`.
- `/ralph-init` readiness now confirms a **derivable `GH_TOKEN`** (not just host `gh` login)
  and that the `Makefile` forwards it; a new `make smoke-base` verifies the built image
  actually contains `gh` (CI does not build the image).

*Rebuild the base image and ensure the `Makefile` forwards `GH_TOKEN`.* The
`RALPH_REVIEW_GATE=0` offline path needs neither.

## [0.3.3] — 2026-06-15

### Docs
- Added a **vitest scoped-coverage recipe** (`coverage.all` + provider note) to the coverage
  template, for JS/TS brownfield projects.

## [0.3.2] — 2026-06-15

### Changed
- **Recommended-option convention across all skills.** Every choice a Ralph skill presents
  now marks exactly one option "(recommended)" (shown first) with a one-line rationale tied to
  your actual repo. High-stakes/irreversible choices (gate command, coverage threshold/mode,
  auto-merge, review-gate changes) state the risk and still require explicit confirmation;
  where there is no safe default, the skill says so rather than fabricate one. Presentation
  only — no defaults or behavior change.

## [0.3.1] — 2026-06-15

### Docs
- Documented `/ralph-build-base` everywhere and dropped the stale clone-first build flow.

## [0.3.0] — 2026-06-15

### Added
- **Build the base image straight from the installed plugin — no source clone.** New
  `/ralph-build-base` skill (the third skill) rebuilds `ralph-base:v1` from the plugin's
  bundled `base/` with one command — the intended path after a `/plugin update` that touched
  the runner, keeping runner and plugin in lockstep. Host UID/GID matching is preserved;
  provisioning fails loudly with the unmet precondition (and prints the explicit build command
  + clone fallback) instead of leaving you to hit a missing-image error at loop start.
- **Patch/scoped coverage for brownfield projects.** `/ralph-init` now detects a brownfield
  target and offers patch/scoped coverage (gating only the lines/paths a turn changes) as the
  recommended option — warning that a global floor on an under-covered codebase fails the
  first commit. Greenfield still recommends a global floor; coverage stays mandatory in every
  case.

## [0.2.0] — 2026-06-15

### Added
- **Outer-loop independent review gate** (`RALPH_REVIEW_GATE`, **on by default**). After a
  committing turn the runner pushes the branch, ensures a PR, requests an independent review
  (GitHub Copilot by default; `RALPH_REVIEWER` is the seam), and treats *zero findings + green
  CI* (CI read directly as ground truth) as the only PASS — closing the "wired-wrong but
  green" gap that tests, types, and lint structurally cannot catch. Findings go to
  `review-findings.md` and become the agent's top-priority work next turn; persistent findings
  halt after `RALPH_REVIEW_MAX_ROUNDS`. All GitHub work is the runner's — the container agent
  stays GitHub-blind, so the gate works with any agent. `RALPH_AUTO_MERGE` (separate, off)
  controls whether a PASSED PR merges or is parked for a human.
  **Breaking:** loop mode now requires a git remote, an authenticated `gh`, and a non-base
  branch; `RALPH_REVIEW_GATE=0` is the offline opt-out.
- **Coverage gate.** The single-source gate (`scripts/gate.sh`) now includes a coverage
  threshold run in CI order, so "tests pass" also means "the code is tested." A shortfall
  fails the gate like any other check. `/ralph-init` infers the coverage invocation for your
  stack and confirms the threshold with you. Coverage is framed honestly as a *supporting*
  floor (the review gate catches the faked-precondition class).

New config keys: `RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`, `RALPH_REVIEW_MAX_ROUNDS`,
`RALPH_BASE_BRANCH`, `RALPH_REVIEWER`.

## [0.1.0] — 2026-06-11

### Added
- **Initial release.** The Ralph loop harness: a podman base image baking the runner
  (`ralph.sh`, `until_reset.py`) onto PATH, and a Claude Code plugin (`/ralph-init`,
  `/ralph-status`) that scaffolds a project's config from templates.
- **Enforced quality gate + loop-ready skeleton.** `/ralph-init` scaffolds a single-source
  gate (`scripts/gate.sh`, in CI order: format → lint → type → test), a pre-commit hook that
  blocks red commits, and a CI workflow that runs the same script — so a red gate yields no
  commit, which the loop counts as a stall and halts for review instead of compounding broken
  work. It also seeds the specs/tests/decisions skeleton, a non-stop `STATUS.md` breadcrumb,
  `docs/questions.md`, and a spec-*writing guide* (never a fake placeholder spec). Existing
  files are never overwritten.

[0.8.2]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.8.2
[0.8.1]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.8.1
[0.8.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.8.0
[0.7.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.7.0
[0.6.3]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.6.3
[0.6.2]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.6.2
[0.6.1]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.6.1
[0.6.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.6.0
[0.5.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.5.0
[0.4.1]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.4.1
[0.4.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.4.0
[0.3.3]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.3.3
[0.3.2]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.3.2
[0.3.1]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.3.1
[0.3.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.3.0
[0.2.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.2.0
[0.1.0]: https://github.com/swinney/keep-on-ralphing/releases/tag/v0.1.0
