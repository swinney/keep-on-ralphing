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

Resolve the templates and write, in the target repo root:

- **`ralph.conf`** — from `ralph.conf.example`, with the inferred values
  (RALPH_CONTAINER=<image>, RALPH_RUNTIME=podman, paths, etc.).
- **`PROMPT.md`** — from `PROMPT.md.template`, filling `{{PROJECT_NAME}}`,
  `{{SPECS_DIR}}`, `{{TESTS_DIR}}`, `{{DECISIONS_DIR}}`, `{{GATE_COMMAND}}`. Keep
  the whole portable contract intact (one task/turn, spec→test→implement, full
  gate before commit, stop conditions, the no-`Co-Authored-By` rule).
- **`Containerfile`** — from `Containerfile.template`: `FROM ralph-base:v1` plus
  the project's toolchain block.
- **`Makefile`** — from `Makefile.template`, with IMAGE/RUNTIME filled.
- **`tasks.md`** — only if absent: a starter with a couple of `- [ ] 1.1 ...`
  example tasks and a note to replace them.

Then ensure the state dir is gitignored — append `.ralph/` to the repo's
`.gitignore` (create it if missing).

## 4. Report, then offer to build

- Print a short table of every value, marked **inferred** or **asked**.
- Tell the user the next steps explicitly:
  1. In a clone of `keep-on-ralphing`: `make build-base` (builds `ralph-base:v1`).
  2. In this project: `make build`, then `make login` (one-time), then `make loop`.
- Offer to run `make build` for them (and `make build-base` if they have the
  keep-on-ralphing repo locally). Do not run `make loop` unattended unless asked.

## Guardrails
- Scaffold config only — never write `ralph.sh`, `until_reset.py`, or any
  `scripts/` machinery into the target repo (it comes from the image).
- The generated config must run headless (no interactive prompt) after the
  one-time `make login`.
- Do not invent a gate command — read it from CI / confirm with the user. A wrong
  gate is the most damaging thing you can scaffold.
