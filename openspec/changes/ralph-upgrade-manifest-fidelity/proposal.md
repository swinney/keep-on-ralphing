## Why

The 0.8.1 manifest-backfill (`ralph-upgrade-refinements`) has a correctness bug surfaced by the first live
re-run. `/ralph-upgrade` writes `.ralph-scaffold.json` recording "a content hash of each Ralph-owned config
file **as it stands after the upgrade**" — which includes the **customized** files it correctly skipped
(`gate.sh`, a project's real `Containerfile`/`ci.yml`).

But the read side classifies a file as **pristine** (= "safe to regenerate wholesale") when
`current hash == recorded hash`. Recording a customized file at its *customized* hash therefore poisons the
manifest: on the **next** `/ralph-upgrade`, that file's `current == recorded` → it is misread as **pristine**
→ the skill proposes **regenerating it into the generic template**, destroying the customization the skill is
specifically built to preserve. It is confirm-gated (the operator sees the diff), so not silent — but the
skill proposing to clobber a real scoped-coverage gate / toolchain file is a data-loss defect.

Root cause: "pristine" is only sound if the recorded hash represents the **template baseline**. The backfill
recorded the file's *actual* content, which for customized files is not the template.

## What Changes

- **Record only template-faithful files in the manifest.** After a confirmed upgrade, `/ralph-upgrade` SHALL
  record a hash **only for files whose post-upgrade content matches the re-rendered current template**
  (genuinely template-faithful — created/regenerated/clean), and SHALL **omit** any file it left customized
  or insert-merged with operator edits (e.g. `gate.sh`, a customized `Containerfile`/`ci.yml`, a `Makefile`
  carrying extra edits). A customized file's hash MUST NOT be recorded as the baseline.
- **A file absent from the manifest is feature-detected, never wholesale-regenerated.** The read side treats
  an un-recorded file the same as the manifest-absent case for that file (insert-only / preserve), so omitted
  customized files stay safe on the next run.

This keeps the clean-regenerate benefit for genuinely untouched files while making it impossible for the
manifest to mark a customized file pristine.

## Capabilities

### Modified Capabilities
- `config-upgrade`: correct the manifest-write requirement — record only template-faithful files (omit
  customized ones), and treat an un-recorded file as feature-detection on read.

## Impact

- **Plugin:** `skills/ralph-upgrade/SKILL.md` (§2 read: un-recorded → feature-detect; §3 write: template-
  faithful only). `.claude-plugin/plugin.json` 0.8.1 → 0.8.2 (bug-fix patch).
- **No runner change** — host-side skill text only; no base-image rebuild.
- **Compatibility:** fixes a latent data-loss path; non-breaking. A manifest already written by 0.8.1 (e.g.
  archi's) over-records customized files — re-running `/ralph-upgrade` under 0.8.2 rewrites it correctly
  (omitting them). Until then the confirm-gate is the backstop (do not accept a proposal to regenerate a
  customized file).
