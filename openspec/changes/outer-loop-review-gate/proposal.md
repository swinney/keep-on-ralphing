## Why

The harness enforces a strong *inner* loop (spec → test → implement → local gate → commit) but ships no
*outer* loop: it never pushes, opens a PR, or obtains an independent review before work is considered done.
The `keep-on-the-borderlands` field log proved this is the highest-value missing piece — an independent
reviewer (Copilot) repeatedly caught the **"wired-wrong but green" class** that tests, types, and lint
structurally cannot (e.g. a field stored as a string but treated as an enum; all 11 tests green, both code
paths broken). The `ralph-framework-v1` distillation graduated *independent review before merge* to a
Layer-1 pillar — "copy verbatim" methodology — yet the kit `/ralph-init` scaffolds none of it. On
borderlands the entire push → PR → review → merge cycle was operated **by hand**.

## What Changes

- Add an **opt-in outer loop** to the runner (`base/scripts/ralph.sh`): after a turn commits, optionally
  push the branch, ensure a PR exists, request an independent review, and wait on the verdict — reusing the
  existing usage-limit **pause/replay** machinery for the asynchronous review wait.
- Keep the container agent **100% GitHub-blind.** All remote interaction (`gh`/git) lives in the runner, so
  the outer loop works regardless of which coding agent runs in the container (Claude Code or otherwise).
  Review findings re-enter the agent's world only through its existing universal interface: a file of tasks.
- **Pass bar = zero findings + green CI** (the framework default), the lowest-common-denominator signal that
  any reviewer can produce. A clean+green result may auto-merge; otherwise findings are written back as
  prioritized agent work.
- **Bound review rounds** (`RALPH_REVIEW_MAX_ROUNDS`): a reviewer that keeps surfacing new findings escalates
  to a human stall (writes `STATUS.md`) instead of looping forever — the outer-loop analogue of `RALPH_MAX_STALLS`.
- **Reviewer as a seam, not a hardcode.** GitHub Copilot review is the v1 default implementation, isolated
  behind one runner step so projects without Copilot can substitute another reviewer later.
- **Review ON by default; auto-merge a separate opt-in:** `RALPH_REVIEW_GATE` defaults to ON — the loop is
  GitHub-dependent, so loop mode refuses to start without a remote + `gh` + a non-base branch.
  `RALPH_AUTO_MERGE` separately (default OFF) enables auto-merging a clean+green PR; merge is never assumed.
  `RALPH_REVIEW_GATE=0` is the explicit offline opt-out.
- Extend `/ralph-init` to scaffold the review-gate surface: the new `ralph.conf` keys (documented, off),
  a machine-written `review-findings.md`, a `PROMPT.md` clause giving findings priority over `tasks.md`, and
  a precondition report (remote present, `gh` authed, reviewer reachable).
- Out of scope (future changes): Layer-2 work-class model dial, the autonomy-precondition framing
  correction, Layer-3 operator checklists, and a coverage gate (tracked separately).

## Capabilities

### New Capabilities
- `review-gate`: the opt-in outer loop — push → ensure-PR → request independent review → poll CI+review
  verdict (pause/replay) → on clean+green optionally auto-merge, else write findings back as prioritized
  agent tasks; bounded review rounds escalate to a human stall; the agent never touches GitHub; the reviewer
  step is a replaceable seam with Copilot-on-GitHub as the default.

### Modified Capabilities
- `project-bootstrap`: `/ralph-init` additionally scaffolds the review-gate config surface — the new
  (default-off) `ralph.conf` keys, the `review-findings.md` sink, the `PROMPT.md` finding-priority clause,
  and a precondition/precheck report — without breaking the zero-config offline default.

## Impact

- **Runner:** `base/scripts/ralph.sh` gains an opt-in outer-loop stage and new preflight checks; adds a
  dependency on `gh` (and a remote/auth) **only when `RALPH_REVIEW_GATE=1`**.
- **Templates:** `templates/ralph.conf.example`, `templates/PROMPT.md.template`; new `review-findings.md`
  seed handling.
- **Plugin:** `skills/ralph-init/SKILL.md` (scaffold + precondition report), `skills/ralph-status` (surface
  PR/review state if present).
- **Tests:** `base/tests/` gains an outer-loop scaffold that stubs `gh` and the reviewer (no network, no real
  PR), mirroring how `test_ralph_runner.sh` stubs `claude`.
- **This repo's specs:** new `review-gate` spec; `project-bootstrap` delta.
- **Compatibility:** review is ON by default, so a scaffolded loop now requires GitHub (remote + `gh` + a
  non-base branch) to run — `/ralph-init` ensures this and `RALPH_REVIEW_GATE=0` is the offline opt-out. The
  kit's own inner-loop tests opt out explicitly; the new review-gate suite stubs `gh` (no network).
