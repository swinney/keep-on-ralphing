# keep-on-ralphing — team update (talking script)

A script written for the ear, for a verbal team update. Section headers are
navigation beats for the speaker — don't read them aloud. ~4–5 minutes spoken.

---

## Opening

So I want to walk you through something I just stood up called **keep-on-ralphing**.
The name's a pun, bear with me. It's a reusable harness for driving an AI coding
agent through a project, autonomously, one task at a time. If you've heard me talk
about the "Ralph loop" before — this is that, finally pulled out into something
any of us can drop into a repo.

## The why

Let me back up to why this exists. We built our MUD project — Keep on the
Borderlands — almost entirely by running Claude in a loop. Not me babysitting it
prompt by prompt. A loop: it reads a task list, picks the next unchecked task,
writes the spec, writes the tests, implements until they pass, runs the full CI
gate, commits, and exits. Then it does it again. The commit graph *is* the
progress signal — if commits are landing, it's working; if they stop, something's
wrong and it halts for a human.

The problem was: all the machinery to *run* that loop was tangled up inside the
game's repo. Shell scripts, a container definition, a bunch of operator know-how.
None of it portable. So if any of you wanted to run a loop on your own project,
you'd be copy-pasting scripts and inevitably they'd drift out of sync.
keep-on-ralphing fixes that.

## What it actually is — the three pieces

It comes in three pieces, and the split matters.

First, there's a **base container image**. This is the sandbox the loop runs
inside — and the sandbox is the whole point, because the agent runs with
permissions fully skipped. It can do anything... but only to a throwaway container
and your bind-mounted repo. The image bakes the loop runner onto the path. So your
project never carries the machinery — it just inherits it.

Second, there's a **Claude Code plugin**. You install it once, and it gives you two
commands. One is `/ralph-init` — you run it in any repo and it reads the project,
figures out your test command from your CI config, your toolchain, your project
name, and writes you a small config: a couple of files, nothing you maintain by
hand. The other is `/ralph-status` — ask it "how's the loop doing" and it reads the
runtime state and tells you what turn it's on, what it last committed, whether it's
stalled.

Third is the **per-project config** itself — the thin layer `/ralph-init`
generates. That's the only thing that lives in your repo. Everything else comes
from the image and the plugin.

The reason for that split: fix the runner once, in the base image, and every
project that uses it gets the fix for free. No drift. That's the entire design
philosophy.

## How you'd use it

Concretely, here's the whole adoption path. You clone the repo and build the base
image once — one make command. You install the plugin in Claude Code — two lines.
Then in your project you run `/ralph-init`, build your loop image, log in once, and
type `make loop`. That's it. It runs until it finishes the task list, or hits a
stop condition you defined, or you Ctrl-C it.

## Status — be honest

Where it stands today: the base image builds and is verified. The plugin installs
and works. And I'm in the middle of proving the whole thing end-to-end by making
our *own* MUD repo the first consumer — eating our own dog food. That migration's
been smooth, and it's already caught one real bug — a PATH issue that would've
bitten the first person who tried it — which is exactly what a proof run is
supposed to do. One final live test left and it's done.

## Scope — set expectations

One thing to be clear on: this is deliberately narrow. Linux, podman, single
architecture, shared among us through GitHub. It's not a public product, there's no
marketplace listing, I didn't build for Mac or Windows or Docker. It does one thing
well for our setup. If we outgrow that, we extend it then — not before.

## Close

So — that's keep-on-ralphing. If you've got a project with a clear task list and a
real test suite, this'll let you point an agent at it and walk away. I'll share the
repo link and a quickstart after this. Happy to pair with anyone who wants to try
it on something real — honestly that's the best way to shake out the rough edges.
Questions?
