## Why

`/ralph-init` is deliberately **no-overwrite**: it scaffolds only missing files and skips everything
that already exists. That makes it safe to re-run but **unable to propagate template *changes*** into an
already-initialized project. So upgrading a consumer across kit versions today is a manual, error-prone
merge — and the kit ships **no migration tooling** for it.

The cost is concrete and already biting. A consumer scaffolded at v0.2 that rebuilds to a current base
image inherits a runner whose default-on review gate now needs `gh` + a forwarded `GH_TOKEN`, but their
v0.2 `Makefile` predates the `GH_TOKEN` forwarding (added v0.4.0) and the `check-base` preflight (added
v0.6.3). The loop then **refuses to start** (`gh is not authenticated`) until the operator hand-merges the
`Makefile` — a silent, surprising break with no guidance. As installs accumulate, this hand-merge becomes
recurring toil, and the `Makefile` (the host↔container seam) is exactly the file where a missed change
breaks the loop rather than merely under-configuring it.

The runner half of "upgrade" is already solved (base-image rebuild + the freshness guard). The **in-repo
config half is the gap.** This change fills it without compromising the property that makes `/ralph-init`
safe.

## What Changes

- **New `/ralph-upgrade` skill (host-side, LLM-driven).** It compares a project's scaffolded config against
  the current bundled templates and proposes a **confirm-gated** merge that ADDS missing pieces while
  preserving the operator's customizations — never a silent overwrite. `/ralph-init` stays a pure
  first-time scaffolder (no-overwrite); `/ralph-upgrade` owns *changes*. The two are complementary, not
  overlapping.
- **Per file-type strategy** across the in-repo data channel, by difficulty:
  - **`Makefile`** (the hard, load-bearing case): **feature-detect + targeted block insertion** — detect
    whether known upgrade blocks are present (`GH_TOKEN` export + `-e GH_TOKEN` in `RUN_FLAGS`, the
    `check-base` target + its `loop`/`loop-once` prerequisite) and inject the missing ones at the right
    place, preserving custom targets/flags. Placeholders are re-rendered from `ralph.conf`
    (`RALPH_CONTAINER`/`RALPH_RUNTIME`) before comparison so unchanged lines don't read as diffs.
  - **`ralph.conf`**: append documented-but-missing keys (commented / at their built-in defaults), so new
    knobs become discoverable without changing behavior.
  - **`PROMPT.md`**: offer to append new contract clause-blocks (e.g. discipline clauses, the work-class
    tag convention) the project lacks.
  - **New files** (e.g. `docs/operator-checklist.md`): create if absent — the existing no-overwrite path.
- **Scaffold provenance manifest (precision upgrade).** `/ralph-init` writes a small **tracked** manifest
  (`.ralph-scaffold.json` at the repo root) recording the template version + a content hash per generated file
  at generation time. When present, `/ralph-upgrade` uses the hashes to classify each file as **pristine**
  (untouched → safe to regenerate wholesale from the current template) or **customized** (→ preserve edits,
  insert only missing blocks) instead of pure heuristics. When absent (legacy projects — the v0.2→v0.7 case),
  `/ralph-upgrade` **falls back to feature-detection**, so it works on projects scaffolded before this change.
  It is tracked, not gitignored, because the kit is team-shared via GitHub and the manifest must travel with
  the repo to be useful on a clone.
- **Strictly bounded scope.** `/ralph-upgrade` never touches the runner/loop machinery (that is the base
  image — it points the operator to `/ralph-build-base`), never auto-applies without showing a diff and
  getting confirmation, and never edits non-Ralph files.

## Capabilities

### New Capabilities
- `config-upgrade`: a host-side `/ralph-upgrade` skill that detects drift between a consumer's scaffolded
  config and the current templates and proposes a confirm-gated, customization-preserving merge that adds
  missing config (Makefile blocks, conf keys, PROMPT clauses, new files) — using a tracked scaffold manifest
  to classify files as pristine/customized when provenance exists and a feature-detection fallback when it
  does not, and which defers all runner/base-image upgrades to `/ralph-build-base`.

### Modified Capabilities
- `project-bootstrap`: `/ralph-init` additionally writes a **scaffold provenance manifest** (template
  version + per-file content hash) at generation, and the init/upgrade boundary is made explicit — init
  remains no-overwrite (first-time scaffolding only); propagating template *changes* is `/ralph-upgrade`'s
  job, not init's.

## Impact

- **Plugin:** new `skills/ralph-upgrade/SKILL.md`; `skills/ralph-init/SKILL.md` gains manifest-writing and a
  pointer to `/ralph-upgrade` for upgrades. `.claude-plugin/plugin.json` lists the new skill (version bump).
- **Templates/example:** the scaffold manifest format; `example/` gains the manifest so it stays the golden
  reference.
- **Docs:** README documents the upgrade path (`/plugin update` → `/ralph-build-base` → `/ralph-upgrade`);
  CHANGELOG may carry per-release "consumer migration notes" the skill can also key on.
- **No runner change.** This is host-side (skills/templates/docs) only — a one-channel (plugin) release; it
  does not touch `base/scripts/` and needs no base-image rebuild.
- **Compatibility:** additive and non-breaking. Existing projects gain an opt-in upgrade path; the manifest
  is absent on legacy projects and the skill degrades to feature-detection; nothing changes until the
  operator runs `/ralph-upgrade` and confirms a diff.
