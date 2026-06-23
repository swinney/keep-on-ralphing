## 1. Manifest backfill (surface + write)

- [x] 1.1 `skills/ralph-upgrade/SKILL.md` §2: when no manifest, state the upgrade WILL write one (bootstrapping the precise path for next time)
- [x] 1.2 §4 (confirm): list "write/refresh `.ralph-scaffold.json`" as an explicit, approvable plan item
- [x] 1.3 §3/§5: write the manifest after a confirmed upgrade (post-upgrade hashes) and report it; even in the legacy/no-manifest case

## 2. ralph.conf documented-section detection

- [x] 2.1 §3 `ralph.conf` strategy: also diff the template's commented documentation sections (e.g. the work-class dispatch block) and offer absent ones, not only missing active keys

## 3. Specs-guide skip when a spec system is present

- [x] 3.1 `skills/ralph-upgrade/SKILL.md`: skip the specs-dir guide when `openspec/` or an established specs body exists (note why)
- [x] 3.2 `skills/ralph-init/SKILL.md`: codify the same skip rule for the specs-writing guide

## 4. Release + validation

- [x] 4.1 Bump `.claude-plugin/plugin.json` 0.8.0 → 0.8.1 (host-side; no base rebuild)
- [x] 4.2 `make test` green; `openspec validate ralph-upgrade-refinements --strict` passes
