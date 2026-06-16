## Context

This change ports the two remaining `ralph-framework-v1` layers into the kit. Layer 1 already landed (review
gate, coverage gate). The source specs (`work-dispatch`, `operator-discipline` in `keep-on-the-borderlands`)
are written abstractly ("the framework SHALL…"); this change translates them into concrete kit artifacts:
runner code, templates, the `/ralph-init` skill, and scaffolded operator docs.

The framework itself tags these layers honestly: Layer 2 is *configurable/project-specific* (the classifier is
portable, the dispatch table is per-project) and Layer 3 is *unenforceable methodology*. So most of this change
is scaffolded config + docs; only two pieces are genuinely enforceable runner features. The design names which
is which rather than overclaiming.

`base/scripts/ralph.sh` constraints carry over: agent-agnostic (shells out to the agent, watches git), old-
runtime-safe (bash 3.2; `printf %q`+`eval`; no associative arrays), config precedence `environment > ralph.conf
> default`. `RALPH_MODEL` is currently a single global passed as `claude --model`.

## Goals / Non-Goals

**Goals:**
- Two concrete, enforceable wins: operator-tagged work-class → model dispatch, and a one-orchestrator
  workspace lock.
- Faithfully port the methodology (autonomy preconditions, velocity guidance, operator discipline) as
  scaffolded operator docs + reinforced `PROMPT.md` constraints.
- Stay non-breaking: untagged tasks and single-loop usage behave exactly as today.

**Non-Goals:**
- A per-task interactive *supervision* mode in the runner — supervision stays the operator's `--once`-vs-loop
  choice, guided by docs (the framework's supervision half is an operating decision, not runner machinery).
- A full non-Claude agent-command abstraction — the class→model table is the seam, but v1 wires the existing
  `claude --model` path.
- Auto-classification of work — explicitly forbidden by the framework ("never auto").
- Re-deriving Layer 1 (done) or building fan-out (`extras/` stays unsupported).

## Decisions

### D1 — Work class is operator-tagged in tasks.md; the runner maps class → model
The runner reads an optional work-class tag on the selected task and looks it up in a `ralph.conf` dispatch
table (e.g. `RALPH_MODEL_STATEFUL`), falling back to `RALPH_MODEL` when untagged. *Why:* the framework forbids
auto-classification; tagging keeps the human as classifier while the runner mechanizes dispatch. The tag syntax
must not collide with the existing `- [ ]` checkbox, the `Ralph-Task:` trailer, or the `⛔ MILESTONE GATE`
marker `first_task()` already strips — a trailing `(stateful)`/`(pure)` token is the leading candidate, pinned
in tasks.

### D2 — Model selection stays agent-agnostic behind a class→model string map
The dial maps a work class to a *model string*; v1 passes it via the existing `claude --model` path, but the
table is the indirection point so a future agent-command change substitutes cleanly. No new agent capability is
required and the default (untagged) path is byte-for-byte unchanged.

### D3 — Cost-not-correctness is preserved structurally
Because the gate + commit-as-truth are untouched, a misclassified task can at worst stall (no commit), never
ship a bad commit. The dial therefore needs no correctness safeguards of its own — the convergence machine
already is the safeguard. This is asserted in the spec and verified by leaning on existing stall behavior.

### D4 — One-orchestrator lock: PID lockfile in RALPH_STATE_DIR with stale detection
At startup the runner writes `$RALPH_STATE_DIR/lock` containing its PID; if a live PID already owns it, refuse
to start; if the recorded PID is dead, reclaim. Released on normal exit and via the existing SIGINT trap.
*Why a lock over nothing:* competing loops corrupting shared state was a real field-log failure (§5.15); the
lock is cheap, enforceable, and bash 3.2-safe. *Why PID over flock:* `flock` isn't universally present and the
runner targets portability; a PID file with a liveness check is the lowest-common-denominator.

### D5 — Operator discipline encoded for two audiences
The in-container agent is itself an automated operator (it reproduces failures, theorizes about CI/the
reviewer inside turns), so its discipline goes into `PROMPT.md` as constraints (triage-before-brute-force,
defer-to-ground-truth, constraints-in-prompt, no debug scaffolding — some already present, now consolidated).
The human operator's discipline goes into a scaffolded checklist doc (the three pre-action checklists + four
autonomy preconditions + output≠discipline). Instrumentation substitute (a) already exists as `.ralph/`.

### D6 — Methodology lands as docs, and the change says so
Autonomy framing, velocity guidance, and the output≠discipline caution are documentation requirements, not
code. The proposal and specs label them as such so the change is not mistaken for more enforceable surface than
it has — matching the framework's own self-description of Layers 2–3.

## Risks / Trade-offs

- **Work-class tag adds tasks.md surface that the agent must respect.** → Keep syntax minimal and orthogonal to
  existing markers; default-safe when absent; the dial is opt-in per task.
- **Model dispatch is Claude-coupled in v1.** → Isolated behind the class→model table; documented as the seam;
  acceptable because changing the agent command is out of scope here.
- **PID lock false-positives across containers/hosts sharing a bind-mounted state dir.** → Record enough to
  detect liveness in the same PID namespace; document that the lock guards one workspace within one host/namespace,
  which is the actual failure it targets.
- **Docs-heavy change risks reading as low-value.** → The two runner features are the concrete core; the docs
  port graduated methodology that already earned its keep on N=1 — honestly framed, not padded.
- **Old-runtime compatibility.** → No associative arrays; class→model lookup via `eval`/case, consistent with
  the existing config-snapshot approach.

## Migration Plan

Non-breaking and additive. Untagged tasks use `RALPH_MODEL` exactly as today; the lock only blocks a genuine
second concurrent loop on one workspace (stale locks self-heal). Rollback is removing the dispatch-table keys
(falls back to the single model) and the lock is inert for single-loop use. The offline test suite is
unaffected.

## Open Questions

- **Work-class tag syntax** — trailing `(stateful)`/`(pure)` token vs. a `model:` hint vs. a per-task HTML
  comment. Pin during tasks against `first_task()`'s existing parsing/stripping.
- **Where the operator checklist doc lives** — scaffolded into the consumer repo by `/ralph-init` (per the
  project-bootstrap delta) vs. shipped only as plugin reference docs. Leaning scaffolded, so it travels with the
  project, consistent with `STATUS.md`/`questions.md` seeding.
- **Lock granularity** — workspace-path keyed only, or also state-dir keyed when `RALPH_STATE_DIR` is
  relocated. Resolve in tasks.
