---
name: ralph-init
description: Use to set up the Ralph loop harness in the CURRENT project — scaffolds ralph.conf, PROMPT.md, a thin Containerfile (FROM the ralph base image) and Makefile, and a tasks.md starter, inferring values from the repo. Triggers: "set up the ralph loop", "ralph init", "add the harness to this project".
---

# ralph-init — scaffold the Ralph harness into a project

Your job is to generate the per-project config a project needs to run the Ralph
loop, by filling this plugin's bundled templates with values inferred from the
target repo. The loop **machinery** lives in the `ralph-base` container image, so
you scaffold *config only* — never copy `ralph.sh`/`until_reset.py` into the repo.

## 0. Locate the templates

The templates ship with this plugin. Read them from the plugin directory — prefer
`$CLAUDE_PLUGIN_ROOT/templates/` if that variable is set, otherwise find the
plugin install path and read `templates/` under it:

- `templates/ralph.conf.example`
- `templates/PROMPT.md.template`
- `templates/Containerfile.template`
- `templates/Makefile.template`
- `templates/gate.sh.template`
- `templates/pre-commit.template`
- `templates/ci.yml.template`
- `templates/STATUS.md.seed`
- `templates/questions.md.seed`
- `templates/specs-README.md.template`

The fully-resolved `example/` directory in the same plugin is your golden
reference for what good output looks like.

The plugin also bundles `base/` (the base-image `Containerfile` + the runner
scripts) and the root `Makefile`, so the `ralph-base:v1` image can be built from
`$CLAUDE_PLUGIN_ROOT` without a separate source clone — see §4.

## 1. Confirm the target

Run in the **target project's repo root** (the repo you want the loop to build —
NOT this plugin). Confirm with the user if the cwd is ambiguous. If a `ralph.conf`
or `PROMPT.md` already exists, stop and ask before overwriting.

## 2. Infer the project context (ask only what you can't infer)

Gather these, reading the repo; state each as "inferred X" or ask if unsure:

- **Project name** — from `pyproject.toml [project].name`, `package.json` `name`,
  or the repo directory name.
- **Specs dir** — look for `docs/specs/`, `specs/`, `openspec/`; default `docs/specs`.
- **Tests dir** — look for `tests/`, `test/`; default `tests`.
- **Decisions dir** — look for `docs/decisions/`; default `docs/decisions`.
- **Greenfield vs brownfield** — assess the target with cheap signals: pre-existing
  source beyond the feature being added, an existing test suite of unknown coverage,
  an existing lockfile/CI, or the loop targeting a feature subdir of a larger app
  (e.g. tasks under `openspec/changes/<feature>/`). Little/no prior source →
  greenfield; anything else, or unclear → treat as brownfield. Do NOT run the test
  suite to measure coverage. This assessment drives the coverage-mode recommendation.
- **Gate command** — read CI (`.github/workflows/*.yml`) for the lint/type/test
  sequence; otherwise infer from the toolchain. The gate MUST include a
  test-COVERAGE check with a threshold, not just a test run. This MUST match what CI
  runs, in CI order. **Confirm the gate, the coverage threshold, AND the coverage
  MODE with the user** — a wrong/too-aggressive value, or the wrong mode, blocks
  every commit. Present each as a recommended option with a repo-specific reason (per
  the Guardrails convention); these are high-stakes, so the rationale states the risk
  and you require confirmation rather than silently applying it. For the threshold,
  recommend a starting value that fits the repo (e.g. higher for a scoped pure-logic
  gate than for a global floor). The coverage-MODE choice you present MUST always include patch/scoped
  coverage (gating only the lines/paths a turn changed) as a first-class option — not
  only "global floor vs none". Order the recommended option by the assessment:
    - **Greenfield → recommend a GLOBAL floor**, e.g.
      `ruff format . && ruff check . && mypy . && pytest --cov=<pkg> --cov-fail-under=80`.
    - **Brownfield → recommend PATCH/SCOPED coverage**: coverage limited to the changed
      package/paths — Python `pytest --cov=<new_pkg>`, vitest
      `--coverage.include='<feature-dir>/**' --coverage.thresholds.lines=<N>`, or
      `go test -cover ./<feature-pkg>/...`; true diff-coverage (`diff-cover` vs the base
      branch) is the stricter alternative. **Warn** that a GLOBAL floor on an
      under-covered existing codebase fails the very first commit. Never silently pick a
      global floor the codebase does not already meet; leave the final mode to the user.
- **Toolchain install** — the exact tools the gate command invokes, INCLUDING the
  coverage tool (e.g. `pytest-cov`), as a `RUN`/install block for the Containerfile
  (pin versions where you can read them from lockfiles/config). Add the same
  coverage tool to the CI workflow's toolchain step.
- **Container image name** — default `<project>-loop` (kebab-case).
- **Runtime** — `podman` (this harness targets podman on Linux).

## 3. Write the files

Resolve the templates and write, in the target repo root. **Never overwrite a
file or directory that already exists** — leave it intact and record it as
*skipped* for the report (see §4).

### 3a. Config

- **`ralph.conf`** — from `ralph.conf.example`, with the inferred values
  (RALPH_CONTAINER=<image>, RALPH_RUNTIME=podman, paths, etc.). This includes the
  **review-gate keys** (`RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`,
  `RALPH_REVIEW_MAX_ROUNDS`, `RALPH_BASE_BRANCH`, `RALPH_REVIEWER`). The loop is
  **GitHub-dependent by default**: keep `RALPH_REVIEW_GATE=1` and ensure GitHub is
  ready (§3d). Set it to `0` only if the user explicitly asks for an offline loop
  with no review. (`RALPH_AUTO_MERGE` stays `0` — merging is still the user's call.)
- **`PROMPT.md`** — from `PROMPT.md.template`, filling `{{PROJECT_NAME}}`,
  `{{SPECS_DIR}}`, `{{TESTS_DIR}}`, `{{DECISIONS_DIR}}`. The gate command is NOT a
  PROMPT placeholder — it lives only in `scripts/gate.sh` (below); the prompt just
  references that script. Keep the whole portable contract intact (one task/turn,
  spec→test→implement, run `./scripts/gate.sh` before commit, stop conditions, the
  no-`Co-Authored-By` rule, and the `review-findings.md`-comes-first clause).
- **`Containerfile`** — from `Containerfile.template`: `FROM ralph-base:v1` plus
  the project's toolchain block.
- **`Makefile`** — from `Makefile.template`, with IMAGE/RUNTIME filled. It carries
  the `hooks` target that installs the gate hook (below).
- **`tasks.md`** — only if absent: a starter with a couple of `- [ ] 1.1 ...`
  example tasks and a note to replace them.

### 3b. Gate (single source + enforcement + CI)

- **`scripts/gate.sh`** — from `gate.sh.template`, with `{{GATE_COMMAND}}` filled
  by the inferred gate (in CI order). `chmod +x` it. This is the ONE home of the
  gate command.
- **`hooks/pre-commit`** — from `pre-commit.template`, verbatim (it only execs
  `scripts/gate.sh`). `chmod +x` it. The `Makefile` `hooks` target points git at
  this via `core.hooksPath`.
- **`.github/workflows/ci.yml`** — from `ci.yml.template`, filling
  `{{TOOLCHAIN_INSTALL}}` with the GitHub-runner setup of the gate's tools
  (best-effort; flag it for the user to confirm — see Guardrails).
- **hooks-path conflict guard:** before relying on `core.hooksPath hooks`, check
  the target repo for a pre-existing `core.hooksPath` (`git config --get
  core.hooksPath`) or a populated `.git/hooks` (non-sample hooks). If either
  exists, do NOT silently override — warn the user that `core.hooksPath hooks`
  will supersede their existing hooks and ask them to consolidate into `hooks/`.

### 3c. Project readiness (each only if absent)

- The **specs / tests / decisions directories** (the inferred `SPECS_DIR`,
  `TESTS_DIR`, `DECISIONS_DIR`), each with a `.gitkeep` so the empty dir is tracked.
- **`STATUS.md`** — from `STATUS.md.seed` (a cold-start breadcrumb that is NOT a
  stop reason).
- **`docs/questions.md`** — from `questions.md.seed`.
- A **spec-writing guide** — from `specs-README.md.template` (filling
  `{{PROJECT_NAME}}`), written as `<SPECS_DIR>/README.md`, ONLY if absent. This is
  a GUIDE, not a starter spec: do NOT scaffold a placeholder spec the loop could
  mistake for real requirements (a convincing-but-fake spec makes the loop build
  the wrong thing). If the user can describe the first subsystem in a sentence or
  two, offer to write that as the first REAL spec (`<SPECS_DIR>/<system>.md`);
  otherwise leave the dir with just the guide and let the loop's normal
  spec→test→implement workflow take over.

### 3d. Review gate (ON by default — ensure GitHub during init)

The loop's **outer-loop review gate is ON by default**: after a turn commits, the
runner (never the agent) pushes the branch, opens/uses a PR, requests an
independent review (GitHub Copilot by default), and treats *zero findings + green
CI* as the only PASS — writing any findings to `review-findings.md` for the agent
to resolve next turn. The container agent stays GitHub-blind, so this works with
any coding agent.

Because it is on by default, **this loop is GitHub-dependent**: loop mode refuses
to start without a git remote, an authenticated `gh`, and a non-base feature
branch. So **ensure those during init** — do not leave the user to discover the
refusal at first run:

- Check `git remote` — if none, help the user add one (`git remote add origin
  <url>`); a GitHub remote is required.
- Check `gh auth status` — if unauthenticated, tell the user to run `gh auth
  login` (an interactive step they run on the host).
- Check `gh auth token` returns a value — the runner runs `gh` *inside the
  container*, so the loop forwards a host-derived `GH_TOKEN` (the generated
  `Makefile` does `export GH_TOKEN ?= $(shell gh auth token)` + `-e GH_TOKEN`).
  Host `gh auth status` alone does NOT authenticate the in-container runner; a
  derivable token does. Confirm the generated `Makefile` forwards `GH_TOKEN`.
- Confirm the loop will run on a non-base feature branch (not directly on the
  default branch).
- Report each as ready/blocked (§4). If a precondition cannot be met now, tell the
  user the loop will not start until it is — or, only if they explicitly want an
  offline loop with no review, set `RALPH_REVIEW_GATE=0` in `ralph.conf`.

Then ensure the runtime state is gitignored — append `.ralph/` and
`/review-findings.md` to the repo's `.gitignore` (create it if missing).
`review-findings.md` is machine-written by the review gate, like `.ralph/`, so it
must not be committed.

## 4. Report, then offer to build

- Print a short table of every value, marked **inferred** or **asked**.
- Print a second table of every file/dir written, each marked **created** or
  **skipped (already present)** — covering config (§3a), the gate components
  `scripts/gate.sh` / `hooks/pre-commit` / `.github/workflows/ci.yml` (§3b), and
  the readiness items: specs/tests/decisions dirs, `STATUS.md`, `docs/questions.md`,
  the specs-dir guide and any first spec captured (§3c). If you hit a hooks-path
  conflict, surface the warning here.
- Note the **gating reach**: once `make build`/`loop` sets `core.hooksPath`, the
  gate applies to EVERY commit in the repo — host or container — because
  `.git/config` is shared. Tell the user that host-side committers need the gate's
  toolchain installed locally (or should commit via `make shell`); the gate is
  designed to run where the toolchain lives (the container).
- Print a **GitHub readiness** report — the review gate is ON by default, so the
  loop will REFUSE to start until these are met. Check and mark each
  present/blocked: a git remote (`git remote`), an authenticated `gh` (`gh auth
  status`), and a non-base feature branch. For any that are blocked, give the
  user the exact fix (`git remote add origin <url>`, `gh auth login`, check out a
  feature branch). If they instead want an offline loop with no review, the
  opt-out is `RALPH_REVIEW_GATE=0` in `ralph.conf`.
- Tell the user the next steps explicitly:
  1. Build the base image `ralph-base:v1` from the plugin's **bundled** `base/` —
     no clone needed: `make -C "$CLAUDE_PLUGIN_ROOT" build-base`. The plugin ships
     `base/` and the root `Makefile`, so this builds the same image the source repo
     does (registry-free, host UID/GID-matched). Contributors working from a
     `keep-on-ralphing` checkout can run `make build-base` there instead.
  2. In this project: `make build` (also installs the gate hook), then `make login`
     (one-time), then `make loop`.
  3. Confirm the CI workflow's toolchain-setup block matches the Containerfile.
- Offer to build `ralph-base:v1` for them now from the bundled base —
  `make -C "$CLAUDE_PLUGIN_ROOT" build-base` — and to run `make build` here. If
  `$CLAUDE_PLUGIN_ROOT` is unset, or `make`/the container runtime is missing, say
  which precondition is unmet and fall back to printing the explicit
  `podman build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t
  ralph-base:v1 -f "$CLAUDE_PLUGIN_ROOT/base/Containerfile" "$CLAUDE_PLUGIN_ROOT/base"`
  (or a source-clone build) — never skip the build silently, or the user hits a
  missing-image error at `make loop`. Do not run `make loop` unattended unless asked.
- After a `/plugin update` that touched the runner (`base/`), the base image is
  stale: tell the user to run **`/ralph-build-base`** to rebuild `ralph-base:v1`
  from the freshly-installed bundled `base/`.

## Guardrails
- **Every choice you present gets a recommended option with a repo-specific reason.**
  When you ask the user to choose (coverage mode/threshold, the gate command,
  task/spec wiring, GitHub/offline, …), mark exactly ONE option "(recommended)",
  present it first, and give a one-line rationale tied to THIS repo — not a static
  default (e.g. "recommended for this repo — a global floor would fail the first
  commit on the untested scaffold"). The reason is what lets a non-expert choose
  well; "(recommended)" alone just moves the cursor. Two carve-outs: (1) **recommend
  ≠ pre-decide** — for high-stakes/irreversible choices (gate command, coverage
  threshold/mode, auto-merge, review-gate changes) state the *risk* in the rationale
  and still require explicit confirmation, never silent-accept; (2) where there is no
  safe default, say so plainly rather than fabricate a recommendation. This governs
  presentation only — it changes nothing about the actual defaults below.
- Never write the loop *machinery* (`ralph.sh`, `until_reset.py`) into the target
  repo — it comes from the image. `scripts/gate.sh` is the one exception that is
  NOT machinery: it is project-OWNED config (this project's own gate command),
  analogous to `ralph.conf`. Writing it is correct; vendoring the runner is not.
- Building `ralph-base:v1` from the plugin's bundled `base/` (`$CLAUDE_PLUGIN_ROOT`)
  is **read-only build context**, NOT vendoring: it reads the bundled sources to
  produce the image and copies nothing into the target repo. Do not copy `base/`,
  the base `Containerfile`, or the runner scripts into the consumer — the single
  source stays the plugin's `base/`. Resolve `$CLAUDE_PLUGIN_ROOT` at build time;
  never write a version-pinned plugin cache path into a generated file (the
  per-version cache dir is pruned after an update).
- The generated config must run headless (no interactive prompt) after the
  one-time `make login`.
- Do not invent a gate command — read it from CI / confirm with the user. A wrong
  gate is the most damaging thing you can scaffold (it is now enforced by a hook
  AND CI, so a wrong gate blocks every commit).
- The gate MUST include a coverage threshold, but never set it aggressively by
  fiat — confirm the number AND the mode with the user (a too-high threshold, or a
  global floor on an under-covered brownfield repo, blocks every commit). Always
  offer patch/scoped coverage as a first-class option; recommend it for a brownfield
  target and a global floor for greenfield. Coverage is a SUPPORTING gate: it catches
  lazy/trivial tests, not tests that fake the precondition that matters — the
  independent-review gate and real-artifact verification are what catch that class,
  and the review gate is also the backstop for scoped coverage's blind spot (changes
  outside the scoped path). Say so; don't oversell it.
- The CI workflow's `{{TOOLCHAIN_INSTALL}}` is best-effort — CI runner setup can't
  be fully inferred. Always flag it for the user to confirm against the Containerfile.
- Never overwrite existing files/dirs; preserve and report them as skipped.
- The review gate is ON by default (the loop is GitHub-dependent): ensure the
  GitHub preconditions during init rather than letting the user hit the runtime
  refusal. Only set `RALPH_REVIEW_GATE=0` if the user explicitly asks for an
  offline loop. `RALPH_AUTO_MERGE` stays OFF unless the user opts in — auto-merging
  is a separate, explicit choice.
