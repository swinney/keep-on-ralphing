## Context

`/ralph-init` scaffolds config but not enforcement or the structure `PROMPT.md` assumes
(see proposal). The harness has a strong existing principle: **consumer repos carry no
loop machinery** — `ralph.sh`/`until_reset.py` come from the `ralph-base` image, never
vendored. Any new files this change adds to a consumer must be *project-owned config*, not
harness machinery, or they violate that principle.

The loop's progress signal is "did `HEAD` advance this turn?" (`ralph.sh`). The stall
counter and `RALPH_MAX_STALLS` halt depend on a no-progress turn producing no commit. A
gate that blocks bad commits therefore slots into the existing design without touching the
runner — it just changes *which* turns produce a commit.

Constraints: Linux + podman, rootless, `/workspace` bind-mounted (so `.git` is shared
between host and container). Git is the only VCS. `scripts/gate.sh` runs inside the
container where the project toolchain exists.

## Goals / Non-Goals

**Goals:**
- One source of the gate command; PROMPT, hook, and CI all reference it.
- Structural enforcement: a red gate cannot produce a commit, so it becomes a stall.
- A freshly-initialized project is loop-ready: the dirs/files `PROMPT.md` reads all exist.
- No change to `base/` or `ralph.sh`; enforcement rides on a standard git hook.

**Non-Goals:**
- Not a security boundary. `git commit --no-verify` can bypass the hook; this is a
  *quality* gate against an honest agent, not a sandbox escape control (the container is
  the security boundary).
- Not retrofitting already-initialized projects automatically (re-run `/ralph-init` or add
  the files by hand).
- Not perfectly inferring CI runner setup — the toolchain-setup step in the CI workflow is
  a best-effort, clearly-marked block the operator confirms (same posture as the
  Containerfile's `{{TOOLCHAIN_INSTALL}}`).
- Not supporting non-git VCS or multi-arch.

## Decisions

### D1: `scripts/gate.sh` is project-owned config, not harness machinery
The "consumer carries no `scripts/`" rule targets the *loop runner*. The gate command is
inherently project-specific (it encodes that project's formatter/linter/types/tests), so
`scripts/gate.sh` is legitimately owned by the consumer repo — analogous to `ralph.conf`.
It is rendered from a template with the inferred gate, `set -euo pipefail`, commands in CI
order. *Alternative considered:* a Makefile `gate` target instead of a script — rejected
because the git hook and CI both need to call it without assuming `make` is present in
every context, and a plain script is the lowest common denominator.

### D2: Enforce via a tracked `hooks/` dir + `core.hooksPath`, set idempotently by the Makefile
The hook must be (a) active inside the container at commit time, (b) survive a clone, and
(c) be visible/reviewable. Approach: commit a tracked `hooks/pre-commit` that execs
`scripts/gate.sh`, and point git at it with `git config core.hooksPath hooks`. Because
`/workspace/.git/config` is shared between host and container, setting it once on the host
applies in the container. The consumer Makefile gains an idempotent `hooks` target (run
`git config core.hooksPath hooks`) made a prerequisite of `loop`/`loop-once`/`build`, so
no operator step is forgotten and `ralph.sh` stays untouched.

*Alternatives considered:*
- **`.git/hooks/pre-commit` install** — not tracked, doesn't survive clone, clobbers
  existing hooks silently. Rejected.
- **Set `core.hooksPath` in the Containerfile** — `.git` doesn't exist at image build
  time (it's in the runtime bind mount). Rejected.
- **A pre-commit-framework dependency** — adds a third-party tool and config; overkill for
  one hook and against the harness's "avoid dependencies" lean. Rejected.

*Known cost:* `core.hooksPath` overrides *all* of `.git/hooks`. `/ralph-init` must detect
a pre-existing `core.hooksPath` or populated `.git/hooks` and warn rather than silently
override (ties to the project-bootstrap "report/skip" requirement).

### D3: CI workflow runs the same `scripts/gate.sh`
`.github/workflows/ci.yml` (rendered from a template) checks out, runs a marked
toolchain-setup block, then `bash scripts/gate.sh` on push and PR. The gate command itself
is never duplicated — only the *environment setup* differs between the container and the
GitHub runner, which is unavoidable. This satisfies `/ralph-init`'s own guardrail that the
loop gate "MUST match what CI runs."

### D4: `PROMPT.md.template` references the script
The pre-commit step changes from an inlined `{{GATE_COMMAND}}` to "run `./scripts/gate.sh`
(it formats/lints/type-checks/tests in CI order) and fix any failure before committing —
the pre-commit hook will block a red commit; never bypass it with `--no-verify`." The
`{{GATE_COMMAND}}` placeholder moves to `gate.sh.template`, so it still has exactly one
home. The existing "actually FORMAT, not just check" guidance stays.

### D5: Verify enforcement with a kit test
Add `base/tests/test_gate_hook.sh` (wired into `run.sh`), in the style of
`test_ralph_runner.sh`: build a git fixture, install the template hook + a stub
`gate.sh`, attempt a commit while the stub is red (assert: commit aborted, `HEAD`
unchanged) and while green (assert: commit created). This keeps the central claim — "a red
gate yields no commit" — actually tested rather than asserted.

## Risks / Trade-offs

- **Agent bypasses with `--no-verify`** → PROMPT explicitly forbids it; the hook is a
  backstop for honest mistakes, and `--no-verify` in a turn log is an audit signal. Not
  treated as a security control (see Non-Goals).
- **`core.hooksPath` clobbers existing hooks** → `/ralph-init` detects and warns; operator
  consolidates. Documented in the init report.
- **CI toolchain setup can't be fully inferred** → marked, best-effort block confirmed with
  the operator; the gate *command* is still single-source.
- **Gate slowness on every commit** → the loop commits ~once per turn, so the cost is one
  gate run per turn, which the agent should be running anyway. Negligible.
- **`scripts/gate.sh` looks like vendored machinery** → documented (D1) as project-owned
  config; the rule it might seem to break is specifically about the loop *runner*.

## Migration Plan

Forward-only for `/ralph-init`: projects initialized after this change get the gate and
skeleton. Existing projects opt in by re-running `/ralph-init` (which skips files already
present) or copying `scripts/gate.sh`, `hooks/pre-commit`, and the workflow by hand and
running `git config core.hooksPath hooks`. Rollback is `git config --unset core.hooksPath`
plus deleting the added files — no base-image or runner change to revert.

## Resolved Questions

### D6: Gating reach — repo-wide, documented (not extended to a pre-build hook)
Keep `core.hooksPath` set by the Makefile `build`/`loop`/`loop-once` prerequisite;
do NOT have `/ralph-init` set it at scaffold time. Consequence, now documented in
the skill report and the README/CLAUDE gate notes: because `.git/config` is shared
via the bind mount, once it is set the gate applies to *every* commit in the repo —
host or container. Host-side committers therefore need the gate's toolchain locally
(or should commit via `make shell`); the gate is designed to run where the toolchain
lives (the container). We do NOT make the hook skip when tools are absent — a
silent pass is exactly the failure mode the gate exists to prevent. Pre-build
commits stay ungated, which is correct: the image/toolchain may not exist yet.

### D7: Ship a spec-writing GUIDE, not a placeholder seed spec
Replace the placeholder seed spec with `<SPECS_DIR>/README.md` rendered from
`specs-README.md.template` — a guide the loop reads for orientation but never as
requirements. Rationale: a spec is dangerous in proportion to how convincing it
looks, because the loop builds to whatever is in `specs/`. An obviously-empty
placeholder is low-value; a tailored fake is actively harmful (hallucinated
requirements). The guide removes the "first turn builds a toy" failure mode
entirely. Where the operator can describe the first subsystem, `/ralph-init` offers
to write that as the first REAL spec — turning "what should the loop build first?"
into an explicit human decision, which is the on-philosophy answer for a spec-driven
harness. *Alternative considered:* generic placeholder spec — rejected (the
build-a-toy risk); language-tailored spec — rejected (fake requirements are worse
than none).
