## 1. Fix the manifest semantics in the skill

- [x] 1.1 `skills/ralph-upgrade/SKILL.md` §3 (write): record a hash ONLY for files whose post-upgrade content matches the re-rendered current template; OMIT customized / insert-merged files (gate.sh, customized Containerfile/ci.yml, a Makefile with extra edits). Explain why (recording a customized file → next run misreads it pristine → clobbers it).
- [x] 1.2 `skills/ralph-upgrade/SKILL.md` §2 (read): a project file ABSENT from the manifest's `files` is feature-detected (insert-only, preserve), never wholesale-regenerated.

## 2. Release + validation

- [x] 2.1 Bump `.claude-plugin/plugin.json` 0.8.1 → 0.8.2 (bug-fix; host-side, no base rebuild)
- [x] 2.2 `make test` green; `openspec validate ralph-upgrade-manifest-fidelity --strict` passes
