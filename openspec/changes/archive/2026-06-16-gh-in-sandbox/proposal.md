## Why

The review gate is ON by default, and the runner (`ralph.sh`) — which runs **inside the loop container** —
requires `gh` plus working `gh` auth to push, open the PR, and read the verdict. But the base image never
installs `gh`, and nothing provisions `gh` auth into the container. So a stock `make loop` **refuses to start**:

```
ralph: RALPH_REVIEW_GATE=1 but 'gh' is not on PATH — refusing to start
```

The marquee default-on feature is non-functional out of the box. This was found in a real run on a consumer
fork. The test suite missed it because `test_review_gate.sh` **stubs `gh`** and CI **does not build the image**,
so nothing ever checked that the real container has `gh` — the exact "tests green, real artifact broken" class
the review gate itself exists to catch.

The review-gate spec already says the runner (not the agent) performs all `git`/`gh` work, which means `gh` must
exist where the runner runs — the container. The image was built as if the *whole* container were GitHub-blind;
in fact only the agent is.

## What Changes

- **`base/Containerfile` installs `gh`** (official GitHub CLI apt repo, `signed-by` keyring) — it is generic
  loop machinery the runner needs, like `git`.
- **The consumer `Makefile` provisions `gh` auth** by forwarding a host-derived token into the container:
  `export GH_TOKEN ?= $(shell gh auth token)` + `-e GH_TOKEN` in the run flags. Token-via-env is used because
  keyring-based host auth does not live in `~/.config/gh`, so mounting gh config would not carry auth; `export`
  + `-e GH_TOKEN` (no inline value) keeps the token out of the process argv.
- **The container stays agent-blind:** only the runner uses `gh`/`GH_TOKEN`; the `claude` invocation is
  unchanged. The token lives in the throwaway container's env (the user's own token).
- **`ralph.sh` preflight messages** name `GH_TOKEN` so a present-but-unauthed `gh` points the user at the fix.
- **`/ralph-init` readiness** confirms a *derivable* `GH_TOKEN` (`gh auth token` works), not just host
  `gh auth status`, and that the generated `Makefile` forwards it.
- **A build-smoke check** (`make smoke-base`) verifies the built image actually contains `gh` — since CI cannot
  build the image and the unit suite stubs `gh`, this gap needs a check that runs against the built artifact.

## Capabilities

### Modified Capabilities

- `review-gate`: add that the sandbox image provides the runner's GitHub tooling (`gh`) and the loop provisions
  its auth (`GH_TOKEN`) into the container — the runtime prerequisites for the default-on gate to actually run.
- `project-bootstrap`: the GitHub-readiness step additionally confirms a derivable `GH_TOKEN` and that the
  generated `Makefile` forwards it into the container.

## Impact

- **Base image:** `base/Containerfile` (+`gh`); requires `make build-base` / `/ralph-build-base` rebuild on
  every machine. Image grows by the `gh` package.
- **Templates/example:** `templates/Makefile.template`, `example/Makefile` (GH_TOKEN forwarding).
- **Runner:** `base/scripts/ralph.sh` preflight messages only (no logic change — `gh` honors `GH_TOKEN`).
- **Plugin/docs:** `skills/ralph-init/SKILL.md` readiness; `CLAUDE.md`, `README.md`.
- **Verification:** new `make smoke-base`; `make test` unchanged (still stubs `gh`, runs without the image).
- **Compatibility:** `RALPH_REVIEW_GATE=0` offline loop is unaffected (never needed `gh`). Existing users must
  rebuild the base image to get `gh`.
