## Context

Refinements to the `config-upgrade` capability after `/ralph-upgrade`'s first live run. All three are
skill-prompt behaviors (host-side); no runner or template-file change. The skill already *intended* to write
the manifest (it is mentioned in the per-file section) — the fix is to make it a surfaced, confirmable,
reported action, plus two detection-completeness tweaks.

## Decisions

### D1 — Manifest backfill is a first-class, surfaced action (not an apply-time side effect)
The upgrade lists "write/refresh `.ralph-scaffold.json`" in its plan and report, and writes it after a
confirmed upgrade — including (especially) when the project had no manifest. *Why surface it:* it creates a
TRACKED file the operator commits, so it must be visible and approvable, not silent. *Why it matters most on
the first run:* without it the next upgrade stays in feature-detection mode forever; writing it is what
enables the precise pristine/customized path (the manifest's whole purpose). The manifest hashes the files as
they stand *after* the upgrade applies (so "pristine" next time means "unchanged since this upgrade").

### D2 — `ralph.conf` detection covers documented sections, not just active keys
Template additions are sometimes commented documentation blocks with no active key (e.g. the work-class
dispatch table). "Missing active key" detection misses these. The skill also diffs the template's commented
doc sections against the project's `ralph.conf` and offers absent ones (still commented / behavior-neutral).

### D3 — Skip the specs guide when a spec system is present
If the project already uses a recognized spec system (OpenSpec `openspec/`, or an established `specs/` body),
the generic specs-*writing guide* is redundant and confusing. Both `/ralph-init` (create) and `/ralph-upgrade`
(create-if-absent) skip it in that case, instead of relying on agent judgment. Detection is cheap: presence of
`openspec/` or a non-trivial existing specs directory.

## Risks / Trade-offs
- **Refreshing a manifest could mask a hand-edit made between runs.** → The manifest is written only after a
  confirmed upgrade and reflects post-upgrade state; the operator saw and approved the diffs, so the recorded
  hashes match what they accepted. Non-issue.
- **Over-eager specs-guide skip.** → Only skip on a clear spec-system signal; when unsure, fall back to the
  existing create-if-absent behavior.

## Migration Plan
Additive, host-side. No base-image rebuild. `0.8.0 → 0.8.1`.
