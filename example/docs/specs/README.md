# Specs — Acme Widgets

This directory holds the written specs the Ralph loop builds from. **This file is a
guide, not a spec** — the loop reads it for orientation but never as requirements,
so it can sit here safely until you write real specs.

> Why a guide and not a starter spec: the loop treats anything that looks like a
> spec as truth and builds to it. A plausible-but-fake spec would make the loop
> build the wrong thing. So we ship guidance instead — you (or `/ralph-init`) write
> the first real spec.

## How to write a spec

One subsystem per file (`<system>.md`). A spec says WHAT the subsystem does in
enough detail that a test suite can be derived from it without further decisions:

- **Overview** — what this subsystem is responsible for, and what it is explicitly NOT.
- **Behavior** — normative statements: "The system SHALL …"; "Given <state>, when
  <event>, then <outcome>." Each should map to at least one test.
- **Edge cases** — empty / null / boundary inputs → defined behavior.
- **Out of scope** — what this subsystem deliberately does not do.

The loop's first turns will read these specs, derive tests from them, then implement
until the tests pass — one task per turn. No specs here yet means the loop has
nothing to build; add at least one before running it in earnest.
