## Context

The kit splits work across three channels (in-container `base/`, host-side `skills/`, in-repo data generated
from `templates/`). Upgrades to the first two are already handled: the runner ships in the base image
(`/ralph-build-base` + the freshness guard rebuild it), and skills/templates reach a machine via
`/plugin update`. The **in-repo data channel has no upgrade path** — `/ralph-init` is no-overwrite by
contract, so it can seed a *new* project but cannot carry template *changes* into an existing one.

The motivating failure: a v0.2 consumer's `Makefile` lacks the `GH_TOKEN` forwarding (v0.4.0) and
`check-base` preflight (v0.6.3); after a base rebuild the default-on review gate refuses to start. The
`Makefile` is the host↔container seam where missing changes *break* rather than merely under-configure.

## Goals / Non-Goals

**Goals:**
- A `/ralph-upgrade` skill that brings a consumer's scaffolded config up to the current templates, **adding
  missing pieces while preserving customizations**, always via a shown diff + explicit confirmation.
- Work on **legacy projects with no provenance** (feature-detection) and **better** on projects that carry a
  scaffold manifest (pristine/customized classification).
- Keep `/ralph-init` a pure first-time scaffolder; do not make it overwrite.

**Non-Goals:**
- Upgrading the runner / base image (that is `/ralph-build-base` + freshness — out of scope, only referenced).
- Silent / unattended application — every change is confirm-gated.
- A general-purpose merge tool for arbitrary files — scope is the Ralph-owned config set.
- Editing the spec/test/decisions *content* a project authored (only the scaffolded skeleton/config).

## Decisions

### D1 — `/ralph-upgrade` is a host-side, LLM-driven skill, not a script
Merging config while preserving human customizations is judgment-heavy (which blocks are "the same intent",
where to insert, what not to touch). An LLM skill — like `/ralph-init` and `/ralph-status` — fits; a
mechanical patch tool would mangle customized `Makefile`s. *Why not extend `/ralph-init`:* conflating them
would forfeit init's "can never destroy my tuned config" guarantee. Two skills, one boundary: init seeds,
upgrade changes.

### D2 — Feature-detection is the baseline; the manifest enables pristine-detection
The skill MUST work with no provenance (the entire motivating v0.2→v0.7 population has none): it detects
whether each known upgrade block exists and proposes inserting the missing ones (idempotent — "ensure these
exist"). When a scaffold manifest is present (projects scaffolded at/after this change), the skill uses its
per-file hashes to **classify each file** rather than guess:
- **Pristine** (current file hash == the manifest's recorded hash → untouched since scaffold): safe to
  **regenerate wholesale** from the current template (re-rendered with the project's values), since there are
  no customizations to preserve — a precise, clean upgrade.
- **Customized** (hashes differ): fall back to feature-detection / targeted block insertion that preserves
  the operator's edits.

*Why hashes, not stored original content:* a literal three-way text merge would require the original template
text, but the plugin bundles only the *current* templates, not historical versions — so storing per-file
hashes (and re-rendering the current template) is what is actually reconstructable. The hash buys the
decisive signal — *did the operator touch this file?* — which is what separates a safe wholesale upgrade from
a careful merge. *Why both modes:* feature-detection covers legacy and is safe-but-coarse; the manifest
removes the guesswork going forward without being a prerequisite.

### D3 — Re-render placeholders before comparing
Templates carry `{{PLACEHOLDER}}`s the project filled in. The skill re-renders the current template with the
project's actual values (read from `ralph.conf`: `RALPH_CONTAINER`, `RALPH_RUNTIME`, paths, project name)
before diffing, so substituted lines don't show as spurious changes. This is what lets a diff isolate the
*real* upgrade delta.

### D4 — Per-file strategy, ordered by risk
- **`Makefile` (high-stakes):** feature-detect the known blocks (`GH_TOKEN` export, `-e GH_TOKEN` in
  `RUN_FLAGS`, the `check-base` target + `loop`/`loop-once` prerequisite). Insert missing blocks at the
  correct location; never reorder or drop custom targets/flags. This is the case that *breaks* the loop, so
  it is surfaced first and most explicitly.
- **`ralph.conf` (low-risk):** append documented keys the file lacks, commented / at built-in defaults, so
  behavior is unchanged and the new knobs become discoverable.
- **`PROMPT.md` (medium):** offer to append missing contract clause-blocks; preserve the operator's edits.
- **New files** (`docs/operator-checklist.md`, future seeds): create if absent — the existing no-overwrite
  path, reused.

### D5 — Confirm-gated, never silent; the Makefile change is flagged high-stakes
Following the kit's recommended-option convention, the skill shows the proposed diff per file, marks the
recommended action, states the *risk* for high-stakes items (the `Makefile`/`GH_TOKEN` change can be what
unblocks a refusing loop), and requires explicit confirmation before writing. It never applies blind.

### D6 — Scope boundary: config only, runner deferred
The skill explicitly does NOT rebuild or modify the base image / runner. When it detects the project is on an
old base (via the existing freshness signal), it tells the operator to run `/ralph-build-base` — it does not
try to do it. This keeps the two upgrade halves (runner = image, config = this skill) cleanly separated.

### D7 — The manifest reuses the provenance-stamp pattern; it is TRACKED at the repo root
The base image already uses a content-hash provenance stamp (`base_version.sh`). The scaffold manifest is the
same idea for generated files: `{ "template_version": "<plugin version at scaffold>", "files": { "<path>":
"<sha256-at-generation>" } }`. It is written to **`.ralph-scaffold.json` at the repo root and is TRACKED
(committed)** — *not* inside the gitignored `.ralph/` runtime dir.

*Why tracked, not gitignored:* the kit is team-shared via GitHub, and `/ralph-upgrade` may run on a fresh
clone or a different machine than where `/ralph-init` ran. A manifest under gitignored `.ralph/` would be
absent from every clone, so the precision path (D2) would never fire for the multi-machine workflow it
exists to serve. The manifest is durable provenance *about tracked files*, so it belongs alongside them in
version control — and committing it keeps its recorded hashes matching the committed config. *Why a root
dotfile, not `.ralph/scaffold.json`:* `/ralph-init` gitignores `.ralph/` wholesale, so keeping the manifest
there would require a fragile `!.ralph/scaffold.json` un-ignore exception; a sibling root dotfile keeps the
split clean — `.ralph/` = ephemeral runtime, `.ralph-scaffold.json` = durable provenance. `template_version`
is the human-readable plugin version label; the per-file hashes are the authoritative classifier (D2). The
manifest is advisory: its absence never blocks the skill.

## Risks / Trade-offs

- **A bad `Makefile` merge breaks the loop.** → Confirm-gated diff (D5); feature-detection only *inserts*
  known blocks and never rewrites existing lines; the operator sees and approves the exact change.
- **Feature-detection can miss a non-obvious change** a manifest would catch. → Documented limitation;
  manifest-bearing projects get the precise path (D2); the skill reports which mode it used so the operator
  knows the confidence level.
- **Heavily-customized files.** → The LLM merge preserves customizations and surfaces genuine conflicts for
  the human to resolve rather than auto-picking.
- **Scope creep into a general merge tool.** → Bounded to the Ralph config set (D6); arbitrary files are out.
- **"Docs would be cheaper."** → True for a single delta; the skill earns its keep once installs accumulate
  and the `Makefile` silent-break recurs. CHANGELOG "consumer migration notes" can complement the skill.

## Migration Plan

Additive, host-side only (one-channel/plugin release; no base-image rebuild). `/ralph-init` starts writing
the manifest for new projects; existing projects simply gain `/ralph-upgrade` and are upgraded via
feature-detection. Rollback is dropping the skill; the manifest is inert advisory data.

## Open Questions

- ~~**Manifest location**~~ — RESOLVED (D7): tracked `.ralph-scaffold.json` at the repo root, not gitignored
  `.ralph/scaffold.json` — the kit is team-shared via GitHub, so the manifest must travel with the repo or the
  precision path never fires on a clone.
- **CHANGELOG-driven hints** — should the skill parse a structured "consumer migration notes" section per
  release to drive Makefile/conf insertions, or keep the known-block set encoded in the skill itself?
  Leaning skill-encoded for v1 (no parsing dependency), with CHANGELOG notes as human-facing backup.
- **How far back to support feature-detection** — only the currently-known blocks (GH_TOKEN, check-base, the
  v0.5–0.7 conf keys/clauses), or a general "diff against current template and offer each hunk"? v1: the
  known-block set + a generic "these template lines are absent — add them?" fallback.
