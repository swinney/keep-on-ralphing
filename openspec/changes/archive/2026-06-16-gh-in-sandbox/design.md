## Context

`ralph.sh` is the loop container's entrypoint (`podman run … ralph.sh`), so the *runner* executes in-container.
The review gate's `git push` / `gh pr` / verdict-read all run there. The base image carries `git` but not `gh`,
and the run flags forward no GitHub credential, so the default-on gate's preflight (`command -v gh`, `gh auth
status`) fails immediately.

## Goals / Non-goals

- **Goal:** a stock default-on loop starts and can push/PR/review without manual container surgery.
- **Goal:** keep the agent GitHub-blind — only the runner touches `gh`.
- **Non-goal:** changing the gate logic, the offline (`=0`) path, or the "runner owns remote interaction"
  principle.
- **Non-goal:** baking a GitHub credential into the image (auth is provided at run time, per-user).

## Decisions

### D1 — `gh` belongs in the base image

`gh` is generic loop machinery the runner needs, exactly like `git` — not project toolchain. So it goes in
`base/Containerfile`, not a consumer layer. Install via the official apt repo with a `signed-by` keyring
(current documented method), fetching the key with `curl` (already in the base; avoids adding `wget`):

```dockerfile
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
```

Latest stable from the repo (not version-pinned) — acceptable for a periodically-rebuilt base; pinning is a
later option if reproducibility demands it.

### D2 — Auth via host-derived `GH_TOKEN`, not a mounted gh config

The host authenticates with the system **keyring**, so `~/.config/gh` holds no token — mounting it would carry
no credential. `gh auth token` extracts the token on the host; forward it into the container as an env var. In
the consumer `Makefile`:

```make
export GH_TOKEN ?= $(shell gh auth token 2>/dev/null)
RUN_FLAGS := … -e GH_TOKEN …
```

`export` puts it in the recipe environment; `-e GH_TOKEN` (no inline value) forwards it without exposing the
token in `ps`/argv. `?=` lets a pre-set `GH_TOKEN` (e.g. CI) win. In-container, `gh` honors `GH_TOKEN`, so
`gh auth status` passes with no `gh auth login` and no logic change in `ralph.sh`.

### D3 — Container stays agent-blind

Only the runner reads `gh`/`GH_TOKEN`; the `claude` invocation is unchanged. The token sits in a throwaway
container's env — the same trust boundary that already makes `--dangerously-skip-permissions` acceptable.

### D4 — Verification must run against the built image

The unit suite stubs `gh` and CI doesn't build the image, so neither can catch "image lacks `gh`." Add a
`make smoke-base` target that builds (or uses) `ralph-base:v1` and asserts `gh`, `git`, and `ralph.sh` are on
PATH. Keep it OUT of `make test` (CI has no image); run it after `build-base`. `log()`/document that `make test`
green does NOT cover image contents.

### D5 — Readiness reflects the token, not just host login

`/ralph-init`'s GitHub-readiness already checks host `gh auth status`; add that `gh auth token` returns a value
(so a token is forwardable) and that the generated `Makefile` forwards `GH_TOKEN`. Host login alone is
insufficient — the *container* needs the token.

## Risks / Trade-offs

- **Token in container env** — accepted (throwaway container, user's own token; same boundary as the agent).
- **Image size + a network apt repo at build time** — minor; the base already apt-installs and npm-installs.
- **No CI coverage of image contents** — inherent (CI doesn't build); mitigated by `make smoke-base` as a
  documented post-build step.

## Migration

Existing users rebuild the base (`/ralph-build-base` or `make build-base`) to get `gh`, and regenerate or
hand-edit their `Makefile` to forward `GH_TOKEN` (one `export` line + `-e GH_TOKEN`). The `RALPH_REVIEW_GATE=0`
offline path is unaffected.
