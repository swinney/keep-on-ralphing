## 1. Brownfield assessment in /ralph-init

- [x] 1.1 Add a brownfield-assessment step to `skills/ralph-init/SKILL.md` §2: classify the target using cheap signals (pre-existing source beyond the feature, existing test suite, existing lockfile/CI, loop targeting a feature subdir) and record greenfield / brownfield / unclear
- [x] 1.2 Treat "unclear" as not-clearly-greenfield (offer the brownfield path); never run the test suite to measure coverage at init

## 2. Coverage-mode question

- [x] 2.1 Update the coverage confirmation in `skills/ralph-init/SKILL.md` so the mode choice ALWAYS includes patch/scoped coverage as a first-class option (not only global floor vs none)
- [x] 2.2 Order the recommended option by the brownfield assessment (brownfield → patch/scoped first; greenfield → global floor first); never auto-switch without the user's confirmation
- [x] 2.3 Add the explicit warning that a global floor on an under-covered existing codebase fails the first commit (in §2 and the Guardrails coverage clause)

## 3. Scoped/patch recipe in templates

- [x] 3.1 Extend `templates/gate.sh.template` with a concrete per-ecosystem scoped recipe (Python `--cov=<path>`, vitest `--coverage.include=<dir> --coverage.thresholds.lines=<N>`, go `-cover ./<pkg>/...`), plus the true diff-coverage option noted as the stricter alternative
- [x] 3.2 Ensure the emitted brownfield `scripts/gate.sh` is copy-correct and adds the right coverage tooling to the Containerfile + CI toolchain blocks (covered by the §2 toolchain-install guidance, unchanged)
- [x] 3.3 Leave `example/` (Acme Widgets, greenfield) on the global floor — unchanged

## 4. Docs

- [x] 4.1 Note the brownfield/patch coverage mode in `CLAUDE.md`'s PROMPT/gate section (coverage stays a supporting gate; the review gate is the backstop for scoped coverage's blind spot)

## 5. Verification

- [ ] 5.1 Smoke-test on a brownfield throwaway target: confirm `/ralph-init` assesses brownfield, offers patch/scoped as the recommended option, warns about the global-floor trap, and emits a scoped `scripts/gate.sh` — DEFERRED: needs the 0.3.0 plugin released so the cache carries the SKILL.md edits
- [ ] 5.2 Smoke-test a greenfield target: confirm the global floor is still the default and the output is unchanged — DEFERRED with 5.1 (same release dependency)
- [x] 5.3 `make test` stays green (no runner/gate-enforcement behaviour regressed)
- [x] 5.4 `openspec validate scaffold-coverage-mode --strict` passes
