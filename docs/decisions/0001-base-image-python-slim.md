# 0001 — Base image: `python:3.12-slim` (not Alpine, not distroless)

- **Status:** Accepted
- **Date:** 2026-06-11
- **Scope:** `base/Containerfile` (the `ralph-base` sandbox image)

## Context

The `ralph-base` image is built once, locally, registry-free (`make build-base`) and
is never pushed or pulled. Consumers layer their own toolchain on top via
`FROM ralph-base:v1`. The question raised: is there a *more minimal* base than
`python:3.12-slim`, or is the current choice right?

The runner (`base/scripts/ralph.sh` + `until_reset.py`) pins a specific contract the
base image must satisfy:

- **python3** — status emission + `until_reset.py`. **Stdlib only** (`json`, `re`,
  `datetime`); no third-party packages.
- **GNU `stdbuf`** — line-buffers turn output so `tail -f` is live (`ralph.sh:177`).
- **GNU `timeout -k`** — TERM-then-KILL grace window on a hung turn (`ralph.sh:177`).
- **bash** — the runner is bash, not POSIX sh; `make shell`/`make login` need an
  interactive shell.
- **git** — the commit graph is the progress signal.
- **node + npm** — to `npm install -g @anthropic-ai/claude-code`.
- **claude** — the agent, which ships **prebuilt native binaries** (e.g. ripgrep) built
  against **glibc**.

## Decision

Keep `python:3.12-slim`. Do **not** pursue a smaller base for size's sake.

Rationale:

1. **Size is not a real axis here.** The image is built locally and never distributed,
   so a smaller base saves a one-time local-disk increment and nothing else — no pull
   latency, no registry egress, no cold-start cost. The usual motivation for chasing a
   minimal image does not apply.
2. **The minimal options break the runner's contract.**
   - **Alpine** (musl + busybox): busybox `timeout` historically lacks `-k` and has **no
     `stdbuf`** at all — you would `apk add coreutils` and lose most of the size win
     anyway. The dealbreaker is musl: Claude Code's bundled native binaries are built for
     glibc, so musl gambles the whole agent on per-release compatibility.
   - **distroless / scratch**: no shell and no package manager — disqualified by
     `make shell`, `make login`, and the build-time `npm install`.

## The trip-wire (when to revisit)

The one axis on which `python:3.12-slim` is arguably sub-optimal is **Node currency**,
not size. Node comes from Debian's apt (older; e.g. 18.x on bookworm), while the image
always installs the *latest* Claude Code on each rebuild. The day Claude Code's minimum
Node version exceeds Debian's apt Node, the python base breaks.

**If that happens, switch the base to `node:22-slim` (or current LTS) and
`apt-get install python3`** — not to a smaller image. The runner uses only Python's
stdlib, so a stock apt `python3` is sufficient and the language flip costs nothing on the
Python side, while fixing the genuinely fragile dependency (Node).

## Alternatives considered

| Base | Verdict |
|---|---|
| `python:3.12-slim` (current) | **Accepted.** Works; glibc; GNU coreutils builtin. Node from apt is the only soft spot. |
| `node:22-slim` + `apt install python3` | Viable future move — only if the Node floor bites. Inverts the "python is primary" framing. |
| `debian:bookworm-slim` + both | Most neutral, but still apt-old Node; no real win over current. |
| Alpine (musl) | Rejected: breaks `stdbuf`/`timeout -k`, and musl risks Claude Code's native deps. |
| distroless / scratch | Rejected: no shell / package manager; incompatible with `make shell`/`login`/build. |

## Consequences

- The base stays glibc + GNU coreutils, so the runner's `stdbuf`/`timeout -k` usage is
  safe and Claude Code's native binaries run as shipped.
- Node version tracks Debian apt rather than upstream LTS; accepted as a known, monitored
  risk with a documented remediation above.
