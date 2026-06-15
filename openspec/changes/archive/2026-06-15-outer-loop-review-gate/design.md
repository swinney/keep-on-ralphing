## Context

`base/scripts/ralph.sh` drives one turn at a time and uses the commit graph as the only progress signal. Its
loop body (`run_turn` + the `while true` controller) already has the three control patterns this change
extends: commit detection (`before`/`after` `head_rev`), a **usage-limit pause/replay** (wait on an external
clock, then replay the same turn without counting a stall), and a stall counter that halts to `STATUS.md`. The
runner is deliberately agent-agnostic — it shells out to the coding agent and watches git — and old-runtime
compatible (bash 3.2, `printf %q`+`eval`).

The `keep-on-the-borderlands` field log and the `ralph-framework-v1` distillation establish *independent review
before merge* as a Layer-1 correctness pillar that the kit does not yet ship: borderlands ran the whole
push → PR → review → merge cycle by hand. This change makes that cycle an opt-in part of the runner.

The decisive constraint, raised explicitly: **the in-container agent may not be Claude Code.** It may lack a
GitHub MCP, `gh` auth, or the ability to wait on async remote state. So the design cannot push GitHub work into
the agent.

## Goals / Non-Goals

**Goals:**
- Add an opt-in outer loop (publish → review → verdict → feedback → optional merge) to `ralph.sh`.
- Keep the container agent 100% GitHub-blind; all remote work is the runner's, via `git`/`gh`.
- Reuse the existing pause/replay and stall machinery rather than inventing new control flow.
- Default-off and offline-preserving: zero new requirements for existing consumers or the test suite.
- Pass bar = zero findings + green CI; reviewer isolated behind one replaceable step.

**Non-Goals:**
- Layer-2 work-class model dial and the autonomy-precondition framing correction (separate change).
- Layer-3 operator checklists (separate change).
- A coverage gate (separate, smaller change).
- Making the *coding agent itself* pluggable (`claude -p` is still hardcoded; orthogonal to this change).
- A full multi-reviewer abstraction — v1 ships the Copilot default behind a seam, not a plugin system.

## Decisions

### D1 — Runner-owned orchestration; the agent only ever sees tasks
All push/PR/review/merge happens in `ralph.sh` using `git`/`gh`. Review findings re-enter the agent through the
one interface every coding agent already has: a file of work to do (`review-findings.md`), made highest-priority
by a `PROMPT.md` clause. *Why over agent-owned:* an arbitrary agent has no guaranteed `gh`/MCP and cannot model
an async review wait inside one synchronous turn; runner-owned is the only option that survives a swapped agent,
and it co-locates GitHub auth in one place. *Why over a pure hybrid split:* "agent resolves findings as tasks"
is already the hybrid — the agent's half is just ordinary task work, requiring no new capability.

### D2 — The outer loop is a stage appended after a committing turn
In the `while true` controller, after the existing usage-limit and STATUS checks, add: *if gate ON and this turn
committed,* run the publish→review→verdict stage. A non-committing turn skips it (nothing new to review). This
keeps the inner loop's "commit = progress" axiom intact and means the outer loop is purely additive.

### D3 — Verdict waiting reuses pause/replay, not a stall
CI and review are asynchronous. The runner polls (bounded) for the verdict using the same approach as the
usage-limit pause: sleep, re-check, do not increment `stalls`. A pending verdict is "waiting on an external
clock," exactly the case pause/replay already models. *Alternative rejected:* treating a pending review as a
stall would trip `RALPH_MAX_STALLS` and halt healthy loops.

### D4 — Pass bar = zero findings + green CI, CI read directly by the runner
Lowest-common-denominator signal any reviewer can emit (a findings list; empty = clean). The runner reads CI
status from the CI system itself, never trusting a reviewer's claim about CI — porting the framework's
"verify the reviewer's external-state claims against ground truth" scenario. *Alternatives rejected:* "APPROVED
review state" and "no high-severity findings" both assume reviewer capabilities an arbitrary reviewer won't
reliably provide.

### D5 — Review ON by default; auto-merge a separate, default-off switch
`RALPH_REVIEW_GATE` defaults to ON: independent review is the highest-value gate (the field log's finding), so
the loop is GitHub-dependent by default and refuses to start without a remote + `gh` + a non-base branch
(`/ralph-init` ensures these; `RALPH_REVIEW_GATE=0` is the offline opt-out). `RALPH_AUTO_MERGE` is separate and
defaults OFF: getting the review and feeding findings back is high-value and low-risk, but auto-merging into a
base branch is not a safe default (branch protection, release branches), so merge control stays explicit.
Config precedence follows the existing `environment > ralph.conf > default` rule (snapshot-and-reapply), so the
new keys need no special handling.

### D6 — Reviewer behind one isolated step; Copilot is the default
"Request review of PR → return findings" is a single shell function with a defined contract (in: PR ref; out:
findings, empty = clean). The v1 body requests a GitHub Copilot review and reads its findings via `gh`. CI
status lives outside this step. This makes a future alternative reviewer a one-function substitution without a
plugin framework now.

### D7 — Findings withhold author intent
The PR the reviewer sees carries the diff and ground-truth repo state but not the agent's reasoning/rationale,
preserving the orthogonality that makes review catch the wired-wrong class (framework rule ③). Concretely: the
runner controls PR creation and does not pipe per-turn agent output into the PR body.

### D8 — Testing mirrors the existing stubbed-`claude` scaffold
A new `base/tests/test_review_gate.sh` stubs `gh` (and the reviewer/CI verdicts) and drives `ralph.sh` against
git fixtures with `RALPH_REVIEW_GATE=1`, asserting: publish-on-commit, findings → `review-findings.md`, pending
verdict ≠ stall, bounded rounds → `STATUS.md`, auto-merge on/off. No network, no real PR — same philosophy as
`test_ralph_runner.sh` stubbing `claude`.

## Risks / Trade-offs

- **Reviewer non-determinism → endless rounds.** A reviewer that surfaces fresh nits every pass never converges.
  → `RALPH_REVIEW_MAX_ROUNDS` bounds it and escalates to a human `STATUS.md` stall (D3/spec).
- **Coverage illusion remains.** Review catches wired-wrong, but the field log's §5.18 "faked precondition" class
  needs end-to-end real-artifact exercise that this change does not add. → Out of scope; documented; future work.
- **`gh`/auth/remote drift in-container.** Auth or remote may be absent in the sandbox. → Fail-fast preflight when
  `RALPH_REVIEW_GATE=1`; default-off means most consumers never hit this.
- **Branch/merge assumptions vary wildly across repos.** → Auto-merge is a separate default-off switch; base branch
  is configurable; default behavior parks the PR for a human.
- **PROMPT.md contract creep.** Adding the finding-priority clause risks diluting the one-task-per-turn focus.
  → Keep the clause minimal and scoped: "resolve `review-findings.md` first, then the first `tasks.md` task."
- **Old-runtime compatibility.** New runner code must stay bash 3.2-safe (no associative arrays), consistent with
  the existing file.

## Migration Plan

Non-breaking and additive. Existing consumers see no change until they set `RALPH_REVIEW_GATE=1`. Rollback is
setting it back to `0` (or removing the keys); the runner stage is skipped entirely when off. The kit's own
offline test suite is unaffected because the default path adds no `gh`/network dependency.

## Open Questions

- **PR granularity vs. branch lifecycle:** does the loop run on one long-lived branch with one evolving PR, or
  rotate branches/PRs per milestone? v1 assumes one branch + one reusable PR per loop run; milestone batching is
  a Layer-2 velocity concern deferred with the work-class dial.
- **Copilot review invocation specifics:** exact `gh`/API surface to request a Copilot review and read findings +
  CI status is to be pinned during implementation against the current GitHub API.
- **Where `review-findings.md` lives** relative to gitignore: committed (audit trail) vs. gitignored (ephemeral).
  Leaning gitignored like `.ralph/`, resolved in tasks.
