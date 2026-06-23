## Why

First live use of `/ralph-upgrade` (0.8.0) on a legacy project surfaced three gaps — the skill worked well
(feature-detection correctly preserved customizations, flagged the high-stakes `Makefile`, confirm-gated),
but:

1. **Manifest backfill was invisible.** The upgrade plan listed the file changes but never mentioned writing
   `.ralph-scaffold.json`. The backfill instruction is buried in the skill's per-file section and absent from
   the confirm/report steps — so the operator couldn't see (or approve) that a tracked manifest would be
   created. A legacy project's *first* upgrade is exactly when the manifest must be written: it is what turns
   every *subsequent* run from coarse feature-detection into precise pristine/customized classification. If
   it is not surfaced and written, the skill never graduates out of the weaker mode — the self-improving loop
   the manifest exists for silently never starts.
2. **`ralph.conf` detection only finds missing *active keys*, not missing *commented documentation
   sections*.** The run offered the 4 missing active keys but not the commented work-class dispatch block
   (`# RALPH_MODEL_STATEFUL=...`, added 0.7.0), which carries no active key — so the project's `ralph.conf`
   stayed missing the documented dispatch knobs.
3. **The specs-dir guide skip was luck, not policy.** The skill skipped the generic specs-writing guide
   because the project uses OpenSpec — correct, but by agent judgment, not a codified rule.

## What Changes

- **Surface and write the manifest on upgrade.** `/ralph-upgrade` SHALL include writing/refreshing
  `.ralph-scaffold.json` as an explicit, confirmable item in its plan and report, and SHALL write it after a
  confirmed upgrade — so a legacy project's first run bootstraps the precise manifest path for next time.
- **Offer missing documented sections, not just keys.** `ralph.conf` upgrade SHALL also detect and offer
  commented documentation blocks the current template added (e.g. the work-class dispatch section), not only
  missing active keys.
- **Codify the spec-system skip.** `/ralph-upgrade` (and `/ralph-init`) SHALL skip scaffolding the generic
  specs-dir writing guide when the project already uses a spec system (OpenSpec, etc.), rather than relying on
  ad-hoc judgment.

## Capabilities

### Modified Capabilities
- `config-upgrade`: add the manifest-backfill behavior (write + surface it); broaden `ralph.conf` detection
  to documented sections; codify skipping the specs guide when a spec system is present.

## Impact

- **Plugin:** `skills/ralph-upgrade/SKILL.md` (surface + write the manifest; conf documented-section detection;
  specs-guide skip), a one-line note in `skills/ralph-init/SKILL.md` (specs-guide skip). `.claude-plugin/plugin.json`
  version bump.
- **No runner change** — host-side skill text only; one-channel (plugin) release, **no base-image rebuild**.
  `0.8.0 → 0.8.1` (refinement).
- **Compatibility:** additive and non-breaking; the upgrade skill simply surfaces/writes the manifest and
  catches more gaps. Existing manifests are refreshed, not broken.
