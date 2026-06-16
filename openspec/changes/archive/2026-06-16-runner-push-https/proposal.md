## Why

After `gh` + `GH_TOKEN` shipped (0.4.0) the review gate's `gh` API calls work, but the runner still pushes the
branch with a plain `git push` to the consumer's configured remote. When that remote is **SSH**
(`git@github.com:…` — the default for most clones), the push **fails inside the container**: there is no `ssh`
binary, no key, and no git credential helper. The failure is **silently swallowed** by `|| true`, so the loop
proceeds and the PR is created (over HTTPS by `gh pr create`) — but every *subsequent* turn's commits never reach
the remote. The PR goes stale and CI reviews old code.

Observed on the houses fork: local branch at `7e48eb5`, remote stuck at `f96c75b`; in-container
`git push` → `error: cannot run ssh: No such file or directory`. The bug was invisible because the test suite
stubs `gh`/`git` and never pushes to a real SSH remote.

## What Changes

- The runner SHALL push over an **authenticated HTTPS transport derived from `GH_TOKEN`**, regardless of whether
  the consumer's remote is SSH or HTTPS. When the review gate is on, the runner configures git once at startup:
  `gh auth setup-git` (HTTPS credential helper backed by the token) **and** an SSH→HTTPS rewrite
  (`git config --global url."https://github.com/".insteadOf "git@github.com:"`), so `git push` to a
  `git@github.com:` remote transparently goes over HTTPS with the token. (Validated in-container: the dry-run
  push then succeeds.)
- The branch push **SHALL no longer be silently swallowed.** A failed push SHALL be reported with a clear
  `ralph:` message rather than `|| true` hiding it and the gate proceeding on a stale remote.
- No SSH binary/key is added — the token-over-HTTPS path is the supported credential, consistent with 0.4.0.

## Capabilities

### Modified Capabilities

- `review-gate`: the runner pushes over an authenticated HTTPS transport derived from the provisioned token,
  rewriting SSH remotes to HTTPS, and surfaces push failures instead of hiding them.

## Impact

- **Runner:** `base/scripts/ralph.sh` — git auth/rewrite setup in the review-gate preflight; push no longer
  `|| true`-silenced. Requires a **base-image rebuild** (`ralph.sh` is baked in).
- **Tests:** `base/tests/test_review_gate.sh` — add a scenario asserting the runner configures the HTTPS
  rewrite/credential and that a failing push is reported, using the existing `gh`/git stubs.
- **Docs:** `CLAUDE.md` note that the runner pushes over HTTPS+token (SSH remotes are rewritten).
- **Compatibility:** HTTPS-remote consumers are unaffected (the rewrite only matches `git@github.com:`); the
  offline `RALPH_REVIEW_GATE=0` path never pushes. Existing users rebuild the base image to get the fix.
