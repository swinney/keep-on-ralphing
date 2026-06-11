# keep-on-ralphing — team update (speaker outline)

Talking points for a verbal update — beats + cues, not a script. Flesh out the
words live. Bold = a phrase worth landing verbatim. ~4–5 min.

---

### 1. Hook
- New thing: **keep-on-ralphing** (yes, it's a pun)
- One line: **a reusable harness for driving an AI coding agent through a project, one task at a time**
- Callback: "the Ralph loop" I've mentioned — now extracted so *anyone* can use it

### 2. Why it exists
- We built the MUD **almost entirely by running Claude in a loop** — not prompt-by-prompt babysitting
- What a loop turn does: read task list → pick next task → spec → tests → implement till green → run full CI gate → commit → exit → repeat
- Key idea: **the commit graph is the progress signal** — commits landing = working; commits stop = halt for a human
- The problem: machinery was **tangled inside the game repo** — scripts, container, tribal knowledge, not portable → drift if copied

### 3. The three pieces (the split is the point)
- **Base container image** — the sandbox
  - agent runs with permissions skipped → only safe because it's a **throwaway container + your bind-mounted repo**
  - bakes the runner onto PATH → **your project carries no machinery, it inherits it**
- **Claude Code plugin** — two commands
  - `/ralph-init` — reads your repo, infers gate command from CI + toolchain, writes a small config
  - `/ralph-status` — "how's the loop doing": current turn, last commit, stalled?
- **Per-project config** — the only thing in your repo; thin, generated, not hand-maintained
- Payoff line: **fix the runner once in the base image, every project gets it for free — no drift**

### 4. How you'd use it (the whole path)
- clone + `make build-base` (once)
- install plugin (2 lines in Claude Code)
- in your project: `/ralph-init` → `make build` → `make login` (once) → `make loop`
- runs until: task list done / a stop condition / Ctrl-C

### 5. Status (be honest)
- base image: **builds + verified**
- plugin: **installs + works**
- proving end-to-end by making **our own MUD the first consumer** (dogfooding)
- already **caught a real bug** (PATH issue that'd bite the first user) — that's the point of a proof run
- **one final live test left**

### 6. Scope (set expectations)
- deliberately narrow: **Linux, podman, single-arch, shared via GitHub**
- NOT: public product, marketplace, Mac/Windows/Docker
- "does one thing well for our setup; extend it when we outgrow it, not before"

### 7. Close
- if you've got a project with **a clear task list and a real test suite**, point an agent at it and walk away
- I'll drop the **repo link + quickstart** after
- **offer to pair** with anyone who wants to try it on something real — best way to find rough edges
- Questions?
