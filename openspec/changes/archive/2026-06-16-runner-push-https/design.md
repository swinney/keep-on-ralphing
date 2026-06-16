## Context

`run_review_gate` does `git push -u origin "$(working_branch)" … || true`, then `gh pr create`. `gh` uses the
API (HTTPS + `GH_TOKEN`), so PR creation works; but `git push` uses the remote's transport. SSH remotes can't
authenticate in the container (no `ssh`, no key), and the `|| true` hides the failure. The credential we have is
`GH_TOKEN`, which authenticates HTTPS — so the push must go over HTTPS.

## Decisions

### D1 — Push over HTTPS+token; rewrite SSH remotes rather than depending on remote protocol

Two git settings, applied once when the review gate is on:

```sh
gh auth setup-git                                                  # credential.https://github.com.helper = !gh auth git-credential
git config --global url."https://github.com/".insteadOf "git@github.com:"   # SSH remote -> HTTPS transparently
```

`insteadOf` rewrites the SSH URL to HTTPS at push time; `gh auth setup-git` supplies the token-backed credential
for that HTTPS push. This makes `git push` work for both SSH and HTTPS consumer remotes with the one credential
we already provision. Validated: in-container `git push --dry-run` against a `git@github.com:` remote then
succeeds. Writing to the container's `~/.gitconfig` (`--global`) is fine — throwaway container.

### D2 — Run it in the review-gate preflight, idempotently

Place the setup in the existing `RALPH_REVIEW_GATE=1` startup block (right after the `gh auth` check), so it
runs once per loop and only when pushing is actually needed. Both commands are idempotent. Not run on the
offline (`=0`) path.

### D3 — Stop hiding push failures

Replace `git push … || true` with a check that reports a failed push (`ralph: review-gate could not push …`).
A push that doesn't land means the PR can't reflect current code, so it must be visible — silence is what let
the stale-PR bug hide. Keep it non-fatal (the next turn retries), but logged.

### D4 — No SSH binary/key

Adding `openssh-client` wouldn't help (no key to authenticate with), and managing keys in the sandbox is out of
scope. The token-over-HTTPS path is the single supported credential, consistent with the 0.4.0 `GH_TOKEN` model.

## Risks / Trade-offs

- **`--global` git config in-container** — acceptable; the container is per-run and throwaway.
- **`insteadOf` only matches `github.com`** — fine; the harness targets GitHub. Other hosts would need their own
  rewrite, out of scope.
- **Testability** — the suite stubs `gh`/`git` with no real remote, so the test asserts the *configuration*
  (rewrite + credential helper set, push failure surfaced), not a real network push; the real push is validated
  by `make smoke-base`-style manual check, as with the rest of the gh path.

## Migration

Rebuild the base image (`/ralph-build-base` or `make build-base`) to pick up the new `ralph.sh`. HTTPS-remote
consumers see no behavioral change; SSH-remote consumers now push successfully instead of silently failing.
