## Why

`ralph-framework-v1` (distilled from `keep-on-the-borderlands`) graduated three layers. Layer 1 (the
convergence machine) is now ported into the kit — the review gate is pillar ③ and the coverage gate supports
②′. The remaining two graduated layers are **not** in the kit: **Layer 2 — work-dispatch** (match model tier
and supervision mode to each unit's work class; treat unattended autonomy as a gated opt-in, not the headline)
and **Layer 3 — operator-discipline** (the unenforceable process layer the commit-graph instrument is blind
to). The field log paid for both the hard way: M3 stalled on stateful work run cheap/unattended while M4/M5
ran clean on the same harness (work-class evidence), and M10's fan-out shipped clean commits through heavy
thrash — "resilience masks sloppiness" — because no signal tracked operator discipline.

These layers are honest about their nature: Layer 2 is *configurable/project-specific* and Layer 3 is
*unenforceable methodology*. So this change is **mostly methodology-porting (scaffolded config + operator
docs) plus two concrete, enforceable runner wins.**

## What Changes

- **Work-class model dispatch (concrete).** The runner gains an optional per-task work-class → model map so a
  task the operator marks *stateful* gets the stronger model from turn 1 (avoiding stall-then-escalate waste),
  while unmarked/pure tasks use the default. Operator-tagged, **never auto-classified** (the framework forbids
  "auto"). Default behavior is unchanged when nothing is tagged.
- **One-orchestrator lock (concrete).** The runner takes a workspace lock in `RALPH_STATE_DIR` and refuses to
  start a second concurrent loop on the same workspace (with stale-lock detection) — directly enforcing the
  Layer-3 "one orchestrator at a time" rule that competing loops violated in the field log.
- **Autonomy framing correction (docs/config).** Consumer-facing docs and `/ralph-init` present unattended
  execution as an **opt-in mode gated on four preconditions**, recording the evidence verdict (catalytic +
  narrow-band, not a general accelerator) and reinforcing that `extras/` fan-out is unsupported/net-negative.
- **Operator discipline, encoded for both audiences.** The agent-facing rules (triage-before-brute-force,
  defer-to-ground-truth, constraints-in-prompt, no debug scaffolding) are reinforced in `PROMPT.md`; the
  human-facing rules become a scaffolded operator checklist doc carrying the three pre-action checklists, the
  four autonomy preconditions, and the "output quality ≠ operator discipline" caution.
- **Velocity guidance (docs).** Document that the bottleneck is the human-gate cycle, so velocity effort
  targets serial latency (batch milestones per PR, auto-merge on clean review — already shipped) rather than
  parallelizing the loop.
- Out of scope: changing supervision into a per-task interactive runner mode (it stays the operator's
  `--once`-vs-loop choice, guided by docs); a full non-Claude agent-command abstraction (the class→model
  table is the seam, but v1 wires the existing `claude --model` path).

## Capabilities

### New Capabilities
- `work-dispatch`: operator-tagged work-class → model dispatch in the runner (cost dial, not a correctness
  lever — a misclass at worst stalls, never ships a bad commit), a scaffolded dispatch table, and the
  autonomy-as-gated-opt-in framing + velocity-targets-serial-latency guidance.
- `operator-discipline`: the one-orchestrator workspace lock (enforceable), the agent-facing discipline rules
  in `PROMPT.md`, and the scaffolded human-operator checklist doc (three pre-action checklists + four autonomy
  preconditions + output≠discipline), reusing the existing `.ralph/` instrumentation as substitute (a).

### Modified Capabilities
- `project-bootstrap`: `/ralph-init` additionally scaffolds the work-class dispatch table (off/default-safe in
  `ralph.conf`), the operator checklist doc, and the autonomy-precondition note — under the existing
  no-overwrite rule, without changing the zero-config default.

## Impact

- **Runner:** `base/scripts/ralph.sh` — per-task model selection from a class→model map; a workspace
  lockfile with stale detection. Both additive; bash 3.2-safe; default path unchanged when untagged.
- **Templates:** `templates/ralph.conf.example` (dispatch-table keys), `templates/PROMPT.md.template`
  (work-class tag convention + reinforced discipline clauses), a new operator-checklist template.
- **Plugin:** `skills/ralph-init/SKILL.md` (scaffold the table + checklist + precondition note),
  `skills/ralph-status/SKILL.md` (surface the active model per turn / lock state).
- **Tests:** `base/tests/` — work-class model selection (stub `claude`, assert the model passed per tagged
  task) and the one-orchestrator lock (a second invocation refuses); no network.
- **This repo's specs:** new `work-dispatch` and `operator-discipline`; `project-bootstrap` delta.
- **Compatibility:** non-breaking — untagged tasks use the existing single model; the lock only blocks a
  genuine second concurrent loop; all scaffolding is additive and no-overwrite.
