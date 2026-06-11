# Fan-out Harness Spec (M10 scaling)

Design for running the **content layer** of the build in parallel: several Ralph
Loops, each in its own container + clone, each producing one independent cave
tribe, merged back as it lands. Scope is M10 (the remaining Caves of Chaos
tribes); the mechanism generalises to any future parallel-content milestone.

This is **operational tooling**, not a game subsystem, so it has no `tests/`
suite of its own (the discipline in CLAUDE.md §3 is for game subsystems);
verification is by `bash -n`, a `--dry-run` plan mode, and exercising the
parameterised runner against a temp task file. The *content* each loop produces
still goes through the full spec→test→implement gate.

---

## 1. Why this exists (and its one hard rule)

Field log §10 established the charter: **you don't speed up a convergence loop by
parallelising the loop — you parallelise the independent units the architecture
was designed to produce.** The systems layer (M1–M6) is shared-state and stays
**serial**. The content layer (zones/tribes) is embarrassingly parallel *iff*
each unit touches no shared files.

**Hard rule: a tribe unit must be buildable, testable, and mergeable touching
ZERO files another tribe touches.** Everything below serves that rule. Where it
can't be honoured (the shared ravine hub, the canonical `tasks.md`), the design
routes around it explicitly.

---

## 2. Decisions (resolved with the user)

| Fork | Decision |
|---|---|
| Concurrency | **Pool, default 2** (dial up to 3 when token budget allows); refill as each tribe finishes. |
| Merge model | **Per-tribe PRs, auto-merge when Copilot-clean**; stop only for findings needing judgment. |
| Isolation | **Local clone per tribe** (container git 2.47 < 2.48 makes worktree relative-paths fragile; `.git` is 1.2M so clone cost is nil). |
| Model tier | **Sonnet on tribes** (content/replication); **Opus** on the serial integration task. |
| Zone structure | **Per-tribe subpackages + discovery aggregator** (this spec, §3) — the prerequisite that makes the hard rule true. |

---

## 3. Component A — caves zone restructure (serial prerequisite)

The M9 kobold content is flat (`caves/rooms.py`, `caves/mobs.py`, `caves/build.py`
hold single module-level lists). Five tribes appending to those files would
collide on every PR. Restructure so each tribe is a self-contained subpackage and
the aggregator needs no per-tribe edit.

### 3.1 Target layout

```
world/zones/caves/
├── __init__.py        # re-exports build(); aggregates tribe data for validation
├── _hub.py            # SHARED: ravine hub rooms + the wilderness ↔ caves link
├── discovery.py       # find + import tribe subpackages (no per-tribe edit)
├── kobold/            # M9 content, migrated verbatim
│   ├── __init__.py    # exposes ROOMS, EXITS, MOB_TEMPLATES, SPAWNS, NPCS, build()
│   ├── rooms.py  exits.py  mobs.py  spawns.py  npcs.py
├── orc/  goblin/  hobgoblin/  bugbear/  gnoll/   # added by M10 fan-out
```

### 3.2 Discovery aggregator

`caves/discovery.py` enumerates immediate subdirectories of the `caves` package
(skipping names with a leading `_` and `__pycache__`), imports each as a tribe
module, and collects its `build` callable and pure data lists. `caves.build()`
becomes:

```python
def build() -> None:
    from world.zones.caves import _hub, discovery   # lazy: defer Evennia import
    _hub.build()                       # ravine hub + wilderness link (idempotent)
    for tribe in discovery.tribes():   # deterministic order (sorted by name)
        tribe.build()                  # each tribe wires only its own rooms/mobs
```

Discovery is **filesystem-driven**, so adding `caves/orc/` is sufficient — no
shared file changes. Order is sorted-by-name for deterministic builds/tests.

### 3.3 Shared hub

`_hub.py` owns the ravine entrance rooms (`ravine`, `ravine_north`, …), the
`caves:ravine_mouth` alias, and the forward `enter` exit from the Wilderness
(the logic currently in `caves/build.py::_link_to_wilderness`). Every tribe's
own entrance exit attaches to a hub room **by tag lookup**, never by editing the
hub — the same deferred/idempotent pattern the zone builders already use.

### 3.4 Invariants

- Importing `caves` stays Evennia-free (lazy imports preserved).
- `build()` stays idempotent and order-independent across hub + tribes.
- The migration is structural only: `tests/zones/test_caves.py` (the M9 suite)
  stays green, adjusted only for the kobold import path (`caves.kobold.*`).
- Each tribe subpackage carries the **pure-data testability** contract: data
  modules import no Evennia.

This refactor is a single serial PR (`M10 prep: caves per-tribe restructure +
discovery aggregator`) landed **before** the fan-out launches.

---

## 4. Component B — `ralph.sh` parameterisation

Two new env vars, both defaulted so existing single-loop behaviour is byte-for-
byte unchanged:

| Var | Default | Purpose |
|---|---|---|
| `RALPH_TASKS` | `tasks.md` | task file `first_task()` reads — points a tribe loop at its scoped list so loops don't all grab the same first task. |
| `RALPH_STATE_DIR` | `.ralph` | per-loop state/log/turn dir. Clones isolate this naturally; parameterising is cheap insurance and keeps the door open for worktrees. |

Changes: replace the hard-coded `tasks.md` in `first_task()` with `$RALPH_TASKS`,
and the hard-coded `.ralph` paths with `$RALPH_STATE_DIR`. The usage-limit pause,
stall detection, and STATUS.md stop condition are unchanged and apply per-loop.

---

## 5. Component C — `scripts/fanout.sh` (host orchestrator)

Runs on the host (it manages clones + containers). Not inside a loop container.

### 5.1 Tribe manifest

A small declarative list (in the script or `scripts/m10-tribes.txt`): the five
M10 units —

```
orc        # Vile Rune + Decapitator rivalry (one unit: the two tribes are interdependent)
goblin     # goblins + ogre ally
hobgoblin  # King Nardo
bugbear
gnoll      # gnolls + owlbear
```

The orc rivalry is **one** unit (the two orc tribes reference each other; splitting
them would create a cross-clone dependency). The minotaur maze + Shrine passage is
**not** here — it is the serial integration task (§8).

### 5.2 Per-tribe preparation

For each tribe `T`:
1. `git clone <local-repo> ../kotb-wt/m10-<T>` (full clone — instant at 1.2M,
   no network), then **reset the clone's `origin` to the GitHub URL** and
   `git fetch origin` — so the loop's `git push` and PR target GitHub, not the
   local path. Base branch `main` in the clone already equals `origin/main`
   (synced at orchestration start).
2. In the clone: `git checkout -b tribe/m10-<T>`.
3. Write the scoped task list to the clone's `.ralph/tribe-tasks.md` (gitignored
   — `.ralph/` already is). The canonical `tasks.md` is **never** edited by a
   tribe loop, so nothing merges back to clobber it.
4. Reuse the existing `PROMPT.md` unchanged.

### 5.3 Pool scheduler

Maintain ≤ `FANOUT_CONCURRENCY` (default 2) running tribe containers. Launch:

```
podman run --name kotb-ralph-m10-<T> \
  --userns=keep-id -e RALPH_MODEL=claude-sonnet-4-6 \
  -e RALPH_TASKS=.ralph/tribe-tasks.md \
  -v <clone>:/workspace -v <CLAUDE_DIR>:/home/claude/.claude \
  kotb-ralph ./scripts/ralph.sh
```

The shared `CLAUDE_DIR` auth mount is read-mostly and safe across concurrent
loops. When a slot frees, launch the next manifest entry.

### 5.4 Gate → land → free slot

Poll each clone's `STATUS.md`:
- **Tribe gate reached** (`<T> complete — …`): push `tribe/m10-<T>`, open its PR,
  request Copilot; if CI-green + zero findings → auto-merge; else leave for human
  triage. Either way the container is done → free the slot.
- **Stall halt** (the runner's max-stalls message): surface it, do **not** auto-PR,
  free the slot, flag for human. A stalled tribe never auto-lands.

Clones are removed after their PR merges (the git *branch* is kept — pr-flow
rule: never `--delete-branch`).

### 5.5 `--dry-run`

Prints the full plan — clones, branches, scoped task files, launch commands,
pool order — and launches nothing. The primary test seam (§7).

---

## 6. Component D — per-tribe task template

Each scoped `tribe-tasks.md` is the **proven M9 kobold shape**, parameterised by
tribe (this is the "replication of the M9 pattern" §10 predicted):

```
- [ ] world/zones/caves/<T>/ lair rooms + <T> mobs (pure data + builder)
- [ ] <T> leaders wired to the M6 leadership-halt + rival scouting
- [ ] Faction standing shifts observable in <T> behavior (M4 ↔ zone)
- [ ] tests/zones/test_<T>.py green (rooms/mobs/leaders/faction)
- [ ] ⛔ TRIBE GATE — write "<T> complete — paused for review." to STATUS.md and stop.
```

Tribe-specific content (mob stats, room names, the orc rivalry, ogre/owlbear
allies, King Nardo) comes from `docs/specs/zones/caves.md`, which each loop reads.
The template is the *structure*; the spec supplies the *content*.

---

## 7. Component E — `scripts/fanout-status.sh`

`make status` reads one `.ralph`. This aggregates across all active clones: for
each `../kotb-wt/m10-*`, print tribe, current turn, last commit subject, and
STATUS state (running / gated / stalled). One screen, the parallel analogue of
the single-loop digest.

---

## 8. Component F — serial integration task (post-fan-out)

After all five tribe PRs merge, the **minotaur maze + Shrine passage + the
cross-faction rivalry/repop-halt integration test** runs on the **single loop,
Opus** (it wires tribes together and asserts faction rivalries + repop halts fire
across them — stateful, cross-package, not an independent unit). This is the M10
exit criterion and the analogue of M9's vertical-slice test.

---

## 9. Data flow

```
manifest ─▶ for each tribe: clone ▶ branch ▶ write .ralph/tribe-tasks.md
   │
   ▼  (pool, ≤2 concurrent)
container[T]: ralph.sh ──loop──▶ commits to tribe/m10-<T> ──▶ STATUS.md gate
   │                                                              │
   │  stall ─▶ surface, no PR, free slot                          ▼
   └──────────────────────────────────────▶ push ▶ PR ▶ (clean? auto-merge) ▶ free slot
                                                                  │
   all tribes merged ─────────────────────────────────────────────▶ serial integration task (Opus)
```

## 10. Error handling

- **Usage limit:** absorbed per-loop by the runner's limit-pause (each clone
  pauses/resumes independently).
- **Stalled tribe:** surfaced, never auto-PR'd; slot freed; human triages.
- **Concurrent pushes:** distinct branches → no contention. Distinct packages +
  discovery aggregator → no merge conflicts on land.
- **Crash/host reboot:** "progress = a commit" holds per clone; relaunch
  re-clones only tribes without a merged PR.
- **Disk:** clones are ~the tracked tree (1.2M `.git`); negligible.

## 11. Build / sequencing order

1. **Component A** (caves restructure) — serial PR, tests green.
2. **Component B** (`ralph.sh` params) — can ride with A or its own commit.
3. **Components C–E** (`fanout.sh`, template, status) — the harness, with
   `--dry-run` verified.
4. **Launch fan-out** for the five tribes (pool of 2, Sonnet).
5. **Component F** — serial integration task (Opus) → M10 exit.

## 12. Out of scope

- Network hardening of the parallel containers (field log §7, "later").
- Auto-tuning concurrency to live token budget (manual `FANOUT_CONCURRENCY`).
- Generalising beyond caves tribes (the discovery pattern would extend, but M10
  is the only planned parallel-content milestone; M11 Shrine is serial).
