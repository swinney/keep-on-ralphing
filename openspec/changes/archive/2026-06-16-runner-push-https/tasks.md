## 1. Runner: authenticated HTTPS push

- [x] 1.1 `base/scripts/ralph.sh` preflight (gate on, after `gh auth`): `gh auth setup-git` + `git config --global url."https://github.com/".insteadOf "git@github.com:"` (idempotent)
- [x] 1.2 `run_review_gate` push no longer `|| true`-silenced — reports `ralph: review-gate could not push …` on failure (non-fatal, retried next turn)

## 2. Tests

- [x] 2.1 `base/tests/test_review_gate.sh` #11: asserts the runner runs `gh auth setup-git` and sets the SSH→HTTPS `insteadOf` rewrite
- [x] 2.2 #12: asserts a failing push is reported (origin pointed at a bogus path), not swallowed — 18/18 review-gate tests green

## 3. Build + docs

- [x] 3.1 Rebuilt `ralph-base:v1` (ralph.sh re-baked); `make smoke-base` OK
- [x] 3.2 `CLAUDE.md`: runner pushes over HTTPS+token, rewrites SSH remotes, surfaces failed pushes

## 4. Verification

- [x] 4.1 In-container dry-run validated manually: SSH-remote fixture pushes after setup (`f96c75b..7e48eb5 … -> ralph-harness-trial`, exit 0)
- [x] 4.2 `make test` green; `openspec validate runner-push-https --strict` passes
- [ ] 4.3 Fork follow-up (user): rebuild `houses-loop`, re-run the loop, confirm new commits reach the PR (remote advances past `f96c75b`) — DEFERRED to the user's fork run
