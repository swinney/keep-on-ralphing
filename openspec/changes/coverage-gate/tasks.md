## 1. Templates — the coverage step

- [ ] 1.1 Update `templates/gate.sh.template` header guidance: the gate MUST include a coverage check with a threshold, in CI order; document the global-floor default and the patch/diff-coverage brownfield option
- [ ] 1.2 Add the coverage clause to `templates/PROMPT.md.template`: meet the threshold by testing the real path; exclude genuinely-untestable code via the standard pragma or escalate to questions.md; never delete tests or lower the threshold — keep the placeholder set closed

## 2. /ralph-init — inference, confirmation, toolchain

- [ ] 2.1 Extend `skills/ralph-init/SKILL.md` §2 inference to derive the coverage invocation + a starting threshold for the detected toolchain, fold it into the gate command in CI order
- [ ] 2.2 Require confirming the threshold with the user (a wrong threshold blocks every commit); add the coverage tooling to the inferred Containerfile and CI toolchain blocks
- [ ] 2.3 Add a guardrail: never set an aggressive threshold by fiat; coverage is a supporting gate (necessary-not-sufficient) — note the review gate / acceptance verification catch what coverage cannot

## 3. Example golden reference

- [ ] 3.1 Add a concrete coverage step to `example/scripts/gate.sh` (e.g. `pytest --cov=acme_widgets --cov-fail-under=80`) in CI order
- [ ] 3.2 Reflect the coverage tooling in `example/Containerfile` and `example/.github/workflows/ci.yml`; add the coverage clause to `example/PROMPT.md`

## 4. Docs

- [ ] 4.1 Update `CLAUDE.md` (PROMPT contract section) to note the gate now includes coverage, with the honest necessary-not-sufficient caveat
- [ ] 4.2 Update `README.md` gate paragraph to mention the coverage floor and its honest scope

## 5. (Optional) this repo's own gate

- [ ] 5.1 Decide whether to add a coverage step to this kit's own `make test`; if yes, wire it for the python portion (`test_until_reset.py`) and record the decision

## 6. Validation

- [ ] 6.1 `make test` green (no regressions; the kit's bash-based suite is unaffected by template/skill text changes)
- [ ] 6.2 `openspec validate coverage-gate --strict` passes
