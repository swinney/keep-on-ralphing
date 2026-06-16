## 1. gh in the base image

- [x] 1.1 Add `gh` install to `base/Containerfile` (official apt repo, `signed-by` keyring, key fetched via the already-present `curl`); clean apt lists after
- [x] 1.2 Rebuilt `ralph-base:v1`; `gh version 2.94.0` runs in the image (`make smoke-base` OK)

## 2. Auth provisioning (consumer Makefile)

- [x] 2.1 `templates/Makefile.template`: `export GH_TOKEN ?= $(shell gh auth token 2>/dev/null)` + `-e GH_TOKEN` in RUN_FLAGS (no inline value)
- [x] 2.2 `example/Makefile`: same forwarding (golden reference)
- [x] 2.3 Offline path unaffected — `RALPH_REVIEW_GATE=0` skips the gate block (existing gate=0 test still green); no gh/token needed

## 3. Runner preflight messages

- [x] 3.1 `base/scripts/ralph.sh`: gh-missing message points to rebuilding the base; gh-unauthed message points to forwarding `GH_TOKEN`

## 4. /ralph-init readiness

- [x] 4.1 `skills/ralph-init/SKILL.md` §3d: readiness confirms `gh auth token` returns a value and that the generated `Makefile` forwards `GH_TOKEN`; notes host login alone doesn't authenticate the in-container runner

## 5. Docs

- [x] 5.1 `CLAUDE.md`: only the agent is GitHub-blind; the runner needs gh in-container → gh ships in base, Makefile forwards GH_TOKEN; image contents covered by `make smoke-base`
- [x] 5.2 `README.md`: base-image section lists `gh` + the `GH_TOKEN` forward

## 6. Verification against the built image

- [x] 6.1 Added `make smoke-base` (asserts gh/git/ralph.sh/until_reset.py in `ralph-base:v1`); kept OUT of `make test`
- [x] 6.2 `make test` green (still stubs `gh`, no image needed) — 15/15 review-gate + suites
- [x] 6.3 `openspec validate gh-in-sandbox --strict` passes
- [x] 6.4 Mechanism validated end-to-end here: gh in image + forwarded `GH_TOKEN` → `gh auth status` succeeds in-container (`Logged in … (GH_TOKEN)`). Fork's own full-loop run is the user's step: rebuild `houses-loop` FROM the new base + add the `GH_TOKEN` forward to its 0.3.0-era Makefile
