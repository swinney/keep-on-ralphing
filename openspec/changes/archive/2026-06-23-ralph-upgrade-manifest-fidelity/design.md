## Context

Bug fix to the `config-upgrade` manifest semantics shipped in 0.8.1. Host-side skill text only.

## Decisions

### D1 — The manifest records the template baseline, realized as "template-faithful files only"
"Pristine = current == recorded → safe to regenerate wholesale" is sound **only if** the recorded hash is the
template baseline (what a clean scaffold/upgrade-to-template produces). Init satisfies this trivially (the
generated file *is* the template output). The 0.8.1 backfill broke it by recording the file's actual content,
which for customized files diverges from the template.

The fix, evaluated **after the upgrade applies**: record a file's hash only when its post-upgrade content
equals the re-rendered current template (created files, regenerated-pristine files, and insert-merges that
happen to land exactly on the template). **Omit** every file that still differs from the template (customized
or insert-merged-with-extra-edits). Post-upgrade, a template-faithful file's actual hash *is* the template
baseline, so recording the actual hash is correct for exactly those files — and omitting the rest prevents a
customized file from ever being recorded as a baseline.

*Why omit rather than mark-customized:* a file absent from the manifest is already handled as
"manifest-absent for this file" → feature-detection (insert-only, preserve). Omission reuses that safe path
with no schema change. `gate.sh` naturally omits itself forever (its `{{GATE_COMMAND}}` is project-specific,
so it never equals a template baseline) — which is correct: it must never be wholesale-regenerated.

### D2 — Read side: an un-recorded file is feature-detected, never regenerated
`§2` already treats a malformed/partial manifest's affected files as manifest-absent. Make it explicit that a
file *present in the project but absent from the manifest's `files`* is feature-detected for this run — so an
omitted customized file is preserved, not regenerated.

## Risks / Trade-offs
- **A genuinely-untouched file that, post-upgrade, still does not byte-match the template** (e.g. an insert-
  merge that preserved an unrelated operator edit) is omitted and feature-detected next time instead of
  cleanly regenerated. → Correct and safe: it *does* carry an edit, so insert-only is the right treatment;
  the only cost is slightly less precision, never data loss.

## Migration Plan
Additive host-side fix, 0.8.1 → 0.8.2, no base rebuild. A 0.8.1-written manifest is corrected by one re-run
of `/ralph-upgrade` under 0.8.2.
