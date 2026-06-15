## 1. Gate templates (single source)

- [x] 1.1 Add `templates/gate.sh.template`: `set -euo pipefail` + `{{GATE_COMMAND}}` placeholder, commands in CI order; render target is `scripts/gate.sh` (executable)
- [x] 1.2 Add `templates/pre-commit.template` (the hook): execs `scripts/gate.sh`, aborts the commit on non-zero exit, prints a clear "gate failed — commit blocked" message; render target is `hooks/pre-commit`
- [x] 1.3 Add `templates/ci.yml.template` (GitHub Actions): checkout → marked `{{TOOLCHAIN_INSTALL}}` setup block → `bash scripts/gate.sh`, triggered on push and pull_request; render target is `.github/workflows/ci.yml`

## 2. Prompt + Makefile wiring

- [x] 2.1 Edit `templates/PROMPT.md.template`: replace the inlined `{{GATE_COMMAND}}` pre-commit step with "run `./scripts/gate.sh`" guidance, keep the "actually FORMAT" note, add "never bypass the hook with `--no-verify`"; remove `{{GATE_COMMAND}}` from the placeholder list (it now lives in `gate.sh.template`)
- [x] 2.2 Edit `templates/Makefile.template`: add an idempotent `hooks` target (`git config core.hooksPath hooks`) and make it a prerequisite of `build`, `loop`, and `loop-once`; document it in the `help` block

## 3. Readiness seeds

- [x] 3.1 Add `templates/STATUS.md.seed`: a non-empty cold-start breadcrumb that is NOT a stop reason
- [x] 3.2 Add `templates/questions.md.seed`: short header explaining the escalation file's purpose
- [x] 3.3 Add `templates/specs-README.md.template`: a spec-WRITING guide (not a placeholder spec) for `<SPECS_DIR>/README.md` (see §7)

## 4. Update the /ralph-init skill

- [x] 4.1 Add a "scaffold the gate" step to `skills/ralph-init/SKILL.md`: render `scripts/gate.sh` (chmod +x), `hooks/pre-commit` (chmod +x), and `.github/workflows/ci.yml` from the templates using the inferred gate + toolchain
- [x] 4.2 Add a "scaffold project readiness" step: create the specs/tests/decisions dirs (git-tracked placeholder), seed `STATUS.md`, `docs/questions.md`, and the seed spec — each only if absent
- [x] 4.3 Add the `core.hooksPath` conflict guard: detect a pre-existing `core.hooksPath` or populated `.git/hooks` and warn instead of silently overriding
- [x] 4.4 Extend the init report to list every gate + readiness component as created or skipped; update the "Guardrails" to note `scripts/gate.sh` is project-owned config (not vendored loop machinery)
- [x] 4.5 Update the no-overwrite rule so existing specs/tests/decisions/`STATUS.md`/`questions.md` are preserved and reported as skipped

## 5. Worked example

- [x] 5.1 Add resolved `scripts/gate.sh`, `hooks/pre-commit`, and `.github/workflows/ci.yml` to `example/` for the Acme Widgets (Python) toolchain
- [x] 5.2 Update `example/PROMPT.md` to the script-referencing gate step and `example/Makefile` to the `hooks` target; add the seeded `STATUS.md`, `docs/questions.md`, dirs, and seed spec to `example/`

## 6. Verify enforcement

- [x] 6.1 Add `base/tests/test_gate_hook.sh`: git fixture + template hook + stub `gate.sh`; assert a red gate aborts the commit (HEAD unchanged) and a green gate commits
- [x] 6.2 Wire `test_gate_hook.sh` into `base/tests/run.sh` and confirm `make test` runs and passes the new test alongside the existing suite
- [x] 6.3 Update `README.md` (Tests section + the channel diagram/scaffold list) and `CLAUDE.md` to mention the gate components `/ralph-init` now scaffolds

## 7. Open-question resolutions (design D6, D7)

- [x] 7.1 D6 — document the repo-wide gating reach + host-toolchain requirement in the skill report/guardrails, `README.md`, and `CLAUDE.md`; keep gating as a `build`/`loop` prerequisite (no pre-build gating, no skip-when-tools-absent)
- [x] 7.2 D7 — replace the placeholder seed spec with a spec-writing guide (`specs-README.md.template` → `<SPECS_DIR>/README.md`); update the skill §3c to write the guide and optionally capture a real first spec from the operator; update `example/` (`docs/specs/README.md`); update the `project-bootstrap` spec requirement
