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
- **Gate command** — read CI (`.github/workflows/*.yml`) for the lint/type/test
  sequence; otherwise infer from the toolchain (e.g. Python →
  `ruff format . && ruff check . && mypy . && pytest`). This MUST match what CI
  runs, in CI order. Confirm it with the user.
- **Toolchain install** — the exact tools the gate command invokes, as a
  `RUN`/install block for the Containerfile (pin versions where you can read them
  from lockfiles/config).
- **Container image name** — default `<project>-loop` (kebab-case).
- **Runtime** — `podman` (this harness targets podman on Linux).

## 3. Write the files

Resolve the templates and write, in the target repo root. **Never overwrite a
file or directory that already exists** — leave it intact and record it as
*skipped* for the report (see §4).

### 3a. Config

- **`ralph.conf`** — from `ralph.conf.example`, with the inferred values
  (RALPH_CONTAINER=<image>, RALPH_RUNTIME=podman, paths, etc.). This includes the
  **opt-in review-gate keys** (`RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`,
  `RALPH_REVIEW_MAX_ROUNDS`, `RALPH_BASE_BRANCH`, `RALPH_REVIEWER`) — leave them at
  their default OFF/empty values. Do NOT enable the gate; that is the user's call
  (see §3d and the precondition report in §4).
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

### 3d. Review gate (opt-in — scaffold OFF, never enable)

The loop has an optional **outer-loop review gate**: when enabled, the runner
(never the agent) pushes the branch, opens/uses a PR, requests an independent
review (GitHub Copilot by default), and treats *zero findings + green CI* as the
only PASS — writing any findings to `review-findings.md` for the agent to resolve
next turn. The container agent stays GitHub-blind, so this works with any coding
agent. Scaffold the keys (above) but **leave the gate OFF**: it requires a git
remote, an authenticated `gh`, and running on a non-base feature branch — the
offline inner loop stays the zero-config default. Enabling it is the user's
decision; you only report readiness (§4).

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
- Print a **review-gate readiness** report (the gate is scaffolded OFF). Check and
  mark each precondition present/missing: a git remote (`git remote`), an
  authenticated `gh` (`gh auth status`), and the default reviewer (GitHub Copilot
  review available on the repo). Tell the user the gate stays off until they set
  `RALPH_REVIEW_GATE=1` in `ralph.conf` with those met and run the loop on a
  non-base feature branch. Do NOT enable it for them.
- Tell the user the next steps explicitly:
  1. In a clone of `keep-on-ralphing`: `make build-base` (builds `ralph-base:v1`).
  2. In this project: `make build` (also installs the gate hook), then `make login`
     (one-time), then `make loop`.
  3. Confirm the CI workflow's toolchain-setup block matches the Containerfile.
- Offer to run `make build` for them (and `make build-base` if they have the
  keep-on-ralphing repo locally). Do not run `make loop` unattended unless asked.

## Guardrails
- Never write the loop *machinery* (`ralph.sh`, `until_reset.py`) into the target
  repo — it comes from the image. `scripts/gate.sh` is the one exception that is
  NOT machinery: it is project-OWNED config (this project's own gate command),
  analogous to `ralph.conf`. Writing it is correct; vendoring the runner is not.
- The generated config must run headless (no interactive prompt) after the
  one-time `make login`.
- Do not invent a gate command — read it from CI / confirm with the user. A wrong
  gate is the most damaging thing you can scaffold (it is now enforced by a hook
  AND CI, so a wrong gate blocks every commit).
- The CI workflow's `{{TOOLCHAIN_INSTALL}}` is best-effort — CI runner setup can't
  be fully inferred. Always flag it for the user to confirm against the Containerfile.
- Never overwrite existing files/dirs; preserve and report them as skipped.
- Never enable the review gate on the user's behalf — scaffold the keys OFF and
  only report readiness. Turning on `RALPH_REVIEW_GATE`/`RALPH_AUTO_MERGE` (which
  add a remote/`gh`/push dependency and can auto-merge) is always the user's call.
