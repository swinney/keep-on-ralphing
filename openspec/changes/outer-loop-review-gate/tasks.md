## 1. Test harness (write first — drives the runner work)

- [x] 1.1 Add `base/tests/test_review_gate.sh` skeleton that stubs `gh`, the reviewer, and CI verdicts, and drives `ralph.sh` against a git fixture with `RALPH_REVIEW_GATE=1` (no network, no real PR) — mirroring `test_ralph_runner.sh`'s `claude` stub
- [x] 1.2 Wire `test_review_gate.sh` into `base/tests/run.sh` and the CLAUDE.md single-slice command list
- [x] 1.3 Add a stub-`gh` helper that records invocations and replays scripted findings/CI/merge results, so each scenario below can assert exact runner behaviour

## 2. Config, preflight, and opt-in plumbing (runner)

- [x] 2.1 Add `RALPH_REVIEW_GATE`, `RALPH_AUTO_MERGE`, `RALPH_REVIEW_MAX_ROUNDS`, and a base-branch key to `ralph.sh`'s config block, default OFF/safe, honouring `environment > ralph.conf > default`
- [x] 2.2 When `RALPH_REVIEW_GATE=1`, preflight a configured git remote, authenticated `gh`, and a reachable reviewer; refuse to start with a message naming the unmet precondition
- [x] 2.3 Test: gate unset/`0` runs the inner loop with no `gh`/remote/network use; gate `1` with a missing precondition refuses to start

## 3. Reviewer seam and CI status (runner)

- [x] 3.1 Implement an isolated `request_review <pr-ref>` step returning a findings list (empty = clean), with a GitHub Copilot review as the default body
- [x] 3.2 Implement CI-status reading directly from the CI system for the PR head, separate from the reviewer step; never derive CI status from reviewer claims
- [x] 3.3 Test: reviewer step is substitutable (an alternative stub satisfying the contract leaves the rest of the gate unchanged); CI verdict comes only from the CI source

## 4. Publish + verdict + findings stage (runner)

- [x] 4.1 After the existing usage-limit/STATUS checks, add a stage that runs only when the gate is ON and the turn committed: push the branch and ensure one PR vs. the base branch exists (create if absent, reuse if present), withholding agent intent from PR input
- [x] 4.2 Poll for the review+CI verdict using the usage-limit pause/replay approach; a pending verdict must NOT increment the stall counter
- [x] 4.3 Compute PASS iff zero findings AND green CI; on NOT-PASS with findings, write them to `review-findings.md`; on a later PASS for the same PR, clear `review-findings.md`
- [x] 4.4 Test: commit → push + PR + review request; findings → `review-findings.md`; pending verdict ≠ stall; passed re-review clears findings

## 5. Bounded rounds and merge policy (runner)

- [x] 5.1 Track consecutive finding-producing review rounds per PR; on reaching `RALPH_REVIEW_MAX_ROUNDS`, write a stop reason to `STATUS.md` and halt
- [x] 5.2 On PASS: if `RALPH_AUTO_MERGE=1` merge the PR into the base branch, else leave it ready for a human
- [x] 5.3 Test: exhausted rounds halt to `STATUS.md`; auto-merge on merges, auto-merge off parks the PR

## 6. Templates and the PROMPT.md contract

- [x] 6.1 Add the documented, default-off review-gate keys to `templates/ralph.conf.example`
- [x] 6.2 Add a minimal `PROMPT.md.template` clause: resolve outstanding `review-findings.md` entries before the first `tasks.md` task — without diluting one-task-per-turn; keep the placeholder set closed
- [x] 6.3 Decide and implement `review-findings.md` lifecycle (lean: gitignored like `.ralph/`); reflect it in the `.gitignore` handling
- [x] 6.4 Update `example/` (Acme Widgets golden reference) to match the new templates

## 7. /ralph-init scaffolding and readiness report

- [x] 7.1 Extend `skills/ralph-init/SKILL.md` to scaffold the review-gate config surface (keys off by default, `review-findings.md`, the PROMPT clause) under the existing no-overwrite rule
- [x] 7.2 Add a precondition/readiness report: git remote present, `gh` authenticated, default reviewer available — each marked present/missing, with a note that the gate stays off until the user opts in; never enable on the user's behalf
- [x] 7.3 Update `skills/ralph-status/SKILL.md` to surface PR/review state when the gate is active

## 8. Docs and validation

- [x] 8.1 Update `CLAUDE.md` (this repo) and `README.md` to document the opt-in outer loop and the agent-blind/runner-owned principle
- [x] 8.2 Run the full kit suite (`make test`) green, including the new `test_review_gate.sh`
- [x] 8.3 `openspec validate outer-loop-review-gate --strict` passes
