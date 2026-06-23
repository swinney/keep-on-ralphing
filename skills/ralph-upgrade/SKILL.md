---
name: ralph-upgrade
description: Use to bring a project's ALREADY-scaffolded Ralph config up to the current plugin templates — adds missing pieces (Makefile blocks, ralph.conf keys, PROMPT clauses, new files) while preserving the operator's customizations, always via a shown diff + confirmation. Use after a /plugin update when a project was scaffolded by an older version. Triggers: "upgrade the ralph config", "ralph-upgrade", "update my Makefile/ralph.conf to the latest templates", "my loop refuses to start after updating", "bring this project up to the latest harness".
---

# ralph-upgrade — bring an existing project's config up to the current templates

`/ralph-init` is a first-time scaffolder: it is **no-overwrite**, so it can seed a new project but
**cannot propagate template *changes*** into a project that already has those files. This skill fills that
gap. It compares a consumer's scaffolded config against the current bundled `templates/` and proposes a
**confirm-gated** merge that ADDS what is missing while **preserving the operator's customizations** — it
never overwrites blindly.

Scope boundary, up front:
- This skill upgrades the **in-repo config channel only** (the files `/ralph-init` generates). It does
  **not** touch the runner / base image — that is the base-image channel; if the project is on a superseded
  base, point the operator to **`/ralph-build-base`** (see §6).
- It only reads/writes the **Ralph-owned config set** (below). It never modifies arbitrary repo files.

The Ralph-owned config set (the upgrade targets): `ralph.conf`, `PROMPT.md`, `Makefile`, `Containerfile`,
`scripts/gate.sh`, `hooks/pre-commit`, `.github/workflows/ci.yml`, `STATUS.md`, `docs/questions.md`, the
specs-dir `README.md` guide, and `docs/operator-checklist.md`.

## 0. Locate the current templates

Read the bundled templates the same way `/ralph-init` does — prefer `$CLAUDE_PLUGIN_ROOT/templates/` if set,
else resolve the plugin install path. The fully-resolved `$CLAUDE_PLUGIN_ROOT/example/` is the golden
reference for what a current, fully-upgraded project looks like — use it to sanity-check your merges.

## 1. Confirm the target + read the project's values

Run in the **target project's repo root** (the project to upgrade, NOT this plugin). Confirm the cwd if
ambiguous. Read `ralph.conf` for the project's own values (`RALPH_CONTAINER`, `RALPH_RUNTIME`, the paths,
the project name) — you need these to re-render templates in §3 so substituted placeholders do not read as
spurious changes.

## 2. Decide the upgrade mode (manifest vs feature-detection)

Look for a scaffold provenance manifest at the repo root: **`.ralph-scaffold.json`** (written by a current
`/ralph-init`; format `{ "template_version": "<plugin version>", "files": { "<path>": "<sha256>" } }`).

- **Manifest present** — for each tracked file, compute its current content hash (`sha256sum` /
  `shasum -a 256`) and compare to the recorded hash:
  - **Pristine** (current == recorded → untouched since scaffold): you MAY regenerate it wholesale from the
    current template (re-rendered with the project's values, §3) — there are no customizations to lose, so
    this is the clean, precise path.
  - **Customized** (current != recorded): do NOT regenerate. Upgrade by **inserting only the missing
    blocks** and preserving the operator's edits (feature-detection, §3).
  A literal three-way merge is intentionally NOT attempted: the plugin bundles only the *current* templates,
  not the historical version the project scaffolded from, so the recorded hash (a "did the operator touch
  this?" signal) is what is reconstructable — and sufficient.
- **Manifest absent** (legacy projects — e.g. anything scaffolded before manifests existed, the v0.2→v0.7
  case) — fall back to **feature-detection** for every file: detect whether each known upgrade block is
  present and offer to insert the missing ones.

**Report which mode you used** ("manifest-based" vs "feature-detection") so the operator knows the
confidence level. If the manifest is malformed/partial, treat the affected files as manifest-absent and say
so; a bad manifest never blocks the upgrade.

## 3. Per-file upgrade strategy

For each file in the Ralph-owned config set, **re-render the current template with the project's values
first** (so a substituted `{{PLACEHOLDER}}` does not show as a diff), then:

- **`Makefile` (high-stakes — surface FIRST).** A missing block here can make the loop *refuse to start*,
  so this is the most important file. Detect and offer the known upgrade blocks, inserting any that are
  absent at the correct location, **without** reordering or dropping custom targets/flags:
  - the **`GH_TOKEN` export** (`export GH_TOKEN ?= $(shell gh auth token ...)`) and its **`-e GH_TOKEN`**
    forwarding in `RUN_FLAGS` — the default-on review gate runs `gh` *inside the container* and needs the
    token; without this a review-gated loop refuses to start. State this risk explicitly.
  - the **`check-base`** target and its `loop`/`loop-once` prerequisite (refuses a loop image built on a
    superseded base).
- **`ralph.conf` (low-risk).** Append documented keys the file lacks — **commented / at their built-in
  defaults** — so new knobs become discoverable without changing behavior. Never reorder or rewrite the
  operator's existing values.
- **`PROMPT.md` (medium).** Offer to append missing contract clause-blocks (e.g. the discipline clauses,
  the work-class tag convention) the project lacks; preserve the operator's wording and any custom rules.
- **New files** (e.g. `docs/operator-checklist.md`, the specs-dir guide). Create if absent — the same
  no-overwrite create `/ralph-init` does. Never overwrite an existing one.
- **Generic fallback.** For any other template line/section absent from the project's file, offer it as an
  opt-in hunk (clearly labeled) rather than forcing it.

After a successful upgrade, **refresh `.ralph-scaffold.json`** (if present, or offer to create it) so the
recorded hashes match the now-upgraded files and future upgrades stay precise.

## 4. Confirm before writing (never silent, never blind overwrite)

This is a high-stakes skill — a bad `Makefile` merge breaks the loop. So:
- Show the proposed change **per file as a diff** before writing anything.
- Mark the recommended action and, for high-stakes items (the `Makefile`/`GH_TOKEN` change — it can be what
  unblocks a refusing loop), **state the risk** and require explicit confirmation.
- Never apply silently; never replace a customized line in place of merely inserting what is absent. If a
  genuine conflict exists (a customized file whose region the template also changed), surface it for the
  operator to resolve — do not auto-pick.

## 5. Report

Print a compact report: the mode used (manifest vs feature-detection); per file, one of **upgraded** /
**already current** / **skipped (customized — manual review)** / **created**; and any conflicts left for the
operator. End with the base-image note (§6) if relevant.

## 6. Defer runner/base-image upgrades

This skill does **not** rebuild or modify the base image. If you observe the project is on a superseded base
(e.g. via `/ralph-status` freshness or the `check-base` signal), tell the operator to run **`/ralph-build-base`**
(then `make build` in the project) — do not attempt the rebuild here. The two upgrade halves stay separate:
runner = the base image (`/ralph-build-base`), config = this skill.

## Guardrails
- **Confirm-gated, always.** Show a diff and get explicit confirmation before writing; never overwrite a
  customized line, only insert what is missing. Surface real conflicts; never auto-resolve them.
- **Config channel only.** Never rebuild/modify the base image or runner; defer that to `/ralph-build-base`.
  Never read or modify files outside the Ralph-owned config set.
- **`/ralph-init` stays the scaffolder; this skill owns changes.** Do not tell the operator to re-run
  `/ralph-init` to adopt template changes — that is this skill's job (init is no-overwrite and would skip
  them).
- **Re-render placeholders before diffing** so a project's filled-in values are not mistaken for drift.
- If you present the operator a choice, follow the Ralph recommended-option convention: mark one option
  "(recommended)" first with a one-line, repo-specific reason; for high-stakes changes (the `Makefile`)
  state the risk and require confirmation.
